import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../stores/order_store.dart';
import '../widgets/bora/bora.dart';
import 'client/reservation/my_reservation_lists_screen.dart';
import 'client_home_screen.dart';
import 'order_tracking_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

/// Host dos 3 tabs do cliente: Início · Pedidos · Perfil.
///
/// Cada tab tem a sua própria `BoraAppBar` — este widget só gere o
/// `IndexedStack` e a `BoraBottomNav`. Eventos globais (e.g. pedido aceite
/// por estafeta → push tracking) são observados aqui porque sobrevivem às
/// trocas de tab.
class ClientMainScreen extends StatefulWidget {
  const ClientMainScreen({super.key});

  @override
  State<ClientMainScreen> createState() => _ClientMainScreenState();
}

class _ClientMainScreenState extends State<ClientMainScreen> {
  int _selectedIndex = 0;

  /// Orders we have already pushed a tracking screen for.
  /// Prevents re-navigation on every rebuild after the user presses back.
  final Set<String> _navigatedOrderIds = {};

  final List<Widget> _screens = const [
    ClientHomeScreen(),
    OrdersScreen(),
    MyReservationListsScreen(),
    ProfileScreen(),
  ];

  OrderModel? _findActiveOrder(List<OrderModel> orders) {
    for (final o in orders) {
      // BUG 6 — incluir cancelled na exclusão (cliente não deve abrir
      // detail de pedido cancelado automaticamente).
      if (o.status.index >= OrderStatus.driverAccepted.index &&
          o.status != OrderStatus.delivered &&
          o.status != OrderStatus.rejected &&
          o.status != OrderStatus.cancelled) {
        return o;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderStore>().orders;
    final activeOrder = _findActiveOrder(orders);
    if (activeOrder != null && !_navigatedOrderIds.contains(activeOrder.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_navigatedOrderIds.contains(activeOrder.id)) return;
        _navigatedOrderIds.add(activeOrder.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(order: activeOrder),
          ),
        );
      });
    }

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BoraBottomNav(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BoraBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Início',
          ),
          BoraBottomNavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            label: 'Pedidos',
          ),
          BoraBottomNavItem(
            icon: Icons.event_available_outlined,
            activeIcon: Icons.event_available,
            label: 'Reservas',
          ),
          BoraBottomNavItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
