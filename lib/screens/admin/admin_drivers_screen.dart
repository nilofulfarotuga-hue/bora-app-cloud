import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/gps_parado.dart';
import '../../widgets/admin/escolher_estafeta_sheet.dart' show haQuantoTempo;
import 'admin_driver_detail_screen.dart';

/// Gestão de Entregadores (PT-BR). Aba "Todos" lê a tabela `drivers`; a aba
/// "Online" [A10 23/09] lê a RPC `admin_drivers_for_assignment` (a mesma do
/// "Escolher entregador") para mostrar, por entregador ligado, o último sinal e
/// o GPS — "GPS ok" ou, em vermelho, "GPS parado há X min" (`gps_fresco`
/// falso, limite `dispatch_gps_fresh_seconds` no servidor). É o caso Euliney:
/// heartbeat vivo, app morta, 19 h sem posição, e o painel dizia "online".
class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _drivers = [];

  /// Linhas da RPC admin_drivers_for_assignment por `drivers.id` (heartbeat,
  /// `gps_age_s`, `gps_fresco`). null = a RPC falhou → a aba "Online" cai no
  /// `is_online` da tabela, sem a linha de presença.
  Map<String, Map<String, dynamic>>? _presenca;
  bool _loading = true;
  String? _error;
  late TabController _tab;
  String _statusFilter = 'all'; // all | approved | pending | rejected
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> lista;
      try {
        final data = await Supabase.instance.client
            .from('drivers')
            .select(
              'id, name, phone, vehicle_type, is_online, approval_status, rating, total_deliveries',
            )
            .order('name');
        lista = List<Map<String, dynamic>>.from(data);
      } catch (_) {
        // Fallback se as colunas rating/total_deliveries não existirem.
        final data = await Supabase.instance.client
            .from('drivers')
            .select('id, name, phone, vehicle_type, is_online, approval_status')
            .order('name');
        lista = List<Map<String, dynamic>>.from(data);
      }
      final presenca = await _carregarPresenca();
      if (mounted) {
        setState(() {
          _drivers = lista;
          _presenca = presenca;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// [A10] Presença de cada entregador aprovado (heartbeat + GPS), pela RPC do
  /// "Escolher entregador" sem pedido nem pesquisa. Nunca deita a aba abaixo:
  /// em erro devolve null e a aba "Online" usa só o `is_online` da tabela.
  Future<Map<String, Map<String, dynamic>>?> _carregarPresenca() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_drivers_for_assignment',
        params: {'p_order_id': null, 'p_search': null},
      );
      if (res is! List) return null;
      final out = <String, Map<String, dynamic>>{};
      for (final r in res.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final id = m['driver_id']?.toString();
        if (id != null && id.isNotEmpty) out[id] = m;
      }
      return out;
    } catch (e) {
      debugPrint('[AdminDrivers] presença (admin_drivers_for_assignment): $e');
      return null;
    }
  }

  void _openDetail(Map<String, dynamic> driver) {
    final id = driver['id'] as String?;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDriverDetailScreen(driverId: id),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textSubtle;
    }
  }

  String _statusLabel(String status) {
    const labels = {
      'approved': 'Aprovado',
      'pending': 'Pendente',
      'rejected': 'Rejeitado'
    };
    return labels[status] ?? status;
  }

  List<Map<String, dynamic>> _filtered({required bool onlyOnline}) {
    return _aplicarFiltros(
      _drivers.where(
        (d) => !onlyOnline || ((d['is_online'] as bool?) ?? false),
      ),
    );
  }

  /// Aba "Online" [A10]: as linhas da RPC com `is_online` (já ordenadas pelo
  /// servidor: ligados agora primeiro, depois pelo último sinal), no formato da
  /// lista, com rating/pedidos da tabela quando existem e a presença em
  /// `_presenca`. Sem RPC cai no `is_online` da tabela.
  List<Map<String, dynamic>> _online() {
    final presenca = _presenca;
    if (presenca == null) return _filtered(onlyOnline: true);
    final porId = {for (final d in _drivers) d['id']?.toString(): d};
    return _aplicarFiltros(
      presenca.values.where((p) => p['is_online'] == true).map((p) {
        final id = p['driver_id']?.toString();
        final base = porId[id] ?? const <String, dynamic>{};
        return <String, dynamic>{
          ...base,
          'id': id,
          'name': p['name'],
          'phone': p['phone'],
          'vehicle_type': p['vehicle_type'],
          'is_online': true,
          'approval_status': base['approval_status'] ?? 'approved',
          '_presenca': p,
        };
      }),
    );
  }

  List<Map<String, dynamic>> _aplicarFiltros(
    Iterable<Map<String, dynamic>> src,
  ) {
    return src.where((d) {
      if (_statusFilter != 'all' &&
          (d['approval_status'] as String? ?? 'pending') != _statusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = (d['name'] as String? ?? '').toLowerCase();
        final phone = (d['phone'] as String? ?? '').toLowerCase();
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !phone.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildList(List<Map<String, dynamic>> drivers) {
    if (drivers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sem entregadores nesta lista.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: drivers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = drivers[i];
          final status = d['approval_status'] as String? ?? 'pending';
          final isOnline = d['is_online'] as bool? ?? false;
          final rating = (d['rating'] as num?)?.toDouble();
          final totalDeliveries = (d['total_deliveries'] as num?)?.toInt();
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: ListTile(
              onTap: () => _openDetail(d),
              leading: Stack(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        _statusColor(status).withValues(alpha: 0.15),
                    child: Icon(
                      d['vehicle_type'] == 'car'
                          ? Icons.directions_car
                          : Icons.two_wheeler,
                      color: _statusColor(status),
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                d['name'] as String? ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['phone'] as String? ?? ''),
                  if (d['_presenca'] is Map)
                    _linhaPresenca(
                      Map<String, dynamic>.from(d['_presenca'] as Map),
                    ),
                  if (rating != null || totalDeliveries != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          if (rating != null) ...[
                            const Icon(Icons.star,
                                size: 13, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                          ],
                          if (totalDeliveries != null)
                            Text('$totalDeliveries pedidos',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54)),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [A10] "sinal há 3 s · GPS ok" ou, em vermelho, "GPS parado há 19 min".
  Widget _linhaPresenca(Map<String, dynamic> p) {
    final hb = DateTime.tryParse(p['last_heartbeat_at']?.toString() ?? '');
    final gpsFresco = p['gps_fresco'] != false;
    final gpsAge = (p['gps_age_s'] as num?)?.toInt();
    final corGps = gpsFresco ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering, size: 13, color: Colors.black54),
          const SizedBox(width: 3),
          Text(
            'sinal ${haQuantoTempo(hb)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Icon(
            gpsFresco ? Icons.gps_fixed : Icons.gps_off,
            size: 13,
            color: corGps,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              gpsFresco ? 'GPS ok' : gpsParadoTexto(gpsAge),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: corGps,
                fontWeight: gpsFresco ? null : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Procurar por nome ou telefone',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      })
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Todos', 'all'),
                _chip('Aprovados', 'approved'),
                _chip('Pendentes', 'pending'),
                _chip('Rejeitados', 'rejected'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = value),
        labelStyle: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600),
        selectedColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allFiltered = _filtered(onlyOnline: false);
    final onlineFiltered = _online();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text('Gestão de Entregadores'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Todos (${allFiltered.length})'),
            Tab(text: 'Online (${onlineFiltered.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : Column(
                  children: [
                    _buildFilters(),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          _buildList(allFiltered),
                          _buildList(onlineFiltered),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
