// Painel da farmácia (parceiro) — receitas e pedidos especiais (missão farmacias-2026-11-11).
// - FarmaciaReceitasCartao: cartão no topo do separador Pedidos (só farmácias), com o número à espera
//   e o TOQUE PERSISTENTE enquanto houver algum pedido por responder.
// - ParceiroPrescricoesScreen: lista em tempo real.
// - ParceiroPrescricaoDetalheScreen: ver a receita e responder "Tenho, aceito" / "Não tenho".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../models/pedido_prescricao.dart';
import '../../../models/restaurant_model.dart';
import '../../../services/incoming_job_alert.dart';
import '../../../services/prescricao_service.dart';
import '../../../services/sound_service.dart';
import '../../../widgets/bora/bora_bottom_action_bar.dart';
import '../../../widgets/bora_foto_ecra_inteiro.dart';

String _hora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _rotuloEstadoParceiro(PrescricaoEstado e) {
  switch (e) {
    case PrescricaoEstado.enviado:
      return 'À espera da sua resposta';
    case PrescricaoEstado.aceite:
      return 'Aceite — à espera do cliente';
    case PrescricaoEstado.aceiteParcial:
      return 'Aceite em parte — à espera do cliente';
    case PrescricaoEstado.recusado:
      return 'Não tinha';
    case PrescricaoEstado.expirado:
      return 'Expirou sem resposta';
    case PrescricaoEstado.cancelado:
      return 'Cancelado pelo cliente';
    case PrescricaoEstado.confirmado:
      return 'Confirmado — preparar';
    case PrescricaoEstado.entregue:
      return 'Entregue';
  }
}

/// Lê "12,34" / "12.34" / "12" → cêntimos. Null se não for um valor válido.
int? centsDeTexto(String s) {
  final t = s.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0 || v > 1000) return null;
  return (v * 100).round();
}

// ───────────────────────────────────────────────────────────────── cartão + alarme

class FarmaciaReceitasCartao extends StatefulWidget {
  const FarmaciaReceitasCartao({super.key, required this.restaurant});
  final RestaurantModel restaurant;

  @override
  State<FarmaciaReceitasCartao> createState() => _FarmaciaReceitasCartaoState();
}

class _FarmaciaReceitasCartaoState extends State<FarmaciaReceitasCartao> {
  final _svc = PrescricaoService();
  final _som = SoundService();
  StreamSubscription<List<PedidoPrescricao>>? _sub;
  List<PedidoPrescricao> _lista = const [];
  final Set<String> _avisados = {};
  bool _aTocar = false;

  bool get _eFarmacia => widget.restaurant.category == BusinessCategory.pharmacy;

  @override
  void initState() {
    super.initState();
    if (_eFarmacia) {
      _sub = _svc.daLoja(widget.restaurant.id).listen(_aoMudar, onError: (_) {});
    }
  }

  void _aoMudar(List<PedidoPrescricao> l) {
    if (!mounted) return;
    setState(() => _lista = l);
    final aEspera = l.where((p) => p.estado.aEsperaDaFarmacia).toList();
    if (aEspera.isNotEmpty && !_aTocar) {
      _aTocar = true;
      unawaited(_som.playLoop());
      HapticFeedback.heavyImpact();
    } else if (aEspera.isEmpty && _aTocar) {
      _aTocar = false;
      unawaited(_som.stop());
    }
    for (final p in aEspera) {
      if (_avisados.add(p.id)) {
        unawaited(IncomingJobAlert.show(
          id: p.id,
          type: 'prescricao_nova',
          title: p.eReceita ? 'Nova receita para aviar' : 'Pedido especial de um cliente',
          body: 'Toque para ver e responder: tem ou não tem.',
          extraPayload: {'orderId': p.id},
        ));
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_aTocar) unawaited(_som.stop());
    super.dispose();
  }

  Future<void> _abrir() async {
    if (_aTocar) {
      _aTocar = false;
      unawaited(_som.stop());
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ParceiroPrescricoesScreen(restaurantId: widget.restaurant.id, farmaciaNome: widget.restaurant.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_eFarmacia) return const SizedBox.shrink();
    final n = _lista.where((p) => p.estado.aEsperaDaFarmacia).length;
    final destaque = n > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: destaque ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('farmacia_receitas_cartao'),
          borderRadius: BorderRadius.circular(16),
          onTap: _abrir,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.receipt_long, size: 30, color: destaque ? Colors.white : AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Receitas e pedidos especiais',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: destaque ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    destaque ? '$n à espera de resposta — toque para responder' : 'Sem pedidos à espera',
                    style: TextStyle(color: destaque ? Colors.white : AppColors.textSecondary),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right, color: destaque ? Colors.white : AppColors.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── lista

class ParceiroPrescricoesScreen extends StatelessWidget {
  const ParceiroPrescricoesScreen({super.key, required this.restaurantId, required this.farmaciaNome});
  final String restaurantId;
  final String farmaciaNome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Receitas e pedidos especiais')),
      body: StreamBuilder<List<PedidoPrescricao>>(
        stream: PrescricaoService().daLoja(restaurantId),
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return ParceiroPrescricoesLista(pedidos: s.data!);
        },
      ),
    );
  }
}

/// Lista testável (sem rede).
class ParceiroPrescricoesLista extends StatelessWidget {
  const ParceiroPrescricoesLista({super.key, required this.pedidos, this.agora});
  final List<PedidoPrescricao> pedidos;
  final DateTime Function()? agora;

  @override
  Widget build(BuildContext context) {
    final aEspera = pedidos.where((p) => p.estado.aEsperaDaFarmacia).toList();
    final confirmados = pedidos.where((p) => p.estado == PrescricaoEstado.confirmado || p.estado == PrescricaoEstado.entregue).toList();
    final outros = pedidos.where((p) => !aEspera.contains(p) && !confirmados.contains(p)).toList();
    final agoraDt = (agora ?? DateTime.now)();

    Widget seccao(String t, List<PedidoPrescricao> l, {bool forte = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('$t (${l.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: forte ? AppColors.primaryDark : AppColors.textPrimary)),
        );

    Widget cartao(PedidoPrescricao p) {
      final falta = p.expiraEm?.difference(agoraDt);
      final min = falta == null ? null : (falta.inSeconds / 60).ceil();
      final espera = p.estado.aEsperaDaFarmacia;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: espera ? AppColors.primaryWash : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Icon(p.eReceita ? Icons.receipt_long : Icons.search, color: AppColors.primary, size: 28),
            title: Text(p.eReceita ? 'Receita' : 'Pedido especial', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              _hora(p.createdAt),
              if (p.morada != null) p.morada!,
              _rotuloEstadoParceiro(p.estado),
              if (espera && min != null) (min > 0 ? 'Responda em $min min' : 'A expirar'),
            ].join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ParceiroPrescricaoDetalheScreen(prescricaoId: p.id)),
            ),
          ),
        ),
      );
    }

    if (pedidos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Ainda não há pedidos. Quando um cliente enviar uma receita, toca e aparece aqui.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        seccao('À espera de resposta', aEspera, forte: true),
        ...aEspera.map(cartao),
        if (confirmados.isNotEmpty) ...[seccao('Confirmados pelo cliente', confirmados), ...confirmados.map(cartao)],
        if (outros.isNotEmpty) ...[seccao('Respondidos', outros), ...outros.map(cartao)],
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────── detalhe

class ParceiroPrescricaoDetalheScreen extends StatelessWidget {
  const ParceiroPrescricaoDetalheScreen({super.key, required this.prescricaoId});
  final String prescricaoId;

  @override
  Widget build(BuildContext context) {
    final svc = PrescricaoService();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pedido do cliente')),
      body: StreamBuilder<PedidoPrescricao?>(
        stream: svc.acompanhar(prescricaoId),
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting && !s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = s.data;
          if (p == null) return const Center(child: Text('Pedido não encontrado.'));
          return ParceiroPrescricaoCorpo(pedido: p, service: svc);
        },
      ),
    );
  }
}

/// Corpo testável do detalhe.
class ParceiroPrescricaoCorpo extends StatefulWidget {
  const ParceiroPrescricaoCorpo({super.key, required this.pedido, this.service, this.semImagens = false});
  final PedidoPrescricao pedido;
  final PrescricaoService? service;

  /// Testes: não pedir URLs assinados.
  final bool semImagens;

  @override
  State<ParceiroPrescricaoCorpo> createState() => _ParceiroPrescricaoCorpoState();
}

class _ParceiroPrescricaoCorpoState extends State<ParceiroPrescricaoCorpo> {
  bool _aResponder = false;
  PrescricaoService get _svc => widget.service ?? PrescricaoService();
  PedidoPrescricao get p => widget.pedido;

  Widget _cartao(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
        child: child,
      );

  Widget _codigo(String rotulo, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: const TextStyle(color: AppColors.textSecondary)),
            SelectableText(valor, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ]),
        ),
        IconButton(
          tooltip: 'Copiar',
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: valor));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado.')));
          },
        ),
      ]),
    );
  }

  Widget _imagem(String? caminho, String titulo, {double altura = 220}) {
    if (caminho == null || widget.semImagens) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: _svc.urlAssinado(caminho, segundos: 600),
      builder: (context, s) {
        final url = s.data;
        if (url == null) {
          return SizedBox(height: altura, child: const Center(child: CircularProgressIndicator()));
        }
        return GestureDetector(
          onTap: () => BoraFotoEcraInteiro.abrir(context, urlOrPath: url, titulo: titulo),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, height: altura, width: double.infinity, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => SizedBox(height: altura, child: const Center(child: Text('Não foi possível abrir a imagem.')))),
          ),
        );
      },
    );
  }

  Future<void> _tenho() async {
    final r = await showModalBottomSheet<_RespostaAceite>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FolhaTenhoAceito(eReceita: p.eReceita),
    );
    if (r == null) return;
    await _responder(() => _svc.responder(p.id,
        aceita: true,
        valorCents: r.cents,
        parcial: r.parcial,
        itensDisponiveis: r.itens,
        tempoPreparacaoMin: r.minutos));
  }

  Future<void> _naoTenho() async {
    final r = await showModalBottomSheet<_RespostaRecusa>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FolhaNaoTenho(eReceita: p.eReceita),
    );
    if (r == null) return;
    await _responder(() => _svc.responder(p.id, aceita: false, motivo: r.motivo, motivoTexto: r.texto, voltaATer: r.voltaATer));
  }

  Future<void> _responder(Future<void> Function() f) async {
    if (_aResponder) return;
    setState(() => _aResponder = true);
    try {
      await f();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resposta enviada ao cliente.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
      }
    } finally {
      if (mounted) setState(() => _aResponder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final espera = p.estado.aEsperaDaFarmacia;
    final confirmado = p.estado == PrescricaoEstado.confirmado || p.estado == PrescricaoEstado.entregue;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            if (p.isDemo && confirmado)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                child: const Text('Demonstração: nenhum estafeta é chamado e nada é cobrado.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF9A3412))),
              ),
            _cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.eReceita ? 'Receita' : 'Pedido especial', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${_hora(p.createdAt)} · ${_rotuloEstadoParceiro(p.estado)}', style: const TextStyle(color: AppColors.textSecondary)),
            ])),
            if (confirmado)
              _cartao(Column(children: [
                const Text('O cliente confirmou', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                const SizedBox(height: 8),
                const Text('Código de levantamento (o estafeta mostra-o ao chegar)', textAlign: TextAlign.center),
                const SizedBox(height: 6),
                FittedBox(
                  child: Text(p.codigoLevantamento ?? '—',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6)),
                ),
                const SizedBox(height: 6),
                Text('Total ${eurosDeCents(p.totalCents)} · ${p.metodoPagamento == 'cash' ? 'dinheiro' : p.metodoPagamento == 'mbway' ? 'MB Way' : 'cartão'}'),
              ])),
            if (p.eReceita)
              _cartao(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (p.receitaFotoPath != null) _imagem(p.receitaFotoPath, 'Receita'),
                if (p.receitaFotoPath != null) const SizedBox(height: 8),
                _codigo('Número da receita', p.receitaNumero),
                _codigo('Código de acesso e dispensa', p.receitaCodigoAcesso),
                _codigo('Código de direito de opção', p.receitaCodigoOpcao),
                if (p.dadosApagadosEm != null)
                  const Text('Os dados da receita já foram apagados (30 dias).', style: TextStyle(color: AppColors.textSecondary)),
              ]))
            else
              _cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('O cliente procura', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(p.descricao ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (p.pedidoFotoPath != null) ...[const SizedBox(height: 10), _imagem(p.pedidoFotoPath, 'Foto do cliente', altura: 180)],
              ])),
            if ((p.nota ?? '').isNotEmpty)
              _cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Nota do cliente', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(p.nota!),
              ])),
            if ((p.morada ?? '').isNotEmpty)
              _cartao(Row(children: [
                const Icon(Icons.place_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(p.morada!)),
              ])),
            if (p.eReceita && p.consentimentoEm != null)
              _cartao(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Autorização assinada às ${_hora(p.consentimentoEm!)} (versão ${p.consentimentoVersao ?? '—'})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((p.consentimentoTexto ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p.consentimentoTexto!, style: const TextStyle(color: AppColors.textSecondary)),
                ],
                if (p.assinaturaPath != null) ...[const SizedBox(height: 8), _imagem(p.assinaturaPath, 'Assinatura', altura: 90)],
              ])),
            if (!espera && !confirmado && p.valorMedicamentosCents != null)
              _cartao(Text('Respondeu: ${eurosDeCents(p.valorMedicamentosCents)}'
                  '${(p.itensDisponiveis ?? '').isNotEmpty ? ' (tem: ${p.itensDisponiveis})' : ''}')),
          ],
        ),
      ),
      if (espera)
        BoraBottomActionBar(
          color: Colors.white,
          children: [
            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                key: const ValueKey('farmacia_tenho_aceito'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _aResponder ? null : _tenho,
                icon: const Icon(Icons.check_circle, size: 26),
                label: const Text('Tenho, aceito'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                key: const ValueKey('farmacia_nao_tenho'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error, width: 1.5),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _aResponder ? null : _naoTenho,
                icon: const Icon(Icons.close),
                label: const Text('Não tenho'),
              ),
            ),
          ],
        ),
    ]);
  }
}

class _RespostaAceite {
  const _RespostaAceite(this.cents, this.parcial, this.itens, this.minutos);
  final int cents;
  final bool parcial;
  final String? itens;
  final int? minutos;
}

class _RespostaRecusa {
  const _RespostaRecusa(this.motivo, this.texto, this.voltaATer);
  final String motivo;
  final String? texto;
  final String? voltaATer;
}

class FolhaTenhoAceito extends StatefulWidget {
  const FolhaTenhoAceito({super.key, required this.eReceita});
  final bool eReceita;
  @override
  State<FolhaTenhoAceito> createState() => _FolhaTenhoAceitoState();
}

class _FolhaTenhoAceitoState extends State<FolhaTenhoAceito> {
  final _valor = TextEditingController();
  final _itens = TextEditingController();
  bool _falta = false;
  int? _min = 15;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    _itens.dispose();
    super.dispose();
  }

  void _confirmar() {
    final c = centsDeTexto(_valor.text);
    if (c == null) return setState(() => _erro = 'Escreva o valor total, por exemplo 23,50.');
    if (_falta && _itens.text.trim().isEmpty) return setState(() => _erro = 'Diga quais tem.');
    Navigator.of(context).pop(_RespostaAceite(c, _falta, _falta ? _itens.text.trim() : null, _min));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, BoraBottomActionBar.folgaInferior(context, base: 16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Tenho, aceito', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('farmacia_valor'),
          controller: _valor,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: 'Valor total a pagar pelo cliente (€)',
            hintText: '0,00',
            suffixText: '€',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        CheckboxListTile(
          value: _falta,
          onChanged: (v) => setState(() => _falta = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
          title: Text(widget.eReceita ? 'Falta algum medicamento' : 'Só tenho parte do pedido'),
        ),
        if (_falta)
          TextField(
            controller: _itens,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: 'Quais tem?', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
        const SizedBox(height: 12),
        const Text('Tempo de preparação', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final m in const [10, 15, 20, 30])
            ChoiceChip(
              label: Text('$m min'),
              selected: _min == m,
              selectedColor: AppColors.primaryWash,
              onSelected: (_) => setState(() => _min = m),
            ),
        ]),
        if (_erro != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_erro!, style: const TextStyle(color: AppColors.error))),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: _confirmar,
            child: const Text('Enviar ao cliente', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

class FolhaNaoTenho extends StatefulWidget {
  const FolhaNaoTenho({super.key, required this.eReceita});
  final bool eReceita;
  @override
  State<FolhaNaoTenho> createState() => _FolhaNaoTenhoState();
}

class _FolhaNaoTenhoState extends State<FolhaNaoTenho> {
  String _motivo = PrescricaoMotivo.semStock;
  final _texto = TextEditingController();
  final _volta = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    _volta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motivos = [
      PrescricaoMotivo.semStock,
      if (widget.eReceita) PrescricaoMotivo.receitaInvalida,
      PrescricaoMotivo.outro,
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, BoraBottomActionBar.folgaInferior(context, base: 16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Não tenho', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final m in motivos)
          RadioListTile<String>(
            value: m,
            // ignore: deprecated_member_use
            groupValue: _motivo,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => _motivo = v ?? _motivo),
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            title: Text(PrescricaoMotivo.rotulo(m)),
          ),
        if (_motivo == PrescricaoMotivo.outro)
          TextField(
            controller: _texto,
            decoration: InputDecoration(labelText: 'Qual o motivo?', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _volta,
          decoration: InputDecoration(
            labelText: 'Quando volta a ter? (opcional)',
            hintText: 'Ex.: amanhã de manhã',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(_RespostaRecusa(
              _motivo,
              _texto.text.trim().isEmpty ? null : _texto.text.trim(),
              _volta.text.trim().isEmpty ? null : _volta.text.trim(),
            )),
            child: const Text('Avisar o cliente', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
