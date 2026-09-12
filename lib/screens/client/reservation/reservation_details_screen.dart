import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../models/reservation_model.dart';
import '../../../stores/reservation_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'reservation_checkout_screen.dart' show kOccasionOptions;

import '../../../l10n/tr.dart';

/// Reservas PRO F3.B — detalhes completos de uma reserva.
/// Recebe callback `onCancelRequested` para reusar `_cancel()` do parent.
/// Botões acção variam conforme estado + janela temporal.
class ReservationDetailsScreen extends StatefulWidget {
  const ReservationDetailsScreen({
    super.key,
    required this.reservation,
    this.onCancelRequested,
  });

  final ReservationModel reservation;
  final VoidCallback? onCancelRequested;

  @override
  State<ReservationDetailsScreen> createState() =>
      _ReservationDetailsScreenState();
}

class _ReservationDetailsScreenState extends State<ReservationDetailsScreen> {
  bool _arriving = false;

  @override
  void initState() {
    super.initState();
    // 2026-05-14 — H1 fix: garantir stream realtime + fetch inicial.
    final store = context.read<ReservationStore>();
    store.subscribeMyReservations();
    if (store.findById(widget.reservation.id) == null) {
      // ignore: discarded_futures
      store.fetchMyReservations();
    }
  }

  /// 2026-05-14 — Lookup reactivo no store (listen:false, safe em handlers).
  /// Para o build re-renderizar quando o status mudar, o build() chama
  /// context.watch<ReservationStore>() (linha no inicio).
  /// Fallback: widget.reservation enquanto stream nao popular o store.
  ReservationModel get _r =>
      Provider.of<ReservationStore>(context, listen: false)
          .findById(widget.reservation.id) ??
      widget.reservation;

  bool get _arriveWindowActive {
    final diff = _r.reservedFor.difference(DateTime.now());
    // 30min antes até 60min depois reserved_for.
    return diff.inMinutes <= 30 && diff.inMinutes >= -60;
  }

  Future<void> _markArrived() async {
    if (_arriving) return;
    setState(() => _arriving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().markArrived(_r.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Chegada confirmada. O parceiro foi avisado.'.tr)),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _arriving = false);
    }
  }

  Future<void> _openMaps() async {
    final query = Uri.encodeComponent(
      _r.restaurantName ?? 'Restaurante',
    );
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o mapa.'.tr)),
      );
    }
  }

  Future<void> _callRestaurant(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível ligar.'.tr)),
      );
    }
  }

  void _comingSoonCalendar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Adicionar ao calendário — em breve.'.tr),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2026-05-14 — H1 fix: subscrever ReservationStore para re-render quando
    // o status muda em tempo real (parceiro aprova/rejeita). Watch ignora o
    // valor; o getter _r faz o lookup com listen:false.
    context.watch<ReservationStore>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Detalhes da reserva'.tr),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  _buildWhenCard(),
                  const SizedBox(height: 12),
                  if (_hasDetails()) _buildDetailsCard(),
                  if (_hasDetails()) const SizedBox(height: 12),
                  _buildPaymentCard(),
                  const SizedBox(height: 12),
                  _buildRestaurantCard(),
                ],
              ),
            ),
            _buildActionsBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final photoUrl = _r.restaurantPhotoUrl;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: (photoUrl != null && photoUrl.isNotEmpty)
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _photoFallback(),
                      )
                    : _photoFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _r.restaurantName ?? 'Restaurante',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusBadge(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoFallback() => Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.restaurant_outlined,
          color: AppColors.primary,
          size: 28,
        ),
      );

  Widget _buildStatusBadge() {
    final (label, color) = _resolveStatus();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  (String, Color) _resolveStatus() {
    final r = _r;
    if (r.isFinished) return ('Concluída'.tr, AppColors.primary);
    if (r.isNoShow) return ('Não compareceu'.tr, Colors.red);
    if (r.isArrived) return ('Chegou'.tr, AppColors.primary);
    if (r.status == ReservationStatus.seated) {
      return ('Sentado'.tr, AppColors.primary);
    }
    if (r.isApproved) return ('Confirmada'.tr, AppColors.primary);
    if (r.isPending) {
      return (
        r.status == ReservationStatus.pendingPayment
            ? 'Aguarda pagamento'.tr
            : 'Pendente',
        AppColors.accent,
      );
    }
    if (r.isCancelled) return (_labelForStatus(r.status), Colors.grey);
    return (_labelForStatus(r.status), Colors.grey);
  }

  static String _labelForStatus(String status) {
    switch (status) {
      case 'pending':              return 'Pendente'.tr;
      case 'pending_payment':      return 'Aguarda pagamento'.tr;
      case 'confirmed':            return 'Confirmada'.tr;
      case 'approved':             return 'Confirmada'.tr;
      case 'arrived':              return 'Chegou'.tr;
      case 'seated':               return 'Sentado'.tr;
      case 'completed':            return 'Concluída'.tr;
      case 'no_show':              return 'Não compareceu'.tr;
      case 'cancelled_by_client':  return 'Cancelada por si'.tr;
      case 'cancelled_by_partner': return 'Cancelada pelo restaurante'.tr;
      case 'cancelled_by_admin':   return 'Cancelada pela Bora'.tr;
      case 'cancelled_refunded':   return 'Cancelada (reembolso)'.tr;
      // F5 (2026-08-16): status novo do fix refund-fantasma — o refund
      // automático falhou e o admin foi alertado; o registo não mente.
      case 'cancelled_refund_pending': return 'Cancelada (reembolso a processar)'.tr;
      case 'cancelled_no_refund':  return 'Cancelada (sem reembolso)'.tr;
      case 'rejected_refunded':    return 'Recusada (reembolso)'.tr;
      case 'cancelled':            return 'Cancelada'.tr;
      case 'rejected':             return 'Recusada'.tr;
      default:                     return status;
    }
  }

  Widget _buildWhenCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.event, text: 'Quando'.tr),
            const SizedBox(height: 8),
            Text(
              _formatDateTimePt(_r.reservedFor.toLocal()),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _r.people == 1 ? '1 pessoa' : '${_r.people} pessoas',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasDetails() {
    return (_r.notes != null && _r.notes!.isNotEmpty) ||
        (_r.specialRequests != null && _r.specialRequests!.isNotEmpty) ||
        (_r.occasion != null && _r.occasion!.isNotEmpty);
  }

  Widget _buildDetailsCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.info_outline, text: 'Detalhes'.tr),
            const SizedBox(height: 8),
            if (_r.occasion != null && _r.occasion!.isNotEmpty)
              _DetailRow(
                label: 'Ocasião'.tr,
                value: kOccasionOptions[_r.occasion] ?? _r.occasion!,
              ),
            if (_r.specialRequests != null && _r.specialRequests!.isNotEmpty)
              _DetailRow(
                label: 'Pedidos especiais'.tr,
                value: _r.specialRequests!,
              ),
            if (_r.notes != null && _r.notes!.isNotEmpty)
              _DetailRow(label: 'Notas'.tr, value: _r.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard() {
    final eur = (_r.prepaymentCents / 100).toStringAsFixed(2);
    final status = _r.status;
    String label;
    Color color = AppColors.textSecondary;
    if (_r.isPending) {
      label = 'A processar'.tr;
      color = AppColors.accent;
    } else if (_r.isApproved || _r.isArrived || _r.isFinished) {
      label = 'Confirmado'.tr;
      color = AppColors.primary;
    } else if (status == ReservationStatus.cancelledRefunded ||
        status == ReservationStatus.rejectedRefunded) {
      label = 'Reembolsado'.tr;
      color = AppColors.primary;
    } else if (status == ReservationStatus.cancelledNoRefund || _r.isNoShow) {
      label = 'Não reembolsado'.tr;
      color = Colors.red;
    } else {
      label = '—';
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.credit_card,
              text: 'Pagamento'.tr,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '€{0} pré-pagamento'.trArgs([eur]),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.storefront_outlined,
              text: 'Restaurante'.tr,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openMaps,
                    icon: const Icon(Icons.directions, size: 18),
                    label: Text('Como chegar'.tr),
                  ),
                ),
                if (_r.clientPhone.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callRestaurant(_r.clientPhone),
                      icon: const Icon(Icons.phone, size: 18),
                      label: Text('Ligar'.tr),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsBar() {
    final actions = <Widget>[];

    if (_r.isPending) {
      actions.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              widget.onCancelRequested?.call();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            label: Text(
              'Cancelar reserva'.tr,
              style: const TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      );
    } else if (_r.isApproved && _r.arrivedAt == null) {
      if (_arriveWindowActive) {
        actions.add(
          Expanded(
            child: FilledButton.icon(
              onPressed: _arriving ? null : _markArrived,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _arriving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.location_on),
              label: Text(
                'Estou aqui'.tr,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      } else {
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                widget.onCancelRequested?.call();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              label: Text(
                'Cancelar'.tr,
                style: const TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        );
        actions.add(const SizedBox(width: 8));
        actions.add(
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _comingSoonCalendar,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Calendário'.tr),
            ),
          ),
        );
      }
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(children: actions),
    );
  }

  static String _formatDateTimePt(DateTime dt) {
    const weekdays = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final wd = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final mo = months[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${dt.day} de $mo • $hh:$mm';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
