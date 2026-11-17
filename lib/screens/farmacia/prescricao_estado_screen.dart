// Estado de um pedido de receita / pedido especial (missão farmacias-2026-11-11).
// Acompanha em tempo real: a resposta da farmácia aparece em segundos.
// Aceite → valores + pagamento (cartão, MB Way, dinheiro) + confirmar.
// Recusado/expirado → motivo e "não foi cobrado nada". Confirmado → códigos.
// 17/11/2026 (receita-cartao-mbway-17-11): cartão e MB Way pagam pelo caminho do Favor
// (PrescricaoPagamentoService); dinheiro e demonstração continuam em prescricao_confirmar.
// Confirmado com pedido real → "Acompanhar a entrega" abre o acompanhamento normal.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../models/order_model.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/prescricao_pagamento_service.dart';
import '../../services/prescricao_service.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora_foto_ecra_inteiro.dart';
import '../../widgets/farmacia/lembrete_mensal_sheet.dart';
import '../../widgets/mbway_espera_pedido_dialog.dart';
import '../order_tracking_screen.dart';
import 'prescricao_enviar_screen.dart';

class PrescricaoEstadoScreen extends StatefulWidget {
  const PrescricaoEstadoScreen({super.key, required this.prescricaoId, this.service});

  final String prescricaoId;
  final PrescricaoService? service;

  @override
  State<PrescricaoEstadoScreen> createState() => _PrescricaoEstadoScreenState();
}

class _PrescricaoEstadoScreenState extends State<PrescricaoEstadoScreen> {
  late final PrescricaoService _svc = widget.service ?? PrescricaoService();
  StreamSubscription<PedidoPrescricao?>? _sub;
  PedidoPrescricao? _pedido;
  String? _nomeFarmacia;
  int _taxa = 0;
  bool _carregou = false;
  String? _erroCarregar;

  @override
  void initState() {
    super.initState();
    _sub = _svc.acompanhar(widget.prescricaoId).listen((p) {
      if (!mounted) return;
      final primeira = _pedido == null && p != null;
      setState(() {
        _pedido = p;
        _carregou = true;
      });
      if (primeira) _carregarExtras(p);
    }, onError: (_) async {
      // Sem tempo real (rede fraca): lê uma vez.
      try {
        final p = await _svc.obter(widget.prescricaoId);
        if (!mounted) return;
        setState(() {
          _pedido = p;
          _carregou = true;
        });
        if (p != null) _carregarExtras(p);
      } catch (e) {
        if (mounted) setState(() => _erroCarregar = PrescricaoService.mensagemDe(e));
      }
    });
  }

  Future<void> _carregarExtras(PedidoPrescricao p) async {
    try {
      final c = await _svc.consentimento(p.restaurantId);
      if (mounted) setState(() => _taxa = c.taxaServicoCents);
    } catch (_) {}
    try {
      final r = await PrescricaoServiceLojas.nome(p.restaurantId);
      if (mounted) setState(() => _nomeFarmacia = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_nomeFarmacia ?? 'Pedido à farmácia')),
      body: !_carregou
          ? Center(
              child: _erroCarregar != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_erroCarregar!, textAlign: TextAlign.center))
                  : const CircularProgressIndicator(),
            )
          : p == null
              ? const Center(child: Text('Pedido não encontrado.'))
              : PrescricaoEstadoCorpo(
                  pedido: p,
                  taxaServicoCents: _taxa,
                  farmaciaNome: _nomeFarmacia ?? 'farmácia',
                  service: _svc,
                ),
    );
  }
}

/// Nome da loja (lido uma vez; a RLS só deixa ver a quem pode).
class PrescricaoServiceLojas {
  static final Map<String, String> _cache = {};
  static Future<String?> nome(String restaurantId) async {
    if (_cache.containsKey(restaurantId)) return _cache[restaurantId];
    final r = await PrescricaoService().nomeDaLoja(restaurantId);
    if (r != null) _cache[restaurantId] = r;
    return r;
  }
}

/// Corpo testável (sem rede): desenha o estado do pedido.
class PrescricaoEstadoCorpo extends StatefulWidget {
  const PrescricaoEstadoCorpo({
    super.key,
    required this.pedido,
    required this.taxaServicoCents,
    required this.farmaciaNome,
    this.service,
    this.pagamento,
    this.agora,
  });

  final PedidoPrescricao pedido;
  final int taxaServicoCents;
  final String farmaciaNome;
  final PrescricaoService? service;

  /// Cartão / MB Way (para testes; por defeito o real).
  final PrescricaoPagamentoService? pagamento;
  final DateTime Function()? agora;

  @override
  State<PrescricaoEstadoCorpo> createState() => _PrescricaoEstadoCorpoState();
}

class _PrescricaoEstadoCorpoState extends State<PrescricaoEstadoCorpo> {
  String _metodo = 'card';
  bool _aConfirmar = false;

  /// app-15-11: o servidor recusou confirmar (ex.: a entrega de receitas ainda
  /// não está ligada nesta farmácia). Fica à vista em vez de sumir num aviso.
  String? _recusaConfirmar;

  String? _fotoCaminho;
  Future<String?>? _fotoUrl;
  bool _aCancelar = false;
  Timer? _relogio;

  PrescricaoService get _svc => widget.service ?? PrescricaoService();
  late final PrescricaoPagamentoService _pag = widget.pagamento ?? PrescricaoPagamentoService(prescricoes: widget.service);
  PedidoPrescricao get p => widget.pedido;

  /// Número do MB Way (pré-preenchido com o da conta).
  final _telefoneMbway = TextEditingController();
  bool _telefonePreenchido = false;

  /// O pagamento entrou e espera-se que o servidor ligue a receita ao pedido (segundos).
  bool _aguardaLigacao = false;
  bool _ligacaoDemorou = false;
  Timer? _relogioLigacao;
  bool _aAbrirPedido = false;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && p.estado.aEsperaDaFarmacia) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_telefonePreenchido) return;
    _telefonePreenchido = true;
    try {
      final tel = Provider.of<AuthStore>(context, listen: false).currentClient?.phone ?? '';
      final digitos = tel.replaceAll(RegExp(r'\D'), '');
      _telefoneMbway.text = digitos.length > 9 ? digitos.substring(digitos.length - 9) : digitos;
    } catch (_) {
      // Sem AuthStore (testes): o cliente escreve o número.
    }
  }

  @override
  void didUpdateWidget(covariant PrescricaoEstadoCorpo old) {
    super.didUpdateWidget(old);
    // O servidor ligou a receita ao pedido: acabou a espera.
    if (_aguardaLigacao && !p.estado.aEsperaDoCliente) {
      _relogioLigacao?.cancel();
      _aguardaLigacao = false;
      _ligacaoDemorou = false;
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _relogioLigacao?.cancel();
    _telefoneMbway.dispose();
    super.dispose();
  }

  void _mostrar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _esperarLigacao() {
    if (!mounted) return;
    setState(() {
      _aguardaLigacao = true;
      _ligacaoDemorou = false;
    });
    _relogioLigacao?.cancel();
    _relogioLigacao = Timer(const Duration(seconds: 40), () {
      if (mounted && _aguardaLigacao) setState(() => _ligacaoDemorou = true);
    });
  }

  Future<void> _confirmar({required bool soDisponiveis}) async {
    if (_aConfirmar || _aguardaLigacao) return;
    // Dinheiro e loja de demonstração: como antes (prescricao_confirmar).
    if (_metodo == 'cash' || p.isDemo) {
      setState(() => _aConfirmar = true);
      try {
        await _svc.confirmar(p.id, metodo: _metodo, soDisponiveis: soDisponiveis);
        if (mounted) setState(() => _recusaConfirmar = null);
      } catch (e) {
        _tratarErro(e);
      } finally {
        if (mounted) setState(() => _aConfirmar = false);
      }
      return;
    }
    if (_metodo == 'mbway') {
      await _pagarMbway(soDisponiveis: soDisponiveis);
    } else {
      await _pagarCartao(soDisponiveis: soDisponiveis);
    }
  }

  void _tratarErro(Object e) {
    final msg = PrescricaoService.mensagemDe(e);
    if (!mounted) return;
    // O PrescricaoErro já vem sem o código no texto: lê-se do campo `codigo`.
    if (PrescricaoService.codigoDe(e) == 'RECEITA_REAL_POR_LIGAR') {
      setState(() => _recusaConfirmar = msg);
    } else {
      _mostrar(msg);
    }
  }

  Future<void> _pagarCartao({required bool soDisponiveis}) async {
    setState(() => _aConfirmar = true);
    try {
      final r = await _pag.pagarComCartao(p.id, soDisponiveis: soDisponiveis);
      if (r == ResultadoCartaoReceita.cancelado) {
        _mostrar('Pagamento cancelado. Não foi cobrado nada.');
      } else {
        _mostrar('Pagamento aceite. A chamar o estafeta…');
        _esperarLigacao();
      }
    } catch (e) {
      _tratarErro(e);
    } finally {
      if (mounted) setState(() => _aConfirmar = false);
    }
  }

  Future<void> _pagarMbway({required bool soDisponiveis}) async {
    final tel = _telefoneMbway.text.replaceAll(RegExp(r'\D'), '');
    if (tel.length != 9) {
      _mostrar('Escreva o número do MB Way (9 algarismos).');
      return;
    }
    setState(() => _aConfirmar = true);
    try {
      final prep = await _pag.prepararMbway(p.id, soDisponiveis: soDisponiveis);
      if (prep.jaPago) {
        _esperarLigacao();
        return;
      }
      final pedido = await _pag.pedirMbway(prep.orderId, tel);
      if (!mounted) return;
      var pago = false;
      if (pedido.erro != null && !pedido.jaTratado) {
        // Não chegou ao MB WAY: o pedido fica cancelado sem custo e pode tentar outra vez.
        final c = await _pag.cancelarMbwayNaoPago(prep.orderId);
        if (c != CancelarMbway.jaPago) {
          _mostrar(c == CancelarMbway.falhou
              ? '${pedido.erro!}\nNão conseguimos cancelar por falta de rede: volte a este ecrã daqui a pouco.'
              : pedido.erro!);
          return;
        }
        pago = true;
      }
      if (!pago) {
        if (!mounted) return;
        pago = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => MbwayEsperaPedidoDialog(orderId: prep.orderId, amount: prep.cobrarCents / 100.0),
            ) ??
            false;
      }
      var cancelou = CancelarMbway.cancelado;
      if (!pago) {
        // O servidor recusa cancelar se o dinheiro entrou entretanto: aí segue como pago.
        cancelou = await _pag.cancelarMbwayNaoPago(prep.orderId);
        pago = cancelou == CancelarMbway.jaPago;
      }
      if (pago) {
        _mostrar('Pagamento MB WAY confirmado. A chamar o estafeta…');
        _esperarLigacao();
      } else if (cancelou == CancelarMbway.falhou) {
        _mostrar('O MB WAY não foi confirmado e não conseguimos cancelar por falta de rede. '
            'Não aprove o MB WAY se já não quiser; volte a este ecrã daqui a pouco.');
      } else {
        _mostrar('O MB WAY não foi confirmado. Não foi cobrado nada; pode tentar outra vez.');
      }
    } catch (e) {
      _tratarErro(e);
    } finally {
      if (mounted) setState(() => _aConfirmar = false);
    }
  }

  Future<void> _cancelarMbwayPendente() async {
    final id = p.pagamentoOrderId;
    if (id == null || _aConfirmar) return;
    setState(() => _aConfirmar = true);
    try {
      final c = await _pag.cancelarMbwayNaoPago(id);
      if (c == CancelarMbway.jaPago) {
        _mostrar('O pagamento MB WAY já tinha entrado. A chamar o estafeta…');
        _esperarLigacao();
      } else if (c == CancelarMbway.falhou) {
        _mostrar('Não conseguimos cancelar por falta de rede. Tente outra vez daqui a pouco.');
      } else {
        _mostrar('MB WAY cancelado. Não foi cobrado nada.');
      }
    } finally {
      if (mounted) setState(() => _aConfirmar = false);
    }
  }

  /// Abre o acompanhamento normal do pedido (mapa, estafeta, chat).
  Future<void> _acompanharEntrega(String orderId) async {
    if (_aAbrirPedido) return;
    setState(() => _aAbrirPedido = true);
    try {
      final row = await Supabase.instance.client.from('orders').select().eq('id', orderId).maybeSingle();
      if (!mounted) return;
      if (row == null) {
        _mostrar('Ainda não conseguimos abrir o pedido. Veja em "Pedidos".');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => OrderTrackingScreen(order: OrderModel.fromSupabase(row)),
      ));
    } catch (_) {
      _mostrar('Sem ligação. Tente outra vez daqui a pouco.');
    } finally {
      if (mounted) setState(() => _aAbrirPedido = false);
    }
  }

  Future<void> _cancelar() async {
    if (_aCancelar) return;
    final sim = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar o pedido?'),
        content: const Text('A farmácia deixa de o preparar. Não é cobrado nada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Não')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sim, cancelar')),
        ],
      ),
    );
    if (sim != true) return;
    setState(() => _aCancelar = true);
    try {
      await _svc.cancelar(p.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
      }
    } finally {
      if (mounted) setState(() => _aCancelar = false);
    }
  }

  void _enviarOutraVez() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PrescricaoEnviarScreen(
        restaurantId: p.restaurantId,
        farmaciaNome: widget.farmaciaNome,
        tipo: p.tipo,
        repetirDe: p,
      ),
    ));
  }

  // Material (e não Container com cor): os RadioListTile do pagamento pintam no
  // Material mais próximo (Flutter 3.47 avisa se houver uma caixa colorida pelo meio).
  Widget _cartao({required Widget child, Color? cor}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: cor ?? Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      );

  Widget _cabecalho(IconData icone, Color cor, String titulo, String? texto) {
    return _cartao(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: cor.withValues(alpha: 0.12), child: Icon(icone, color: cor)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(titulo,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
        ]),
        if (texto != null) ...[
          const SizedBox(height: 10),
          Text(texto, style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }

  Widget _linha(String a, String b, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: forte ? 17 : 15, fontWeight: forte ? FontWeight.w800 : FontWeight.w500))),
          Text(b, style: TextStyle(fontSize: forte ? 18 : 15, fontWeight: forte ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  Widget _valores() {
    final taxa = p.taxaServicoCents ?? widget.taxaServicoCents;
    final total = p.totalCents ?? ((p.valorMedicamentosCents ?? 0) + taxa);
    return _cartao(
      child: Column(children: [
        _linha(p.eReceita ? 'Medicamentos' : 'Produtos', eurosDeCents(p.valorMedicamentosCents)),
        _linha('Taxa do serviço (entrega)', eurosDeCents(taxa)),
        const Divider(height: 18),
        _linha('Total', eurosDeCents(total), forte: true),
      ]),
    );
  }

  Widget _pagamento() {
    Widget op(String v, IconData i, String t) => RadioListTile<String>(
          value: v,
          // ignore: deprecated_member_use
          groupValue: _metodo,
          // ignore: deprecated_member_use
          onChanged: (x) => setState(() => _metodo = x ?? _metodo),
          activeColor: AppColors.primary,
          contentPadding: EdgeInsets.zero,
          title: Row(children: [Icon(i, size: 20), const SizedBox(width: 8), Flexible(child: Text(t))]),
        );
    return _cartao(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Como quer pagar?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        op('card', Icons.credit_card, 'Cartão'),
        op('mbway', Icons.phone_iphone, 'MB Way'),
        if (_metodo == 'mbway')
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: TextField(
              key: const Key('prescricao_mbway_telefone'),
              controller: _telefoneMbway,
              keyboardType: TextInputType.phone,
              maxLength: 9,
              decoration: const InputDecoration(
                labelText: 'Número do MB Way',
                prefixText: '+351 ',
                counterText: '',
              ),
            ),
          ),
        op('cash', Icons.payments_outlined, 'Dinheiro na entrega'),
        // Igual a qualquer Favor com compra: cartão/MB Way cobram payment_buffer_total (margem
        // errand_buffer_multiplier). 17/11: a devolução automática da margem está DESLIGADA no
        // servidor (trg_excedente_preautorizacao), por isso o texto não promete devolver.
        if (!p.isDemo && _metodo != 'cash')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _metodo == 'card'
                  ? 'O cartão é cobrado com a margem do Favor, um pouco acima do total. Vê o valor exato antes de pagar.'
                  : 'O MB Way pede o valor com a margem do Favor, um pouco acima do total. Vê o valor exato na app MB WAY antes de aprovar.',
              key: const Key('prescricao_nota_margem'),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
      ]),
    );
  }

  Widget _faixaDemo() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: const Text(
          'Demonstração: nada foi cobrado e não foi chamado nenhum estafeta.',
          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
        ),
      );

  Widget _codigoGrande(String rotulo, String codigo, String ajuda) => _cartao(
        child: Column(children: [
          Text(rotulo, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(codigo,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8, color: AppColors.primaryDark)),
          ),
          const SizedBox(height: 6),
          Text(ajuda, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      );

  Widget? _fotoPequena() {
    final caminho = p.receitaFotoPath ?? p.pedidoFotoPath;
    if (caminho == null) return null;
    // app-15-11: o ecrã redesenha-se de 20 em 20 s; pede-se o link uma vez só.
    if (_fotoCaminho != caminho) {
      _fotoCaminho = caminho;
      _fotoUrl = _svc.urlAssinado(caminho);
    }
    return FutureBuilder<String?>(
      future: _fotoUrl,
      builder: (context, s) {
        final url = s.data;
        if (url == null) return const SizedBox.shrink();
        return _cartao(
          child: Row(children: [
            GestureDetector(
              onTap: () => BoraFotoEcraInteiro.abrir(context, urlOrPath: url, titulo: p.eReceita ? 'Receita' : 'Foto'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(p.eReceita ? 'A sua receita' : 'A foto que enviou')),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final agora = (widget.agora ?? DateTime.now)();
    final filhos = <Widget>[];
    final botoes = <Widget>[];

    if (p.isDemo && (p.estado == PrescricaoEstado.confirmado || p.estado == PrescricaoEstado.entregue)) {
      filhos.add(_faixaDemo());
    }

    switch (p.estado) {
      case PrescricaoEstado.enviado:
        final falta = p.expiraEm?.difference(agora);
        final min = falta == null ? null : (falta.inSeconds / 60).ceil().clamp(0, 999);
        filhos.add(_cabecalho(Icons.hourglass_top, AppColors.primary, 'Enviado à ${widget.farmaciaNome}',
            'A farmácia vai responder em poucos minutos se tem ${p.eReceita ? 'os seus medicamentos' : 'o que pediu'} e quanto custa.'
            '${min != null ? '\nSe não responder em $min min, avisamos e não é cobrado nada.' : ''}'));
        filhos.add(const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 6)));
        botoes.add(OutlinedButton(
          onPressed: _aCancelar ? null : _cancelar,
          child: Text(_aCancelar ? 'A cancelar…' : 'Cancelar pedido'),
        ));
        break;
      case PrescricaoEstado.aceite:
      case PrescricaoEstado.aceiteParcial:
        final parcial = p.estado == PrescricaoEstado.aceiteParcial;
        final extra = [
          if (parcial && (p.itensDisponiveis ?? '').isNotEmpty) 'Tem: ${p.itensDisponiveis}',
          if (p.tempoPreparacaoMin != null) 'Fica pronto em cerca de ${p.tempoPreparacaoMin} min.',
        ].join('\n');
        filhos.add(_cabecalho(
          Icons.check_circle,
          AppColors.success,
          parcial
              ? 'A farmácia tem parte do seu pedido'
              : (p.eReceita ? 'A farmácia tem os seus medicamentos' : 'A farmácia tem o que pediu'),
          extra.isEmpty ? null : extra,
        ));
        filhos.add(_valores());
        if (_recusaConfirmar != null) {
          filhos.add(_cartao(
            child: Row(children: [
              const Icon(Icons.storefront, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$_recusaConfirmar\nA farmácia já tem a sua resposta pronta: pode ir lá levantar.',
                  key: const Key('prescricao_recusa_confirmar'),
                ),
              ),
            ]),
          ));
          botoes.add(TextButton(onPressed: _aCancelar ? null : _cancelar, child: const Text('Cancelar pedido')));
          break;
        }
        if (_aguardaLigacao) {
          filhos.add(_cartao(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _ligacaoDemorou
                    ? 'O pagamento entrou mas o pedido ainda não apareceu. Veja em "Pedidos" daqui a pouco; se não aparecer, fale connosco no chat de ajuda.'
                    : 'Pagamento recebido. A chamar o estafeta…',
                key: const Key('prescricao_aguarda_ligacao'),
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              if (!_ligacaoDemorou) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 6),
              ],
            ]),
          ));
          break;
        }
        if (p.mbwayPorConcluir) {
          // Voltou ao ecrã com um MB Way por aprovar: o mesmo pedido, nunca outro.
          filhos.add(_cartao(
            child: Text(
              'Tem um pagamento MB WAY por aprovar. Abra a app MB WAY e aprove, ou peça outra vez.',
              key: const Key('prescricao_mbway_pendente'),
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ));
          _metodo = 'mbway';
          filhos.add(_pagamento());
          botoes.add(BoraPrimaryButton(
            label: 'Pedir o MB WAY outra vez',
            icon: Icons.phone_iphone,
            loading: _aConfirmar,
            onPressed: _aConfirmar ? null : () => _confirmar(soDisponiveis: p.soDisponiveis ?? true),
          ));
          botoes.add(TextButton(
            onPressed: _aConfirmar ? null : _cancelarMbwayPendente,
            child: const Text('Cancelar este MB WAY'),
          ));
          break;
        }
        filhos.add(_pagamento());
        botoes.add(BoraPrimaryButton(
          label: parcial ? 'Quero só o que há' : 'Confirmar e pagar',
          icon: Icons.check,
          loading: _aConfirmar,
          onPressed: _aConfirmar ? null : () => _confirmar(soDisponiveis: true),
        ));
        botoes.add(TextButton(onPressed: _aCancelar ? null : _cancelar, child: const Text('Cancelar')));
        break;
      case PrescricaoEstado.recusado:
        final motivo = [PrescricaoMotivo.rotulo(p.motivoRecusa), if ((p.motivoTexto ?? '').isNotEmpty) p.motivoTexto!]
            .where((x) => x.isNotEmpty)
            .join(' — ');
        filhos.add(_cabecalho(Icons.info_outline, AppColors.warning, 'A farmácia não tem o seu pedido',
            '${motivo.isEmpty ? '' : 'Motivo: $motivo\n'}${(p.voltaATer ?? '').isNotEmpty ? 'Volta a ter: ${p.voltaATer}\n' : ''}Não foi cobrado nada.'));
        botoes.add(OutlinedButton(onPressed: _enviarOutraVez, child: const Text('Enviar outra vez')));
        break;
      case PrescricaoEstado.expirado:
        filhos.add(_cabecalho(Icons.timer_off_outlined, AppColors.textSecondary, 'A farmácia não respondeu a tempo',
            'Não foi cobrado nada. Pode enviar outra vez.'));
        botoes.add(BoraPrimaryButton(label: 'Enviar outra vez', icon: Icons.refresh, onPressed: _enviarOutraVez));
        break;
      case PrescricaoEstado.cancelado:
        filhos.add(_cabecalho(Icons.cancel_outlined, AppColors.textSecondary, 'Pedido cancelado', 'Não foi cobrado nada.'));
        botoes.add(OutlinedButton(onPressed: _enviarOutraVez, child: const Text('Enviar outra vez')));
        break;
      case PrescricaoEstado.confirmado:
      case PrescricaoEstado.entregue:
        final entregue = p.estado == PrescricaoEstado.entregue;
        // app-15-11: em demonstração não há estafeta nem cobrança — nada de
        // "pagamento" nem de código "para dar ao estafeta".
        filhos.add(_cabecalho(Icons.verified, AppColors.success, entregue ? 'Entregue' : 'Pedido confirmado',
            entregue
                ? null
                : p.isDemo
                    ? 'A farmácia vê o pedido como teste.'
                    : 'A farmácia já está a preparar. Pagamento: ${_rotuloMetodo(p.metodoPagamento)}.'));
        if (!entregue && !p.isDemo && (p.codigoEntrega ?? '').isNotEmpty) {
          filhos.add(_codigoGrande('Código de entrega', p.codigoEntrega!, 'Diga este código ao estafeta quando ele chegar.'));
        }
        if ((p.codigoLevantamento ?? '').isNotEmpty) {
          filhos.add(_cartao(
            child: Row(children: [
              const Icon(Icons.qr_code_2, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('Código de levantamento na farmácia: ${p.codigoLevantamento}')),
            ]),
          ));
        }
        filhos.add(_valores());
        final pedidoReal = p.orderId;
        if (!entregue && !p.isDemo && pedidoReal != null && pedidoReal.isNotEmpty) {
          botoes.add(BoraPrimaryButton(
            key: const Key('prescricao_acompanhar_entrega'),
            label: 'Acompanhar a entrega',
            icon: Icons.delivery_dining,
            loading: _aAbrirPedido,
            onPressed: _aAbrirPedido ? null : () => _acompanharEntrega(pedidoReal),
          ));
        }
        botoes.add(OutlinedButton.icon(
          onPressed: () => LembreteMensalSheet.abrir(context,
              restaurantId: p.restaurantId, farmaciaNome: widget.farmaciaNome, prescricaoId: p.id),
          icon: const Icon(Icons.event_repeat),
          label: const Text('Repetir todos os meses'),
        ));
        // app-15-11: o lembrete mensal ("Toque para pedir outra vez") abre este
        // ecrã; tem de haver um botão para pedir outra vez.
        botoes.add(TextButton.icon(
          key: const Key('prescricao_pedir_outra_vez'),
          onPressed: _enviarOutraVez,
          icon: const Icon(Icons.refresh),
          label: const Text('Pedir outra vez'),
        ));
        break;
    }

    final foto = _fotoPequena();
    if (foto != null) filhos.add(foto);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ...filhos,
        const SizedBox(height: 4),
        for (final b in botoes) Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(width: double.infinity, child: b)),
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
      ],
    );
  }

  static String _rotuloMetodo(String? m) {
    switch (m) {
      case 'card':
        return 'cartão';
      case 'mbway':
        return 'MB Way';
      case 'cash':
        return 'dinheiro na entrega';
      default:
        return '—';
    }
  }
}
