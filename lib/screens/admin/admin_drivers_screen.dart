import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import 'admin_driver_detail_screen.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _drivers = [];
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
      final data = await Supabase.instance.client
          .from('drivers')
          .select(
              'id, name, phone, vehicle_type, is_online, approval_status, rating, total_deliveries')
          .order('name');
      if (mounted) {
        setState(() {
          _drivers = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback se as colunas rating/total_deliveries não existirem.
      try {
        final data = await Supabase.instance.client
            .from('drivers')
            .select('id, name, phone, vehicle_type, is_online, approval_status')
            .order('name');
        if (mounted) {
          setState(() {
            _drivers = List<Map<String, dynamic>>.from(data);
            _loading = false;
          });
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _error = e2.toString();
            _loading = false;
          });
        }
      }
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
        return AppColors.primary;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
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
    return _drivers.where((d) {
      if (onlyOnline && !((d['is_online'] as bool?) ?? false)) return false;
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
    final onlineFiltered = _filtered(onlyOnline: true);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Entregadores'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.black54,
          indicatorColor: AppColors.primary,
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
