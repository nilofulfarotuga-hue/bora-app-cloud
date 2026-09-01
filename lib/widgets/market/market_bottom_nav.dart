import 'package:flutter/material.dart';

import '../../config/app_colors.dart';


import '../../l10n/tr.dart';
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
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.storefront_outlined),
          activeIcon: const Icon(Icons.storefront),
          label: 'Loja'.tr,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.menu_outlined),
          activeIcon: const Icon(Icons.menu),
          label: 'Categorias'.tr,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.refresh_outlined),
          activeIcon: const Icon(Icons.refresh),
          label: 'Pedir de novo'.tr,
        ),
      ],
    );
  }
}
