import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../stores/restaurant_store.dart';
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
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return const RegisterPartnerScreen();
    }

    if (authStore.hasPartnerAccounts) {
      return const PartnerLoginScreen();
    }

    return const RegisterPartnerScreen();
  }
}