import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../stores/session_store.dart';
import 'client_home_screen.dart';

import 'orders_screen.dart';
import 'profile_screen.dart';

class ClientMainScreen extends StatefulWidget {
  const ClientMainScreen({super.key});

  @override
  State<ClientMainScreen> createState() => _ClientMainScreenState();
}

class _ClientMainScreenState extends State<ClientMainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    ClientHomeScreen(),
    OrdersScreen(),
    ProfileScreen(),
  ];

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
    return Scaffold(
      appBar: AppBar(
        title: const Text("BORA - Cliente"),
                actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch Mode',
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
            label: "Home",
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