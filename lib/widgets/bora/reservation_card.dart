import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/reservation_model.dart';

/// Card de reserva (Reservas PRO F3.A).
///
/// Reutilizado por MyReservations (cliente). Recebe callbacks opcionais —
/// quem consome decide o que renderizar.
class ReservationCard extends StatelessWidget {
  const ReservationCard({
    super.key,
    required this.reservation,
    this.onCancel,
    this.onArrive,
    this.onDetails,
  });

  final ReservationModel reservation;
  final VoidCallback? onCancel;
  final VoidCallback? onArrive;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final restaurantName =
        (r.restaurantName != null && r.restaurantName!.isNotEmpty)
            ? r.restaurantName!
            : 'Restaurante';
    final photoUrl = r.restaurantPhotoUrl;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RestaurantThumb(photoUrl: photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurantName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTimePt(r.reservedFor.toLocal()),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _peopleLabel(r.people),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(reservation: r),
              ],
            ),
            if (r.specialRequests != null && r.specialRequests!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pedido: ${r.specialRequests}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
            if (onCancel != null || onArrive != null || onDetails != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (onDetails != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDetails,
                        child: const Text('Ver detalhes'),
                      ),
                    ),
                  if (onDetails != null &&
                      (onArrive != null || onCancel != null))
                    const SizedBox(width: 8),
                  if (onArrive != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onArrive,
                        icon: const Icon(Icons.location_on, size: 18),
                        label: const Text('Estou aqui'),
                      ),
                    ),
                  if (onArrive != null && onCancel != null)
                    const SizedBox(width: 8),
                  if (onCancel != null)
                    IconButton(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined),
                      color: Colors.red,
                      tooltip: 'Cancelar reserva',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _peopleLabel(int people) =>
      people == 1 ? '1 pessoa' : '$people pessoas';

  /// Formata DateTime PT-PT sem `intl` (não está em pubspec):
  /// "Sex, 9 mai • 20:30"
  static String _formatDateTimePt(DateTime dt) {
    const weekdays = [
      'Seg',
      'Ter',
      'Qua',
      'Qui',
      'Sex',
      'Sáb',
      'Dom',
    ];
    const months = [
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
    final wd = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final mo = months[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${dt.day} $mo • $hh:$mm';
  }
}

class _RestaurantThumb extends StatelessWidget {
  const _RestaurantThumb({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ThumbFallback(),
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return const _ThumbFallback();
                },
              )
            : const _ThumbFallback(),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant_outlined,
        color: AppTheme.primary,
        size: 28,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.reservation});
  final ReservationModel reservation;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(reservation);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  static (String, Color) _resolve(ReservationModel r) {
    if (r.isFinished) {
      return ('Concluída', AppTheme.primary);
    }
    if (r.isNoShow) {
      return ('Não compareceu', Colors.red);
    }
    if (r.isArrived) {
      return ('Chegou', AppTheme.primary);
    }
    if (r.status == ReservationStatus.seated) {
      return ('Sentado', AppTheme.primary);
    }
    if (r.isApproved) {
      return ('Confirmada', AppTheme.primary);
    }
    if (r.isPending) {
      return (
        r.status == ReservationStatus.pendingPayment
            ? 'Aguarda pagamento'
            : 'Pendente',
        AppTheme.secondary,
      );
    }
    if (r.isCancelled) {
      return (_labelForStatus(r.status), Colors.grey);
    }
    return (_labelForStatus(r.status), Colors.grey);
  }

  static String _labelForStatus(String status) {
    switch (status) {
      case 'pending':              return 'Pendente';
      case 'pending_payment':      return 'Aguarda pagamento';
      case 'confirmed':            return 'Confirmada';
      case 'approved':             return 'Confirmada';
      case 'arrived':              return 'Chegou';
      case 'seated':               return 'Sentado';
      case 'completed':            return 'Concluída';
      case 'no_show':              return 'Não compareceu';
      case 'cancelled_by_client':  return 'Cancelada por si';
      case 'cancelled_by_partner': return 'Cancelada pelo restaurante';
      case 'cancelled_by_admin':   return 'Cancelada pela Bora';
      case 'cancelled_refunded':   return 'Cancelada (reembolso)';
      case 'cancelled_no_refund':  return 'Cancelada (sem reembolso)';
      case 'rejected_refunded':    return 'Recusada (reembolso)';
      case 'cancelled':            return 'Cancelada';
      case 'rejected':             return 'Recusada';
      default:                     return status;
    }
  }
}
