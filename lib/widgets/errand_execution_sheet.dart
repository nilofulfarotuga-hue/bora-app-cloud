// FAVORES — Fase 4 — Bottom-sheet de execução do estafeta.
// 3 fases sequenciais:
//   1. Recolha (se home_stop): confirmar receita/cartão/dinheiro. Se dinheiro,
//      input do valor + S1/N5 aviso quando cash < estimativa.
//   2. Compra (se has_purchase): foto talão obrigatória + valor digitado →
//      RPC finalize_errand_purchase (escreve final_total via GUC bypass).
//   3. Entrega: mostra "valor a cobrar" (cash), "troco a devolver"
//      (paragem+dinheiro) ou "nada a cobrar" (cartão/MBWay).
// Status mapping (N6):
//   driverAccepted = a caminho do 1º ponto (casa ou favor)
//   pickedUp       = saiu do local do favor (após compra/recolha)
//   onTheWay       = a caminho da entrega
//   delivered      = entregue (advance pelo botão final)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/talao_pendente_service.dart';
import '../stores/order_store.dart';
import 'driver_invoice_nif_card.dart';
import 'favor_teto_compra_card.dart';
import 'private_bucket_image.dart';
import '../utils/safe_image_picker.dart';

enum _Phase { collect, purchase, deliver, done }

class ErrandExecutionSheet extends StatefulWidget {
  const ErrandExecutionSheet({super.key, required this.order});
  final OrderModel order;

  static Future<void> show(BuildContext context, OrderModel order) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ErrandExecutionSheet(order: order),
    );
  }

  @override
  State<ErrandExecutionSheet> createState() => _ErrandExecutionSheetState();
}

class _ErrandExecutionSheetState extends State<ErrandExecutionSheet> {
  late _Phase _phase;
  final _cashReceivedCtrl = TextEditingController();
  final _talaoTotalCtrl = TextEditingController();
  File? _receiptPhoto;

  /// M1 08/11/2026 ("toda foto de talão ... nunca se pode perder"): a foto do
  /// talão vai para a fila do telemóvel ANTES de subir, com o mesmo fotoId em
  /// todas as tentativas (o servidor não duplica nem substitui).
  TalaoPendente? _talaoPendente;
  bool _busy = false;
  String? _error;

  bool _disputed = false; // retorno do finalize (talão acima do autorizado)

  // M1 08/11/2026 — tecto da compra + aprovação do cliente vivem no
  // FavorTetoCompraCard (errand_teto_compra); a folha só lê o controlador
  // para ligar/desligar o "Confirmar compra".
  final _tetoCtrl = FavorTetoController();

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _phase = o.errandHomeStop
        ? _Phase.collect
        : (o.errandHasPurchase ? _Phase.purchase : _Phase.deliver);
    if (o.errandHasPurchase) unawaited(_reporTalaoGuardado());
  }

  /// M1 08/11/2026: a app fechou depois da foto do talão → ao reabrir a folha
  /// a foto guardada no telemóvel volta (e o valor, se o campo está vazio).
  /// "Tirar nova foto" continua a funcionar: a nova fica como extra.
  Future<void> _reporTalaoGuardado() async {
    await TalaoPendenteService.carregar();
    final t = TalaoPendenteService.ultimoDo(widget.order.id);
    if (t == null || !mounted || _receiptPhoto != null) return;
    setState(() {
      _talaoPendente = t;
      _receiptPhoto = File(t.localPath);
      if (_talaoTotalCtrl.text.trim().isEmpty && t.totalCents > 0) {
        _talaoTotalCtrl.text =
            (t.totalCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      }
    });
  }

  @override
  void dispose() {
    _tetoCtrl.dispose();
    _cashReceivedCtrl.dispose();
    _talaoTotalCtrl.dispose();
    super.dispose();
  }

  int get _cashReceivedCents {
    final raw = _cashReceivedCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw) ?? 0;
    return (v * 100).round();
  }

  int get _talaoCents {
    final raw = _talaoTotalCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw) ?? 0;
    return (v * 100).round();
  }

  /// [ronda 04/10 · app-estafeta #9] Câmara protegida contra dois toques
  /// (SafeImagePicker ignora o segundo em vez de rebentar com
  /// `already_active`) e sem setState depois de a folha fechar.
  Future<void> _pickReceipt() async {
    XFile? x;
    try {
      x = await SafeImagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
    } catch (e) {
      debugPrint('[favor] câmara: $e');
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir a câmara. Tenta de novo.');
      }
      return;
    }
    if (x == null || !mounted) return;
    final path = x.path;
    setState(() {
      _receiptPhoto = File(path);
      // Foto nova = entrada nova na fila; a anterior (se já foi guardada)
      // continua lá e sobe como extra.
      _talaoPendente = null;
    });
  }

  Future<void> _confirmCollect() async {
    final o = widget.order;
    final isCashStop = o.errandHomeStopReason == 'dinheiro';

    // S1 / N5 — aviso (não bloqueia) se cash recebido < estimativa
    if (isCashStop && o.errandHasPurchase) {
      if (_cashReceivedCents <= 0) {
        setState(() => _error = 'Indica o dinheiro que recebeste do cliente.');
        return;
      }
      if (_cashReceivedCents < o.errandEstimatedPurchaseCents) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar valor'),
            content: Text(
              'Recebeste €${(_cashReceivedCents / 100).toStringAsFixed(2)} '
              'mas a compra estimada é ~€${(o.errandEstimatedPurchaseCents / 100).toStringAsFixed(2)}.\n\n'
              'Pode ser que o cliente tenha decidido comprar menos. Confirmas?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Corrigir'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
        if (go != true) return;
      }
    }

    // Persiste cash recebido e avança para o próximo estado.
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (isCashStop && _cashReceivedCents > 0) {
        final res = await Supabase.instance.client.rpc(
          'estafeta_registar_dinheiro_paragem',
          params: {'p_order_id': o.id, 'p_cents': _cashReceivedCents},
        );
        if (res is! Map || res['ok'] != true) {
          throw Exception('dinheiro da paragem não gravado: $res');
        }
      }
      // Avança estado: driverAccepted → pickedUp se há compra; senão → onTheWay
      if (!mounted) return;
      final store = context.read<OrderStore>();
      if (o.errandHasPurchase) {
        await store.markErrandArrivedAtErrand(o);
        if (!mounted) return;
        setState(() => _phase = _Phase.purchase);
      } else {
        await store.markErrandOnTheWay(o);
        if (!mounted) return;
        setState(() => _phase = _Phase.deliver);
      }
    } catch (e) {
      debugPrint('[favor] confirmar recolha: $e');
      if (mounted) {
        setState(() => _error =
            'Não foi possível guardar. Verifica a ligação e tenta de novo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalizePurchase() async {
    final o = widget.order;
    if (_receiptPhoto == null) {
      setState(() => _error = 'Tira foto do talão.');
      return;
    }
    if (_talaoCents <= 0) {
      setState(() => _error = 'Indica o valor exacto do talão.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // M1 08/11/2026: primeiro no telemóvel, depois no servidor (mesmo
      // fotoId em todas as tentativas). Falhou → fica guardada, sobe sozinha
      // e o próximo "Confirmar compra" reenvia a MESMA foto.
      var talao = _talaoPendente;
      if (talao == null) {
        talao = await TalaoPendenteService.guardar(
          orderId: o.id,
          foto: _receiptPhoto!,
          totalCents: _talaoCents,
        );
        _talaoPendente = talao;
      }
      final path = (talao.enviado ? talao.path : null) ??
          await TalaoPendenteService.enviar(talao);
      final atual = TalaoPendenteService.porFotoId(talao.fotoId) ?? talao;
      if (!mounted) return;
      if (path == null) {
        setState(() {
          if (atual.estado == TalaoPendente.estadoSemFicheiro) {
            _talaoPendente = null;
            _receiptPhoto = null; // pede outra foto
          }
          _error = TalaoPendenteService.avisoNaoEnviado(atual);
        });
        return;
      }
      // "Talão guardado no servidor ✓" aparece debaixo da foto.
      setState(() => _talaoPendente = atual);
      // Chama a RPC criada na Fase 2.C — escreve final_total/final_purchase
      // via GUC bypass, dispara ocr-receipt + charge-extra se buffer ultrapassado.
      final res = await Supabase.instance.client.rpc(
        'finalize_errand_purchase',
        params: {
          'p_order_id': o.id,
          'p_driver_typed_total_cents': _talaoCents,
          'p_receipt_photo_url': path,
        },
      );
      // 8.2 — talão acima do autorizado sem consentimento → disputa admin.
      final disputed = res is Map && res['dispute'] == true;
      if (!mounted) return;
      await context.read<OrderStore>().markErrandOnTheWay(o);
      setState(() {
        _disputed = disputed;
        _phase = _Phase.deliver;
      });
    } catch (e) {
      debugPrint('[favor] finalizar compra: $e');
      if (mounted) {
        setState(() => _error =
            'Não foi possível fechar a compra. Verifica a ligação e tenta de novo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markDelivered() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<OrderStore>().markErrandDelivered(widget.order);
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      Navigator.pop(context);
    } catch (e) {
      debugPrint('[favor] marcar entregue: $e');
      if (mounted) {
        setState(() => _error =
            'Não foi possível marcar como entregue. Tenta de novo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Cálculo do que cobrar / devolver na entrega
  ({String label, double amount, bool isRefund}) _deliveryAmount() {
    final o = widget.order;
    if (o.paymentMethod != PaymentMethod.cash) {
      return (label: 'Nada a cobrar', amount: 0, isRefund: false);
    }
    // Paragem-casa modo dinheiro: estafeta tem o dinheiro do cliente, devolve troco
    if (o.errandHomeStop && o.errandHomeStopReason == 'dinheiro') {
      final received = (o.errandHomeStopCashCents ?? _cashReceivedCents) / 100.0;
      final talao = (_talaoCents > 0
              ? _talaoCents
              : (o.finalPurchaseValue ?? 0) * 100)
          .toDouble() /
          100.0;
      // Cobra taxas, devolve troco da diferença
      final fees = o.deliveryFee;
      final change = received - talao;
      final netToReturn = change - fees;
      return netToReturn >= 0
          ? (label: 'Devolver ao cliente', amount: netToReturn, isRefund: true)
          : (label: 'Cobrar ao cliente', amount: -netToReturn, isRefund: false);
    }
    // Cash normal: cobra total
    return (
      label: 'Cobrar ao cliente',
      amount: o.finalTotal ?? o.total,
      isRefund: false
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(order: o, phase: _phase),
              const SizedBox(height: 16),
              if (_phase == _Phase.collect) _buildCollect(o),
              if (_phase == _Phase.purchase) _buildPurchase(o),
              if (_phase == _Phase.deliver) _buildDeliver(o),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Fase 1: recolha ───────────────────────────────────────────────────
  Widget _buildCollect(OrderModel o) {
    final reason = o.errandHomeStopReason ?? 'outro';
    final isCash = reason == 'dinheiro';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('1. Recolha em casa do cliente',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Motivo: ${_reasonLabel(reason)}'),
        if (isCash) ...[
          const SizedBox(height: 12),
          Text(
            'Estimativa da compra: '
            '~€${(o.errandEstimatedPurchaseCents / 100).toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cashReceivedCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Dinheiro recebido do cliente',
              prefixText: '€ ',
            ),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _confirmCollect,
          child: Text(_busy ? 'A guardar…' : 'Confirmar recolha'),
        ),
      ],
    );
  }

  // ── Fase 2: compra na loja ────────────────────────────────────────────
  Widget _buildPurchase(OrderModel o) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('2. Compra na loja',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(o.errandLocation ?? 'Local do favor',
            style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        // M1 08/11/2026 — "Podes comprar até X €" + "O preço é maior" +
        // contagem do prazo do cliente + resposta (errand_teto_compra).
        FavorTetoCompraCard(order: o, controller: _tetoCtrl),
        const SizedBox(height: 12),
        // 8.1 — foto que o cliente enviou do que comprar (opcional).
        if (o.errandRequestPhotoUrl != null &&
            o.errandRequestPhotoUrl!.isNotEmpty) ...[
          const Text('Foto do cliente (o que comprar)',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          PrivateBucketImage(
            urlOrPath: o.errandRequestPhotoUrl!,
            height: 160,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 12),
        ],
        // M1 08/11/2026 — NIF da fatura (loja não-parceira; esconde-se sozinho).
        if (!o.isPartnerStore) ...[
          DriverInvoiceNifCard(orderId: o.id),
          const SizedBox(height: 12),
        ],
        if (_receiptPhoto == null)
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickReceipt,
            icon: const Icon(Icons.photo_camera),
            label: const Text('Tirar foto do talão (obrigatório)'),
          )
        else
          Stack(alignment: Alignment.topRight, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_receiptPhoto!,
                  height: 180, fit: BoxFit.cover),
            ),
            IconButton(
              onPressed: _pickReceipt,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Tirar nova foto',
            ),
          ]),
        if (_talaoPendente?.enviado ?? false) ...[
          const SizedBox(height: 6),
          const Text('Talão guardado no servidor ✓',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success)),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _talaoTotalCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Total no talão',
            prefixText: '€ ',
          ),
        ),
        const SizedBox(height: 16),
        // M1 08/11: aprovação pendente de MB Way ou Favor a cancelar desligam
        // o botão (o fecho da compra em si não muda).
        ListenableBuilder(
          listenable: Listenable.merge([_tetoCtrl, _talaoTotalCtrl]),
          builder: (context, _) {
            final motivo = _tetoCtrl.motivoBloqueio(_talaoCents);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed:
                      _busy || motivo != null ? null : _finalizePurchase,
                  child: Text(_busy ? 'A enviar…' : 'Confirmar compra'),
                ),
                if (motivo != null) ...[
                  const SizedBox(height: 6),
                  Text(motivo,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // ── Fase 3: entrega ───────────────────────────────────────────────────
  Widget _buildDeliver(OrderModel o) {
    final d = _deliveryAmount();
    final color = d.amount == 0
        ? AppColors.textSecondary
        : (d.isRefund ? AppColors.warning : AppColors.success);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('3. Entrega',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        // 8.2 — talão acima do autorizado: em revisão pelo suporte (não cobrar).
        if (_disputed) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning),
            ),
            child: const Text(
              'Valor acima do autorizado — em revisão pelo suporte. '
              'Não cobres o extra ao cliente.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.label, style: TextStyle(color: color, fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                '€${d.amount.toStringAsFixed(2)}',
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _markDelivered,
          child: Text(_busy ? 'A guardar…' : 'Marcar como entregue'),
        ),
      ],
    );
  }

  static String _reasonLabel(String r) {
    switch (r) {
      case 'receita':
        return 'Receita médica';
      case 'cartao':
        return 'Cartão de crédito';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return 'Outro';
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.phase});
  final OrderModel order;
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14B8A6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('FAVOR',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                if (order.errandSpeed == 'express') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('EXPRESSO',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Text(
                order.errandDescription ?? 'Favor',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
