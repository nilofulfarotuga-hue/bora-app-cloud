// 8.2 — Banner de autorização de orçamento (cliente).
// Aparece SÓ quando errand com compra está com `errand_budget_status='pending'`
// (estafeta pediu aumento ANTES de comprar — timing A).
//
// [08/11/2026 · m1-dinheiro-favores] Aprovação com tecto: lê
// `errand_teto_compra` e, com um pedido de aprovação `pendente`, mostra o
// preço da loja, o tecto, a foto da etiqueta, a contagem decrescente e três
// botões (Aprovar / Comprar só até X / Cancelar Favor) → RPC
// `cliente_favor_responder`. Ao responder cala o toque persistente
// (IncomingJobAlert). Se o servidor ainda não tiver as funções novas (ou o
// pedido vier do fluxo antigo), fica o cartão antigo de dois botões com
// `client_respond_budget_increase` — nada se parte antes do deploy.
// Self-contained: seguro para montar em qualquer ecrã que tenha a OrderModel viva.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/incoming_job_alert.dart';
import '../utils/euros.dart';
import 'private_bucket_image.dart';

import '../l10n/tr.dart';

class ErrandBudgetBanner extends StatefulWidget {
  const ErrandBudgetBanner({
    super.key,
    required this.order,
    this.lerTeto,
    this.responder,
  });
  final OrderModel order;

  /// Só para testes.
  final Future<Map<String, dynamic>> Function(String pedidoId)? lerTeto;
  final Future<Map<String, dynamic>> Function(String pedidoId, String resposta)?
      responder;

  static Future<Map<String, dynamic>> lerTetoDoServidor(String pedidoId) async {
    final r = await Supabase.instance.client
        .rpc('errand_teto_compra', params: {'p_order_id': pedidoId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> responderNoServidor(
      String pedidoId, String resposta) async {
    final r = await Supabase.instance.client.rpc('cliente_favor_responder',
        params: {'p_order_id': pedidoId, 'p_resposta': resposta});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  @override
  State<ErrandBudgetBanner> createState() => _ErrandBudgetBannerState();
}

class _ErrandBudgetBannerState extends State<ErrandBudgetBanner> {
  bool _responded = false;
  bool _busy = false;

  // ── Aprovação com tecto (08/11/2026) ────────────────────────────────────
  Map<String, dynamic>? _teto;
  bool _aCarregar = false;
  bool _rpcFalhou = false;
  String? _aResponder;
  String? _resultado;
  bool _resultadoOk = true;
  DateTime? _fim;
  Timer? _relogio;

  bool get _precisaDeLer =>
      widget.order.serviceType == OrderServiceType.errand &&
      widget.order.errandBudgetStatus == 'pending';

  @override
  void initState() {
    super.initState();
    if (_precisaDeLer) _ler();
  }

  @override
  void didUpdateWidget(covariant ErrandBudgetBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.order;
    final b = widget.order;
    if (a.id == b.id &&
        a.errandBudgetStatus == b.errandBudgetStatus &&
        a.errandBudgetRequestedCents == b.errandBudgetRequestedCents) {
      return;
    }
    if (a.id != b.id) {
      _resultado = null;
      _responded = false;
      _teto = null;
    }
    if (_precisaDeLer) {
      // Pedido novo do estafeta (ou outro pedido): volta ao início.
      _resultado = null;
      _responded = false;
      _busy = false;
      _teto = null;
      _ler();
    } else {
      _pararRelogio();
    }
  }

  @override
  void dispose() {
    _pararRelogio();
    super.dispose();
  }

  Future<void> _ler() async {
    final pedido = widget.order.id;
    _aCarregar = true;
    Map<String, dynamic>? r;
    try {
      r = await (widget.lerTeto ?? ErrandBudgetBanner.lerTetoDoServidor)(pedido);
    } catch (_) {
      r = null; // sem a função no servidor ou sem rede: cartão antigo
    }
    if (!mounted || widget.order.id != pedido) return;
    final lido = r;
    final ok = lido != null && lido['ok'] == true;
    setState(() {
      _aCarregar = false;
      _teto = ok ? lido : null;
      _rpcFalhou = !ok;
      _armarRelogio();
    });
  }

  Map<String, dynamic>? get _aprovacao {
    final a = _teto?['aprovacao'];
    return a is Map ? Map<String, dynamic>.from(a) : null;
  }

  int get _pedidoCents =>
      (_aprovacao?['pedido_cents'] as num?)?.toInt() ??
      widget.order.errandBudgetRequestedCents ??
      0;

  int get _tetoCents =>
      (_aprovacao?['teto_cents'] as num?)?.toInt() ??
      (_teto?['teto_cents'] as num?)?.toInt() ??
      0;

  bool get _eMbway {
    final m = _teto?['metodo'];
    if (m is String && m.isNotEmpty) return m == 'mbway';
    return widget.order.paymentMethod == PaymentMethod.mbway;
  }

  int get _segundosRestantes {
    final fim = _fim;
    if (fim == null) return 0;
    final ms = fim.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// O prazo vem em `segundos_restantes` (contado no servidor — não depende
  /// do relógio do telemóvel); sem ele usa `expira_em`.
  void _armarRelogio() {
    _pararRelogio();
    final a = _aprovacao;
    if (a == null || a['estado'] != 'pendente') {
      _fim = null;
      return;
    }
    final seg = (a['segundos_restantes'] as num?)?.toInt();
    if (seg != null) {
      _fim = DateTime.now().add(Duration(seconds: seg));
    } else {
      _fim = DateTime.tryParse('${a['expira_em'] ?? ''}');
    }
    if (_fim == null || _segundosRestantes <= 0) return;
    _relogio = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_segundosRestantes <= 0) t.cancel();
      setState(() {});
    });
  }

  void _pararRelogio() {
    _relogio?.cancel();
    _relogio = null;
  }

  String _mmss(int segundos) {
    final m = (segundos ~/ 60).toString().padLeft(2, '0');
    final s = (segundos % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<bool> _confirmarCancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar o Favor?'.tr),
        content: Text(
            'O estafeta não compra nada e pedimos ao suporte para fechar o teu Favor.'
                .tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar'.tr),
          ),
          TextButton(
            key: const Key('btn_favor_cancelar_confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('Cancelar Favor'.tr),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _responder(String resposta) async {
    if (_busy) return;
    if (resposta == 'cancelar') {
      final confirmou = await _confirmarCancelar();
      if (!mounted) return;
      if (!confirmou) return;
    }
    final pedido = widget.order.id;
    setState(() {
      _busy = true;
      _aResponder = resposta;
    });
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> r;
    try {
      r = await (widget.responder ?? ErrandBudgetBanner.responderNoServidor)(
          pedido, resposta);
    } catch (_) {
      r = const {'ok': false, 'error': 'rede'};
    }
    if (!mounted) return;
    if (r['ok'] == true) {
      unawaited(IncomingJobAlert.dismiss(idAlertaFavorAprovacao(pedido)));
      _pararRelogio();
      setState(() {
        _busy = false;
        _aResponder = null;
        _resultadoOk = resposta != 'cancelar';
        _resultado = _textoDoResultado(resposta, r);
      });
      return;
    }
    final erro = '${r['error'] ?? ''}';
    final msg = switch (erro) {
      'sem_pedido_pendente' => 'Este pedido de aprovação já foi respondido.'.tr,
      'pedido_fechado' => 'Este Favor já terminou.'.tr,
      _ => 'Não foi possível responder. Tenta outra vez.'.tr,
    };
    setState(() {
      _busy = false;
      _aResponder = null;
    });
    messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    if (erro == 'sem_pedido_pendente' || erro == 'pedido_fechado') {
      unawaited(IncomingJobAlert.dismiss(idAlertaFavorAprovacao(pedido)));
      unawaited(_ler());
    }
  }

  String _textoDoResultado(String resposta, Map<String, dynamic> r) {
    switch (resposta) {
      case 'aprovar':
        return _eMbway
            ? 'Aprovado. Se pagaste por MB Way, aprova também o pedido que chega à app MB Way.'
                .tr
            : 'Aprovado. O estafeta já pode comprar.'.tr;
      case 'so_ate_teto':
        final doServidor = (r['teto_cents'] as num?)?.toInt() ?? 0;
        final teto = doServidor > 0 ? doServidor : _tetoCents;
        return 'Combinado: o estafeta compra só até {0}.'
            .trArgs([eurCents(teto)]);
      default:
        return 'Pedimos o cancelamento do teu Favor. O suporte vai fechar o pedido.'
            .tr;
    }
  }

  // ── Fluxo antigo (antes do deploy do servidor) ──────────────────────────
  Future<void> _respond(bool approve) async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'client_respond_budget_increase',
        params: {'p_order_id': widget.order.id, 'p_approve': approve},
      );
      if (!mounted) return;
      unawaited(
          IncomingJobAlert.dismiss(idAlertaFavorAprovacao(widget.order.id)));
      setState(() => _responded = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? 'Compra maior autorizada. O estafeta vai prosseguir.'.tr
            : 'Recusaste. O estafeta não vai comprar.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Não foi possível responder: {0}'.trArgs([e.toString().replaceFirst('Exception: ', '')])),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    if (o.serviceType != OrderServiceType.errand) {
      return const SizedBox.shrink();
    }
    final resultado = _resultado;
    if (resultado != null) return _cartaoResultado(resultado);
    if (_responded || o.errandBudgetStatus != 'pending') {
      return const SizedBox.shrink();
    }
    final a = _aprovacao;
    if (a != null && a['estado'] == 'pendente') {
      return _cartaoAprovacao(context, a);
    }
    // A ler o servidor pela 1.ª vez: não pisca o cartão antigo.
    if (_aCarregar && _teto == null && !_rpcFalhou) {
      return const SizedBox.shrink();
    }
    return _cartaoAntigo(context);
  }

  Widget _cartaoResultado(String texto) {
    return Container(
      key: const Key('favor_aprovacao_resultado'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              _resultadoOk ? Icons.check_circle_outline : Icons.info_outline,
              color: AppColors.primary,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 14, height: 1.35, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _cartaoAprovacao(BuildContext context, Map<String, dynamic> a) {
    final pedido = eurCents(_pedidoCents);
    final teto = eurCents(_tetoCents);
    final foto = '${a['foto_url'] ?? ''}'.trim();
    final restantes = _segundosRestantes;
    final temRelogio = _fim != null;
    final acabou = temRelogio && restantes <= 0;

    Widget aCarregar() => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

    return Container(
      key: const Key('favor_aprovacao_banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aprova o preço do teu Favor'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'O estafeta está na loja: o total é {0} (podia comprar até {1}).'
                .trArgs([pedido, teto]),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          if (foto.isNotEmpty) ...[
            const SizedBox(height: 10),
            PrivateBucketImage(
              key: const Key('favor_aprovacao_foto'),
              urlOrPath: foto,
              height: 180,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(12),
              tituloAmpliada: 'Foto da etiqueta'.tr,
            ),
          ],
          if (temRelogio) ...[
            const SizedBox(height: 10),
            if (acabou)
              Text(
                'O tempo acabou — o estafeta pode comprar só até {0} ou cancelar.'
                    .trArgs([teto]),
                key: const Key('favor_aprovacao_tempo_acabou'),
                style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error),
              )
            else
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tens {0} para responder.'.trArgs([_mmss(restantes)]),
                      key: const Key('favor_aprovacao_contagem'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('btn_favor_aprovar'),
            onPressed: _busy ? null : () => _responder('aprovar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _aResponder == 'aprovar'
                ? aCarregar()
                : Text('Aprovar {0}'.trArgs([pedido])),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('btn_favor_so_ate_teto'),
            onPressed: _busy ? null : () => _responder('so_ate_teto'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(48),
            ),
            child: _aResponder == 'so_ate_teto'
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Comprar só até {0}'.trArgs([teto])),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('btn_favor_cancelar'),
            onPressed: _busy ? null : () => _responder('cancelar'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: _aResponder == 'cancelar'
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Cancelar Favor'.tr),
          ),
        ],
      ),
    );
  }

  Widget _cartaoAntigo(BuildContext context) {
    final o = widget.order;
    final requested = (o.errandBudgetRequestedCents ?? 0) / 100.0;
    final estimated = o.errandEstimatedPurchaseCents / 100.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Autorizar compra maior?'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'O estafeta precisa de ~€{0} (orçaste €{1}). Pagas o valor do talão.'.trArgs([requested.toStringAsFixed(2), estimated.toStringAsFixed(2)]),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  child: Text('Recusar'.tr),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Autorizar'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
