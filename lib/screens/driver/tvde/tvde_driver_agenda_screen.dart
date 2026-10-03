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

  /// Devolver a reserva à Bora, a partir da AGENDA.
  ///
  /// A cicatriz (24/09/2026): o Danilo tinha uma reserva atribuída a ele para as 21h40 e
  /// não havia botão nenhum para a devolver — a reserva teve de passar ao Valdemir à mão,
  /// por SQL. O botão existia, mas só no ecrã da corrida a decorrer; uma reserva para daí a
  /// horas vive AQUI, na agenda, e aqui não havia saída.
  ///
  /// Sem penalizações inventadas: devolver cedo é bom para toda a gente, porque dá tempo à
  /// Bora de encontrar outro motorista. O servidor (`tvde_reservation_release`) é que trata
  /// de pôr a reserva outra vez à procura e de avisar o admin.
  Future<void> _devolver(TvdeRide r) async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Devolver esta reserva?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: Spacing.xs),
              const Text(
                'Vamos procurar outro motorista para o cliente. Não és penalizado — '
                'avisar cedo é o que ajuda.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.md),
              for (final m in const [
                'Imprevisto',
                'Estou longe',
                'Carro com problema',
                'Outro',
              ])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.undo, size: 18),
                  title: Text(m),
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
              const SizedBox(height: Spacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Afinal fico com ela'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (motivo == null || !mounted) return;

    final store = context.read<TvdeDriverStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await store.releaseReservation(r.id, motivo: motivo);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Reserva devolvida. Já estamos a procurar outro motorista.'
          : 'Já não dá para devolver esta reserva — fala com a Bora.'),
    ));
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
    // [Regra de ouro do motorista, 2026-08-21] O numero GRANDE e o que ELE
    // ganha. A variavel chamava-se `ganho` mas lia o preco do CLIENTE
    // (estFareCents) — mostrava-lhe 25,00 EUR quando ele recebe 22,00 EUR.
    // O total do cliente passa a aparecer so em pequeno, e so em dinheiro.
    final ganho = ((r.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    final cobra = (r.estFareCents / 100).toStringAsFixed(2);
    // [Ida-e-volta marcada · 23/09] perna de um pacote: a IDA e a VOLTA vêm
    // marcadas no cartão. No pacote a dinheiro o cliente paga o PACOTE ao
    // motorista da ida (não a tarifa desta perna) — o valor certo aparece no
    // ecrã da corrida; aqui não se mostra um número que estaria errado.
    final perna = tvdePernaDoPacote(r);
    final mostraCobranca =
        perna == null && r.paymentMethod == 'cash' && r.estFareCents > 0;
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
          if (perna != null) ...[
            const SizedBox(height: Spacing.xs),
            Container(
              key: const Key('agenda_perna_pacote'),
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(perna,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          Text(_faltam(r.scheduledAt),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle)),
          if (mostraCobranca) ...[
            const SizedBox(height: Spacing.xs),
            Text('cobras €$cobra ao cliente',
                key: const Key('agenda_cobra_cliente'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSubtle)),
          ],
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
          // [24/09] Saída honesta para quem já sabe que não vai conseguir. Aparece enquanto
          // a reserva está atribuída a ele e ainda não começou.
          if (r.reservationStatus == 'atribuida' ||
              r.reservationStatus == 'ativada') ...[
            const SizedBox(height: Spacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _devolver(r),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Devolver reserva'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.warning),
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
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

/// Rótulo da perna de um pacote ida-e-volta, ou `null` se a reserva não é
/// de um pacote. "Ida" = corrida com vale e sem ser volta; "Volta" = a perna
/// de regresso (`is_return_leg`).
String? tvdePernaDoPacote(TvdeRide r) {
  if (r.isReturnLeg) return 'Volta · pacote ida-e-volta';
  if (r.roundtripCreditId != null) return 'Ida · pacote ida-e-volta';
  return null;
}
