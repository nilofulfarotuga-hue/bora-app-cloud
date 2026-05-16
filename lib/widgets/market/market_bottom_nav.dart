import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

class MarketBottomNav extends StatelessWidget {
  const MarketBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: onTap,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      backgroundColor: Colors.white,
      elevation: 8,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.storefront_outlined),
          activeIcon: Icon(Icons.storefront),
          label: 'Loja',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu_outlined),
          activeIcon: Icon(Icons.menu),
          label: 'Categorias',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.refresh_outlined),
          activeIcon: Icon(Icons.refresh),
          label: 'Pedir de novo',
        ),
      ],
    );
  }
}
