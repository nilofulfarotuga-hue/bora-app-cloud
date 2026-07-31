// T9 — Admin clients management screen.
// Mirrors admin_drivers_screen pattern. Uses admin_list_clients RPC.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/admin/admin_user_roles_sheet.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminClientsScreen extends StatefulWidget {
  const AdminClientsScreen({super.key});

  @override
  State<AdminClientsScreen> createState() => _AdminClientsScreenState();
}

class _AdminClientsScreenState extends State<AdminClientsScreen> {
  final _search = TextEditingController();
  bool _bannedOnly = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];

  // Q5 (2026-05-17) — contagem de blocks por cliente.
  // client_user_id → numero de restaurantes em que está blocked.
  Map<String, int> _blocksByClient = const {};

  // Q5 — cache de partners para dropdown no dialog block (lazy-loaded).
  List<Map<String, dynamic>>? _partnersCache;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      debugPrint('[admin_clients] RPC admin_list_clients '
          'search=${_search.text} banned_only=$_bannedOnly');
      final res = await Supabase.instance.client.rpc(
        'admin_list_clients',
        params: {
          'p_search': _search.text.isEmpty ? null : _search.text.trim(),
          'p_banned_only': _bannedOnly,
          'p_limit': 100,
          'p_offset': 0,
        },
      );
      debugPrint('[admin_clients] RPC response type=${res.runtimeType} '
          'len=${res is List ? res.length : "?"}');
      if (res is List && res.isNotEmpty) {
        debugPrint('[admin_clients] sample row keys=${(res.first as Map).keys.toList()}');
      }
      if (mounted) {
        setState(() {
          _clients = (res as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
      }
      // Q5 — carregar blocks em paralelo (não bloqueante).
      _loadBlocksByClient();
    } catch (e, st) {
      debugPrint('[admin_clients] _load error: $e\n$st');
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Q5 — contagem de blocks por cliente carregada via SELECT directo
  // (RLS admin policy permite). Não bloqueia o load principal.
  Future<void> _loadBlocksByClient() async {
    try {
      final rows = await Supabase.instance.client
          .from('client_restaurant_profiles')
          .select('client_user_id')
          .eq('is_blocked', true);
      final counts = <String, int>{};
      for (final raw in (rows as List)) {
        final id = (raw as Map)['client_user_id']?.toString();
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      if (mounted) setState(() => _blocksByClient = counts);
    } catch (e) {
      debugPrint('[admin_clients] _loadBlocksByClient error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadPartnersOnce() async {
    if (_partnersCache != null) return _partnersCache!;
    try {
      final res = await Supabase.instance.client
          .rpc('admin_partners_with_counts');
      _partnersCache = ((res as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) => (a['name'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['name'] as String? ?? '').toLowerCase()));
      return _partnersCache!;
    } catch (e) {
      debugPrint('[admin_clients] _loadPartnersOnce error: $e');
      return const [];
    }
  }

  String _initialFor(Map<String, dynamic> c) {
    final name = (c['bora_name'] as String?) ?? '';
    final email = (c['email'] as String?) ?? '';
    final source = name.isNotEmpty ? name : email;
    return source.isNotEmpty ? source[0].toUpperCase() : '?';
  }

  String _displayNameFor(Map<String, dynamic> c) {
    final name = (c['bora_name'] as String?) ?? '';
    final email = (c['email'] as String?) ?? '—';
    return name.isNotEmpty ? name : email;
  }

  Future<void> _ban(Map<String, dynamic> client) async {
    final reasonCtrl = TextEditingController();
    bool permanent = false;
    DateTime? until;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Banir ${client['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Ban permanente'),
                value: permanent,
                onChanged: (v) => setSt(() => permanent = v),
              ),
              if (!permanent)
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(until == null
                      ? 'Escolher data fim'
                      : 'Até ${until.toString().substring(0, 10)}'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                    );
                    if (picked != null) setSt(() => until = picked);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('BANIR'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    if (reasonCtrl.text.trim().length < 3) return;

    try {
      await Supabase.instance.client.rpc('admin_ban_client', params: {
        'p_user_id': client['user_id'],
        'p_reason': reasonCtrl.text.trim(),
        'p_banned_until': permanent ? null : until?.toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Banido')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _unban(Map<String, dynamic> client) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desbanir ${client['email']}'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desbanir')),
        ],
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      await Supabase.instance.client.rpc('admin_unban_client', params: {
        'p_user_id': client['user_id'],
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Desbanido')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // Q5 (2026-05-17) — Bloquear cliente de um restaurante específico.
  // admin_block_client(p_client_user_id uuid, p_restaurant_id text, p_reason text)
  // Diferente de ban: este é por-restaurante (cliente continua a poder
  // usar a Bora noutros parceiros). Uso típico: parceiro pediu para banir
  // cliente da SUA loja.
  Future<void> _block(Map<String, dynamic> client) async {
    final reasonCtrl = TextEditingController();
    String? selectedPartnerId;
    String? selectedPartnerName;
    final partners = await _loadPartnersOnce();
    if (!mounted) return;
    if (partners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem parceiros disponíveis.'),
          backgroundColor: AppColors.warning));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Bloquear de restaurante · ${client['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O cliente não vai conseguir pedir deste restaurante. '
                'Continua activo noutros parceiros.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedPartnerId,
                decoration: const InputDecoration(labelText: 'Restaurante'),
                items: partners.map((p) {
                  final id = p['id']?.toString() ?? '';
                  final name = (p['name'] as String?) ?? id;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (v) => setSt(() {
                  selectedPartnerId = v;
                  selectedPartnerName = partners
                      .firstWhere(
                        (x) => x['id']?.toString() == v,
                        orElse: () => const {},
                      )['name'] as String?;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                    labelText: 'Motivo (obrigatório, 3+ chars)'),
                maxLines: 2,
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: (selectedPartnerId != null &&
                      reasonCtrl.text.trim().length >= 3)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Bloquear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('admin_block_client', params: {
        'p_client_user_id': client['user_id'],
        'p_restaurant_id': selectedPartnerId,
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Cliente bloqueado de ${selectedPartnerName ?? selectedPartnerId}.'),
            backgroundColor: AppColors.warning));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  // Q5 (2026-05-17) — Desbloquear cliente de um restaurante.
  // Mostra lista dos restaurantes onde o cliente está bloqueado e permite
  // escolher qual desbloquear.
  Future<void> _unblock(Map<String, dynamic> client) async {
    final clientUserId = client['user_id'] as String?;
    if (clientUserId == null) return;
    // Carrega profiles bloqueados deste cliente.
    List<Map<String, dynamic>> blocked = const [];
    try {
      final rows = await Supabase.instance.client
          .from('client_restaurant_profiles')
          .select('restaurant_id, blocked_reason, blocked_at')
          .eq('client_user_id', clientUserId)
          .eq('is_blocked', true);
      blocked = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error));
      }
      return;
    }
    if (!mounted) return;
    if (blocked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cliente não tem nenhum bloqueio activo.')));
      return;
    }
    // Enriquecer com nomes de partners (cache).
    final partners = await _loadPartnersOnce();
    final partnerName = <String, String>{
      for (final p in partners)
        (p['id']?.toString() ?? ''): (p['name'] as String?) ?? '?'
    };
    if (!mounted) return;

    final noteCtrl = TextEditingController();
    String? targetRid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Desbloquear · ${client['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha de qual restaurante remover o bloqueio.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.maxFinite,
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: blocked.length,
                  itemBuilder: (_, i) {
                    final b = blocked[i];
                    final rid = (b['restaurant_id'] as String?) ?? '';
                    final name = partnerName[rid] ?? rid;
                    final reason = b['blocked_reason'] as String? ?? '—';
                    return RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(reason,
                          style: const TextStyle(fontSize: 11)),
                      value: rid,
                      groupValue: targetRid,
                      onChanged: (v) => setSt(() => targetRid = v),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  helperText: 'Visível no audit log',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed:
                  targetRid != null ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Desbloquear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('admin_unblock_client', params: {
        'p_client_user_id': clientUserId,
        'p_restaurant_id': targetRid,
        'p_note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Desbloqueado.'),
            backgroundColor: AppColors.success));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _showHistory(Map<String, dynamic> client) async {
    try {
      final res = await Supabase.instance.client.rpc('admin_get_client_history', params: {
        'p_user_id': client['user_id'],
        'p_limit': 50,
      });
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final orders = List<Map<String, dynamic>>.from(data['orders'] as List? ?? []);
      final tokens = List<Map<String, dynamic>>.from(data['tokens'] as List? ?? []);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Histórico — ${client['email']}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('Pedidos (${orders.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              ...orders.map((o) => ListTile(
                    title: Text('${o['vendor_name'] ?? '—'} · €${o['price']}'),
                    subtitle: Text('${o['status']} · ${o['created_at']}'),
                  )),
              const SizedBox(height: 12),
              Text('Tokens (${tokens.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ...tokens.map((t) => ListTile(
                    title: Text('${t['amount']} (${t['role']})'),
                    subtitle: Text(
                        '${t['is_used'] == true ? 'usado' : 'activo'} · expira ${t['expires_at']}'),
                  )),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  /// Item 20 (paridade-admin-360): exportar a lista visível para CSV.
  Future<void> _exportCsv() async {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      await AdminExportService.instance.exportCsv(
        filename: 'bora_clientes_$stamp.csv',
        headers: const [
          'email', 'nome', 'telefone', 'criado_em',
          'pedidos', 'total_gasto', 'tokens', 'banido'
        ],
        rows: _clients
            .map((c) => [
                  c['email'] ?? '',
                  c['bora_name'] ?? '',
                  c['bora_phone'] ?? '',
                  c['created_at'] ?? '',
                  c['total_orders'] ?? 0,
                  c['total_spent'] ?? 0,
                  c['token_balance'] ?? 0,
                  (c['is_banned'] == true) ? 'sim' : 'não',
                ])
            .toList(),
        subject: 'Clientes Bora ($stamp)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Clientes',
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
            onPressed: _clients.isEmpty ? null : _exportCsv,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Buscar email/nome/telefone',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Banidos'),
                  selected: _bannedOnly,
                  onSelected: (v) {
                    setState(() => _bannedOnly = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.error.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Erro: $_error',
                      style: const TextStyle(color: AppColors.error))),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _clients.isEmpty
                        ? const Center(child: Text('Sem clientes.'))
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _clients.length,
                        itemBuilder: (ctx, i) {
                          final c = _clients[i];
                          final banned = c['is_banned'] == true;
                          final userId = c['user_id']?.toString() ?? '';
                          final blockCount = _blocksByClient[userId] ?? 0;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Radii.lg),
                            ),
                            child: ListTile(
                              leading: _ClientAvatar(
                                photoUrl: c['photo_url']?.toString(),
                                initials: _initialFor(c),
                                banned: banned,
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(_displayNameFor(c))),
                                  if (banned) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.error,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'BANIDO',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (blockCount > 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'BLOQUEADO em $blockCount',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                  '${c['email'] ?? "—"} · ${c['total_orders'] ?? 0} pedidos · €${c['total_spent'] ?? 0}\n'
                                  '${c['token_balance'] ?? 0} tokens · ${banned ? "BANIDO até ${c['banned_until']}" : "Activo"}'),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'history') _showHistory(c);
                                  if (action == 'roles') {
                                    // MULTI-PAPEL: ver/adicionar/remover papéis.
                                    showAdminUserRolesSheet(
                                      context: context,
                                      userId: c['user_id'] as String,
                                      userLabel:
                                          (c['email'] ?? c['name'] ?? '—')
                                              .toString(),
                                    );
                                  }
                                  if (action == 'ban') _ban(c);
                                  if (action == 'unban') _unban(c);
                                  if (action == 'block') _block(c);
                                  if (action == 'unblock') _unblock(c);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'history', child: Text('Histórico')),
                                  const PopupMenuItem(
                                      value: 'roles',
                                      child: Text('Papéis do usuário')),
                                  if (!banned)
                                    const PopupMenuItem(value: 'ban', child: Text('Banir da app')),
                                  if (banned)
                                    const PopupMenuItem(value: 'unban', child: Text('Desbanir')),
                                  const PopupMenuItem(
                                      value: 'block',
                                      child: Text('Bloquear de restaurante')),
                                  if (blockCount > 0)
                                    const PopupMenuItem(
                                        value: 'unblock',
                                        child: Text('Desbloquear...')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Avatar do cliente no admin panel — mostra foto se existir,
/// senão iniciais. Border vermelha quando banido.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({
    required this.photoUrl,
    required this.initials,
    required this.banned,
  });

  final String? photoUrl;
  final String initials;
  final bool banned;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    final bg = banned ? AppColors.error : AppColors.primary;
    return Container(
      decoration: banned
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.error, width: 2),
            )
          : null,
      child: CircleAvatar(
        backgroundColor: bg,
        backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
        onBackgroundImageError:
            hasPhoto ? (_, __) {/* fallback to initials */} : null,
        child: hasPhoto
            ? null
            : Text(initials, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
