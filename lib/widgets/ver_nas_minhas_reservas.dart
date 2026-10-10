import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../screens/client_main_screen.dart';
import 'bora/bora_bottom_nav_v2.dart';

/// "Ver nas minhas reservas" — no fim de marcar uma corrida para depois, uma
/// limpeza ou uma marcação, leva o cliente ao separador "Reservas", onde a
/// reserva fica (10/10/2026: dois clientes não a encontravam e julgaram-na
/// perdida).
class VerNasMinhasReservas extends StatelessWidget {
  const VerNasMinhasReservas({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () =>
            ClientMainScreen.abrirSeparador(context, BoraNavTab.reservation),
        icon: const Icon(Icons.event_note),
        label: Text('Ver nas minhas reservas'.tr),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Faixa de confirmação para pôr no topo do ecrã que se abre logo a seguir a
/// marcar: diz que ficou marcado e onde se encontra depois.
class ReservaMarcadaFaixa extends StatelessWidget {
  const ReservaMarcadaFaixa({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // O separador chama-se "Reserva" na barra de baixo.
            'Fica guardada no separador Reserva, em baixo.'.tr,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          const VerNasMinhasReservas(),
        ],
      ),
    );
  }
}
