import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/payment_service.dart';

/// PayDebtModal — modal para liquidar dívida wallet (BUG #1 frontend / §54).
///
/// Layout:
///   - Mostra dívida actual
///   - Selector valor: "Pagar dívida (X.XX €)" (default) ou "Pagar mais [input] €"
///   - Selector método: Cartão / MBWay (input phone se MBWay)
///   - Botão Confirmar (desabilitado durante chamada — flag isLoading evita double-click)
///
/// Após sucesso: pop(true). Caller faz refresh wallet. Snackbar com surplus se houve.
class PayDebtModal extends StatefulWidget {
  final int debtCents;
  const PayDebtModal({super.key, required this.debtCents});

  @override
  State<PayDebtModal> createState() => _PayDebtModalState();
}

class _PayDebtModalState extends State<PayDebtModal> {
  bool _payMore = false;
  String _method = 'card';
  bool _isLoading = false;
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  int? _resolveAmountCents() {
    if (!_payMore) return widget.debtCents;
    final raw = _amountCtrl.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    final eur = double.tryParse(raw);
    if (eur == null) return null;
    return (eur * 100).round();
  }

  String? _validate(int? amountCents) {
    if (amountCents == null) return 'Indica um valor válido.';
    if (amountCents < widget.debtCents + 1) {
      return 'Valor deve ser maior que a dívida (€${(widget.debtCents / 100).toStringAsFixed(2)}).';
    }
    if (_method == 'mbway') {
      final phone = _phoneCtrl.text.trim();
      if (!RegExp(r'^\+?351\d{9}$').hasMatch(phone)) {
        return 'Telefone MBWay inválido (formato: +351XXXXXXXXX).';
      }
    }
    return null;
  }

  Future<void> _confirm() async {
    final amountCents = _resolveAmountCents();
    if (_payMore) {
      final err = _validate(amountCents);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    } else if (_method == 'mbway') {
      final phone = _phoneCtrl.text.trim();
      if (!RegExp(r'^\+?351\d{9}$').hasMatch(phone)) {
        setState(() => _error = 'Telefone MBWay inválido (formato: +351XXXXXXXXX).');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final paymentIntentId = await PaymentService().payDebtViaSheet(
        amountCents: amountCents!,
        paymentMethod: _method,
        mbwayPhone: _method == 'mbway' ? _phoneCtrl.text.trim() : null,
      );
      if (!mounted) return;
      if (paymentIntentId == null) {
        setState(() {
          _isLoading = false;
          _error = 'Pagamento cancelado ou recusado.';
        });
        return;
      }
      final surplusCents = amountCents - widget.debtCents;
      final msg = surplusCents > 0
          ? 'Dívida paga! Tens €${(surplusCents / 100).toStringAsFixed(2)} em saldo.'
          : 'Dívida paga!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1B5E20)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Erro: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtEur = widget.debtCents / 100;
    return AlertDialog(
      title: const Text('Pagar dívida'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tens €${debtEur.toStringAsFixed(2)} de dívida.',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text('Quanto queres pagar?', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile<bool>(
              value: false,
              groupValue: _payMore,
              dense: true,
              title: Text('Pagar dívida (€${debtEur.toStringAsFixed(2)})'),
              onChanged: _isLoading ? null : (v) => setState(() => _payMore = v ?? false),
            ),
            RadioListTile<bool>(
              value: true,
              groupValue: _payMore,
              dense: true,
              title: const Text('Pagar mais (excedente vira saldo)'),
              onChanged: _isLoading ? null : (v) => setState(() => _payMore = v ?? false),
            ),
            if (_payMore)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: TextField(
                  controller: _amountCtrl,
                  enabled: !_isLoading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Valor (€)',
                    hintText: '>= ${(debtEur + 0.01).toStringAsFixed(2)}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text('Método', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile<String>(
              value: 'card',
              groupValue: _method,
              dense: true,
              title: const Text('Cartão'),
              onChanged: _isLoading ? null : (v) => setState(() => _method = v ?? 'card'),
            ),
            RadioListTile<String>(
              value: 'mbway',
              groupValue: _method,
              dense: true,
              title: const Text('MBWay'),
              onChanged: _isLoading ? null : (v) => setState(() => _method = v ?? 'card'),
            ),
            if (_method == 'mbway')
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: TextField(
                  controller: _phoneCtrl,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone MBWay',
                    hintText: '+351912345678',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirmar'),
        ),
      ],
    );
  }
}
