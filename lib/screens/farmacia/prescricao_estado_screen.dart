// Estado de um pedido de receita / pedido especial (missão farmacias-2026-11-11).
// Acompanha em tempo real: a resposta da farmácia aparece em segundos.
// Aceite → valores + pagamento (cartão, MB Way, dinheiro) + confirmar.
// Recusado/expirado → motivo e "não foi cobrado nada". Confirmado → códigos.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/prescricao_service.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora_foto_ecra_inteiro.dart';
import '../../widgets/farmacia/lembrete_mensal_sheet.dart';
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
    this.agora,
  });

  final PedidoPrescricao pedido;
  final int taxaServicoCents;
  final String farmaciaNome;
  final PrescricaoService? service;
  final DateTime Function()? agora;

  @override
  State<PrescricaoEstadoCorpo> createState() => _PrescricaoEstadoCorpoState();
}

class _PrescricaoEstadoCorpoState extends State<PrescricaoEstadoCorpo> {
  String _metodo = 'card';
  bool _aConfirmar = false;
  bool _aCancelar = false;
  Timer? _relogio;

  PrescricaoService get _svc => widget.service ?? PrescricaoService();
  PedidoPrescricao get p => widget.pedido;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && p.estado.aEsperaDaFarmacia) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _confirmar({required bool soDisponiveis}) async {
    if (_aConfirmar) return;
    setState(() => _aConfirmar = true);
    try {
      await _svc.confirmar(p.id, metodo: _metodo, soDisponiveis: soDisponiveis);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
      }
    } finally {
      if (mounted) setState(() => _aConfirmar = false);
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
        op('cash', Icons.payments_outlined, 'Dinheiro na entrega'),
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
    return FutureBuilder<String?>(
      future: _svc.urlAssinado(caminho),
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
        filhos.add(_cabecalho(Icons.verified, AppColors.success, entregue ? 'Entregue' : 'Pedido confirmado',
            entregue ? null : 'A farmácia já está a preparar. Pagamento: ${_rotuloMetodo(p.metodoPagamento)}.'));
        if (!entregue && (p.codigoEntrega ?? '').isNotEmpty) {
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
        botoes.add(OutlinedButton.icon(
          onPressed: () => LembreteMensalSheet.abrir(context,
              restaurantId: p.restaurantId, farmaciaNome: widget.farmaciaNome, prescricaoId: p.id),
          icon: const Icon(Icons.event_repeat),
          label: const Text('Repetir todos os meses'),
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
