import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'partner_client_profiles_screen.dart';
import 'partner_floor_plan_editor_screen.dart';
import 'partner_pacing_rules_screen.dart';
import 'partner_reservations_screen.dart';
import 'partner_reservations_stats_screen.dart';
import 'partner_walk_in_screen.dart';

/// Reservas PRO F4 — hub central partner-side.
///
/// Layout 6 entries inspirado em SevenRooms (Reservations / Floor /
/// Guests / Settings / Reports). Adaptado a PT-PT + walk-in shortcut
/// (Resy-like host stand).
class PartnerReservationsHomeScreen extends StatelessWidget {
  const PartnerReservationsHomeScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  final String restaurantId;
  final String restaurantName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Reservas Pro'),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurantName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Gestão de reservas, mesas e clientes.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _Tile(
            icon: Icons.list_alt,
            title: 'Reservas',
            subtitle: 'Pendentes, hoje, histórico',
            onTap: () => _push(
              context,
              PartnerReservationsScreen(
                restaurantId: restaurantId,
                restaurantName: restaurantName,
              ),
            ),
          ),
          _Tile(
            icon: Icons.directions_walk,
            title: 'Walk-in',
            subtitle: 'Sentar cliente sem reserva',
            onTap: () => _push(
              context,
              PartnerWalkInScreen(restaurantId: restaurantId),
            ),
          ),
          _Tile(
            icon: Icons.grid_view_rounded,
            title: 'Planta de sala',
            subtitle: 'Configurar mesas e zonas',
            onTap: () => _push(
              context,
              PartnerFloorPlanEditorScreen(restaurantId: restaurantId),
            ),
          ),
          _Tile(
            icon: Icons.tune,
            title: 'Configurações',
            subtitle: 'Tempos de mesa e pacing',
            onTap: () => _push(
              context,
              PartnerPacingRulesScreen(restaurantId: restaurantId),
            ),
          ),
          _Tile(
            icon: Icons.people_alt_outlined,
            title: 'Clientes',
            subtitle: 'VIP, bloqueios e notas',
            onTap: () => _push(
              context,
              PartnerClientProfilesScreen(restaurantId: restaurantId),
            ),
          ),
          _Tile(
            icon: Icons.bar_chart,
            title: 'Estatísticas',
            subtitle: 'KPIs de reservas e cobertos',
            onTap: () => _push(
              context,
              PartnerReservationsStatsScreen(restaurantId: restaurantId),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
