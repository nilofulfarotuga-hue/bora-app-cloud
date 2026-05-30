import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../models/restaurant_table.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — walk-in rápido (Toast TablesReady-like).
///
/// Form mínimo: pessoas → mesa filtrada por capacidade → nome opcional.
/// Submit chama `partner_seat_walk_in` que cria reservation status=arrived.
class PartnerWalkInScreen extends StatefulWidget {
  const PartnerWalkInScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<PartnerWalkInScreen> createState() => _PartnerWalkInScreenState();
}

class _PartnerWalkInScreenState extends State<PartnerWalkInScreen> {
  int _party = 2;
  RestaurantTable? _selectedTable;
  final _nameCtrl = TextEditingController(text: 'Walk-in');
  final _phoneCtrl = TextEditingController();
  bool _submitting = false;
  Future<List<RestaurantTable>>? _tablesFuture;

  @override
  void initState() {
    super.initState();
    _tablesFuture = context
        .read<PartnerReservasStore>()
        .fetchTables(restaurantId: widget.restaurantId);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _showLargePartyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grupos grandes'),
        content: const Text(
          'Para grupos com mais de 12 pessoas, combina mesas no '
          'editor da planta antes de sentar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (_selectedTable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolhe uma mesa.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PartnerReservasStore>().seatWalkIn(
            restaurantId: widget.restaurantId,
            party: _party,
            tableId: _selectedTable!.id,
            clientName: _nameCtrl.text.trim().isEmpty
                ? 'Walk-in'
                : _nameCtrl.text.trim(),
            clientPhone:
                _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content:
              Text('Sentado na mesa ${_selectedTable!.numero}.'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
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
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Walk-in'),
      body: SafeArea(
        child: FutureBuilder<List<RestaurantTable>>(
          future: _tablesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snap.error.toString().replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final tables = snap.data ?? const <RestaurantTable>[];
            final eligible =
                tables.where((t) => t.capacity >= _party).toList();
            // Auto-deselect se selectedTable já não cabe.
            if (_selectedTable != null &&
                !eligible.contains(_selectedTable)) {
              _selectedTable = null;
            }
            if (tables.isEmpty) {
              return _emptyTablesState();
            }
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pessoas',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (var i = 1; i <= 12; i++)
                                      ChoiceChip(
                                        label: Text('$i'),
                                        selected: _party == i,
                                        selectedColor: AppColors.primary,
                                        labelStyle: TextStyle(
                                          color: _party == i
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        onSelected: (_) =>
                                            setState(() => _party = i),
                                      ),
                                    ActionChip(
                                      label: const Text('13+'),
                                      onPressed: _showLargePartyDialog,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mesa',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (eligible.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'Sem mesas com capacidade suficiente.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final t in eligible)
                                        ChoiceChip(
                                          label: Text(
                                              'Mesa ${t.numero} (${t.capacity})'),
                                          selected: _selectedTable?.id == t.id,
                                          selectedColor: AppColors.primary,
                                          labelStyle: TextStyle(
                                            color: _selectedTable?.id == t.id
                                                ? Colors.white
                                                : AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          onSelected: (_) => setState(
                                              () => _selectedTable = t),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Identificação (opcional)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nome',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Telefone',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                        backgroundColor: AppColors.primary,
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
                          : const Icon(Icons.directions_walk),
                      label: const Text(
                        'Sentar agora',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyTablesState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant_outlined,
                size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Sem mesas configuradas',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Configura primeiro a planta da sala.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
