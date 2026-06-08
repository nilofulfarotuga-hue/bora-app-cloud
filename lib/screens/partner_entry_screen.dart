import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../models/service_provider_model.dart';
import '../stores/partner_appointments_store.dart';
import '../stores/restaurant_store.dart';
import 'partner/services/partner_services_hub_screen.dart';
import 'partner_dashboard_screen.dart';
import 'partner_login_screen.dart';
import 'register_partner_screen.dart';

class PartnerEntryScreen extends StatelessWidget {
  const PartnerEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authStore = context.watch<AuthStore>();
    final restaurantStore = context.watch<RestaurantStore>();

    final partner = authStore.currentPartner;
    final partnerRestaurant = authStore.partnerRestaurant;

    if (partner != null) {
      if (partnerRestaurant != null) {
        return PartnerDashboardScreen(restaurant: partnerRestaurant);
      }

      final existingRestaurant =
          restaurantStore.restaurantByEmail(partner.email);
      if (existingRestaurant != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          authStore.setPartnerRestaurant(existingRestaurant);
        });
        return const _PartnerLoading();
      }

      // No `restaurants` row for this partner. Before assuming an incomplete
      // restaurant signup, check the Serviços/Barbearias vertical: a partner
      // may own a `service_providers` record instead (e.g. the demo
      // barbearia.nobre@bora.app). If so, their home is the marcações hub.
      return const _PartnerNoRestaurantRouter();
    }

    return const PartnerLoginScreen();
  }
}

/// Spinner shown while the partner's restaurant is being attached.
class _PartnerLoading extends StatelessWidget {
  const _PartnerLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

/// Decides the home for a logged-in partner that has no `restaurants` row:
/// the Serviços hub when a `service_providers` record exists, otherwise the
/// restaurant registration flow (legacy behaviour). Covers the session-restore
/// path where role=partner is loaded from prefs without going through login.
class _PartnerNoRestaurantRouter extends StatefulWidget {
  const _PartnerNoRestaurantRouter();

  @override
  State<_PartnerNoRestaurantRouter> createState() =>
      _PartnerNoRestaurantRouterState();
}

class _PartnerNoRestaurantRouterState
    extends State<_PartnerNoRestaurantRouter> {
  late Future<ServiceProviderModel?> _future;

  @override
  void initState() {
    super.initState();
    // Idempotent + cached in the store, so the fresh-login path (which already
    // loaded the provider in PartnerLoginScreen) resolves instantly.
    _future = context.read<PartnerAppointmentsStore>().loadMyProvider();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ServiceProviderModel?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _PartnerLoading();
        }
        if (snap.data != null) {
          return const PartnerServicesHubScreen();
        }
        return const RegisterPartnerScreen();
      },
    );
  }
}
