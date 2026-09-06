import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_store.dart';

import '../../../l10n/tr.dart';

/// [Reserva agendada 2026-08-19] "As minhas reservas" — as viagens que o
/// cliente marcou para depois.
///
/// O ecrã é READ-ONLY sobre o relógio: quem trata da rotação de motoristas,
/// dos lembretes e do re-despacho é o cron `tvde-reservations-sweep`. Aqui só
/// se mostra o que está na linha e se deixa cancelar.
class TvdeMyReservationsScreen extends StatefulWidget {
  const TvdeMyReservationsScreen({super.key});

  @override
  State<TvdeMyReservationsScreen> createState() =>
      _TvdeMyReservationsScreenState();
}

class _TvdeMyReservationsScreenState extends State<TvdeMyReservationsScreen> {
  bool _aCarregar = true;
  int _horasCancelGratis = 2;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final store = context.read<TvdeStore>();
    final limites = await store.loadReservationLimits();
    await store.loadMyReservations();
    if (!mounted) return;
    setState(() {
      _horasCancelGratis = limites['freeCancelHours'] ?? 2;
      _aCarregar = false;
    });
  }

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
    if (d == null) return 'sem hora'.tr;
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${_meses[l.month - 1]} · $hh:$mm';
  }

  /// Cancelar é grátis enquanto faltar mais do que a janela das definições.
  bool _cancelaGratis(TvdeRide r) {
    final quando = r.scheduledAt;
    if (quando == null) return true;
    return quando.toLocal().difference(DateTime.now()).inMinutes >
        _horasCancelGratis * 60;
  }

  Future<void> _cancelar(TvdeRide r) async {
    final gratis = _cancelaGratis(r);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancelar a reserva?'.tr),
        content: Text(
          gratis
              ? 'Ainda estás a tempo — o cancelamento é grátis.'.tr
              : 'Faltam menos de {0} horas para a viagem. Pode haver uma taxa de cancelamento.'.trArgs([_horasCancelGratis]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Manter reserva'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancelar reserva'.tr),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    final store = context.read<TvdeStore>();
    try {
      await store.cancelReservation(r.id);
      if (!mounted) return;
      final online = r.paymentMethod != 'cash';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(online
            // O reembolso é automático do lado do servidor — a app só informa.
            ? 'Reserva cancelada. O reembolso é feito automaticamente.'.tr
            : 'Reserva cancelada.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(traduzErroReserva(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final reservas = store.reservations;

    return Scaffold(
      appBar: AppBar(title: Text('As minhas reservas'.tr)),
      body: _aCarregar
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: reservas.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        const Icon(Icons.event_available,
                            size: 56, color: AppColors.textSubtle),
                        const SizedBox(height: Spacing.md),
                        Center(
                          child: Text(
                            'Ainda não tens viagens marcadas.'.tr,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: Spacing.xl),
                            child: Text(
                              'No ecrã de pedir motorista tens "Marcar para depois".'.tr,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSubtle, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Spacing.lg),
                      itemCount: reservas.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Spacing.md),
                      itemBuilder: (_, i) => _cartao(reservas[i]),
                    ),
            ),
    );
  }

  Widget _cartao(TvdeRide r) {
    final estado = estadoReservaPt(r);
    final preco = (r.estFareCents / 100).toStringAsFixed(2);
    final podeCancelar = r.reservationStatus != 'cancelada';

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event, size: 18, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Text(
                _quando(r.scheduledAt),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              Text('€$preco',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          _linha(Icons.trip_origin, r.originLabel ?? 'Recolha'),
          const SizedBox(height: Spacing.xs),
          _linha(Icons.place_outlined, r.destLabel ?? 'Destino'),
          const SizedBox(height: Spacing.md),
          _chipEstado(r, estado),
          // O servidor cancela sozinho as reservas não pagas ao fim de 15 min.
          if (r.reservationAwaitingPayment) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Termina o pagamento para a reserva ficar marcada. Se não concluíres em 15 minutos, cancelamos sozinhos e não és cobrado.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (r.reservationStatus == 'sem_motorista') ...[
            const SizedBox(height: Spacing.sm),
            Text(
              r.paymentMethod == 'cash'
                  ? 'Não encontrámos motorista para esta hora. Podes marcar outra viagem.'.tr
                  : 'Não encontrámos motorista para esta hora. O reembolso é automático — não precisas de fazer nada.'.tr,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (r.cancelReason == 'payment_timeout') ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'A reserva foi cancelada por o pagamento não ter sido concluído a tempo. Não foste cobrado.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
          if (podeCancelar) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _cancelar(r),
                child: Text(
                  _cancelaGratis(r)
                      ? 'Cancelar (grátis)'.tr
                      : 'Cancelar reserva',
                  style: const TextStyle(color: AppColors.error),
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
          Icon(icon, size: 16, color: AppColors.textSubtle),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      );

  Widget _chipEstado(TvdeRide r, String estado) {
    Color cor;
    switch (r.reservationStatus) {
      case 'atribuida':
      case 'ativada':
        cor = AppColors.primary;
        break;
      case 'sem_motorista':
      case 'cancelada':
        cor = AppColors.error;
        break;
      default:
        cor = AppColors.textSecondary;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado,
        style: TextStyle(
            color: cor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
