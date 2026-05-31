// BLOCO 3.6 — Driver UI para storeShopping não-parceiro v2.
//
// Fluxo:
//   1. Estafeta chega à loja → vê lista de items.
//   2. Marca cada item: ✅ Comprei | ❌ Não tem | 🔄 Substituir | ➕ Adicionar.
//   3. Se substituição/adição diff > €5 (Decisão J) → exige chat com cliente.
//   4. Tira foto do talão (Decisão G: SÓ câmara, sem galeria).
//   5. Digita valor total pago no caixa.
//   6. Chama finalize_storeshopping_purchase_v2 (paralelo a v1).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/receipt_upload_service.dart';

import '../config/app_colors.dart';
import '../models/cart_item.dart';
import '../models/order_model.dart';

@Deprecated(
    'Ecrã órfão (0 callers). O fluxo storeShopping V2 real vive inline em '
    'driver_map_screen.dart. Candidato a remoção — VALIDAR com Danilo antes de '
    'apagar (auditoria 2026-05-31, Lote B2). NÃO religar sem rever a lógica '
    '_allItemsResolved.')
class StoreShoppingPurchaseScreen extends StatefulWidget {
  const StoreShoppingPurchaseScreen({super.key, required this.order});
  final OrderModel order;

  @override
  State<StoreShoppingPurchaseScreen> createState() =>
      _StoreShoppingPurchaseScreenState();
}

class _StoreShoppingPurchaseScreenState
    extends State<StoreShoppingPurchaseScreen> {
  static const double _kThresholdEur = 5.0;

  late final List<_LocalItem> _items;
  final List<_LocalItem> _added = [];
  File? _receiptPhoto;
  final _totalCtrl = TextEditingController();
  bool _submitting = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _items = widget.order.items
        .map((c) => _LocalItem.fromCart(c))
        .toList(growable: false);
    _recoverLostReceiptPhoto();
  }

  /// Recovers photo lost when Android kills the app during camera session.
  Future<void> _recoverLostReceiptPhoto() async {
    final lost = await _picker.retrieveLostData();
    if (lost.isEmpty || !mounted) return;
    final file = lost.file;
    if (file != null) setState(() => _receiptPhoto = File(file.path));
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    super.dispose();
  }

  double get _expectedTotal {
    double sum = 0;
    for (final i in _items) {
      sum += i.effectivePriceCents() * i.effectiveQty() / 100.0;
    }
    for (final a in _added) {
      sum += a.effectivePriceCents() * a.effectiveQty() / 100.0;
    }
    return sum;
  }

  bool get _allItemsResolved =>
      _items.every((i) => i.status != 'pending') && _added.isNotEmpty == false
          ? true
          : _items.every((i) => i.status != 'pending');

  Future<void> _pickReceiptPhoto() async {
    // Decisão G — só câmara, sem galeria.
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() => _receiptPhoto = File(picked.path));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_allItemsResolved) {
      _snack('Marca todos os items antes de finalizar.');
      return;
    }
    if (_receiptPhoto == null) {
      _snack('Tira foto do talão primeiro.');
      return;
    }
    final typedEur = double.tryParse(_totalCtrl.text.replaceAll(',', '.'));
    if (typedEur == null || typedEur <= 0) {
      _snack('Valor do talão inválido.');
      return;
    }
    final typedCents = (typedEur * 100).round();

    // Item com diff>€5 sem confirmação chat → bloqueia
    for (final i in [..._items, ..._added]) {
      if (i.requiresClientConfirm(_kThresholdEur) &&
          i.clientConfirmationMessageId == null) {
        _snack(
          'Contacta o cliente para confirmar "${i.actualName ?? i.originalName}" '
          '(diferença > €${_kThresholdEur.toStringAsFixed(2)}).',
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final supabase = Supabase.instance.client;
      final orderId = widget.order.id;

      // 1) Upload foto via Edge Function (BUG #1 v2 — bypass storage rate).
      final path = await ReceiptUploadService.uploadReceipt(
        orderId: orderId,
        photoFile: _receiptPhoto!,
        totalCents: typedCents,
      );

      // 2) Montar payload items
      final payload = <Map<String, dynamic>>[];
      for (final i in _items) {
        payload.add(i.toRpcJson());
      }
      for (final a in _added) {
        payload.add(a.toRpcJson(addedOverride: true));
      }

      // 3) Chamar RPC v2
      final res = await supabase.rpc(
        'finalize_storeshopping_purchase_v2',
        params: {
          'p_order_id': orderId,
          'p_driver_typed_total_cents': typedCents,
          'p_receipt_photo_url': path,
          'p_items': payload,
        },
      );

      if (!mounted) return;
      _snack('Compra finalizada ✅');
      Navigator.of(context).pop(res);
    } catch (e) {
      if (mounted) _snack('Erro ao finalizar: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final vendor = order.vendorName ?? 'Loja';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Compra • $vendor'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subtotal estimado',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('€${_expectedTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._items.asMap().entries.map((e) =>
              _ItemCard(item: e.value, onUpdate: (n) => setState(() => _items[e.key] = n))),
          ..._added.asMap().entries.map((e) =>
              _ItemCard(item: e.value, isAdded: true, onUpdate: (n) => setState(() => _added[e.key] = n))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _onAddItem,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar item'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Talão do caixa',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ReceiptPreview(file: _receiptPhoto, onPick: _pickReceiptPhoto),
          const SizedBox(height: 12),
          TextField(
            controller: _totalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor pago no caixa (€)',
              prefixIcon: Icon(Icons.euro),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle),
              label: Text(_submitting ? 'A enviar...' : 'Confirmar compra'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _onAddItem() async {
    final result = await showDialog<_LocalItem>(
      context: context,
      builder: (_) => const _AddOrReplaceDialog(mode: _DialogMode.add),
    );
    if (result != null) setState(() => _added.add(result));
  }
}

// ─── Dados locais ───────────────────────────────────────────────────────────

class _LocalItem {
  _LocalItem({
    this.originalItemId,
    required this.originalName,
    required this.originalPriceCents,
    required this.originalQty,
    this.status = 'pending',
    this.actualName,
    this.actualPriceCents,
    this.actualQty,
    this.clientConfirmationMessageId,
  });

  final String? originalItemId;
  final String originalName;
  final int originalPriceCents;
  final int originalQty;
  String status;
  String? actualName;
  int? actualPriceCents;
  int? actualQty;
  String? clientConfirmationMessageId;

  factory _LocalItem.fromCart(CartItem c) => _LocalItem(
        originalItemId: c.productId,
        originalName: c.name,
        originalPriceCents: (c.price * 100).round(),
        originalQty: c.quantity,
      );

  int effectivePriceCents() {
    if (status == 'unavailable') return 0;
    if (status == 'replaced' && actualPriceCents != null) {
      return actualPriceCents!;
    }
    return originalPriceCents;
  }

  int effectiveQty() {
    if (status == 'unavailable') return 0;
    if (status == 'replaced' && actualQty != null) return actualQty!;
    return originalQty;
  }

  int diffCents() {
    if (status == 'replaced') {
      return (actualPriceCents ?? originalPriceCents) - originalPriceCents;
    }
    if (status == 'added') {
      return actualPriceCents ?? 0;
    }
    return 0;
  }

  bool requiresClientConfirm(double thresholdEur) =>
      diffCents().abs() > (thresholdEur * 100).round();

  Map<String, dynamic> toRpcJson({bool addedOverride = false}) => {
        'original_item_id': originalItemId ?? '',
        'original_name': originalName,
        'original_price_cents': originalPriceCents,
        'original_qty': originalQty,
        'status': addedOverride ? 'added' : status,
        if (actualName != null) 'actual_name': actualName,
        if (actualPriceCents != null) 'actual_price_cents': actualPriceCents,
        if (actualQty != null) 'actual_qty': actualQty,
        if (clientConfirmationMessageId != null)
          'client_confirmation_message_id': clientConfirmationMessageId,
      };
}

// ─── Widgets ────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    this.isAdded = false,
    required this.onUpdate,
  });
  final _LocalItem item;
  final bool isAdded;
  final ValueChanged<_LocalItem> onUpdate;

  Color _statusColor() {
    switch (item.status) {
      case 'purchased':
        return AppColors.success;
      case 'unavailable':
        return AppColors.error;
      case 'replaced':
        return AppColors.info;
      case 'added':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon() {
    switch (item.status) {
      case 'purchased':
        return Icons.check_circle;
      case 'unavailable':
        return Icons.cancel;
      case 'replaced':
        return Icons.swap_horiz;
      case 'added':
        return Icons.add_circle;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceEur = (item.originalPriceCents / 100).toStringAsFixed(2);
    final actualEur = item.actualPriceCents != null
        ? (item.actualPriceCents! / 100).toStringAsFixed(2)
        : null;
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(), color: _statusColor()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.originalName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      Text('${item.originalQty}× • €$priceEur',
                          style: TextStyle(color: AppColors.textSecondary)),
                      if (item.status == 'replaced' && item.actualName != null)
                        Text(
                          '→ ${item.actualName} • €${actualEur ?? "?"}',
                          style: TextStyle(color: AppColors.info),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isAdded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _statusBtn(
                      'Comprei',
                      Icons.check,
                      AppColors.success,
                      () => onUpdate(item..status = 'purchased')),
                  _statusBtn(
                      'Não tem',
                      Icons.close,
                      AppColors.error,
                      () => onUpdate(item..status = 'unavailable')),
                  _statusBtn(
                      'Substituir',
                      Icons.swap_horiz,
                      AppColors.info,
                      () => _openReplaceDialog(context)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );
  }

  Future<void> _openReplaceDialog(BuildContext context) async {
    final result = await showDialog<_LocalItem>(
      context: context,
      builder: (_) =>
          _AddOrReplaceDialog(mode: _DialogMode.replace, base: item),
    );
    if (result != null) onUpdate(result);
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.file, required this.onPick});
  final File? file;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 40, color: AppColors.accent),
                  const SizedBox(height: 8),
                  Text('Tirar foto do talão',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file!, fit: BoxFit.cover),
              ),
      ),
    );
  }
}

enum _DialogMode { replace, add }

class _AddOrReplaceDialog extends StatefulWidget {
  const _AddOrReplaceDialog({required this.mode, this.base});
  final _DialogMode mode;
  final _LocalItem? base;

  @override
  State<_AddOrReplaceDialog> createState() => _AddOrReplaceDialogState();
}

class _AddOrReplaceDialogState extends State<_AddOrReplaceDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    if (widget.mode == _DialogMode.replace && widget.base != null) {
      _qtyCtrl.text = widget.base!.originalQty.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == _DialogMode.replace
        ? 'Substituir "${widget.base!.originalName}"'
        : 'Adicionar item';
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nome do produto'),
          ),
          TextField(
            controller: _priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Preço €'),
          ),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantidade'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final price =
                double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
            final qty = int.tryParse(_qtyCtrl.text) ?? 1;
            if (name.isEmpty || price <= 0) return;
            final priceCents = (price * 100).round();
            if (widget.mode == _DialogMode.replace) {
              final b = widget.base!;
              Navigator.pop(
                context,
                _LocalItem(
                  originalItemId: b.originalItemId,
                  originalName: b.originalName,
                  originalPriceCents: b.originalPriceCents,
                  originalQty: b.originalQty,
                  status: 'replaced',
                  actualName: name,
                  actualPriceCents: priceCents,
                  actualQty: qty,
                ),
              );
            } else {
              Navigator.pop(
                context,
                _LocalItem(
                  originalName: name,
                  originalPriceCents: 0,
                  originalQty: 0,
                  status: 'added',
                  actualName: name,
                  actualPriceCents: priceCents,
                  actualQty: qty,
                ),
              );
            }
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
