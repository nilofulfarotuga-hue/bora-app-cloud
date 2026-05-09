import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — configurações partner: turn times + pacing rules.
///
/// 2 tabs (OpenTable pacing manager + Tock turn time inspired).
/// CRUD direct via Supabase SDK (RLS partner_owner).
class PartnerPacingRulesScreen extends StatefulWidget {
  const PartnerPacingRulesScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<PartnerPacingRulesScreen> createState() =>
      _PartnerPacingRulesScreenState();
}

class _PartnerPacingRulesScreenState extends State<PartnerPacingRulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<Map<String, dynamic>>> _turnTimesFuture;
  late Future<List<Map<String, dynamic>>> _pacingFuture;

  static const _dayNames = <String>[
    'Domingo',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _turnTimesFuture = context
          .read<PartnerReservasStore>()
          .fetchTurnTimes(widget.restaurantId);
      _pacingFuture = context
          .read<PartnerReservasStore>()
          .fetchPacingRules(widget.restaurantId);
    });
  }

  Future<void> _addTurnTime() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _TurnTimeDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().insertTurnTime({
        'restaurant_id': widget.restaurantId,
        ...result,
      });
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _addPacingRule() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PacingRuleDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().insertPacingRule({
        'restaurant_id': widget.restaurantId,
        ...result,
      });
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _deleteTurnTime(String id) async {
    final ok = await _confirmDelete('Remover este tempo?');
    if (ok != true || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().deleteTurnTime(id);
      _refresh();
    } catch (_) {/* ignore */}
  }

  Future<void> _deletePacingRule(String id) async {
    final ok = await _confirmDelete('Remover esta regra?');
    if (ok != true || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().deletePacingRule(id);
      _refresh();
    } catch (_) {/* ignore */}
  }

  Future<bool?> _confirmDelete(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  String _dayLabel(int? day) =>
      day == null ? 'Todos os dias' : _dayNames[day.clamp(0, 6)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Tempos de mesa'),
            Tab(text: 'Pacing'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildTurnTimes(),
          _buildPacing(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: _tab.index == 0 ? _addTurnTime : _addPacingRule,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTurnTimes() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _turnTimesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _errorBox(snap.error);
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _emptyBox(
            'Sem tempos definidos.',
            'Define quanto tempo a mesa fica ocupada por tamanho de grupo.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined,
                      color: AppTheme.primary),
                  title: Text(
                    'Pessoas ${r['party_size_min']}-${r['party_size_max']}'
                    ' • ${r['minutes']} min',
                  ),
                  subtitle: Text(_dayLabel(r['day_of_week'] as int?)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    onPressed: () => _deleteTurnTime(r['id'] as String),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPacing() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _pacingFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _errorBox(snap.error);
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _emptyBox(
            'Sem regras de pacing.',
            'Limita reservas por slot para evitar sobrecargas.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final start = (r['slot_start'] as String?) ?? '';
              final end = (r['slot_end'] as String?) ?? '';
              final maxC = r['max_covers'];
              final maxR = r['max_reservations'];
              final walkPct = (r['walk_in_reserved_pct'] as int?) ?? 25;
              final parts = <String>[];
              if (maxC != null) parts.add('$maxC cobertos');
              if (maxR != null) parts.add('$maxR reservas');
              parts.add('$walkPct% walk-in');
              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.schedule,
                      color: AppTheme.primary),
                  title: Text(
                    '${_dayLabel(r['day_of_week'] as int?)}'
                    ' • ${start.substring(0, 5)}-${end.substring(0, 5)}',
                  ),
                  subtitle: Text(parts.join(' • ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    onPressed: () => _deletePacingRule(r['id'] as String),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _errorBox(Object? err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          err.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _emptyBox(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnTimeDialog extends StatefulWidget {
  const _TurnTimeDialog();

  @override
  State<_TurnTimeDialog> createState() => _TurnTimeDialogState();
}

class _TurnTimeDialogState extends State<_TurnTimeDialog> {
  RangeValues _range = const RangeValues(1, 4);
  int _minutes = 90;
  int? _day; // null = todos.

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo tempo de mesa'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Pessoas: ${_range.start.toInt()} - ${_range.end.toInt()}'),
            RangeSlider(
              values: _range,
              min: 1,
              max: 20,
              divisions: 19,
              activeColor: AppTheme.primary,
              labels: RangeLabels(
                _range.start.toInt().toString(),
                _range.end.toInt().toString(),
              ),
              onChanged: (v) => setState(() => _range = v),
            ),
            const SizedBox(height: 8),
            Text('Tempo de mesa: $_minutes min'),
            Slider(
              value: _minutes.toDouble(),
              min: 30,
              max: 300,
              divisions: 18,
              activeColor: AppTheme.primary,
              label: '$_minutes',
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _day,
              decoration: const InputDecoration(
                labelText: 'Dia',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todos os dias'),
                ),
                for (var i = 0; i < 7; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(_PartnerPacingRulesScreenState._dayNames[i]),
                  ),
              ],
              onChanged: (v) => setState(() => _day = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'party_size_min': _range.start.toInt(),
            'party_size_max': _range.end.toInt(),
            'minutes': _minutes,
            'day_of_week': _day,
            'active': true,
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PacingRuleDialog extends StatefulWidget {
  const _PacingRuleDialog();

  @override
  State<_PacingRuleDialog> createState() => _PacingRuleDialogState();
}

class _PacingRuleDialogState extends State<_PacingRuleDialog> {
  int _day = 5; // Sexta default.
  TimeOfDay _start = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 22, minute: 0);
  final _coversCtrl = TextEditingController();
  final _reservasCtrl = TextEditingController();
  int _walkInPct = 25;

  @override
  void dispose() {
    _coversCtrl.dispose();
    _reservasCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickStart() async {
    final p =
        await showTimePicker(context: context, initialTime: _start);
    if (p != null) setState(() => _start = p);
  }

  Future<void> _pickEnd() async {
    final p =
        await showTimePicker(context: context, initialTime: _end);
    if (p != null) setState(() => _end = p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova regra de pacing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: const InputDecoration(
                labelText: 'Dia da semana',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < 7; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(_PartnerPacingRulesScreenState._dayNames[i]),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _day = v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      _start.format(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(_end.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _coversCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Máx. cobertos (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reservasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Máx. reservas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Walk-in reservado: $_walkInPct%'),
            Slider(
              value: _walkInPct.toDouble(),
              min: 0,
              max: 50,
              divisions: 10,
              activeColor: AppTheme.primary,
              label: '$_walkInPct%',
              onChanged: (v) => setState(() => _walkInPct = v.round()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final c = int.tryParse(_coversCtrl.text);
            final r = int.tryParse(_reservasCtrl.text);
            Navigator.pop(context, {
              'day_of_week': _day,
              'slot_start': _fmt(_start),
              'slot_end': _fmt(_end),
              if (c != null) 'max_covers': c,
              if (r != null) 'max_reservations': r,
              'walk_in_reserved_pct': _walkInPct,
              'active': true,
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
