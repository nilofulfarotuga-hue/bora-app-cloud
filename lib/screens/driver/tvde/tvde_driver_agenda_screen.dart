import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/navigation_service.dart';
import '../../../stores/tvde_driver_store.dart';

/// [Reserva agendada 2026-08-19] AGENDA do motorista — as reservas que já são
/// dele, por ordem de hora. É a "memória" que o Danilo pediu: o motorista abre
/// e vê o que tem marcado, sem depender de se lembrar da notificação.
///
/// O relógio é todo do servidor (cron `tvde-reservations-sweep`). Este ecrã só
/// mostra o que está na linha e deixa carregar "A caminho".
class TvdeDriverAgendaScreen extends StatefulWidget {
  const TvdeDriverAgendaScreen({super.key});

  @override
  State<TvdeDriverAgendaScreen> createState() => _TvdeDriverAgendaScreenState();
}

class _TvdeDriverAgendaScreenState extends State<TvdeDriverAgendaScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    context.read<TvdeDriverStore>().loadAgenda();
    // Refresca o "faltam X min" sem bater no servidor.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static const _diasSemana = [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ];
  static const _meses = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  String _quando(DateTime? d) {
    if (d == null) return 'hora a confirmar';
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${_diasSemana[l.weekday - 1]}, ${l.day} ${_meses[l.month - 1]} '
        '· $hh:$mm';
  }

  String _faltam(DateTime? d) {
    if (d == null) return '';
    final min = d.toLocal().difference(DateTime.now()).inMinutes;
    if (min < 0) return 'agora';
    if (min < 60) return 'faltam $min min';
    final h = min ~/ 60;
    if (h < 24) return 'faltam ${h}h';
    return 'faltam ${h ~/ 24} dias';
  }

  Future<void> _aCaminho(TvdeRide r) async {
    final store = context.read<TvdeDriverStore>();
    final ok = await store.reservationReady(r.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Confirmado. Bom trabalho — vai a caminho da recolha.'
          : 'Não consegui confirmar. Tenta outra vez.'),
    ));
    if (ok) {
      await NavigationService.openNavigationOptions(
        context,
        LatLng(r.originLat, r.originLng),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    final agenda = store.agenda;

    return Scaffold(
      appBar: AppBar(title: const Text('A minha agenda')),
      body: RefreshIndicator(
        onRefresh: () => store.loadAgenda(),
        child: agenda.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.event_note,
                      size: 56, color: AppColors.textSubtle),
                  SizedBox(height: Spacing.md),
                  Center(
                    child: Text(
                      'Ainda não tens reservas marcadas.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(height: Spacing.xs),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Spacing.xl),
                      child: Text(
                        'Quando houver uma corrida marcada para ti, chega-te '
                        'aqui uma oferta para aceitares com antecedência.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSubtle, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.lg),
                itemCount: agenda.length,
                separatorBuilder: (_, __) => const SizedBox(height: Spacing.md),
                itemBuilder: (_, i) => _cartao(agenda[i]),
              ),
      ),
    );
  }

  Widget _cartao(TvdeRide r) {
    final ganho = (r.estFareCents / 100).toStringAsFixed(2);
    final confirmou = r.reservationDriverReadyAt != null;
    final minutos =
        r.scheduledAt?.toLocal().difference(DateTime.now()).inMinutes ?? 9999;
    // Perto da hora dá para carregar "A caminho" mesmo sem a notificação —
    // rede de segurança se o push falhar.
    final podeConfirmar = !confirmou && minutos <= 60;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: podeConfirmar ? AppColors.primary : AppColors.divider,
          width: podeConfirmar ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event, size: 18, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  _quando(r.scheduledAt),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Text('€$ganho',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(_faltam(r.scheduledAt),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle)),
          const SizedBox(height: Spacing.sm),
          _linha(Icons.trip_origin, r.originLabel ?? 'Recolha'),
          const SizedBox(height: Spacing.xs),
          _linha(Icons.place_outlined, r.destLabel ?? 'Destino'),
          const SizedBox(height: Spacing.md),

          // O aviso que a missão pede, em texto claro.
          if (confirmou)
            const Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.primary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Já confirmaste que vais. A reserva é tua.',
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.error),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Perto da hora recebes um aviso para confirmares que vais. '
                      'Se não confirmares, a corrida passa a outro motorista.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          if (podeConfirmar) ...[
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _aCaminho(r),
                icon: const Icon(Icons.navigation),
                label: const Text('A caminho'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(IconData icon, String texto) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSubtle),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      );
}
