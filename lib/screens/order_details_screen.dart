import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/map_utils.dart';
import 'chat_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final OrderModel order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  static final Set<String> _promptedRatings = <String>{};

  final DirectionsService _directionsService = DirectionsService();
  List<LatLng> _routePoints = <LatLng>[];
  String? _routeKey;
  int _routeRequestId = 0;

  @override
  Widget build(BuildContext context) {
    const statuses = OrderStatus.values;
    final driverStore = context.watch<DriverStore>();
    final orderStore = context.watch<OrderStore>();
    final DriverModel? assignedDriver = widget.order.assignedDriverId != null
        ? driverStore.getDriverById(widget.order.assignedDriverId!)
        : null;
    final rating = orderStore.ratingForOrder(widget.order.id);

    if (widget.order.status == OrderStatus.delivered && rating == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_promptedRatings.add(widget.order.id)) {
          _showRatingDialog(context, orderStore, widget.order);
        }
      });
    }
    final LatLng? driverLocation = assignedDriver?.location;
    final LatLng? pickupLocation = widget.order.pickupLocation;
    final LatLng? dropoffLocation = widget.order.destination;
    final LatLng? mapCenter = driverLocation ?? pickupLocation ?? dropoffLocation;

    LatLng? routeOrigin;
    LatLng? routeDestination;

    if (driverLocation != null && dropoffLocation != null) {
      routeOrigin = driverLocation;
      routeDestination = dropoffLocation;
    } else if (pickupLocation != null && dropoffLocation != null) {
      routeOrigin = pickupLocation;
      routeDestination = dropoffLocation;
    }

    if (routeOrigin != null && routeDestination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeUpdateRoute(routeOrigin!, routeDestination!);
      });
    } else if (_routePoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _routePoints = <LatLng>[];
          _routeKey = null;
        });
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do pedido'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valor do pedido: €${widget.order.total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.local_shipping,
                  label: 'Serviço',
                  value: widget.order.serviceType.label,
                ),
                _InfoChip(
                  icon: Icons.fastfood,
                  label: 'Produtos',
                  value: '€${widget.order.subtotal.toStringAsFixed(2)}',
                ),
                _InfoChip(
                  icon: Icons.delivery_dining,
                  label: 'Entrega',
                  value: '€${widget.order.deliveryFee.toStringAsFixed(2)}',
                ),
                if (widget.order.serviceFee > 0)
                  _InfoChip(
                    icon: Icons.receipt_long,
                    label: 'Serviço',
                    value: '€${widget.order.serviceFee.toStringAsFixed(2)}',
                  ),
                _InfoChip(
                  icon: Icons.payments,
                  label: 'Ganhos estafeta',
                  value: '€${widget.order.driverEarnings.toStringAsFixed(2)}',
                ),
                _InfoChip(
                  icon: Icons.payment,
                  label: 'Pagamento',
                  value: widget.order.paymentMethod.label,
                ),
                if (widget.order.apartmentDelivery)
                  const _InfoChip(
                    icon: Icons.apartment,
                    label: 'Entrega',
                    value: 'Apartamento +€1.50',
                  ),
              ],
            ),
            if (widget.order.isPurchaseFinalized) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'O seu pedido foi comprado pelo estafeta',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (widget.order.finalTotal != null)
                            Text(
                              'Valor final: €${widget.order.finalTotal!.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.blue.shade600,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (assignedDriver != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Estafeta atribuído',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              _InfoRow(label: 'Nome', value: assignedDriver.name),
              if (driverLocation != null)
                _InfoRow(
                  label: 'Localização',
                  value:
                      '${driverLocation.latitude.toStringAsFixed(4)}, ${driverLocation.longitude.toStringAsFixed(4)}',
                ),
              if ((widget.order.driverPhone ?? '').isNotEmpty)
                _InfoRow(label: 'Telefone', value: widget.order.driverPhone!),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (widget.order.driverPhone ?? '').isEmpty
                          ? null
                          : () => _callPhone(context, widget.order.driverPhone!),
                      icon: const Icon(Icons.call),
                      label: const Text('Ligar estafeta'),
                    ),
                              ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              order: widget.order,
                              senderType: ChatSenderType.client,
                            ),
                      ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat'),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.order.pickupAddress != null && widget.order.pickupAddress!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Recolha',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(widget.order.pickupAddress!),
            ],
            if (widget.order.dropoffAddress != null && widget.order.dropoffAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Entrega',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(widget.order.dropoffAddress!),
            ],
            if ((widget.order.clientPhone ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoRow(label: 'Telefone de contacto', value: widget.order.clientPhone!),
            ],
            if (widget.order.customerNotes != null && widget.order.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Nota do cliente',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(widget.order.customerNotes!),
            ],
            if (widget.order.apartmentDelivery) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.apartment, color: Colors.orange.shade600),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Entrega em apartamento adiciona €1.50 (bônus de €1 para o estafeta).',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (mapCenter != null && (driverLocation != null || dropoffLocation != null))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Progresso da entrega',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: gmaps.GoogleMap(
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        liteModeEnabled: true,
                        initialCameraPosition: gmaps.CameraPosition(
                          target: mapCenter.toGMaps(),
                          zoom: 13,
                        ),
                        markers: {
                          if (driverLocation != null)
                            gmaps.Marker(
                              markerId: const gmaps.MarkerId('driver'),
                              position: driverLocation.toGMaps(),
                              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                                gmaps.BitmapDescriptor.hueGreen,
                              ),
                              infoWindow: const gmaps.InfoWindow(title: 'Estafeta'),
                            ),
                          if (pickupLocation != null)
                            gmaps.Marker(
                              markerId: const gmaps.MarkerId('pickup'),
                              position: pickupLocation.toGMaps(),
                              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                                gmaps.BitmapDescriptor.hueOrange,
                              ),
                              infoWindow: const gmaps.InfoWindow(title: 'Recolha'),
                            ),
                          if (dropoffLocation != null)
                            gmaps.Marker(
                              markerId: const gmaps.MarkerId('dropoff'),
                              position: dropoffLocation.toGMaps(),
                              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                                gmaps.BitmapDescriptor.hueRed,
                              ),
                              infoWindow: const gmaps.InfoWindow(title: 'Entrega'),
                            ),
                        },
                        polylines: {
                          if (_routePoints.isNotEmpty)
                            gmaps.Polyline(
                              polylineId: const gmaps.PolylineId('route'),
                              width: 4,
                              color: Colors.blueAccent,
                              points: _routePoints.toGMaps(),
                            )
                          else if (driverLocation != null && dropoffLocation != null)
                            gmaps.Polyline(
                              polylineId: const gmaps.PolylineId('route'),
                              width: 4,
                              color: Colors.blueAccent,
                              points: [
                                driverLocation.toGMaps(),
                                dropoffLocation.toGMaps(),
                              ],
                            )
                          else if (pickupLocation != null && dropoffLocation != null)
                            gmaps.Polyline(
                              polylineId: const gmaps.PolylineId('route'),
                              width: 4,
                              color: Colors.blueAccent,
                              points: [
                                pickupLocation.toGMaps(),
                                dropoffLocation.toGMaps(),
                              ],
                            ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (rating != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Sua avaliação',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStars(rating.rating),
                  const SizedBox(width: 8),
                  Text(rating.rating.toString()),
                ],
              ),
              if (rating.comment != null && rating.comment!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(rating.comment!),
              ],
            ],
            const SizedBox(height: 20),
            const Text(
              'Status atual:',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              widget.order.status.label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Linha do tempo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.order.status == OrderStatus.delivered && rating == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showRatingDialog(context, orderStore, widget.order),
                    child: const Text('Avaliar entrega'),
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: statuses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final status = statuses[index];
                  final isCompleted = status.index <= widget.order.status.index;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isCompleted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: isCompleted ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isCompleted
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isCompleted
                                ? Colors.black
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _maybeUpdateRoute(LatLng origin, LatLng destination) {
    final key =
        '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}|${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';
    if (_routeKey == key && _routePoints.isNotEmpty) {
      return;
    }

    _routeKey = key;
    final requestId = ++_routeRequestId;

    _directionsService
        .fetchRoute(origin: origin, destination: destination)
        .then((route) {
      if (!mounted || _routeRequestId != requestId) {
        return;
      }
      setState(() {
        if (route != null && route.points.isNotEmpty) {
          _routePoints = route.points;
        } else {
          _routePoints = <LatLng>[origin, destination];
        }
      });
    }).catchError((error) {
      debugPrint('Erro ao carregar rota do pedido: $error');
      if (!mounted || _routeRequestId != requestId) {
        return;
      }
      setState(() {
        _routePoints = <LatLng>[origin, destination];
      });
    });
  }

  @override
  void dispose() {
    _directionsService.dispose();
    super.dispose();
  }

  static Future<void> _callPhone(BuildContext context, String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
      );
    }
  }

  static Widget _buildStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          index < rating ? Icons.star : Icons.star_border,
          size: 18,
          color: Colors.amber,
        ),
      ),
    );
  }

  void _showRatingDialog(
    BuildContext context,
    OrderStore orderStore,
    OrderModel order,
  ) {
    final driverId = widget.order.assignedDriverId;
    if (driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar o estafeta.')),
      );
      return;
    }

    int currentRating = 5;
    final commentController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Avalie a entrega'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      return IconButton(
                        icon: Icon(
                          starValue <= currentRating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () => setState(() => currentRating = starValue),
                      );
                    }),
                  ),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comentário (opcional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    orderStore.submitRating(
                      orderId: widget.order.id,
                      driverId: driverId,
                      rating: currentRating,
                      comment: commentController.text,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Obrigado pelo feedback.')),
                    );
                  },
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(commentController.dispose);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade800),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
