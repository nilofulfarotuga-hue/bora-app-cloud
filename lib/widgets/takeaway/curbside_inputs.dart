import 'package:flutter/material.dart';

import '../../config/app_spacing.dart';

/// D6 — Inputs curbside (cliente espera no carro).
///
/// Checkbox "Vou esperar no carro" + textfield para matrícula/cor/modelo.
/// Quando [isLocked]=true (após `payment_status='paid'`), ambos os
/// controlos ficam disabled — guard UI-only, servidor não bloqueia (D6).
///
/// Reutilizável em [CartScreen] (pré-paid, sempre editável) e em
/// [OrderTrackingScreen] (pós-paid, isLocked=true).
class CurbsideInputs extends StatefulWidget {
  const CurbsideInputs({
    super.key,
    required this.isCurbside,
    required this.curbsideInfo,
    required this.isLocked,
    required this.onCurbsideChanged,
    required this.onInfoChanged,
  });

  final bool isCurbside;
  final String? curbsideInfo;
  final bool isLocked;
  final ValueChanged<bool> onCurbsideChanged;
  final ValueChanged<String?> onInfoChanged;

  @override
  State<CurbsideInputs> createState() => _CurbsideInputsState();
}

class _CurbsideInputsState extends State<CurbsideInputs> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.curbsideInfo ?? '');
  }

  @override
  void didUpdateWidget(covariant CurbsideInputs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.curbsideInfo ?? '';
    if (_controller.text != newText) {
      _controller.text = newText;
      _controller.selection =
          TextSelection.collapsed(offset: newText.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: widget.isCurbside,
          onChanged: widget.isLocked
              ? null
              : (v) => widget.onCurbsideChanged(v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Vou esperar no carro',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'O parceiro leva o pedido até à viatura',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (widget.isCurbside) ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _controller,
            enabled: !widget.isLocked,
            onChanged: widget.onInfoChanged,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Matrícula + cor (ex: AA-12-BB cinza)',
              border: const OutlineInputBorder(),
              helperText: widget.isLocked
                  ? 'Não editável após pagamento confirmado'
                  : null,
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }
}
