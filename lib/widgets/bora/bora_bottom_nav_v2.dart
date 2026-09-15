import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Tabs do navigation principal cliente BORA (4 tabs).
///
/// Mapping com o design system handoff:
/// - [home]: Home / categorias / pesquisa
/// - [delivery]: Acompanhar entrega activa (substitui o antigo "Pedidos")
/// - [reservation]: Reservar mesa (Reservas Mesa Pro)
/// - [profile]: Perfil + definições
enum BoraNavTab {
  home,
  delivery,
  reservation,
  profile,
}

/// Bottom navigation Bora **V2** — 4 tabs igualmente espaçados.
///
/// Visual alinhado com `design_handoff/extraido/preview/comp_bottom_nav.html`:
/// - Fundo branco, height 64, sombra TOPO [AppColors.shadowNav].
/// - Tab activa: ícone preenchido + label `AppColors.primary` (#16A34A), w700.
/// - Tab inactiva: ícone outlined + label `AppColors.textSubtle` (#9CA3AF), w500.
/// - Ícone 24px, label 11px.
///
/// Sem badges nesta versão (vem em fase posterior se o design pedir).
/// O widget **não conhece rotas** — emite apenas o tab seleccionado via
/// [onTabChanged]. Caller decide a navegação.
///
/// Exemplo:
/// ```dart
/// Scaffold(
///   bottomNavigationBar: BoraBottomNavV2(
///     current: _tab,
///     onTabChanged: (tab) => setState(() => _tab = tab),
///   ),
///   body: ...,
/// );
/// ```
class BoraBottomNavV2 extends StatelessWidget {
  const BoraBottomNavV2({
    super.key,
    required this.current,
    required this.onTabChanged,
  });

  final BoraNavTab current;
  final ValueChanged<BoraNavTab> onTabChanged;

  static const List<_NavSpec> _tabs = [
    _NavSpec(
      tab: BoraNavTab.home,
      label: 'Início',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
    ),
    _NavSpec(
      tab: BoraNavTab.delivery,
      label: 'Entrega',
      icon: Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping,
    ),
    _NavSpec(
      tab: BoraNavTab.reservation,
      label: 'Reserva',
      icon: Icons.event_seat_outlined,
      activeIcon: Icons.event_seat,
    ),
    _NavSpec(
      tab: BoraNavTab.profile,
      label: 'Perfil',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: AppColors.shadowNav,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final spec in _tabs)
                Expanded(
                  child: _NavCell(
                    spec: spec,
                    active: current == spec.tab,
                    onTap: () => onTabChanged(spec.tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSpec {
  const _NavSpec({
    required this.tab,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final BoraNavTab tab;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSubtle;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            active ? spec.activeIcon : spec.icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            spec.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
