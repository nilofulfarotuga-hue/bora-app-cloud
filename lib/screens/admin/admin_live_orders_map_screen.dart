import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin/admin_order_service.dart';
import '../../utils/constants.dart';
import '../../widgets/admin/test_order_badge.dart';
import '_admin_cancel_order_dialog.dart';

/// Admin Live Operations — Pedidos & Drivers em Tempo Real (B1).
///
/// Backend: `admin_live_orders` + `admin_live_drivers` RPCs (SECURITY DEFINER).
/// Pinos:
///   - laranja → pickup de pedido pending (created/preparing/callingDriver)
///   - verde   → pickup de pedido active (driverAccepted/pickedUp/onTheWay)
///   - cinza   → dropoff (cliente)
///   - azul    → driver online
///
/// Polling 5s para orders + driver_locations (Realtime channels seriam ideais
/// mas exigem RLS público nas tabelas — preferimos polling via RPC com guard
/// admin para não vazar locations dos drivers a outros utilizadores).
class AdminLiveOrdersMapScreen extends StatefulWidget {
  const AdminLiveOrdersMapScreen({super.key});

  @override
  State<AdminLiveOrdersMapScreen> createState() =>
      _AdminLiveOrdersMapScreenState();
}

class _AdminLiveOrdersMapScreenState extends State<AdminLiveOrdersMapScreen> {
  GoogleMapController? _mapController;
  Timer? _pollTimer;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _drivers = const [];
  Map<String, dynamic>? _selected;

  /// 7-alpha-ADMIN-FILTER: toggle de inclusao de pedidos de teste.
  /// Default false (so reais). Re-fetch ao alternar.
  bool _incluirTeste = false;

  /// BLOCO D (2026-05-18) — toggle heatmap geográfico (client-side, agrupa
  /// pickup lat/lng dos pedidos visíveis em células ~200m e desenha Circles
  /// coloridos por densidade).
  bool _heatmapEnabled = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final supa = Supabase.instance.client;
      final results = await Future.wait([
        // 7-alpha-ADMIN-FILTER: passa toggle como param para a RPC filtrar.
        supa.rpc('admin_live_orders',
            params: {'p_include_test_orders': _incluirTeste}),
        supa.rpc('admin_live_drivers'),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = (results[0] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _drivers = (results[1] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    for (final o in _orders) {
      final id = o['id'] as String;
      final status = o['status'] as String? ?? 'created';
      final isActive = const {
        'driverAccepted',
        'pickedUp',
        'onTheWay'
      }.contains(status);
      final pickupLat = (o['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (o['pickup_lng'] as num?)?.toDouble();
      final dropLat = (o['dropoff_lat'] as num?)?.toDouble();
      final dropLng = (o['dropoff_lng'] as num?)?.toDouble();

      // 7-alpha-ADMIN-FILTER: prefixo [TESTE] no titulo quando is_test_order.
      final isTest = o['is_test_order'] == true;
      final testPrefix = isTest ? '[TESTE] ' : '';

      if (pickupLat != null && pickupLng != null) {
        markers.add(Marker(
          markerId: MarkerId('pickup_$id'),
          position: gmap.LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActive ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: '$testPrefix${o['vendor_name'] as String? ?? 'Coleta'}',
            snippet: '${o['service_type']} · €${o['total']}',
          ),
          onTap: () => setState(() => _selected = o),
        ));
      }

      if (dropLat != null && dropLng != null) {
        markers.add(Marker(
          markerId: MarkerId('drop_$id'),
          position: gmap.LatLng(dropLat, dropLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: '$testPrefix${o['customer_name'] as String? ?? 'Cliente'}',
            snippet: o['dropoff_address'] as String? ?? '',
          ),
          onTap: () => setState(() => _selected = o),
        ));
      }
    }

    for (final d in _drivers) {
      final id = d['driver_id'] as String;
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        markerId: MarkerId('driver_$id'),
        position: gmap.LatLng(lat, lng),
        rotation: (d['heading'] as num?)?.toDouble() ?? 0,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: d['driver_name'] as String? ?? 'Entregador',
          snippet: d['active_order_id'] != null
              ? 'Em entrega · #${(d['active_order_id'] as String).substring(0, 6)}'
              : 'Disponível',
        ),
        onTap: () => setState(() => _selected = d),
      ));
    }

    return markers;
  }

  /// BLOCO D — agrupa pickup lat/lng em células ~200m e devolve Circles.
  /// Cores por densidade: amarelo (1-2) → laranja (3-4) → vermelho (5+).
  Set<Circle> _buildHeatmapCircles() {
    if (!_heatmapEnabled || _orders.isEmpty) return const {};

    // Tamanho da célula em graus (aprox 0.002° ≈ ~220m em latitude).
    const cellSize = 0.002;
    final Map<String, _HeatCell> cells = {};

    for (final o in _orders) {
      final lat = (o['pickup_lat'] as num?)?.toDouble();
      final lng = (o['pickup_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final binLat = (lat / cellSize).floor() * cellSize;
      final binLng = (lng / cellSize).floor() * cellSize;
      final key = '$binLat,$binLng';
      final cell = cells.putIfAbsent(
        key,
        () => _HeatCell(
          centerLat: binLat + cellSize / 2,
          centerLng: binLng + cellSize / 2,
          count: 0,
        ),
      );
      cell.count++;
    }

    final out = <Circle>{};
    for (final c in cells.values) {
      final Color color;
      final double alpha;
      if (c.count >= 5) {
        color = Colors.red;
        alpha = 0.45;
      } else if (c.count >= 3) {
        color = Colors.orange;
        alpha = 0.35;
      } else {
        color = Colors.yellow;
        alpha = 0.25;
      }
      out.add(Circle(
        circleId: CircleId('heat_${c.centerLat}_${c.centerLng}'),
        center: gmap.LatLng(c.centerLat, c.centerLng),
        radius: 150,
        fillColor: color.withValues(alpha: alpha),
        strokeColor: color.withValues(alpha: alpha + 0.15),
        strokeWidth: 1,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _orders
        .where((o) => const {
              'created',
              'preparing',
              'callingDriver'
            }.contains(o['status']))
        .length;
    final activeCount = _orders.length - pendingCount;
    final onlineCount = _drivers.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos ao Vivo'),
        actions: [
          // 7-alpha-ADMIN-FILTER: switch para incluir pedidos de teste.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Incluir testes',
                    style: TextStyle(fontSize: 12)),
                Switch(
                  value: _incluirTeste,
                  activeThumbColor: Colors.orange.shade800,
                  onChanged: (v) {
                    setState(() => _incluirTeste = v);
                    _refresh();
                  },
                ),
              ],
            ),
          ),
          // BLOCO D (2026-05-18) — toggle heatmap geográfico.
          IconButton(
            icon: Icon(
              _heatmapEnabled
                  ? Icons.layers
                  : Icons.layers_outlined,
              color: _heatmapEnabled ? Colors.amber : null,
            ),
            tooltip: _heatmapEnabled
                ? 'Desligar heatmap'
                : 'Ligar heatmap (densidade de pedidos)',
            onPressed: () =>
                setState(() => _heatmapEnabled = !_heatmapEnabled),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Pendentes', pendingCount, Colors.orange),
                _stat('Ativos', activeCount, Colors.green),
                _stat('Entregadores', onlineCount, Colors.blue),
                _stat('Total', _orders.length, Colors.black87),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Text('Erro: $_error',
                  style: TextStyle(color: Colors.red.shade900)),
            ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: gmap.LatLng(kGuardaCenter.latitude,
                        kGuardaCenter.longitude),
                    zoom: 13,
                  ),
                  markers: _buildMarkers(),
                  // BLOCO D (2026-05-18) — overlay heatmap quando activo.
                  circles: _buildHeatmapCircles(),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  onMapCreated: (c) => _mapController = c,
                  onTap: (_) => setState(() => _selected = null),
                ),
                if (_loading)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _SidePanel(
                      data: _selected!,
                      onClose: () => setState(() => _selected = null),
                      onCancelOrder: () async {
                        // Q3 (2026-05-17) — Cancelar pedido directamente do mapa.
                        final order = _selected!;
                        final result =
                            await showDialog<AdminCancelOrderResult>(
                          context: context,
                          builder: (_) =>
                              AdminCancelOrderDialog(order: order),
                        );
                        if (result != null) {
                          if (mounted) {
                            setState(() => _selected = null);
                          }
                          await _refresh();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 18, color: color, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// BLOCO D (2026-05-18) — célula de heatmap (interno).
class _HeatCell {
  _HeatCell({
    required this.centerLat,
    required this.centerLng,
    required this.count,
  });
  final double centerLat;
  final double centerLng;
  int count;
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.data,
    required this.onClose,
    this.onCancelOrder,
  });
  final Map<String, dynamic> data;
  final VoidCallback onClose;
  // Q3 (2026-05-17) — null para drivers (sem cancel applicable).
  final VoidCallback? onCancelOrder;

  bool get _isDriver => data.containsKey('driver_id');

  // Q3 — apenas estados cancelable.
  static const _cancelableStates = {
    'created',
    'preparing',
    'readyForPickup',
    'callingDriver',
    'driverAccepted',
  };

  bool get _isCancelable {
    if (_isDriver) return false;
    final status = data['status'] as String? ?? '';
    return _cancelableStates.contains(status);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(_isDriver ? Icons.two_wheeler : Icons.shopping_bag,
                    color: _isDriver ? Colors.blue : Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isDriver
                        ? (data['driver_name'] as String? ?? 'Entregador')
                        : (data['vendor_name'] as String? ?? 'Pedido'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                // 7-alpha-ADMIN-FILTER: badge teste no sidepanel (so para pedidos).
                if (!_isDriver && data['is_test_order'] == true) ...[
                  const SizedBox(width: 6),
                  const TestOrderBadge(),
                  const SizedBox(width: 6),
                ],
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose),
              ],
            ),
            const Divider(),
            if (_isDriver) ..._driverDetails() else ..._orderDetails(),
            // Q3 (2026-05-17) — botão "Cancelar pedido" só para estados
            // cancelable. Reusa AdminCancelOrderDialog (callback handler do
            // parent state faz o refresh + reset selection).
            if (_isCancelable && onCancelOrder != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined,
                      color: Colors.red, size: 18),
                  label: const Text(
                    'Cancelar pedido',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: onCancelOrder,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _driverDetails() {
    final phone = data['driver_phone'] as String?;
    final vehicle = data['vehicle_type'] as String?;
    final speed = (data['speed_kmh'] as num?)?.toDouble();
    final activeOrder = data['active_order_id'] as String?;
    return [
      if (phone != null) _row(Icons.phone, phone),
      if (vehicle != null) _row(Icons.directions_bike, vehicle),
      if (speed != null)
        _row(Icons.speed, '${speed.toStringAsFixed(0)} km/h'),
      _row(
          Icons.local_shipping,
          activeOrder != null
              ? 'Em entrega · #${activeOrder.substring(0, 6)}'
              : 'Disponível'),
    ];
  }

  List<Widget> _orderDetails() {
    final status = data['status'] as String? ?? '';
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final customer = data['customer_name'] as String? ?? 'Cliente';
    final pickup = data['pickup_address'] as String?;
    final drop = data['dropoff_address'] as String?;
    return [
      _row(Icons.flag, status),
      _row(Icons.person, customer),
      _row(Icons.euro, total.toStringAsFixed(2)),
      if (pickup != null) _row(Icons.store, pickup),
      if (drop != null) _row(Icons.location_on, drop),
    ];
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.black54),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
