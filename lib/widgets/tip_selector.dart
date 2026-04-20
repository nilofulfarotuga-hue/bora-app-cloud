import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable tip selector used at checkout (BR §4.5) and at the rating screen.
///
/// Presets: 1€, 2€, 3€, 5€, plus a free-text field.
/// Emits the selected amount in EUR cents via [onChanged].
class TipSelector extends StatefulWidget {
  const TipSelector({
    super.key,
    required this.onChanged,
    this.initialCents = 0,
    this.enabled = true,
  });

  final void Function(int cents) onChanged;
  final int initialCents;
  final bool enabled;

  @override
  State<TipSelector> createState() => _TipSelectorState();
}

class _TipSelectorState extends State<TipSelector> {
  static const _presets = <int>[100, 200, 300, 500]; // cents

  late int _selectedCents;
  late TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _selectedCents = widget.initialCents;
    _customController = TextEditingController(
      text: _presets.contains(widget.initialCents) || widget.initialCents == 0
          ? ''
          : (widget.initialCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _pickPreset(int cents) {
    setState(() {
      _selectedCents = cents;
      _customController.clear();
    });
    widget.onChanged(cents);
  }

  void _onCustomChanged(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final parsed = double.tryParse(normalized);
    final cents = (parsed != null && parsed > 0) ? (parsed * 100).round() : 0;
    setState(() => _selectedCents = cents);
    widget.onChanged(cents);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gorjeta (opcional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          '80% vai para o estafeta.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final cents in _presets)
              ChoiceChip(
                label: Text('€${(cents / 100).toStringAsFixed(0)}'),
                selected: _selectedCents == cents,
                onSelected:
                    widget.enabled ? (_) => _pickPreset(cents) : null,
              ),
            ChoiceChip(
              label: const Text('Nenhuma'),
              selected: _selectedCents == 0,
              onSelected: widget.enabled ? (_) => _pickPreset(0) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customController,
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Outro valor (€)',
            border: OutlineInputBorder(),
          ),
          onChanged: _onCustomChanged,
        ),
      ],
    );
  }
}
