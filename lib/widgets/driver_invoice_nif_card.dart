// M1 08/11/2026 — NIF da fatura para o estafeta em loja NÃO-parceira.
// M10 b2-nif 09/11/2026 — cartão laranja "NIF PARA A FATURA" + caixa
// obrigatória "Dei este NIF na caixa e está no talão" (ou "Não consegui" com
// motivo) nas folhas do talão (compras e Favor com compra).
//
// Regra do Danilo (04/11 e 08/11): "Não pode esquecer do NIF". Na caixa da
// loja o estafeta dá SEMPRE um NIF: o que o cliente pediu na fatura; sem
// pedido de fatura, o da Bora (setting `nif_compras_nao_parceiro`). Nunca
// "consumidor final". O NIF e se aparece vêm do servidor (RPC
// `driver_order_invoice_nif`, migração 20261109010000_m10_nif_na_caixa.sql) —
// a app não decide nada.
//
// Na loja parceira (a loja trata da fatura), num erro, sem rede ou com a função
// ainda fora do servidor, o cartão não aparece e a caixa não trava nada (nunca
// parte o ecrã onde está nem a entrega). A resposta da caixa sobe em segundo
// plano (`NifCaixaEnvio`, 3 tentativas) e também nunca trava a entrega.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../utils/nif_pt.dart';

/// Chamada a uma função do servidor (injetável nos testes).
typedef NifRpc = Future<dynamic> Function(
    String funcao, Map<String, dynamic> params);

Future<dynamic> _rpcSupabase(String funcao, Map<String, dynamic> params) =>
    Supabase.instance.client.rpc(funcao, params: params);

/// Laranja da marca (#F97316) e o tom escuro para texto legível.
const Color _laranja = Color(0xFFF97316);
const Color _laranjaEscuro = Color(0xFFC2410C);

/// Os motivos de "Não consegui pôr o NIF" ("Outro" pede texto).
const List<String> kMotivosNifNaoDado = [
  'A loja não aceitou',
  'Esqueci-me',
  'Outro',
];

/// O que aparece por baixo do botão de finalizar enquanto a caixa do NIF não
/// tem resposta.
const String kAvisoNifPorResponder =
    'Responde à caixa do NIF: marca "Dei este NIF na caixa" ou '
    '"Não consegui" com o motivo.';

/// A resposta do estafeta à caixa do NIF.
@immutable
class NifCaixaResposta {
  const NifCaixaResposta.dado()
      : dado = true,
        motivo = null;
  const NifCaixaResposta.naoDado(String this.motivo) : dado = false;

  final bool dado;
  final String? motivo;

  @override
  bool operator ==(Object other) =>
      other is NifCaixaResposta && other.dado == dado && other.motivo == motivo;

  @override
  int get hashCode => Object.hash(dado, motivo);

  @override
  String toString() => dado ? 'dado' : 'naoDado($motivo)';
}

/// O que a folha do talão lê para ligar/desligar o botão de finalizar.
class NifCaixaController extends ChangeNotifier {
  bool _aplica = false;
  NifCaixaResposta? _resposta;

  /// O servidor mandou mostrar o NIF neste pedido.
  bool get aplica => _aplica;

  NifCaixaResposta? get resposta => _resposta;

  /// A caixa está à vista e ainda sem resposta → o botão fica desligado.
  bool get porResponder => _aplica && _resposta == null;

  /// Texto a mostrar por baixo do botão, ou null quando não trava.
  String? get motivoBloqueio => porResponder ? kAvisoNifPorResponder : null;

  void definirAplica(bool aplica) {
    if (aplica == _aplica) return;
    _aplica = aplica;
    notifyListeners();
  }

  void responder(NifCaixaResposta? resposta) {
    if (resposta == _resposta) return;
    _resposta = resposta;
    notifyListeners();
  }
}

/// Envio da resposta (`estafeta_confirmar_nif_caixa`): 3 tentativas, nunca
/// lança e nunca faz esperar quem chama [emSegundoPlano].
class NifCaixaEnvio {
  NifCaixaEnvio._();

  static const int tentativas = 3;

  @visibleForTesting
  static NifRpc rpc = _rpcSupabase;

  @visibleForTesting
  static Duration Function(int tentativa) espera =
      (t) => Duration(seconds: 2 * t);

  /// true = gravado (ou o pedido não precisa de NIF); false = desistiu.
  static Future<bool> enviar(String orderId, NifCaixaResposta r) async {
    for (var i = 1; i <= tentativas; i++) {
      try {
        final res = await rpc('estafeta_confirmar_nif_caixa', {
          'p_order_id': orderId,
          'p_dado': r.dado,
          'p_motivo': r.motivo,
        });
        if (res is Map && res['ok'] == true) return true;
        if (res is Map && res['ok'] == false) {
          // Recusa do servidor (ex.: não é o teu pedido): repetir não muda.
          debugPrint('[nif-caixa] recusado: ${res['error']}');
          return false;
        }
        debugPrint('[nif-caixa] resposta inesperada: $res');
      } catch (e) {
        debugPrint('[nif-caixa] tentativa $i falhou: $e');
      }
      if (i < tentativas) await Future<void>.delayed(espera(i));
    }
    return false;
  }

  /// Dispara e esquece: a entrega segue logo, com ou sem rede.
  static void emSegundoPlano(String orderId, NifCaixaResposta r) {
    unawaited(enviar(orderId, r).catchError((Object e) {
      debugPrint('[nif-caixa] $e');
      return false;
    }));
  }
}

class DriverInvoiceNifCard extends StatefulWidget {
  const DriverInvoiceNifCard({
    super.key,
    required this.orderId,
    this.caixa,
    this.rpc,
  });

  final String orderId;

  /// Com controlador: mostra a caixa obrigatória "Dei este NIF na caixa e está
  /// no talão" / "Não consegui" (folhas do talão). Sem ele: só o NIF.
  final NifCaixaController? caixa;

  /// Só para testes: em vez do Supabase.
  final NifRpc? rpc;

  @override
  State<DriverInvoiceNifCard> createState() => _DriverInvoiceNifCardState();
}

class _DriverInvoiceNifCardState extends State<DriverInvoiceNifCard> {
  Map<String, dynamic>? _dados;
  bool _copiado = false;
  bool _dei = false;
  bool _naoConsegui = false;
  String? _motivo;
  final _outroCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant DriverInvoiceNifCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _dados = null;
      _copiado = false;
      _dei = false;
      _naoConsegui = false;
      _motivo = null;
      _outroCtrl.clear();
      widget.caixa
        ?..definirAplica(false)
        ..responder(null);
      _carregar();
    }
  }

  @override
  void dispose() {
    _outroCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final id = widget.orderId;
    try {
      final res = await (widget.rpc ?? _rpcSupabase)(
        'driver_order_invoice_nif',
        {'p_order_id': id},
      );
      if (!mounted || id != widget.orderId) return;
      if (res is Map &&
          res['ok'] == true &&
          res['mostrar'] == true &&
          soDigitosNif(res['nif']?.toString()).isNotEmpty) {
        setState(() {
          _dados = Map<String, dynamic>.from(res);
          _reporResposta(res['confirmado']);
        });
        widget.caixa?.definirAplica(true);
        _atualizarResposta();
      }
    } catch (e) {
      // Calado de propósito: sem o NIF o ecrã continua a funcionar.
      debugPrint('[nif-estafeta] $e');
    }
  }

  /// A folha reabriu depois de o estafeta já ter respondido: a resposta
  /// guardada no servidor volta à caixa.
  void _reporResposta(Object? confirmado) {
    if (confirmado is! Map) return;
    if (confirmado['dado'] == true) {
      _dei = true;
      _naoConsegui = false;
      return;
    }
    final m = (confirmado['motivo'] as String? ?? '').trim();
    if (confirmado['dado'] != false || m.isEmpty) return;
    _dei = false;
    _naoConsegui = true;
    if (kMotivosNifNaoDado.contains(m) && m != 'Outro') {
      _motivo = m;
    } else {
      _motivo = 'Outro';
      _outroCtrl.text = m.startsWith('Outro: ') ? m.substring(7) : m;
    }
  }

  void _atualizarResposta() {
    final caixa = widget.caixa;
    if (caixa == null) return;
    NifCaixaResposta? r;
    if (_dei) {
      r = const NifCaixaResposta.dado();
    } else if (_naoConsegui && _motivo != null) {
      if (_motivo == 'Outro') {
        final t = _outroCtrl.text.trim();
        r = t.length >= 3 ? NifCaixaResposta.naoDado('Outro: $t') : null;
      } else {
        r = NifCaixaResposta.naoDado(_motivo!);
      }
    }
    caixa.responder(r);
  }

  Future<void> _copiar(String nif) async {
    await Clipboard.setData(ClipboardData(text: nif));
    if (mounted) setState(() => _copiado = true);
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    if (d == null) return const SizedBox.shrink();
    final nif = soDigitosNif(d['nif']?.toString());
    if (nif.isEmpty) return const SizedBox.shrink();
    final doCliente = d['tipo'] == 'cliente' || d['pediu_fatura'] == true;
    final nome = (d['nome'] as String? ?? '').trim();
    return Container(
      key: const Key('driver_invoice_nif_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _laranja.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _laranja, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long, color: _laranja, size: 22),
              SizedBox(width: 8),
              Text(
                'NIF PARA A FATURA',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: _laranjaEscuro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  formatarNif(nif),
                  key: const Key('nif_caixa_numero'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('nif_caixa_copiar'),
                onPressed: () => _copiar(nif),
                icon: Icon(_copiado ? Icons.check : Icons.copy, size: 18),
                label: Text(_copiado ? 'Copiado' : 'Copiar'),
              ),
            ],
          ),
          Text(
            doCliente
                ? 'Do cliente — pediu fatura'
                : 'Da Bora — o cliente não pediu fatura',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (doCliente && nome.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Nome na fatura: $nome',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'Diz este NIF na caixa ANTES de pagar.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _laranjaEscuro,
            ),
          ),
          if (widget.caixa != null) ..._caixa(),
        ],
      ),
    );
  }

  List<Widget> _caixa() {
    return [
      const Divider(height: 16),
      CheckboxListTile(
        key: const Key('nif_caixa_dei'),
        value: _dei,
        onChanged: (v) => setState(() {
          _dei = v ?? false;
          if (_dei) _naoConsegui = false;
          _atualizarResposta();
        }),
        title: const Text(
          'Dei este NIF na caixa e está no talão',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: AppColors.primary,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('nif_caixa_nao_consegui'),
          onPressed: () => setState(() {
            _naoConsegui = !_naoConsegui;
            if (_naoConsegui) {
              _dei = false;
            } else {
              _motivo = null;
            }
            _atualizarResposta();
          }),
          icon: Icon(
              _naoConsegui ? Icons.expand_less : Icons.error_outline,
              size: 18),
          label: const Text('Não consegui pôr o NIF'),
        ),
      ),
      if (_naoConsegui) ...[
        const Text('Porquê?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < kMotivosNifNaoDado.length; i++)
              ChoiceChip(
                key: Key('nif_motivo_$i'),
                label: Text(kMotivosNifNaoDado[i]),
                selected: _motivo == kMotivosNifNaoDado[i],
                onSelected: (_) => setState(() {
                  _motivo = kMotivosNifNaoDado[i];
                  _atualizarResposta();
                }),
              ),
          ],
        ),
        if (_motivo == 'Outro') ...[
          const SizedBox(height: 6),
          TextField(
            key: const Key('nif_motivo_outro'),
            controller: _outroCtrl,
            maxLength: 200,
            onChanged: (_) => setState(_atualizarResposta),
            decoration: const InputDecoration(
              labelText: 'Escreve o motivo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ],
    ];
  }
}
