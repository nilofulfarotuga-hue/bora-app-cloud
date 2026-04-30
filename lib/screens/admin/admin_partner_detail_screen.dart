// T3 — Admin partner detail with tabs: Dados / Horários / Estado / Datas Especiais.
// Requires partner_hours_system migration (T4 of sessão nocturna 2026-04-29).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/restaurant_model.dart';
import '../../stores/restaurant_store.dart';
import '_admin_partner_edit_dialog.dart';

class AdminPartnerDetailScreen extends StatefulWidget {
  const AdminPartnerDetailScreen({
    super.key,
    required this.restaurantId,
    required this.initialName,
  });

  final String restaurantId;
  final String initialName;

  @override
  State<AdminPartnerDetailScreen> createState() =>
      _AdminPartnerDetailScreenState();
}

class _AdminPartnerDetailScreenState extends State<AdminPartnerDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  Map<String, dynamic>? _restaurant;
  Map<String, dynamic>? _openStatus; // result of is_partner_open()
  BusinessHours _hours = const BusinessHours();
  bool _savingHours = false;

  static const _days = <({int weekday, String label, String key})>[
    (weekday: DateTime.monday,    label: 'Segunda-feira', key: 'mon'),
    (weekday: DateTime.tuesday,   label: 'Terça-feira',   key: 'tue'),
    (weekday: DateTime.wednesday, label: 'Quarta-feira',  key: 'wed'),
    (weekday: DateTime.thursday,  label: 'Quinta-feira',  key: 'thu'),
    (weekday: DateTime.friday,    label: 'Sexta-feira',   key: 'fri'),
    (weekday: DateTime.saturday,  label: 'Sábado',        key: 'sat'),
    (weekday: DateTime.sunday,    label: 'Domingo',       key: 'sun'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final restaurantData = await Supabase.instance.client
          .from('restaurants')
          .select(
              'id, name, category, address, phone, email, is_partner, is_online, is_active_admin, business_hours')
          .eq('id', widget.restaurantId)
          .single();
      final openData = await Supabase.instance.client.rpc('is_partner_open', params: {
        'p_restaurant_id': widget.restaurantId,
        'p_at': DateTime.now().toUtc().toIso8601String(),
      });
      final results = [restaurantData, openData];
      if (mounted) {
        final r = Map<String, dynamic>.from(results[0] as Map);
        final bh = BusinessHours.fromJson(r['business_hours']);
        setState(() {
          _restaurant = r;
          _hours = bh;
          _openStatus = results[1] is Map
              ? Map<String, dynamic>.from(results[1] as Map)
              : {'is_open': results[1]};
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    }
  }

  // ─── TAB 1 — DADOS ────────────────────────────────────────────────────────

  Widget _buildDadosTab() {
    if (_loading || _restaurant == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _restaurant!;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _infoRow(Icons.store, 'Nome', r['name'] as String? ?? '—'),
          _infoRow(Icons.category, 'Categoria', r['category'] as String? ?? '—'),
          _infoRow(Icons.location_on, 'Morada', r['address'] as String? ?? '—'),
          _infoRow(Icons.phone, 'Telefone', r['phone'] as String? ?? '—'),
          _infoRow(Icons.email, 'Email', r['email'] as String? ?? '—'),
          _infoRow(Icons.handshake,
              r['is_partner'] == true ? 'Parceiro' : 'Não-parceiro', ''),
          _infoRow(Icons.toggle_on,
              r['is_active_admin'] != false ? 'Activo no admin' : 'DESACTIVADO', ''),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final res = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => AdminPartnerEditDialog(
                  restaurantId: widget.restaurantId,
                  initialName: r['name'] as String? ?? '',
                  initialAddress: r['address'] as String? ?? '',
                  initialCategory: r['category'] as String? ?? 'restaurant',
                  initialPhone: r['phone'] as String? ?? '',
                ),
              );
              if (res != null && res['success'] == true) _loadAll();
            },
            icon: const Icon(Icons.edit),
            label: const Text('Editar dados'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (value.isNotEmpty)
              Text(value, style: const TextStyle(fontSize: 15)),
          ]),
        ),
      ]),
    );
  }

  // ─── TAB 2 — HORÁRIOS ─────────────────────────────────────────────────────

  void _updateDay(int weekday, DayHours day) {
    setState(() => _hours = _hours.copyWithDay(weekday, day));
  }

  Future<void> _pickTime(int weekday, bool isOpen) async {
    final current = _hours.dayFor(weekday);
    final raw = isOpen ? current.open : current.close;
    final parts = raw.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    final formatted = '$h:$m';
    _updateDay(weekday,
        isOpen ? current.copyWith(open: formatted) : current.copyWith(close: formatted));
  }

  Future<void> _saveHours() async {
    setState(() => _savingHours = true);
    try {
      final store = context.read<RestaurantStore>();
      await store.adminUpdatePartnerHours(
        restaurantId: widget.restaurantId,
        hours: _hours,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horário guardado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingHours = false);
    }
  }

  Widget _buildHorariosTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._days.map((d) {
          final dh = _hours.dayFor(d.weekday);
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(d.label,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
                  Switch(
                    value: !dh.closed,
                    onChanged: (v) =>
                        _updateDay(d.weekday, dh.copyWith(closed: !v)),
                  ),
                  Text(dh.closed ? 'Fechado' : 'Aberto',
                      style: TextStyle(
                          color: dh.closed ? Colors.grey : AppColors.primary,
                          fontSize: 13)),
                ]),
                if (!dh.closed)
                  Row(children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text('Abre: ${dh.open}'),
                        onPressed: () => _pickTime(d.weekday, true),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.access_time_filled, size: 18),
                        label: Text('Fecha: ${dh.close}'),
                        onPressed: () => _pickTime(d.weekday, false),
                      ),
                    ),
                  ]),
              ]),
            ),
          );
        }),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _savingHours ? null : _saveHours,
          icon: _savingHours
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Guardar horários'),
        ),
      ],
    );
  }

  // ─── TAB 3 — ESTADO ───────────────────────────────────────────────────────

  Widget _buildEstadoTab() {
    if (_openStatus == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isOpen = _openStatus!['is_open'] == true;
    final overrideActive = _openStatus!['override_active'] == true;
    final overrideReason = _openStatus!['override_reason'] as String?;
    final overrideEndsAt = _openStatus!['override_ends_at'] as String?;

    Color badgeColor;
    String badgeLabel;
    IconData badgeIcon;

    if (overrideActive) {
      badgeColor = isOpen ? Colors.green.shade700 : Colors.red.shade700;
      badgeLabel = isOpen ? 'ABERTO (forçado)' : 'FECHADO (forçado)';
      badgeIcon = Icons.admin_panel_settings;
    } else {
      badgeColor = isOpen ? Colors.green : Colors.orange;
      badgeLabel = isOpen ? 'ABERTO (horário)' : 'FECHADO (horário)';
      badgeIcon = isOpen ? Icons.check_circle : Icons.cancel;
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(badgeIcon, color: badgeColor, size: 60),
                const SizedBox(height: 12),
                Text(badgeLabel,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: badgeColor)),
                if (overrideReason != null) ...[
                  const SizedBox(height: 8),
                  Text('Motivo: $overrideReason',
                      style: const TextStyle(color: Colors.grey)),
                ],
                if (overrideEndsAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Até: ${overrideEndsAt.substring(0, 16)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (overrideActive)
            OutlinedButton.icon(
              onPressed: _clearOverride,
              icon: const Icon(Icons.clear, color: Colors.orange),
              label: const Text('Limpar override → voltar a horário regular'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            )
          else ...[
            FilledButton.icon(
              onPressed: () => _setOverride('closed'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.lock),
              label: const Text('Forçar FECHAR'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _setOverride('open'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.lock_open),
              label: const Text('Forçar ABRIR'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setOverride(String state) async {
    final reasonCtrl = TextEditingController();
    DateTime? endsAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(state == 'closed' ? 'Forçar fechar' : 'Forçar abrir'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: reasonCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Motivo (mín 3)')),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(endsAt == null
                  ? 'Sem limite (permanente)'
                  : 'Até ${endsAt.toString().substring(0, 10)}'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().add(const Duration(minutes: 5)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: DateTime.now().add(const Duration(hours: 2)),
                );
                if (picked != null) setSt(() => endsAt = picked);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      final store = context.read<RestaurantStore>();
      await store.adminSetPartnerOverride(
        restaurantId: widget.restaurantId,
        state: state,
        reason: reasonCtrl.text.trim(),
        endsAt: endsAt,
      );
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _clearOverride() async {
    try {
      final store = context.read<RestaurantStore>();
      await store.adminClearPartnerOverride(widget.restaurantId);
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // ─── TAB 4 — DATAS ESPECIAIS ──────────────────────────────────────────────

  List<Map<String, dynamic>> _getSpecialDates() {
    if (_restaurant == null) return [];
    final bh = _restaurant!['business_hours'];
    if (bh is! Map) return [];
    final sd = bh['special_dates'];
    if (sd is! List) return [];
    return sd.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Widget _buildDatasEspeciaisTab() {
    final dates = _getSpecialDates();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Expanded(child: Text('Datas especiais (feriados/eventos)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppColors.primary),
              onPressed: _addSpecialDate,
              tooltip: 'Adicionar data',
            ),
          ]),
          const Divider(),
          if (dates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma data especial configurada.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...dates.map((d) {
              final closed = d['closed'] == true;
              return Card(
                child: ListTile(
                  leading: Icon(closed ? Icons.event_busy : Icons.event_available,
                      color: closed ? Colors.red : Colors.green),
                  title: Text(d['date'] as String? ?? '—'),
                  subtitle: Text(closed
                      ? 'Fechado — ${d['reason'] ?? ''}'
                      : '${d['open'] ?? '?'} – ${d['close'] ?? '?'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeSpecialDate(d['date'] as String),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _addSpecialDate() async {
    DateTime? date;
    bool closed = true;
    final openCtrl = TextEditingController(text: '09:00');
    final closeCtrl = TextEditingController(text: '13:00');
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Adicionar data especial'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(date == null
                    ? 'Seleccionar data'
                    : date.toString().substring(0, 10)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                    initialDate: DateTime.now(),
                  );
                  if (picked != null) setSt(() => date = picked);
                },
              ),
              SwitchListTile(
                title: const Text('Fechado neste dia'),
                value: closed,
                onChanged: (v) => setSt(() => closed = v),
              ),
              if (!closed) ...[
                TextField(controller: openCtrl,
                    decoration: const InputDecoration(labelText: 'Abre (HH:MM)')),
                TextField(controller: closeCtrl,
                    decoration: const InputDecoration(labelText: 'Fecha (HH:MM)')),
              ],
              TextField(controller: reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Motivo (ex: Natal, Feriado)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || date == null || !mounted) return;
    try {
      final dayHours = closed
          ? {'closed': true, 'reason': reasonCtrl.text}
          : {'closed': false, 'open': openCtrl.text, 'close': closeCtrl.text,
             'reason': reasonCtrl.text};
      final store = context.read<RestaurantStore>();
      await store.adminSetPartnerSpecialDate(
        restaurantId: widget.restaurantId,
        date: date!,
        dayHours: dayHours,
      );
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _removeSpecialDate(String dateStr) async {
    // Remove by setting closed=false with no hours (effectively a no-op date)
    // or just update business_hours without that date.
    try {
      final bh = Map<String, dynamic>.from(_restaurant?['business_hours'] as Map? ?? {});
      final sd = (bh['special_dates'] as List? ?? [])
          .where((e) => (e as Map)['date'] != dateStr)
          .toList();
      bh['special_dates'] = sd;
      await Supabase.instance.client
          .from('restaurants')
          .update({'business_hours': bh})
          .eq('id', widget.restaurantId);
      _loadAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _restaurant?['name'] as String? ?? widget.initialName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Dados'),
            Tab(icon: Icon(Icons.schedule), text: 'Horários'),
            Tab(icon: Icon(Icons.toggle_on), text: 'Estado'),
            Tab(icon: Icon(Icons.date_range), text: 'Datas'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildDadosTab(),
                _buildHorariosTab(),
                _buildEstadoTab(),
                _buildDatasEspeciaisTab(),
              ],
            ),
    );
  }
}
