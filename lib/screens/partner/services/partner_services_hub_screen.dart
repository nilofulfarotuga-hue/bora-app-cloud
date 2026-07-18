import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../models/service_provider_model.dart';
import '../../../services/notification_service.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../stores/session_store.dart';
import '../../../utils/staff_terminology.dart';
import '../../../widgets/biometric_login_tile.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../widgets/partner_weekly_closeout_card.dart';
import 'partner_add_walk_in_screen.dart';
import 'partner_agenda_screen.dart';
import 'partner_appointments_finance_screen.dart';
import 'partner_block_slot_screen.dart';
import 'partner_manage_services_screen.dart';
import 'partner_manage_staff_screen.dart';

/// Hub central do painel de marcações (vertical Serviços / Barbearias).
///
/// Layout espelhado em `PartnerReservationsHomeScreen` (lista de tiles).
/// Carrega o prestador do parceiro autenticado (service_providers.user_id =
/// auth.uid()) e disponibiliza os 5 destinos do painel.
class PartnerServicesHubScreen extends StatefulWidget {
  const PartnerServicesHubScreen({super.key});

  @override
  State<PartnerServicesHubScreen> createState() =>
      _PartnerServicesHubScreenState();
}

class _PartnerServicesHubScreenState extends State<PartnerServicesHubScreen> {
  late Future<ServiceProviderModel?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PartnerAppointmentsStore>().loadMyProvider();
    // B2 (2026-06-11): registo defensivo do token FCM (espelha o padrão do
    // partner_dashboard). Sem isto, o parceiro só-serviços nunca aparecia em
    // partner_push_tokens e o push de marcação nova não tinha destino.
    NotificationService.instance.savePushTokenForServicePartner().ignore();
  }

  void _reload() {
    setState(() {
      _future = context
          .read<PartnerAppointmentsStore>()
          .loadMyProvider(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Service-only partners reach this hub as their home screen (no route to
    // pop back to). Offer a logout action so they aren't stranded; when the hub
    // is pushed from the partner dashboard, the back button is the exit instead.
    final isHome = !Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Marcações',
        actions: isHome
            ? [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sair',
                  onPressed: () => _logout(context),
                ),
              ]
            : null,
      ),
      body: FutureBuilder<ServiceProviderModel?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString().replaceFirst('Exception: ', ''),
              onRetry: _reload,
            );
          }
          final provider = snap.data;
          if (provider == null) {
            return const _EmptyState();
          }
          return ListView(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                color: AppColors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Agenda, serviços, ${StaffTerminology.plural(provider.category).toLowerCase()} e financeiro.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // M2 (2026-06-12) — fecho semanal read-only (transparência).
              ProviderWeeklyPayoutCard(providerId: provider.id),
              _Tile(
                icon: Icons.calendar_month,
                title: 'Agenda',
                subtitle: 'Marcações de hoje e da semana',
                onTap: () => _push(context, const PartnerAgendaScreen()),
              ),
              _Tile(
                icon: Icons.add_circle_outline,
                title: 'Adicionar marcação',
                subtitle: 'Cliente sem marcação prévia',
                onTap: () => _push(context, const PartnerAddWalkInScreen()),
              ),
              _Tile(
                icon: Icons.block,
                title: 'Bloquear horário',
                subtitle:
                    'Pausas e folgas de um ${StaffTerminology.singular(provider.category).toLowerCase()}',
                onTap: () => _push(context, const PartnerBlockSlotScreen()),
              ),
              _Tile(
                icon: Icons.content_cut,
                title: 'Serviços',
                subtitle: 'Preços e duração',
                onTap: () =>
                    _push(context, const PartnerManageServicesScreen()),
              ),
              _Tile(
                icon: Icons.people_alt_outlined,
                title: StaffTerminology.plural(provider.category),
                subtitle: 'Equipa e disponibilidade',
                onTap: () => _push(context, const PartnerManageStaffScreen()),
              ),
              _Tile(
                icon: Icons.bar_chart,
                title: 'Financeiro',
                subtitle: 'Receita e liquidações',
                onTap: () =>
                    _push(context, const PartnerAppointmentsFinanceScreen()),
              ),
              // L3 — login com biometria (esconde-se sem biometria).
              const BiometricLoginTile(role: 'partner'),
            ],
          );
        },
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// Logs the partner out and clears the role, so _RootNavigator rebuilds back
  /// to the role chooser. Mirrors the partner dashboard logout flow.
  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.logout();
    await sessionStore.clearRole();
    navigator.popUntil((route) => route.isFirst);
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Sem negócio de serviços',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Esta conta não tem um negócio de marcações associado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
