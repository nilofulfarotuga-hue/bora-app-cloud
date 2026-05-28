import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Bottom navigation Bora — 3 tabs (Início · Pedidos · Perfil).
///
/// Ícone activo verde Bora, inactivo cinzento. Fundo branco com sombra topo.
/// Para apps com mais tabs, usar `BottomNavigationBar` do ThemeData.
@Deprecated(
    'Use BoraBottomNavV2 (4 tabs: home/delivery/reservation/profile). Migração planeada na Fase 4.')
class BoraBottomNav extends StatelessWidget {
  const BoraBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items = defaultItems,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BoraBottomNavItem> items;

  static const List<BoraBottomNavItem> defaultItems = [
    BoraBottomNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Início'),
    BoraBottomNavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Pedidos'),
    BoraBottomNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTab(
                    item: items[i],
                    active: currentIndex == i,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BoraBottomNavItem {
  const BoraBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BoraBottomNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : const Color(0xFF9E9E9E);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? item.activeIcon : item.icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
