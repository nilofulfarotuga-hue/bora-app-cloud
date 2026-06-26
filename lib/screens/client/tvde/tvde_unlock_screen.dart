import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Ecrã de desbloqueio da categoria escondida "Bora Motorista".
/// Mostra o estado do pedido (pendente/aprovado/recusado) e permite pedir
/// acesso. A aprovação é feita pelo admin (Fase 5).
class TvdeUnlockScreen extends StatefulWidget {
  const TvdeUnlockScreen({super.key});

  @override
  State<TvdeUnlockScreen> createState() => _TvdeUnlockScreenState();
}

class _TvdeUnlockScreenState extends State<TvdeUnlockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvdeStore>().refreshAccess();
    });
  }

  Future<void> _request() async {
    final store = context.read<TvdeStore>();
    try {
      await store.requestAccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido enviado! Aguarde a aprovação.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar o pedido.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final status = store.accessRequestStatus;
    final hasAccess = store.tvdeAccess;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Categoria exclusiva'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.lg),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car_filled,
                    size: 48, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Bora Motorista',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Uma categoria exclusiva de transporte de passageiros, '
              'disponível por convite. Pede o desbloqueio e a nossa equipa '
              'analisa o teu pedido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: Spacing.xl),
            _StateCard(status: hasAccess ? 'aprovado' : status),
            const SizedBox(height: Spacing.xl),
            if (!hasAccess && status != 'pendente')
              BoraAccentButton(
                label: status == 'recusado'
                    ? 'Pedir novamente'
                    : 'Quero desbloquear',
                icon: Icons.lock_open,
                loading: store.busy,
                onPressed: _request,
              ),
            if (hasAccess)
              BoraPrimaryButton(
                label: 'Voltar e abrir',
                icon: Icons.check_circle,
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String subtitle;

    switch (status) {
      case 'aprovado':
        icon = Icons.verified;
        color = AppColors.primary;
        title = 'Acesso aprovado';
        subtitle = 'Já podes pedir corridas no Bora Motorista.';
        break;
      case 'pendente':
        icon = Icons.hourglass_top;
        color = AppColors.warning;
        title = 'Pedido em análise';
        subtitle = 'Vamos avisar-te assim que for aprovado.';
        break;
      case 'recusado':
        icon = Icons.cancel;
        color = AppColors.error;
        title = 'Pedido recusado';
        subtitle = 'Podes voltar a pedir o desbloqueio.';
        break;
      default:
        icon = Icons.lock_outline;
        color = AppColors.textSecondary;
        title = 'Sem acesso';
        subtitle = 'Pede o desbloqueio para começar.';
    }

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
