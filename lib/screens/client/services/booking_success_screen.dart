import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../widgets/bora/bora_primary_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'my_appointments_screen.dart';

/// Vertical Serviços — ecrã de sucesso pós-pagamento da marcação.
class BookingSuccessScreen extends StatelessWidget {
  const BookingSuccessScreen({
    super.key,
    required this.providerName,
    required this.serviceName,
    required this.scheduledAt,
    required this.paidCents,
  });

  final String providerName;
  final String serviceName;
  final DateTime scheduledAt;

  /// FIM DO SINAL (2026-08-03) — valor TOTAL do serviço já cobrado.
  final int paidCents;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Marcação confirmada'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 56, color: AppColors.primary),
              ),
              const SizedBox(height: Spacing.xl),
              const Text(
                'Marcação confirmada!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                '$serviceName em $providerName\n${_formatDateTimePt(scheduledAt)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                'Pago: €${(paidCents / 100).toStringAsFixed(2)} — valor total '
                'do serviço. Não há mais nada a pagar na loja.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSubtle),
              ),
              const Spacer(),
              BoraPrimaryButton(
                label: 'Ver as minhas marcações',
                icon: Icons.event_note,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyAppointmentsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Voltar ao início'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDateTimePt(DateTime dt) {
    const weekdays = [
      'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo',
    ];
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    final d = dt.toLocal();
    final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
    final mo = months[(d.month - 1).clamp(0, 11)];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$wd, ${d.day} de $mo • $hh:$mm';
  }
}
