import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../models/order_model.dart';
import '../stores/order_store.dart';
import '../stores/session_store.dart';
import 'client_home_screen.dart';
import 'order_tracking_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

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
    ProfileScreen(),
  ];

  OrderModel? _findActiveOrder(List<OrderModel> orders) {
    for (final o in orders) {
      if (o.status.index >= OrderStatus.driverAccepted.index &&
          o.status != OrderStatus.delivered &&
          o.status != OrderStatus.rejected) {
        return o;
      }
    }
    return null;
  }

    Future<void> _handleSwitchMode() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.logout();
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }



  @override
  Widget build(BuildContext context) {
    // Watch orders: when a driver accepts, navigate to tracking screen once.
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
      appBar: AppBar(
        title: const Text("BORA - Cliente"),
                actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Mudar modo',
            onPressed: _handleSwitchMode,
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
                items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Início",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: "Pedidos",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Perfil",
          ),
        ],

      ),
    );
  }
}