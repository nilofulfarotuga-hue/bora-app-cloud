import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/constants.dart';

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
        supa.rpc('admin_live_orders'),
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

      if (pickupLat != null && pickupLng != null) {
        markers.add(Marker(
          markerId: MarkerId('pickup_$id'),
          position: gmap.LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActive ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: o['vendor_name'] as String? ?? 'Pickup',
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
            title: o['customer_name'] as String? ?? 'Cliente',
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
          title: d['driver_name'] as String? ?? 'Driver',
          snippet: d['active_order_id'] != null
              ? 'Em entrega · #${(d['active_order_id'] as String).substring(0, 6)}'
              : 'Disponível',
        ),
        onTap: () => setState(() => _selected = d),
      ));
    }

    return markers;
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
                _stat('Pending', pendingCount, Colors.orange),
                _stat('Active', activeCount, Colors.green),
                _stat('Drivers', onlineCount, Colors.blue),
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

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.data, required this.onClose});
  final Map<String, dynamic> data;
  final VoidCallback onClose;

  bool get _isDriver => data.containsKey('driver_id');

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
                        ? (data['driver_name'] as String? ?? 'Driver')
                        : (data['vendor_name'] as String? ?? 'Pedido'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose),
              ],
            ),
            const Divider(),
            if (_isDriver) ..._driverDetails() else ..._orderDetails(),
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
