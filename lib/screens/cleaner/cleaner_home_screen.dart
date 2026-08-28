import '../../services/push_token_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/cleaning_models.dart';
import '../../services/roles_service.dart';
import '../../stores/cleaner_store.dart';
import '../../stores/session_store.dart';
import '../../widgets/bora/bora.dart';
import '../../widgets/bora_support_sheet.dart';
import '../../widgets/payments/collect_badge.dart';
import '../../widgets/cleaning_chat_button.dart';
import '../../widgets/multirole_switch_card.dart';
import '../driver/driver_role_apply_screen.dart';
import 'cleaner_apply_screen.dart';
import 'cleaner_availability_screen.dart';
import '../ganhos_screen.dart';
import '../../widgets/botao_rota.dart';
import 'cleaner_history_screen.dart';

/// LIMPEZA — painel da profissional. Router por estado da candidatura:
/// sem registo → convite; pending → em análise; rejected → recandidatar;
/// suspended → aviso; approved → painel (ofertas + agenda + atalhos).
class CleanerHomeScreen extends StatefulWidget {
  const CleanerHomeScreen({super.key});

  @override
  State<CleanerHomeScreen> createState() => _CleanerHomeScreenState();
}

class _CleanerHomeScreenState extends State<CleanerHomeScreen> {
  RolesSummary _roles = RolesSummary.empty();

  @override
  void initState() {
    super.initState();
    // Sem isto, quem for aprovado com a app JA ABERTA fica sem
    // aparelho registado ate reiniciar — e um pedido que chegue
    // nesse intervalo nao toca a ninguem. O portao de autenticacao
    // no main.dart apanha o arranque; isto apanha o meio da sessao.
    PushTokenService.registerForRole('cleaner').ignore();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CleanerStore>().loadProfile();
    });
    // MULTI-PAPEL: saber se já é estafeta (para pré-preencher a candidatura
    // e mostrar o card de troca de papel no painel).
    RolesService.mySummary().then((r) {
      if (mounted) setState(() => _roles = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleanerStore>();
    final profile = store.profile;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Limpezas — Profissional'),
      body: !store.profileLoaded
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? _InviteView(onApply: _openApply)
              : switch (profile.approvalStatus) {
                  'approved' => _PanelView(store: store, roles: _roles),
                  'pending' => const _StatusView(
                      icon: Icons.hourglass_top,
                      color: AppColors.warning,
                      title: 'Candidatura em análise',
                      subtitle:
                          'A equipa Bora está a rever os teus dados. '
                          'Avisamos-te assim que estiver aprovada.',
                    ),
                  'suspended' => const _StatusView(
                      icon: Icons.pause_circle_outline,
                      color: AppColors.error,
                      title: 'Conta suspensa para revisão',
                      subtitle:
                          'A tua conta está em revisão pela equipa Bora. '
                          'Contacta o suporte para mais detalhes.',
                    ),
                  _ => _RejectedView(
                      reason: profile.rejectionReason,
                      onReapply: _openApply,
                    ),
                },
    );
  }

  void _openApply() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // MULTI-PAPEL: se já é estafeta, pré-preenche com os dados do driver.
        builder: (_) => CleanerApplyScreen(prefill: _roles.driverProfile),
      ),
    ).then((_) {
      if (mounted) context.read<CleanerStore>().loadProfile();
    });
  }
}

// ─── estados sem painel ──────────────────────────────────────────────────────

class _InviteView extends StatelessWidget {
  const _InviteView({required this.onApply});
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.primaryWash,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cleaning_services,
                  size: 48, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Ganha com limpezas',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: Spacing.sm),
          const Text(
            'Recebe 85% de cada limpeza + o valor dos produtos quando os '
            'levas. Tu escolhes os dias, as horas e a zona onde trabalhas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: 'Quero candidatar-me',
            icon: Icons.arrow_forward,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: Spacing.lg),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.sm),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _RejectedView extends StatelessWidget {
  const _RejectedView({required this.reason, required this.onReapply});
  final String? reason;
  final VoidCallback onReapply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cancel_outlined, size: 64, color: AppColors.error),
          const SizedBox(height: Spacing.lg),
          const Text('Candidatura recusada',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text('Motivo: $reason',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: 'Candidatar de novo',
            icon: Icons.refresh,
            onPressed: onReapply,
          ),
        ],
      ),
    );
  }
}

// ─── painel aprovado ─────────────────────────────────────────────────────────

class _PanelView extends StatelessWidget {
  const _PanelView({required this.store, required this.roles});
  final CleanerStore store;
  final RolesSummary roles;

  Future<void> _switchToDriver(BuildContext context) async {
    final nav = Navigator.of(context);
    await context.read<SessionStore>().setRole(UserRole.driver);
    // _RootNavigator (na raiz) reconstrói para a home do estafeta.
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final profile = store.profile!;
    return RefreshIndicator(
      onRefresh: () async {
        await store.loadWork();
      },
      child: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          // Disponibilidade geral (interruptor da própria)
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(
                  profile.isActive
                      ? Icons.check_circle
                      : Icons.pause_circle_filled,
                  color: profile.isActive
                      ? AppColors.primary
                      : AppColors.textSubtle,
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.isActive
                            ? 'A receber novas limpezas'
                            : 'Em pausa — sem novas ofertas',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      if (profile.ratingsCount > 0)
                        Text(
                          '★ ${profile.ratingAvg.toStringAsFixed(1)} '
                          '(${profile.ratingsCount}) · '
                          '${profile.cleaningsDone} limpezas',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: profile.isActive,
                  activeThumbColor: AppColors.primary,
                  onChanged: store.busy
                      ? null
                      : (v) => store.setProfile(isActive: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // MULTI-PAPEL: convite/troca para Entregas e Viagens (estafeta).
          MultiRoleSwitchCard(
            icon: Icons.two_wheeler,
            otherStatus: roles.driverStatus,
            inviteTitle: 'Trabalha também em Entregas e Viagens?',
            inviteSubtitle:
                'Usa a mesma conta e ganha nas duas frentes. Só pedimos o '
                'veículo e os documentos.',
            activeTitle: 'As minhas Entregas e Viagens',
            pendingTitle: 'Candidatura a estafeta em análise',
            onInvite: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DriverRoleApplyScreen(prefill: roles.cleanerProfile),
              ),
            ),
            onOpen: () => _switchToDriver(context),
          ),
          const SizedBox(height: Spacing.lg),

          // Atalhos
          Row(
            children: [
              Expanded(
                child: _ShortcutCard(
                  icon: Icons.event_available,
                  label: 'A minha disponibilidade',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CleanerAvailabilityScreen()),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _ShortcutCard(
                  icon: Icons.payments_outlined,
                  label: 'Ganhos',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GanhosScreen()),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _ShortcutCard(
                  icon: Icons.history,
                  label: 'Histórico',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CleanerHistoryScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: _ShortcutCard(
                  icon: Icons.support_agent_outlined,
                  label: 'Suporte',
                  // Mesmo canal do estafeta (BoraIA + WhatsApp + Email).
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const BoraSupportSheet(),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: Spacing.lg),

          if (store.slots.isEmpty) ...[
            InkWell(
              borderRadius: BorderRadius.circular(Radii.lg),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CleanerAvailabilityScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning),
                    SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        'Ainda não marcaste a tua disponibilidade — sem ela '
                        'não recebes ofertas. Toca aqui para marcar os teus '
                        'dias e horas.',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.warning),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
          ],

          // Ofertas pendentes
          if (store.offers.isNotEmpty) ...[
            const _SectionLabel('Novas ofertas'),
            for (final b in store.offers)
              _OfferCard(booking: b, store: store),
            const SizedBox(height: Spacing.md),
          ],

          // Agenda ativa
          const _SectionLabel('As minhas limpezas'),
          if (store.agenda.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: Text(
                'Sem limpezas marcadas. As novas ofertas aparecem aqui.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final b in store.agenda) _AgendaCard(booking: b, store: store),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: Spacing.xs),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary)),
    );
  }
}

String _fmtWhen(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} às ${two(d.hour)}:${two(d.minute)}';
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.booking, required this.store});
  final CleaningBooking booking;
  final CleanerStore store;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final minsLeft =
        b.offerExpiresAt?.difference(DateTime.now()).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.primaryWash,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${b.typeLabel} · ${b.sizeLabel}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(
              '${_fmtWhen(b.scheduledAt)} · ${b.addressCity}\n'
              'Ganhas ${CleaningLabels.euro(b.cleanerEarningsCents)}'
              '${b.productsBy == 'cleaner' ? ' (produtos incluídos)' : ''}'
              '${b.isRecurring ? ' · ${b.recurrenceLabel}' : ''}',
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.4),
            ),
            if (minsLeft != null && minsLeft >= 0)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text('Expira em $minsLeft min',
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: store.busy
                        ? null
                        : () => _run(context, () => store.rejectBooking(b.id),
                            'Oferta recusada.'),
                    child: const Text('Recusar'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    onPressed: store.busy
                        ? null
                        : () => _run(context, () => store.acceptBooking(b.id),
                            'Limpeza aceite! 🎉'),
                    child: const Text('Aceitar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action,
      String successMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      final expired = e.toString().contains('offer');
      messenger.showSnackBar(SnackBar(
          content: Text(expired
              ? 'Esta oferta já não está disponível.'
              : 'Não foi possível concluir. Tenta de novo.')));
    }
  }
}

class _AgendaCard extends StatefulWidget {
  const _AgendaCard({required this.booking, required this.store});
  final CleaningBooking booking;
  final CleanerStore store;

  @override
  State<_AgendaCard> createState() => _AgendaCardState();
}

class _AgendaCardState extends State<_AgendaCard> {
  CleaningBooking get booking => widget.booking;
  CleanerStore get store => widget.store;

  Map<String, dynamic>? _client;

  @override
  void initState() {
    super.initState();
    // Card público do cliente (nome/foto/telefone) — identidade só depois
    // de aceitar, padrão TVDE D2.
    store.clientCard(booking.id).then((c) {
      if (mounted) setState(() => _client = c);
    });
  }

  Future<void> _callClient() async {
    final phone = _client?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${b.typeLabel} · ${b.sizeLabel}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                Text(b.status.labelPt,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmtWhen(b.scheduledAt)}\n'
              '${b.addressStreet}, ${b.addressCity} ${b.addressPostal}'
              '${b.notes.isNotEmpty ? '\nNota: ${b.notes}' : ''}\n'
              'Ganhas ${CleaningLabels.euro(b.cleanerEarningsCents)} · '
              '${b.paymentMethod == 'cash' ? 'Dinheiro no local' : 'Pago na app'}',
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.4),
            ),
            // ABRIR A ROTA (2026-08-29): o motorista tem mapa, quem limpa
            // tinha a morada escrita e copiava-a a mao.
            Align(
              alignment: Alignment.centerLeft,
              // Sem coordenadas: o modelo da limpeza nao as traz, so a
              // morada escrita. O Google Maps procura por ela na mesma.
              child: BotaoRota(
                morada:
                    '${b.addressStreet}, ${b.addressCity} ${b.addressPostal}',
              ),
            ),
            // Badge de cobrança UNIFICADO (mesmo widget do delivery/TVDE):
            // dinheiro → cobrar o total; card/MB Way → já pago (não cobrar).
            const SizedBox(height: 6),
            CollectBadge(
              state: b.paymentMethod == 'cash'
                  ? CollectState.collectCash
                  : CollectState.paidOnline,
              amountCents: b.paymentMethod == 'cash' ? b.totalCents : null,
            ),
            const SizedBox(height: Spacing.sm),
            // Cliente (nome/foto) + comunicação — só com serviço em curso.
            if (const [
              CleaningStatus.accepted,
              CleaningStatus.onTheWay,
              CleaningStatus.inProgress,
              CleaningStatus.done,
            ].contains(b.status)) ...[
              // Parte 7 — durante o serviço (a caminho / em curso / concluir), se
              // for dinheiro, lembrete GRANDE de cobrar (antes era uma linha tímida).
              if (b.paymentMethod == 'cash')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border:
                        Border.all(color: Colors.orange.shade400, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payments,
                          color: Colors.orange.shade900, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'RECEBER ${CleaningLabels.euro(b.totalCents)} EM DINHEIRO',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryWash,
                    backgroundImage:
                        (_client?['photo_url'] as String?)?.isNotEmpty == true
                            ? NetworkImage(_client!['photo_url'] as String)
                            : null,
                    child: (_client?['photo_url'] as String?)?.isNotEmpty == true
                        ? null
                        : const Icon(Icons.person,
                            size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      (_client?['name'] as String?)?.isNotEmpty == true
                          ? _client!['name'] as String
                          : 'Cliente',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  CleaningChatButton(
                    bookingId: b.id,
                    myRole: 'cleaner',
                    title: (_client?['name'] as String?)?.isNotEmpty == true
                        ? _client!['name'] as String
                        : 'Cliente',
                    otherPhone: _client?['phone'] as String?,
                    compact: true,
                  ),
                  if ((_client?['phone'] as String?)?.isNotEmpty == true)
                    IconButton(
                      onPressed: _callClient,
                      tooltip: 'Ligar',
                      icon: const Icon(Icons.call, color: AppColors.primary),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
            ],
            _actionRow(context),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    final b = booking;
    switch (b.status) {
      case CleaningStatus.accepted:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed:
                    store.busy ? null : () => _safe(context, () => store.markOnTheWay(b.id)),
                icon: const Icon(Icons.directions_walk, size: 18),
                label: const Text('A caminho'),
              ),
            ),
            _menu(context),
          ],
        );
      case CleaningStatus.onTheWay:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed:
                    store.busy ? null : () => _safe(context, () => store.markStarted(b.id)),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Iniciar limpeza'),
              ),
            ),
            _menu(context),
          ],
        );
      case CleaningStatus.inProgress:
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: store.busy
              ? null
              : () => _safe(context, () => store.markDone(b.id),
                  aoTerminar: true),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Concluir limpeza'),
        );
      case CleaningStatus.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'À espera da confirmação do cliente (automática em 24 h).',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
            const SizedBox(height: Spacing.sm),
            OutlinedButton.icon(
              onPressed: () => _rateClient(context),
              icon: const Icon(Icons.star_border, size: 18),
              label: const Text('Avaliar o cliente'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Avaliação do cliente pela profissional (avaliação bidirecional — paridade
  /// TVDE/delivery; a mesma RPC cleaning_submit_rating deteta o sujeito).
  Future<void> _rateClient(BuildContext context) async {
    var stars = 5;
    final commentCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Como foi o cliente?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setDialogState(() => stars = i),
                      icon: Icon(i <= stars ? Icons.star : Icons.star_border,
                          color: AppColors.warning, size: 30),
                    ),
                ],
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration:
                    const InputDecoration(hintText: 'Comentário (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Agora não')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enviar')),
          ],
        ),
      ),
    );
    if (submitted != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.rateClient(booking.id, stars, comment: commentCtrl.text.trim());
      messenger.showSnackBar(
          const SnackBar(content: Text('Obrigado pela avaliação! 💚')));
    } catch (e) {
      final already = e.toString().contains('already_rated');
      messenger.showSnackBar(SnackBar(
          content: Text(already
              ? 'Já avaliaste este cliente.'
              : 'Não foi possível enviar a avaliação.')));
    }
  }

  /// Menu com cancelar / no-show (só quando aplicável).
  Widget _menu(BuildContext context) {
    final b = booking;
    final canNoShow = DateTime.now().isAfter(b.scheduledAt);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onSelected: (v) {
        if (v == 'cancel') _confirmCancel(context);
        if (v == 'no_show') _confirmNoShow(context);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'cancel', child: Text('Cancelar esta limpeza')),
        if (canNoShow)
          const PopupMenuItem(
              value: 'no_show', child: Text('Cliente não apareceu')),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final b = booking;
    final hoursLeft =
        b.scheduledAt.difference(DateTime.now()).inMinutes / 60.0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar esta limpeza?'),
        content: Text(hoursLeft < 24
            ? 'Faltam menos de 24 h — este cancelamento conta para o limite '
                'de cancelamentos tardios (3 em 30 dias suspende a conta). '
                'A reserva volta para as outras profissionais.'
            : 'A reserva volta para as outras profissionais.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Manter')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar limpeza',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _safe(context, () => store.cancelBooking(b.id));
    }
  }

  Future<void> _confirmNoShow(BuildContext context) async {
    final b = booking;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cliente não apareceu?'),
        content: const Text(
            'Só marca não comparência se estás na morada à hora marcada e o '
            'cliente não responde. É aplicada a taxa de 100% ao cliente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Marcar não comparência',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _safe(context, () => store.cancelBooking(b.id, noShow: true));
    }
  }

  /// [aoTerminar] marca a ULTIMA accao da limpeza. Ate 2026-08-29 a
  /// profissional ficava presa neste ecra depois de concluir, ate carregar na
  /// setinha — o Danilo apanhou isso no teste ao vivo. Agora volta sozinha ao
  /// ecra de onde veio; a avaliacao do cliente continua aqui enquanto o
  /// pedido esperar a confirmacao dele.
  Future<void> _safe(BuildContext context, Future<void> Function() fn,
      {bool aoTerminar = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await fn();
      if (aoTerminar) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Limpeza concluída. Podes avaliar o cliente em '
                '"A minha Limpeza".')));
        if (navigator.canPop()) navigator.pop();
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível concluir. Tenta de novo.')));
    }
  }
}
