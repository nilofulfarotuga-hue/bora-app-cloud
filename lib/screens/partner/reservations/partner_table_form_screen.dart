import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../models/restaurant_table.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — form add/edit mesa.
///
/// Modo dual via constructor `existing`:
///   - existing == null → ADD (cria nova mesa via partner_add_table)
///   - existing != null → EDIT (UPDATE direct campos editáveis)
class PartnerTableFormScreen extends StatefulWidget {
  const PartnerTableFormScreen({
    super.key,
    required this.restaurantId,
    this.floorPlanId,
    this.existing,
  });

  final String restaurantId;
  final String? floorPlanId;
  final RestaurantTable? existing;

  bool get isEdit => existing != null;

  @override
  State<PartnerTableFormScreen> createState() =>
      _PartnerTableFormScreenState();
}

class _PartnerTableFormScreenState extends State<PartnerTableFormScreen> {
  final _numeroCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _capacity = 4;
  String _zona = 'interior';
  String _shape = 'rectangle';
  bool _submitting = false;

  static const _zonas = <String, String>{
    'interior': 'Interior',
    'esplanada': 'Esplanada',
    'balcao': 'Balcão',
    'privado': 'Privado',
  };

  static const _shapes = <String, String>{
    'rectangle': 'Rectangular',
    'square': 'Quadrada',
    'circle': 'Redonda',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _numeroCtrl.text = e.numero;
      _capacity = e.capacity;
      _zona = e.zona;
      _shape = e.shape;
      _notesCtrl.text = e.notes ?? '';
    }
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Número da mesa é obrigatório.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final store = context.read<PartnerReservasStore>();
      final notes = _notesCtrl.text.trim();
      if (widget.isEdit) {
        await store.updateTable(
          tableId: widget.existing!.id,
          numero: numero,
          capacity: _capacity,
          zona: _zona,
          shape: _shape,
          notes: notes,
        );
      } else {
        await store.addTable(
          restaurantId: widget.restaurantId,
          numero: numero,
          capacity: _capacity,
          zona: _zona,
          floorPlanId: widget.floorPlanId,
          shape: _shape,
          notes: notes.isEmpty ? null : notes,
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(widget.isEdit ? 'Mesa actualizada.' : 'Mesa criada.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Editar mesa' : 'Adicionar mesa'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _numeroCtrl,
                          maxLength: 20,
                          decoration: const InputDecoration(
                            labelText: 'Número / Identificação',
                            hintText: 'Ex: 12, A1, T-3',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Capacidade',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _capacity > 1
                                  ? () => setState(() => _capacity--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '$_capacity',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _capacity < 30
                                  ? () => setState(() => _capacity++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _zona,
                          decoration: const InputDecoration(
                            labelText: 'Zona',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final entry in _zonas.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _zona = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _shape,
                          decoration: const InputDecoration(
                            labelText: 'Forma',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final entry in _shapes.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _shape = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesCtrl,
                          maxLength: 200,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Notas (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(widget.isEdit ? Icons.save : Icons.add),
                  label: Text(
                    widget.isEdit ? 'Guardar' : 'Adicionar mesa',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
