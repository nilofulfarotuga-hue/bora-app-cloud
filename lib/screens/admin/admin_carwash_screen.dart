import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/carwash_upload_service.dart';

/// LAVAGEM AUTO — painel admin (PT-BR, só o Danilo usa).
/// Autoridade total: ver, criar, editar, cancelar, reagendar, reatribuir,
/// gerir lavadores, mexer em todos os preços, acerto semanal, agrupar idas,
/// exportar CSV. Tudo por RPC com `is_admin()` no servidor.
class AdminCarwashScreen extends StatefulWidget {
  const AdminCarwashScreen({super.key});

  @override
  State<AdminCarwashScreen> createState() => _AdminCarwashScreenState();
}

class _AdminCarwashScreenState extends State<AdminCarwashScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lavagem Auto'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pedidos'),
            Tab(text: 'Lavadores'),
            Tab(text: 'Agrupar idas'),
            Tab(text: 'Acertos'),
            Tab(text: 'Configurações'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _AbaPedidos(),
          _AbaLavadores(),
          _AbaAgrupar(),
          _AbaAcertos(),
          _AbaConfig(),
        ],
      ),
    );
  }
}

SupabaseClient get _sb => Supabase.instance.client;

void _msg(BuildContext c, String t) => ScaffoldMessenger.of(c)
    .showSnackBar(SnackBar(content: Text(t)));

// ═══════════════════════════════════════════════════════════════════════════
// PEDIDOS
// ═══════════════════════════════════════════════════════════════════════════

class _AbaPedidos extends StatefulWidget {
  const _AbaPedidos();
  @override
  State<_AbaPedidos> createState() => _AbaPedidosState();
}

class _AbaPedidosState extends State<_AbaPedidos> {
  final _buscaCtrl = TextEditingController();
  String? _status;
  DateTime? _dia;
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;

  static const _estados = {
    'scheduled': 'Procurando lavador',
    'accepted': 'Aceito',
    'on_the_way': 'A caminho',
    'picked_up': 'Carro recolhido',
    'in_progress': 'Lavando',
    'delivering': 'Entregando',
    'delivered': 'Entregue',
    'completed': 'Concluído',
    'cancelled_client': 'Cancelado',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _sb.rpc('admin_list_carwash_bookings', params: {
        'p_status': _status,
        'p_day': _dia?.toIso8601String().split('T').first,
        'p_washer_id': null,
        'p_search': _buscaCtrl.text.trim(),
        'p_limit': 100,
        'p_offset': 0,
      });
      final m = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;
      setState(() {
        _total = (m['total'] as num?)?.toInt() ?? 0;
        _rows = (m['rows'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg(context, 'Erro ao carregar: $e');
    }
  }

  Future<void> _exportar() async {
    try {
      final hoje = DateTime.now();
      final de = hoje.subtract(const Duration(days: 30));
      final csv = await _sb.rpc('admin_export_carwash_csv', params: {
        'p_from': de.toIso8601String().split('T').first,
        'p_to': hoje.toIso8601String().split('T').first,
      });
      await Clipboard.setData(ClipboardData(text: (csv ?? '').toString()));
      if (mounted) {
        _msg(context, 'CSV dos últimos 30 dias copiado para a área de transferência.');
      }
    } catch (e) {
      if (mounted) _msg(context, 'Erro ao exportar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              TextField(
                controller: _buscaCtrl,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Buscar por placa, carro, endereço ou telefone',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward), onPressed: _load),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(_dia == null
                          ? 'Qualquer dia'
                          : '${_dia!.day}/${_dia!.month}'),
                      selected: _dia != null,
                      onSelected: (_) async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dia ?? DateTime.now(),
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 90)),
                        );
                        setState(() => _dia = d);
                        _load();
                      },
                    ),
                    if (_dia != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() => _dia = null);
                          _load();
                        },
                      ),
                    const SizedBox(width: Spacing.sm),
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: _status == null,
                      onSelected: (_) {
                        setState(() => _status = null);
                        _load();
                      },
                    ),
                    for (final e in _estados.entries) ...[
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _status == e.key,
                        onSelected: (_) {
                          setState(() => _status = e.key);
                          _load();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Row(
            children: [
              Text('$_total pedido(s)',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              TextButton.icon(
                  onPressed: _exportar,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Exportar CSV')),
              IconButton(
                  onPressed: () => _novoPedido(context, _load),
                  icon: const Icon(Icons.add_circle, color: AppColors.primary)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final quando =
                          DateTime.tryParse(r['scheduled_at'].toString())
                              ?.toLocal();
                      return ListTile(
                        title: Text(
                            '${r['plate']} · ${_servico(r['service_type'])}'),
                        subtitle: Text(
                          '${_estados[r['status']] ?? r['status']}'
                          '${(r['washer_name'] ?? '').toString().isEmpty ? '' : ' · ${r['washer_name']}'}\n'
                          '${quando == null ? '' : '${quando.day}/${quando.month} ${quando.hour.toString().padLeft(2, '0')}:${quando.minute.toString().padLeft(2, '0')}'}'
                          ' · ${r['address_street']}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          '${(((r['total_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () => _abrirDetalhe(context, r['id'].toString(), _load),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  static String _servico(dynamic s) => switch (s) {
        'full' => 'Lavagem completa',
        'interior' => 'Só interior',
        _ => 'Lavagem externa',
      };
}

/// Criar pedido na mão (walk-in).
Future<void> _novoPedido(BuildContext context, VoidCallback onOk) async {
  final placa = TextEditingController();
  final tel = TextEditingController();
  final endereco = TextEditingController();
  String servico = 'exterior';
  DateTime quando = DateTime.now().add(const Duration(hours: 1));

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setL) => AlertDialog(
        title: const Text('Novo pedido (walk-in)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: servico,
                decoration: const InputDecoration(labelText: 'Serviço'),
                items: const [
                  DropdownMenuItem(value: 'exterior', child: Text('Lavagem externa')),
                  DropdownMenuItem(value: 'full', child: Text('Lavagem completa')),
                  DropdownMenuItem(value: 'interior', child: Text('Só interior')),
                ],
                onChanged: (v) => setL(() => servico = v!),
              ),
              TextField(
                  controller: placa,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Placa (matrícula)')),
              TextField(
                  controller: tel,
                  decoration: const InputDecoration(labelText: 'Telefone do cliente')),
              TextField(
                  controller: endereco,
                  decoration: const InputDecoration(labelText: 'Endereço da coleta')),
              const SizedBox(height: Spacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Quando: ${quando.day}/${quando.month} '
                    '${quando.hour.toString().padLeft(2, '0')}:'
                    '${quando.minute.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: quando,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)));
                  if (d == null || !ctx.mounted) return;
                  final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(quando));
                  if (t == null) return;
                  setL(() => quando =
                      DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Criar')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await _sb.rpc('admin_create_carwash_booking', params: {
      'p_service_type': servico,
      'p_plate': placa.text.trim(),
      'p_client_phone': tel.text.trim(),
      'p_scheduled_at': quando.toUtc().toIso8601String(),
      'p_address_street': endereco.text.trim(),
      'p_address_city': 'Guarda',
    });
    if (context.mounted) _msg(context, 'Pedido criado.');
    onOk();
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
  }
}

/// Detalhe completo + ações (editar, reagendar, cancelar, reatribuir).
Future<void> _abrirDetalhe(
    BuildContext context, String id, VoidCallback onOk) async {
  Map<String, dynamic>? d;
  try {
    final res = await _sb
        .rpc('admin_carwash_booking_detail', params: {'p_id': id});
    d = Map<String, dynamic>.from(res as Map);
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
    return;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text('${d!['plate']} · ${d['car_make_model']}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: Spacing.sm),
          _kv('Situação', d['status'].toString()),
          _kv('Serviço', d['service_type'].toString()),
          _kv('Endereço', d['address_street'].toString()),
          _kv('Telefone', d['client_phone'].toString()),
          _kv('Onde está a chave', d['pickup_notes'].toString()),
          _kv('Lavador', (d['washer_name'] ?? '—').toString()),
          _kv('Pagamento', d['payment_method'].toString()),
          _kv('Total', '${((d['total_cents'] as num) / 100).toStringAsFixed(2)} €'),
          _kv('Repasse ao lavador',
              '${((d['washer_earnings_cents'] as num) / 100).toStringAsFixed(2)} €'),
          _kv('Comissão Bora',
              '${((d['bora_fee_cents'] as num) / 100).toStringAsFixed(2)} €'),
          if (d['eta_minutes'] != null) _kv('ETA prometido', '${d['eta_minutes']} min'),

          const SizedBox(height: Spacing.lg),
          _fotosAdmin('Fotos na coleta (antes)', d['photos_before']),
          _fotosAdmin('Fotos na entrega (depois)', d['photos_after']),
          _fotosAdmin('Foto enviada pelo cliente', d['photos_client']),

          const SizedBox(height: Spacing.lg),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _reatribuir(context, id, onOk);
                },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Reatribuir a outro lavador'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _reagendar(context, id, onOk);
                },
                icon: const Icon(Icons.event),
                label: const Text('Reagendar'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _cancelar(context, id, onOk);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar pedido'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 150,
              child: Text(k,
                  style: const TextStyle(color: AppColors.textSubtle))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );

Widget _fotosAdmin(String titulo, dynamic raw) {
  final lista = (raw is List) ? raw : const [];
  if (lista.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
        child: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
          itemBuilder: (_, i) {
            final path = (lista[i] as Map)['url']?.toString() ?? '';
            return FutureBuilder<String?>(
              future: CarwashUploadService.signedUrl(path),
              builder: (_, snap) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: snap.data == null
                    ? Container(
                        width: 130, height: 100, color: AppColors.surface2)
                    : Image.network(snap.data!,
                        width: 130, height: 100, fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    ],
  );
}

Future<void> _reatribuir(
    BuildContext context, String id, VoidCallback onOk) async {
  List<Map<String, dynamic>> lavadores = [];
  try {
    final res = await _sb
        .rpc('admin_list_washers', params: {'p_status': 'approved', 'p_search': null});
    lavadores =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
    return;
  }
  if (!context.mounted) return;
  if (lavadores.isEmpty) {
    _msg(context, 'Nenhum lavador aprovado disponível.');
    return;
  }

  final escolhido = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Reatribuir para'),
      children: [
        for (final l in lavadores)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, l['id'].toString()),
            child: Text('${l['name']} · ${l['jobs_abertos']} em aberto'),
          ),
      ],
    ),
  );
  if (escolhido == null) return;
  try {
    await _sb.rpc('admin_reassign_carwash_booking',
        params: {'p_id': id, 'p_washer_id': escolhido});
    if (context.mounted) _msg(context, 'Pedido reatribuído.');
    onOk();
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
  }
}

Future<void> _reagendar(
    BuildContext context, String id, VoidCallback onOk) async {
  final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)));
  if (d == null || !context.mounted) return;
  final t = await showTimePicker(
      context: context, initialTime: TimeOfDay.now());
  if (t == null) return;
  final novo = DateTime(d.year, d.month, d.day, t.hour, t.minute);
  try {
    await _sb.rpc('admin_update_carwash_booking', params: {
      'p_id': id,
      'p_patch': {'scheduled_at': novo.toUtc().toIso8601String()},
    });
    if (context.mounted) _msg(context, 'Pedido reagendado.');
    onOk();
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
  }
}

Future<void> _cancelar(
    BuildContext context, String id, VoidCallback onOk) async {
  final motivo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancelar pedido'),
      content: TextField(
          controller: motivo,
          decoration: const InputDecoration(labelText: 'Motivo')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar pedido')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await _sb.rpc('admin_cancel_carwash_booking',
        params: {'p_id': id, 'p_reason': motivo.text.trim()});
    if (context.mounted) _msg(context, 'Pedido cancelado.');
    onOk();
  } catch (e) {
    if (context.mounted) _msg(context, 'Erro: $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LAVADORES
// ═══════════════════════════════════════════════════════════════════════════

class _AbaLavadores extends StatefulWidget {
  const _AbaLavadores();
  @override
  State<_AbaLavadores> createState() => _AbaLavadoresState();
}

class _AbaLavadoresState extends State<_AbaLavadores> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _sb
          .rpc('admin_list_washers', params: {'p_status': null, 'p_search': null});
      if (!mounted) return;
      setState(() {
        _rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg(context, 'Erro: $e');
    }
  }

  Future<void> _patch(String id, Map<String, dynamic> patch) async {
    try {
      await _sb.rpc('admin_update_washer', params: {'p_id': id, 'p_patch': patch});
      if (mounted) _msg(context, 'Atualizado.');
      _load();
    } catch (e) {
      if (mounted) {
        _msg(context, e.toString().contains('washer_has_open_jobs')
            ? 'Este lavador tem pedidos em aberto. Reatribua-os primeiro.'
            : 'Erro: $e');
      }
    }
  }

  Future<void> _editarRaio(Map<String, dynamic> l) async {
    final ctrl = TextEditingController(
        text: (l['service_radius_km'] ?? 8).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Raio de atendimento — ${l['name']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Raio em km',
              helperText: 'Distância máxima da base dele até o carro'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (v == null) return;
    await _patch(l['id'].toString(), {'service_radius_km': v});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Center(child: Text('Nenhum lavador cadastrado ainda.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final l = _rows[i];
          final id = l['id'].toString();
          final status = l['approval_status'].toString();
          final banido = l['is_banned'] == true;
          return ExpansionTile(
            title: Text(l['name'].toString().isEmpty
                ? '(sem nome)'
                : l['name'].toString()),
            subtitle: Text(
                '$status${banido ? ' · BANIDO' : ''} · '
                '${l['washes_done']} lavagens · '
                'raio ${l['service_radius_km']} km · '
                '${l['jobs_abertos']} em aberto'),
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    if (status != 'approved')
                      FilledButton(
                          onPressed: () =>
                              _patch(id, {'approval_status': 'approved'}),
                          child: const Text('Aprovar')),
                    if (status == 'approved')
                      OutlinedButton(
                          onPressed: () =>
                              _patch(id, {'approval_status': 'suspended'}),
                          child: const Text('Suspender')),
                    OutlinedButton(
                        onPressed: () => _editarRaio(l),
                        child: const Text('Editar raio')),
                    OutlinedButton(
                        onPressed: () =>
                            _patch(id, {'is_active': !(l['is_active'] == true)}),
                        child: Text(l['is_active'] == true
                            ? 'Desativar'
                            : 'Ativar')),
                    OutlinedButton(
                        onPressed: () => _patch(id, {'is_banned': !banido}),
                        child: Text(banido ? 'Remover banimento' : 'Banir')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AGRUPAR IDAS — dois ou três carros perto um do outro na mesma viagem
// ═══════════════════════════════════════════════════════════════════════════

class _AbaAgrupar extends StatefulWidget {
  const _AbaAgrupar();
  @override
  State<_AbaAgrupar> createState() => _AbaAgruparState();
}

class _AbaAgruparState extends State<_AbaAgrupar> {
  double _raio = 1.5;
  int _horas = 6;
  List<Map<String, dynamic>> _grupos = [];
  bool _loading = false;

  Future<void> _buscar() async {
    setState(() => _loading = true);
    try {
      final agora = DateTime.now();
      final res = await _sb.rpc('admin_carwash_group_trips', params: {
        'p_from': agora.toUtc().toIso8601String(),
        'p_to': agora.add(Duration(hours: _horas)).toUtc().toIso8601String(),
        'p_radius_km': _raio,
      });
      if (!mounted) return;
      setState(() {
        _grupos = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg(context, 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mostra carros próximos uns dos outros na mesma janela de '
                'horas — para levar dois ou três na mesma viagem.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Raio: ${_raio.toStringAsFixed(1)} km'),
                        Slider(
                          value: _raio,
                          min: 0.5,
                          max: 5,
                          divisions: 9,
                          onChanged: (v) => setState(() => _raio = v),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Janela: $_horas h'),
                        Slider(
                          value: _horas.toDouble(),
                          min: 1,
                          max: 24,
                          divisions: 23,
                          onChanged: (v) => setState(() => _horas = v.toInt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: _buscar, child: const Text('Buscar grupos')),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _grupos.isEmpty
                  ? const Center(
                      child: Text('Nenhum grupo encontrado nessa janela.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: _grupos.length,
                      itemBuilder: (_, i) {
                        final g = _grupos[i];
                        final perto = (g['perto'] as List?) ?? [];
                        return Card(
                          child: ExpansionTile(
                            title: Text('${g['quantos']} carros juntos'),
                            subtitle: Text(
                                '${g['ancora_morada']} · total '
                                '${(((g['total_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)} €'),
                            children: [
                              for (final p in perto)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.directions_car),
                                  title: Text('${(p as Map)['plate']}'),
                                  subtitle: Text('${p['morada']} · ${p['km']} km'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ACERTOS SEMANAIS
// ═══════════════════════════════════════════════════════════════════════════

class _AbaAcertos extends StatefulWidget {
  const _AbaAcertos();
  @override
  State<_AbaAcertos> createState() => _AbaAcertosState();
}

class _AbaAcertosState extends State<_AbaAcertos> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await _sb.rpc('admin_list_carwash_settlements', params: {'p_status': null});
      if (!mounted) return;
      setState(() {
        _rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg(context, 'Erro: $e');
    }
  }

  Future<void> _recalcular() async {
    List<Map<String, dynamic>> lavadores = [];
    try {
      final res = await _sb.rpc('admin_list_washers',
          params: {'p_status': 'approved', 'p_search': null});
      lavadores =
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (!mounted || lavadores.isEmpty) return;

    final escolhido = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Recalcular semana de'),
        children: [
          for (final l in lavadores)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l['id'].toString()),
              child: Text(l['name'].toString()),
            ),
        ],
      ),
    );
    if (escolhido == null) return;

    // Segunda-feira da semana corrente.
    final hoje = DateTime.now();
    final segunda = hoje.subtract(Duration(days: hoje.weekday - 1));
    try {
      await _sb.rpc('admin_carwash_recalc_settlement', params: {
        'p_washer_id': escolhido,
        'p_week_start': segunda.toIso8601String().split('T').first,
      });
      if (mounted) _msg(context, 'Acerto recalculado.');
      _load();
    } catch (e) {
      if (mounted) _msg(context, 'Erro: $e');
    }
  }

  Future<void> _marcarPago(String id) async {
    try {
      await _sb.rpc('admin_mark_carwash_settlement_paid',
          params: {'p_id': id, 'p_method': 'mbway', 'p_reference': ''});
      if (mounted) _msg(context, 'Marcado como pago.');
      _load();
    } catch (e) {
      if (mounted) _msg(context, 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _recalcular,
              icon: const Icon(Icons.calculate),
              label: const Text('Recalcular semana atual'),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const Center(child: Text('Nenhum acerto gerado ainda.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = _rows[i];
                        final ini =
                            DateTime.tryParse(s['week_start_at'].toString());
                        return ListTile(
                          title: Text(s['washer_name'].toString()),
                          subtitle: Text(
                              'Semana de ${ini?.day}/${ini?.month} · '
                              '${s['total_jobs']} lavagens · ${s['status']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  '${(((s['net_payout_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)} €',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              if (s['status'] != 'paid')
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline),
                                  tooltip: 'Marcar como pago',
                                  onPressed: () =>
                                      _marcarPago(s['id'].toString()),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURAÇÕES — todos os preços e ajustes
// ═══════════════════════════════════════════════════════════════════════════

class _AbaConfig extends StatefulWidget {
  const _AbaConfig();
  @override
  State<_AbaConfig> createState() => _AbaConfigState();
}

class _AbaConfigState extends State<_AbaConfig> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _sb.rpc('admin_carwash_settings');
      if (!mounted) return;
      setState(() {
        _rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg(context, 'Erro: $e');
    }
  }

  Future<void> _gravar(String key, dynamic value) async {
    try {
      await _sb.rpc('admin_set_carwash_setting',
          params: {'p_key': key, 'p_value': value});
      if (mounted) _msg(context, 'Salvo.');
      _load();
    } catch (e) {
      if (mounted) _msg(context, 'Erro: $e');
    }
  }

  Future<void> _editarTexto(Map<String, dynamic> s) async {
    final ctrl = TextEditingController(text: s['value'].toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['key'].toString()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s['description']?.toString() ?? '',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.sm),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Valor')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final txt = ctrl.text.trim();
    // número puro fica número; o resto vai como veio (JSON aceita ambos).
    final num? n = num.tryParse(txt);
    await _gravar(s['key'].toString(), n ?? txt);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(Spacing.md),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final s = _rows[i];
          final key = s['key'].toString();
          final v = s['value'];
          final isBool = v is bool;
          return ListTile(
            title: Text(key),
            subtitle: Text(s['description']?.toString() ?? ''),
            trailing: isBool
                ? Switch(
                    value: v,
                    onChanged: (nv) => _gravar(key, nv),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 18),
                    ],
                  ),
            onTap: isBool ? null : () => _editarTexto(s),
          );
        },
      ),
    );
  }
}
