import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/navigation_service.dart';
import '../services/sound_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../stores/session_store.dart';
import 'chat_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_map_screen.dart';
import 'driver_order_action_helper.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  Set<String> _knownOrderIds = {};
  bool _isShowingDialog = false;
  String? _highlightedOrderId;
  final SoundService _soundService = SoundService();
  final Set<String> _processingOrderIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrderStore>().loadOrders();
    });
  }

  @override
  void dispose() {
    _soundService.dispose();
    super.dispose();
  }

  Future<void> _handleTestMode() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.logout();
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final switchModeColor = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final orderStore = context.watch<OrderStore>();
    final driverStore = context.watch<DriverStore>();
    final vehicleType = driverStore.currentVehicleType;
    final availableOrders = orderStore.availableOrders;
    final myOrders = orderStore.myOrders;
    final isAvailable = orderStore.isDriverAvailable;
    final highlightedOrder = _findOrderById(availableOrders, _highlightedOrderId);
    // Driver may accept new orders as long as they are online; capacity is
    // enforced by DriverCapacityService inside acceptOrder.
    final canInteractWithOrders = isAvailable;
    final List<OrderModel> otherOrders = highlightedOrder == null
        ? availableOrders
        : availableOrders
            .where((order) => order.id != highlightedOrder.id)
            .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNewOrders(availableOrders, orderStore);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text("Painel do Estafeta"),
        actions: [
          TextButton.icon(
            onPressed: _handleTestMode,
            style: TextButton.styleFrom(
              foregroundColor: switchModeColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: Icon(Icons.bug_report_outlined, color: switchModeColor),
            label: const Text('Teste'),
          ),
          Row(
            children: [
              Text(
                isAvailable ? "Online" : "Offline",
                style: const TextStyle(fontSize: 12),
              ),
              Switch(
                value: isAvailable,
                onChanged: (value) {
                  orderStore.toggleDriverAvailability(value);
                },
              ),
            ],
          ),
          IconButton(
            tooltip: "Ganhos",
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DriverEarningsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: Icon(
                  vehicleType == VehicleType.car
                      ? Icons.directions_car
                      : Icons.motorcycle,
                ),
                title: Text('Veículo: ${vehicleType.label}'),
                subtitle: Text(
                  vehicleType == VehicleType.car
                      ? 'Pode aceitar todos os serviços disponíveis.'
                      : 'Disponível para restaurantes e pequenas entregas.',
                ),
              ),
            ),
            for (final order in myOrders) ...[
              _buildActiveOrderCard(context, orderStore, order),
              const SizedBox(height: 16),
            ],
            const Text(
              "Pedidos disponíveis",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (highlightedOrder != null) ...[
                    _DriverOrderAlertCard(
                      order: highlightedOrder,
                      isEnabled: canInteractWithOrders,
                      onAccept: () async {
                        await _handleAcceptOrder(
                          highlightedOrder,
                          orderStore,
                          driverStore,
                          isAvailable,
                        );
                      },
                      onReject: () => _handleRejectOrder(
                        highlightedOrder,
                        orderStore,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (highlightedOrder == null && otherOrders.isEmpty)
                    _buildEmptyState(myOrders.isNotEmpty)
                  else
                    ...otherOrders.map(
                      (order) => _AvailableOrderCard(
                        order: order,
                        isEnabled: canInteractWithOrders,
                        onAccept: () async {
                          await _handleAcceptOrder(
                            order,
                            orderStore,
                            driverStore,
                            isAvailable,
                          );
                        },
                        onReject: () => _handleRejectOrder(
                          order,
                          orderStore,
                        ),
                      ),
                    ),
                  if (orderStore.completedOrders.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      "Entregas concluídas",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...orderStore.completedOrders.map(
                      (order) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(order.serviceType.label),
                        subtitle: Text(
                          "€${order.total.toStringAsFixed(2)} • ${order.distanceKm.toStringAsFixed(1)} km",
                        ),
                        trailing: Text(
                          "+€${order.driverEarnings.toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool hasActiveOrder) {
    final message = hasActiveOrder
        ? "Conclua o pedido atual para receber novas entregas."
        : "Nenhum pedido disponível no momento.";

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildActiveOrderCard(
    BuildContext context,
    OrderStore orderStore,
    OrderModel order,
  ) {
    final nextAction = resolveDriverOrderAction(orderStore, order);
    final pickupTarget = order.pickupLocation ?? order.destination;
    final deliveryTarget = order.destination;
    final hasPickedUp = order.status.index >= OrderStatus.pickedUp.index;
    final LatLng? navigationTarget = hasPickedUp ? deliveryTarget : pickupTarget;
    final String navigationLabel = hasPickedUp
        ? "Navegar para cliente"
        : "Navegar para recolha";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Entrega em andamento",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.restaurant,
                  label: "Serviço",
                  value: order.serviceType.label,
                ),
                _InfoChip(
                  icon: Icons.euro,
                  label: "Pedido",
                  value: "€${order.total.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.payments,
                  label: "Ganhos",
                  value: "+€${order.driverEarnings.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.social_distance,
                  label: "Distância",
                  value: "${order.distanceKm.toStringAsFixed(1)} km",
                ),
              ],
            ),
            if (order.vendorName != null) ...[
              const SizedBox(height: 12),
              Text(
                order.vendorName!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                "Recolha:",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(order.pickupAddress!),
            ],
            if (order.dropoffAddress != null && order.dropoffAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                "Entrega:",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(order.dropoffAddress!),
            ],
            if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                "Nota do cliente:",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(order.customerNotes!),
            ],
            if (order.apartmentDelivery) ...[
              const SizedBox(height: 12),
              const _ApartmentDeliveryBanner(),
            ],
            const SizedBox(height: 16),
            Text("Status atual: ${order.status.label}"),
            if (order.isPurchaseFinalized) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.finalTotal != null
                            ? 'Compra realizada · Valor: €${order.finalTotal!.toStringAsFixed(2)}'
                            : 'Compra realizada',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverMapScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map),
                  label: const Text("Ver mapa"),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: navigationTarget == null
                      ? null
                      : () {
                          NavigationService.openNavigationOptions(
                            context,
                            navigationTarget,
                          );
                        },
                  icon: const Icon(Icons.navigation),
                  label: Text(navigationLabel),
                ),
                const SizedBox(width: 12),
                if (nextAction != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _processingOrderIds.contains(order.id)
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              setState(() => _processingOrderIds.add(order.id));
                              final success = await nextAction.execute();
                              if (mounted) {
                                setState(() =>
                                    _processingOrderIds.remove(order.id));
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? nextAction.successMessage
                                        : "Não foi possível atualizar o pedido.",
                                  ),
                                ),
                              );
                            },
                      child: _processingOrderIds.contains(order.id)
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(nextAction.label),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Telefone do cliente: '
              '${(order.clientPhone ?? '').isNotEmpty ? order.clientPhone! : 'Não disponível'}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (order.clientPhone ?? '').isEmpty
                        ? null
                        : () => _callPhone(order.clientPhone!),
                    icon: const Icon(Icons.call),
                    label: const Text('Ligar cliente'),
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
                            order: order,
                            senderType: ChatSenderType.driver,
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
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
        );
      }
    }
  }

  Future<void> _handleAcceptOrder(
    OrderModel order,
    OrderStore orderStore,
    DriverStore driverStore,
    bool isDriverAvailable,
  ) async {
    if (!isDriverAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Fique online para aceitar pedidos.",
          ),
        ),
      );
      return;
    }

    final driver = driverStore.currentDriver;
    if (driver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erro: estafeta não configurado."),
        ),
      );
      return;
    }
    if (!driver.supportsService(order.serviceType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Este pedido requer um veículo do tipo carro.",
          ),
        ),
      );
      return;
    }

    final accepted = await orderStore.acceptOrder(order);
    if (!mounted) return;
    if (accepted) {
      // Navigate to map — success is self-evident from the screen change.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DriverMapScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Não foi possível aceitar este pedido."),
        ),
      );
    }
  }

  void _handleRejectOrder(OrderModel order, OrderStore orderStore) {
    final rejected = orderStore.rejectAvailableOrder(order);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rejected
              ? "Pedido rejeitado."
              : "Não foi possível rejeitar este pedido.",
        ),
      ),
    );
  }

  OrderModel? _findOrderById(List<OrderModel> orders, String? id) {
    if (id == null) return null;
    for (final order in orders) {
      if (order.id == id) {
        return order;
      }
    }
    return null;
  }

  void _handleNewOrders(List<OrderModel> orders, OrderStore store) {
    final currentIds = orders.map((o) => o.id).toSet();
    final newIds = currentIds.difference(_knownOrderIds);

    String? highlightCandidate = _highlightedOrderId;
    if (highlightCandidate != null && !currentIds.contains(highlightCandidate)) {
      highlightCandidate = null;
    }

    if (newIds.isNotEmpty) {
      final newestOrders = orders
          .where((order) => newIds.contains(order.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newOrder = newestOrders.first;
      highlightCandidate = newOrder.id;

      if (newOrder.status == OrderStatus.callingDriver) {
        unawaited(_triggerNewOrderFeedback(newOrder));
        unawaited(_soundService.playLoop());
      }

      if (!_isShowingDialog) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showNewOrderDialog(newOrder, store);
        });
      }
    } else if (highlightCandidate == null && orders.isNotEmpty) {
      highlightCandidate = orders.first.id;
    }

    if (highlightCandidate != _highlightedOrderId && mounted) {
      setState(() {
        _highlightedOrderId = highlightCandidate;
      });
    }

    _knownOrderIds = currentIds;

    if (!orders.any((o) => o.status == OrderStatus.callingDriver)) {
      unawaited(_soundService.stop());
    }
  }

  Future<void> _triggerNewOrderFeedback(OrderModel order) async {
    if (order.status != OrderStatus.callingDriver) return;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // System sound feedback is best effort and may fail silently.
    }

    try {
      if (await Vibration.hasCustomVibrationsSupport()) {
        await Vibration.vibrate(pattern: [0, 500, 150, 500]);
        return;
      }
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 800);
      }
    } catch (_) {
      // Vibration feedback is best-effort and may fail on unsupported platforms
    }
  }

  Future<void> _showNewOrderDialog(OrderModel order, OrderStore store) async {
    if (order.status != OrderStatus.callingDriver) {
      return;
    }

    _isShowingDialog = true;

    if (!mounted) {
      _isShowingDialog = false;
      return;
    }

    final description = order.vendorName ?? order.serviceType.label;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo pedido disponível'),
        content: Text(
          'Um novo pedido de $description está disponível. Deseja verificar? ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ok'),
          ),
        ],
      ),
    );

    _isShowingDialog = false;
  }
}

class _DriverOrderAlertCard extends StatefulWidget {
  const _DriverOrderAlertCard({
    required this.order,
    required this.isEnabled,
    required this.onAccept,
    required this.onReject,
  });

  final OrderModel order;
  final bool isEnabled;
  final Future<void> Function() onAccept;
  final VoidCallback onReject;

  @override
  State<_DriverOrderAlertCard> createState() => _DriverOrderAlertCardState();
}

class _DriverOrderAlertCardState extends State<_DriverOrderAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final baseColor = Colors.orange.shade50;
    final highlightColor = Colors.orange.shade200.withOpacity(0.9);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final backgroundColor = Color.lerp(baseColor, highlightColor, t);
        final borderColor =
            Color.lerp(Colors.orange.shade400, Colors.orange.shade700, t) ??
                Colors.orange.shade500;
        final shadowColor = Colors.orange.withOpacity(0.25 + (0.25 * t));

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Novo pedido disponível",
                          style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ) ??
                              TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      order.serviceType.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ) ??
                          const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (order.vendorName != null &&
                        order.vendorName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        order.vendorName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (order.pickupAddress != null &&
                        order.pickupAddress!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Recolha: ${order.pickupAddress!}",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (order.dropoffAddress != null &&
                        order.dropoffAddress!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Entrega: ${order.dropoffAddress!}",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (order.customerNotes != null &&
                        order.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Nota do cliente:",
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(order.customerNotes!),
                    ],
                    if (order.apartmentDelivery) ...[
                      const SizedBox(height: 12),
                      const _ApartmentDeliveryBanner(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "+€${order.driverEarnings.toStringAsFixed(2)}",
                    style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ) ??
                        TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.social_distance,
                          color: Colors.orange.shade900,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${order.distanceKm.toStringAsFixed(1)} km",
                          style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ) ??
                              const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade900,
                    side: BorderSide(color: Colors.orange.shade900),
                  ),
                  child: const Text("Rejeitar"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (widget.isEnabled && !_isLoading)
                      ? () async {
                          setState(() => _isLoading = true);
                          await widget.onAccept();
                          if (mounted) setState(() => _isLoading = false);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Aceitar pedido"),
                ),
              ),

            ],
          ),
        ],
      ),
    );
  }
}

class _AvailableOrderCard extends StatefulWidget {
  final OrderModel order;
  final bool isEnabled;
  final Future<void> Function() onAccept;
  final VoidCallback onReject;

  const _AvailableOrderCard({
    required this.order,
    required this.isEnabled,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_AvailableOrderCard> createState() => _AvailableOrderCardState();
}

class _AvailableOrderCardState extends State<_AvailableOrderCard> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.serviceType.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (order.vendorName != null) ...[
              const SizedBox(height: 4),
              Text(order.vendorName!),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.euro,
                  label: "Total",
                  value: "€${order.total.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.payments,
                  label: "Ganhos",
                  value: "+€${order.driverEarnings.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.social_distance,
                  label: "Distância",
                  value: "${order.distanceKm.toStringAsFixed(1)} km",
                ),
              ],
            ),
            if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text("Recolha: ${order.pickupAddress!}"),
            ],
            if (order.dropoffAddress != null && order.dropoffAddress!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text("Entrega: ${order.dropoffAddress!}"),
            ],
            if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Nota do cliente:",
                style: TextStyle(color: Colors.grey.shade700),
              ),
              Text(order.customerNotes!),
            ],
            if (order.apartmentDelivery) ...[
              const SizedBox(height: 8),
              const _ApartmentDeliveryBanner(compact: true),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    child: const Text("Rejeitar"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (widget.isEnabled && !_isLoading)
                        ? () async {
                            setState(() => _isLoading = true);
                            await widget.onAccept();
                            if (mounted) setState(() => _isLoading = false);
                          }
                        : null,
                    child: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Aceitar pedido"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApartmentDeliveryBanner extends StatelessWidget {
  const _ApartmentDeliveryBanner({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = Colors.orange.shade50;
    final borderColor = Colors.orange.shade200;
    final iconColor = Colors.orange.shade600;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.orange.shade800,
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compact ? 8 : 12,
        horizontal: compact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.apartment, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Apartment delivery requested — +€1 bonus",
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

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
            "$label: $value",
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}