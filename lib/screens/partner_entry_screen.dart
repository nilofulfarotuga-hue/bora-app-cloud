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
import 'pending_approval_screen.dart';
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
  late Future<String?> _restaurantStatusFuture;

  @override
  void initState() {
    super.initState();
    // BUG (parceiro-serviços preso em "Submetido para Análise", 2026-07-18):
    // `force: true` — este router decide entre o hub de gestão e o ecrã de
    // análise, por isso NUNCA pode confiar num `service_providers` cacheado
    // de uma leitura anterior (ex.: pré-aquecido no login enquanto ainda
    // estava pending). Sempre reconsulta o estado atual no Supabase.
    _future =
        context.read<PartnerAppointmentsStore>().loadMyProvider(force: true);
    // BUG 1 (cadastro parceiro 2026-07-14): sem isto, um parceiro com
    // candidatura 'pending' que faz logout/login caía sempre no wizard do
    // zero (a lista pública de restaurants só inclui approved). Verifica a
    // própria linha (qualquer status) via RLS owner-read dedicada.
    final userId = context.read<AuthStore>().userId;
    _restaurantStatusFuture = userId == null
        ? Future.value(null)
        : context.read<RestaurantStore>().ownRestaurantApprovalStatus(userId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ServiceProviderModel?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _PartnerLoading();
        }
        final provider = snap.data;
        if (provider != null) {
          // BUG (parceiro-serviços preso em "Submetido para Análise",
          // 2026-07-18): antes só se verificava "existe uma linha", nunca o
          // seu `approval_status` — um prestador pending ou rejected entrava
          // directo no hub de gestão, e um aprovado podia ficar preso no
          // ecrã de análise se essa mesma linha tivesse sido lida antes da
          // aprovação. Agora o gate é sempre o status fresco.
          if (provider.approvalStatus == 'approved') {
            return const PartnerServicesHubScreen();
          }
          if (provider.approvalStatus == 'pending') {
            return PendingApprovalScreen(categoryName: provider.category);
          }
          // rejected (ou status desconhecido) — cai para a verificação de
          // `restaurants` abaixo, igual ao ramo já existente para
          // restaurantes: deixa o parceiro refazer a candidatura em vez de
          // lhe dar acesso ao hub com uma candidatura recusada.
        }
        return FutureBuilder<String?>(
          future: _restaurantStatusFuture,
          builder: (context, statusSnap) {
            if (statusSnap.connectionState != ConnectionState.done) {
              return const _PartnerLoading();
            }
            if (statusSnap.data == 'pending') {
              return const PendingApprovalScreen();
            }
            return const RegisterPartnerScreen();
          },
        );
      },
    );
  }
}
