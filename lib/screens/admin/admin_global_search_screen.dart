// BLOCO C (2026-05-18) — Pesquisa Global Admin Cross-Entity.
//
// Padrão Uber Eats / Glovo / iFood admin: barra de pesquisa global no
// AppBar que pesquisa simultaneamente em Clientes, Entregadores, Parceiros
// e Pedidos.
//
// PT-BR (Regra 6).
//
// Sources:
//   • Clientes: admin_list_clients(p_search, p_limit=10)
//   • Entregadores: admin_live_drivers() filtrado client-side
//   • Parceiros: admin_partners_with_counts() filtrado client-side
//   • Pedidos: from('orders') select por id_curto OU customer_name ILIKE

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_primary_button.dart';
import 'admin_clients_screen.dart';
import 'admin_driver_detail_screen.dart';
import 'admin_order_detail_screen.dart';
import 'admin_partner_detail_screen.dart';

class AdminGlobalSearchScreen extends StatefulWidget {
  const AdminGlobalSearchScreen({super.key});

  @override
  State<AdminGlobalSearchScreen> createState() =>
      _AdminGlobalSearchScreenState();
}

class _AdminGlobalSearchScreenState extends State<AdminGlobalSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  List<Map<String, dynamic>> _clients = const [];
  List<Map<String, dynamic>> _drivers = const [];
  List<Map<String, dynamic>> _partners = const [];
  List<Map<String, dynamic>> _orders = const [];

  // Cache dos drivers e partners (não filtrados — filtramos client-side).
  List<Map<String, dynamic>>? _allDriversCache;
  List<Map<String, dynamic>>? _allPartnersCache;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 3) {
      setState(() {
        _clients = const [];
        _drivers = const [];
        _partners = const [];
        _orders = const [];
        _error = null;
        _lastQuery = q;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = q;
    });
    try {
      // Cargas em paralelo.
      final results = await Future.wait([
        _searchClients(q),
        _searchDriversAndPartners(q),
        _searchOrders(q),
      ]);
      if (!mounted || _lastQuery != q) return; // outdated response
      setState(() {
        _clients = results[0] as List<Map<String, dynamic>>;
        final dp = results[1] as Map<String, List<Map<String, dynamic>>>;
        _drivers = dp['drivers'] ?? const [];
        _partners = dp['partners'] ?? const [];
        _orders = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _searchClients(String q) async {
    try {
      final res = await _supabase.rpc('admin_list_clients', params: {
        'p_search': q,
        'p_banned_only': false,
        'p_limit': 10,
        'p_offset': 0,
      });
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _searchDriversAndPartners(
      String q) async {
    // Carrega caches uma vez (sessão de pesquisa).
    if (_allDriversCache == null) {
      try {
        final res = await _supabase.rpc('admin_live_drivers');
        _allDriversCache = (res as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        _allDriversCache = const [];
      }
    }
    if (_allPartnersCache == null) {
      try {
        final res = await _supabase.rpc('admin_partners_with_counts');
        _allPartnersCache = (res as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        _allPartnersCache = const [];
      }
    }
    final lq = q.toLowerCase();
    final drivers = _allDriversCache!.where((d) {
      final name = (d['driver_name'] as String? ?? '').toLowerCase();
      final phone = (d['driver_phone'] as String? ?? '').toLowerCase();
      final id = (d['driver_id'] as String? ?? '').toLowerCase();
      return name.contains(lq) || phone.contains(lq) || id.startsWith(lq);
    }).take(10).toList();
    final partners = _allPartnersCache!.where((p) {
      final name = (p['name'] as String? ?? '').toLowerCase();
      final id = (p['id']?.toString() ?? '').toLowerCase();
      return name.contains(lq) || id.startsWith(lq);
    }).take(10).toList();
    return {'drivers': drivers, 'partners': partners};
  }

  Future<List<Map<String, dynamic>>> _searchOrders(String q) async {
    try {
      // Estratégia: tenta uuid prefix (id) + customer_name ILIKE + vendor_name ILIKE.
      final like = '%$q%';
      final res = await _supabase
          .from('orders')
          .select(
              'id, status, payment_method, vendor_name, customer_name, price, created_at')
          .or('customer_name.ilike.$like,vendor_name.ilike.$like,id.ilike.$q%')
          .order('created_at', ascending: false)
          .limit(10);
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ─── Navegação ────────────────────────────────────────────────────────────

  void _openClient(Map<String, dynamic> c) {
    // Não existe ecrã de detalhe individual de cliente; navegamos para
    // o ecrã de clientes (a pesquisa será reaplicada lá).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminClientsScreen()),
    );
  }

  void _openDriver(Map<String, dynamic> d) {
    final id = (d['driver_id'] as String?) ?? '';
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDriverDetailScreen(driverId: id),
      ),
    );
  }

  void _openPartner(Map<String, dynamic> p) {
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = (p['name'] as String?) ?? id;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPartnerDetailScreen(
          restaurantId: id,
          initialName: name,
        ),
      ),
    );
  }

  void _openOrder(Map<String, dynamic> o) {
    final id = (o['id'] as String?) ?? '';
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminOrderDetailScreen(orderId: id),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasQuery = _lastQuery.length >= 3;
    final hasAnyResult = _clients.isNotEmpty ||
        _drivers.isNotEmpty ||
        _partners.isNotEmpty ||
        _orders.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onChanged,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: const InputDecoration(
              hintText: 'Buscar clientes, entregadores, parceiros, pedidos...',
              hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.white70),
            ),
          ),
        ),
        actions: [
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchCtrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(hasQuery, hasAnyResult),
    );
  }

  Widget _buildBody(bool hasQuery, bool hasAnyResult) {
    if (!hasQuery) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 64, color: AppColors.textSubtle),
              SizedBox(height: 12),
              Text(
                'Digite 3 ou mais caracteres para buscar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              SizedBox(height: 6),
              Text(
                'A busca cobre clientes, entregadores, parceiros e pedidos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              BoraPrimaryButton(
                label: 'Tentar novamente',
                expanded: false,
                onPressed: () => _runSearch(_lastQuery),
              ),
            ],
          ),
        ),
      );
    }
    if (!hasAnyResult) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.textSubtle),
              const SizedBox(height: 12),
              Text(
                'Nenhum resultado para "$_lastQuery".',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_clients.isNotEmpty)
          _buildSection(
            'Clientes',
            Icons.person,
            Colors.blue,
            _clients,
            (c) => _clientTile(c),
          ),
        if (_drivers.isNotEmpty)
          _buildSection(
            'Entregadores',
            Icons.two_wheeler,
            Colors.purple,
            _drivers,
            (d) => _driverTile(d),
          ),
        if (_partners.isNotEmpty)
          _buildSection(
            'Parceiros',
            Icons.storefront,
            Colors.deepOrange,
            _partners,
            (p) => _partnerTile(p),
          ),
        if (_orders.isNotEmpty)
          _buildSection(
            'Pedidos',
            Icons.shopping_bag,
            Colors.green,
            _orders,
            (o) => _orderTile(o),
          ),
      ],
    );
  }

  Widget _buildSection(
    String title,
    IconData icon,
    Color color,
    List<Map<String, dynamic>> rows,
    Widget Function(Map<String, dynamic>) builder,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                '$title (${rows.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        ...rows.map(builder),
        const Divider(height: 1, color: AppColors.divider),
      ],
    );
  }

  Widget _clientTile(Map<String, dynamic> c) {
    final banned = c['is_banned'] == true;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: banned ? Colors.red : Colors.blue,
        child: const Icon(Icons.person, color: Colors.white, size: 16),
      ),
      title: Text((c['bora_name'] as String?) ?? (c['email'] as String? ?? '—')),
      subtitle: Text(
        '${c['email'] ?? '—'} · ${c['total_orders'] ?? 0} pedidos',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: banned
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
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
            )
          : null,
      onTap: () => _openClient(c),
    );
  }

  Widget _driverTile(Map<String, dynamic> d) {
    final isAvailable = d['is_available'] == true;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isAvailable ? Colors.green : Colors.grey,
        child: const Icon(Icons.two_wheeler, color: Colors.white, size: 16),
      ),
      title: Text((d['driver_name'] as String?) ?? '—'),
      subtitle: Text(
        '${d['driver_phone'] ?? '—'} · ${d['vehicle_type'] ?? '—'}',
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _openDriver(d),
    );
  }

  Widget _partnerTile(Map<String, dynamic> p) {
    final orderCount = (p['order_count'] as num?)?.toInt() ?? 0;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.deepOrange,
        child: const Icon(Icons.storefront, color: Colors.white, size: 16),
      ),
      title: Text((p['name'] as String?) ?? '—'),
      subtitle: Text(
        '${p['category'] ?? '—'} · $orderCount pedidos',
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _openPartner(p),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    final id = (o['id'] as String?) ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8) : id;
    final status = (o['status'] as String?) ?? '';
    final total = (o['price'] as num?)?.toDouble() ?? 0;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.green,
        child: const Icon(Icons.shopping_bag, color: Colors.white, size: 16),
      ),
      title: Text(
        '#$shortId · ${o['vendor_name'] ?? '—'}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${o['customer_name'] ?? '—'} · $status · €${total.toStringAsFixed(2)}',
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _openOrder(o),
    );
  }
}
