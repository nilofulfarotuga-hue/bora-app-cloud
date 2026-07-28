// Marcação (vertical Serviços / Barbearias).
//
// Espelha a tabela `appointments`. O cliente vê as suas
// (client_user_id = auth.uid()) via RLS.

/// Status canónicos de uma marcação. DB usa TEXT.
class AppointmentStatus {
  static const String pendingPayment = 'pending_payment';
  static const String confirmed = 'confirmed';
  static const String completed = 'completed';
  static const String noShow = 'no_show';
  static const String cancelled = 'cancelled';
  static const String blocked = 'blocked';
}

class AppointmentModel {
  AppointmentModel({
    required this.id,
    required this.providerId,
    this.serviceId,
    required this.scheduledAt,
    this.staffId,
    this.clientUserId,
    this.clientName,
    this.clientPhone,
    this.durationMinutes = 30,
    this.servicePriceCents = 0,
    this.depositCents = 0,
    this.depositPi,
    this.depositStatus,
    this.fullPaymentMethod,
    this.fullPaymentStatus,
    this.status = AppointmentStatus.pendingPayment,
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.cancelledBy,
    this.noShowAt,
    this.clientNotes,
    this.partnerNotes,
    this.isWalkIn = false,
    this.rescheduleCount = 0,
    this.originalScheduledAt,
    this.lastRescheduledAt,
    DateTime? createdAt,
    // JOIN extras opcionais (populados quando fetch faz JOIN).
    this.providerName,
    this.serviceName,
    this.staffName,
    this.providerPhotoUrl,
    this.providerCancellationPolicy,
    this.providerPaymentMode,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String providerId;

  /// null em slots bloqueados (partner_block_slot grava service_id NULL).
  /// B2 (2026-06-11): era `String` não-nullable — o cast rebentava no parse
  /// da agenda assim que o parceiro bloqueava um horário ("Não foi possível
  /// carregar a agenda").
  final String? serviceId;
  final DateTime scheduledAt;
  final String? staffId;
  final String? clientUserId;
  final String? clientName;
  final String? clientPhone;
  final int durationMinutes;
  final int servicePriceCents;
  final int depositCents;
  final String? depositPi;
  final String? depositStatus;
  final String? fullPaymentMethod;
  final String? fullPaymentStatus;
  final String status;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? cancelledBy;
  final DateTime? noShowAt;
  final String? clientNotes;
  final String? partnerNotes;
  final bool isWalkIn;

  /// BLOCO E (2026-07-28) — reagendamento. A marcação é sempre a MESMA linha
  /// (mesmo `deposit_pi`): reagendar nunca cobra nem reembolsa.
  final int rescheduleCount;
  final DateTime? originalScheduledAt;
  final DateTime? lastRescheduledAt;

  /// Foi reagendada pelo menos uma vez (mostra etiqueta na agenda).
  bool get wasRescheduled => rescheduleCount > 0;

  final DateTime createdAt;

  // JOIN extras (não no schema appointments).
  final String? providerName;
  final String? serviceName;
  final String? staffName;
  final String? providerPhotoUrl;

  /// JOIN extras do parceiro (BLOCO B/E, 2026-07-28) — vêm do
  /// `select('*, service_providers(...)')`. Decidem o que o ecrã do cliente
  /// mostra: cancelar vs reagendar, e sinal vs valor total.
  final String? providerCancellationPolicy;
  final String? providerPaymentMode;

  /// O parceiro só aceita reagendamento (não cancelamento) — e esta marcação
  /// já está paga, portanto o dinheiro está preso a ela.
  bool get isRescheduleOnly =>
      providerCancellationPolicy == 'reschedule_only' && depositStatus == 'paid';

  /// O parceiro cobra o preço cheio do serviço na marcação.
  bool get isFullPaymentMode => providerPaymentMode == 'full';

  /// Preço total do serviço formatado: '€18,00'.
  String get servicePriceLabel =>
      '€${(servicePriceCents / 100).toStringAsFixed(2)}';

  factory AppointmentModel.fromSupabase(Map<String, dynamic> row) {
    DateTime? parseTs(Object? v) => v is String ? DateTime.parse(v) : null;

    // Extrai joins se presentes (select('*, service_providers(...),
    // provider_services(...), staff_members(...)')).
    String? providerName;
    String? providerPhotoUrl;
    String? providerCancellationPolicy;
    String? providerPaymentMode;
    final p = row['service_providers'];
    if (p is Map) {
      providerName = p['name'] as String?;
      providerPhotoUrl =
          (p['photo_url'] as String?) ?? (p['hero_image_url'] as String?);
      providerCancellationPolicy = p['booking_cancellation_policy'] as String?;
      providerPaymentMode = p['booking_payment_mode'] as String?;
    }
    String? serviceName;
    final s = row['provider_services'];
    if (s is Map) serviceName = s['name'] as String?;
    String? staffName;
    final st = row['staff_members'];
    if (st is Map) staffName = st['name'] as String?;

    return AppointmentModel(
      id: row['id'] as String,
      providerId: row['provider_id'] as String,
      serviceId: row['service_id'] as String?,
      scheduledAt: DateTime.parse(row['scheduled_at'] as String),
      staffId: row['staff_id'] as String?,
      clientUserId: row['client_user_id'] as String?,
      clientName: row['client_name'] as String?,
      clientPhone: row['client_phone'] as String?,
      durationMinutes: (row['duration_minutes'] as int?) ?? 30,
      servicePriceCents: (row['service_price_cents'] as int?) ?? 0,
      depositCents: (row['deposit_cents'] as int?) ?? 0,
      depositPi: row['deposit_pi'] as String?,
      depositStatus: row['deposit_status'] as String?,
      fullPaymentMethod: row['full_payment_method'] as String?,
      fullPaymentStatus: row['full_payment_status'] as String?,
      status: (row['status'] as String?) ?? AppointmentStatus.pendingPayment,
      confirmedAt: parseTs(row['confirmed_at']),
      completedAt: parseTs(row['completed_at']),
      cancelledAt: parseTs(row['cancelled_at']),
      cancelReason: row['cancel_reason'] as String?,
      cancelledBy: row['cancelled_by'] as String?,
      noShowAt: parseTs(row['no_show_at']),
      clientNotes: row['client_notes'] as String?,
      partnerNotes: row['partner_notes'] as String?,
      isWalkIn: (row['is_walk_in'] as bool?) ?? false,
      rescheduleCount: (row['reschedule_count'] as int?) ?? 0,
      originalScheduledAt: parseTs(row['original_scheduled_at']),
      lastRescheduledAt: parseTs(row['last_rescheduled_at']),
      createdAt: parseTs(row['created_at']) ?? DateTime.now(),
      providerName: providerName,
      providerPhotoUrl: providerPhotoUrl,
      serviceName: serviceName,
      staffName: staffName,
      providerCancellationPolicy: providerCancellationPolicy,
      providerPaymentMode: providerPaymentMode,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider_id': providerId,
        if (serviceId != null) 'service_id': serviceId,
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        if (staffId != null) 'staff_id': staffId,
        if (clientUserId != null) 'client_user_id': clientUserId,
        if (clientName != null) 'client_name': clientName,
        if (clientPhone != null) 'client_phone': clientPhone,
        'duration_minutes': durationMinutes,
        'service_price_cents': servicePriceCents,
        'deposit_cents': depositCents,
        'status': status,
      };

  /// .stream() do Supabase não suporta JOIN — preserva metadata do
  /// prestador/serviço/staff ao reconstruir a partir de um evento realtime.
  AppointmentModel copyWithJoinInfo({
    String? providerName,
    String? providerPhotoUrl,
    String? serviceName,
    String? staffName,
    String? providerCancellationPolicy,
    String? providerPaymentMode,
  }) =>
      AppointmentModel(
        id: id,
        providerId: providerId,
        serviceId: serviceId,
        scheduledAt: scheduledAt,
        staffId: staffId,
        clientUserId: clientUserId,
        clientName: clientName,
        clientPhone: clientPhone,
        durationMinutes: durationMinutes,
        servicePriceCents: servicePriceCents,
        depositCents: depositCents,
        depositPi: depositPi,
        depositStatus: depositStatus,
        fullPaymentMethod: fullPaymentMethod,
        fullPaymentStatus: fullPaymentStatus,
        status: status,
        confirmedAt: confirmedAt,
        completedAt: completedAt,
        cancelledAt: cancelledAt,
        cancelReason: cancelReason,
        cancelledBy: cancelledBy,
        noShowAt: noShowAt,
        clientNotes: clientNotes,
        partnerNotes: partnerNotes,
        isWalkIn: isWalkIn,
        rescheduleCount: rescheduleCount,
        originalScheduledAt: originalScheduledAt,
        lastRescheduledAt: lastRescheduledAt,
        createdAt: createdAt,
        providerName: providerName ?? this.providerName,
        providerPhotoUrl: providerPhotoUrl ?? this.providerPhotoUrl,
        serviceName: serviceName ?? this.serviceName,
        staffName: staffName ?? this.staffName,
        providerCancellationPolicy:
            providerCancellationPolicy ?? this.providerCancellationPolicy,
        providerPaymentMode: providerPaymentMode ?? this.providerPaymentMode,
      );

  // ─── Helpers de estado (consumidos por screens cliente) ───────────────────

  bool get isConfirmed => status == AppointmentStatus.confirmed;

  bool get isCompleted => status == AppointmentStatus.completed;

  bool get isNoShow => status == AppointmentStatus.noShow;

  bool get isCancelled =>
      status == AppointmentStatus.cancelled || cancelledAt != null;

  bool get isPendingPayment => status == AppointmentStatus.pendingPayment;

  bool get isUpcoming =>
      !isCancelled &&
      !isNoShow &&
      !isCompleted &&
      (isConfirmed || isPendingPayment) &&
      scheduledAt.isAfter(DateTime.now());

  bool get isPast =>
      !isCancelled &&
      (isCompleted || isNoShow || scheduledAt.isBefore(DateTime.now()));
}
