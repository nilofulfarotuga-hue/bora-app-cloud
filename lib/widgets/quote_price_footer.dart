// FAVORES / Bloco 1 — Rodapé sticky de preço live.
//
// Mostra "desde €6" quando origem ou destino estão vazios.
// Quando ambos preenchidos → invoca quote_order_pricing via PaymentService e
// mostra o customer_total exacto (mesma fórmula do create_order — zero drift).
//
// Reusado por:
//   - send_package_form_screen.dart
//   - carry_groceries_form_screen.dart
//
// Para errand, o rodapé já existe inline no errand_form_screen.dart (3 segmentos).
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../services/payment_service.dart';

class QuotePriceFooter extends StatefulWidget {
  const QuotePriceFooter({
    super.key,
    required this.serviceType,
    required this.pickup,
    required this.dropoff,
    this.fallbackLabel = 'desde €6',
  });

  final OrderServiceType serviceType;
  final LatLng? pickup;
  final LatLng? dropoff;
  final String fallbackLabel;

  @override
  State<QuotePriceFooter> createState() => _QuotePriceFooterState();
}

class _QuotePriceFooterState extends State<QuotePriceFooter> {
  final _payment = PaymentService();
  Map<String, dynamic>? _quote;
  bool _loading = false;

  @override
  void didUpdateWidget(covariant QuotePriceFooter old) {
    super.didUpdateWidget(old);
    final changed = old.pickup != widget.pickup || old.dropoff != widget.dropoff;
    if (changed) _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final p = widget.pickup;
    final d = widget.dropoff;
    if (p == null || d == null) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _loading = true);
    final svc = DirectionsService();
    double dist;
    try {
      final route = await svc.fetchRoute(origin: p, destination: d);
      dist = (route != null && route.distanceKm > 0) ? route.distanceKm : 1.0;
    } catch (_) {
      dist = 1.0;
    } finally {
      svc.dispose();
    }
    final q = await _payment.quoteOrder({
      'service_type': widget.serviceType.name,
      'distance_km': dist,
      'is_partner_store': false,
      'subtotal': 0,
      'pickup_lat': p.latitude,
      'pickup_lng': p.longitude,
      'dropoff_lat': d.latitude,
      'dropoff_lng': d.longitude,
    });
    if (!mounted) return;
    setState(() {
      _quote = q;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = (_quote?['customer_total'] as num?)?.toDouble();
    final label = total != null
        ? '€${total.toStringAsFixed(2)}'
        : widget.fallbackLabel;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.shadowNav,
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total estimado',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Row(children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                if (_loading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ]),
            ],
          ),
          const Spacer(),
          if (total != null)
            TextButton(
              onPressed: () => _showBreakdown(context),
              child: const Text('Ver detalhe'),
            ),
        ],
      ),
    );
  }

  void _showBreakdown(BuildContext context) {
    final q = _quote;
    if (q == null) return;
    final delivery = (q['delivery_fee'] as num?)?.toDouble() ?? 0;
    final service = (q['service_fee'] as num?)?.toDouble() ?? 0;
    final bag = (q['bag_fee'] as num?)?.toDouble() ?? 0;
    final total = (q['customer_total'] as num?)?.toDouble() ?? 0;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Detalhe do preço',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            _row('Taxa de entrega', delivery),
            if (service > 0) _row('Taxa de serviço', service),
            if (bag > 0) _row('Saco', bag),
            const Divider(),
            _row('Total', total, strong: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double value, {bool strong = false}) {
    final style = TextStyle(
      fontSize: strong ? 16 : 14,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
