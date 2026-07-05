// LIMPEZA — modelos da vertical de limpeza doméstica (2026-07-05).
// Model → Store → Screen. Todos os valores monetários em cents (int),
// calculados SEMPRE server-side (RPC cleaning_quote / create_cleaning_booking).

/// Estado da reserva de limpeza (espelha o CHECK de cleaning_bookings.status).
enum CleaningStatus {
  scheduled,
  accepted,
  onTheWay,
  inProgress,
  done,
  completed,
  cancelledClient,
  cancelledCleaner;

  static CleaningStatus fromDb(String? raw) {
    switch (raw) {
      case 'accepted':
        return CleaningStatus.accepted;
      case 'on_the_way':
        return CleaningStatus.onTheWay;
      case 'in_progress':
        return CleaningStatus.inProgress;
      case 'done':
        return CleaningStatus.done;
      case 'completed':
        return CleaningStatus.completed;
      case 'cancelled_client':
        return CleaningStatus.cancelledClient;
      case 'cancelled_cleaner':
        return CleaningStatus.cancelledCleaner;
      default:
        return CleaningStatus.scheduled;
    }
  }

  String get labelPt {
    switch (this) {
      case CleaningStatus.scheduled:
        return 'Agendada';
      case CleaningStatus.accepted:
        return 'Confirmada';
      case CleaningStatus.onTheWay:
        return 'A caminho';
      case CleaningStatus.inProgress:
        return 'Em curso';
      case CleaningStatus.done:
        return 'Concluída — confirma';
      case CleaningStatus.completed:
        return 'Concluída';
      case CleaningStatus.cancelledClient:
        return 'Cancelada';
      case CleaningStatus.cancelledCleaner:
        return 'Cancelada pela profissional';
    }
  }

  bool get isCancelled =>
      this == CleaningStatus.cancelledClient ||
      this == CleaningStatus.cancelledCleaner;

  bool get isActive => !isCancelled && this != CleaningStatus.completed;
}

/// Labels PT-PT partilhadas pelo wizard e pelos ecrãs de acompanhamento.
class CleaningLabels {
  static const types = {
    'standard': 'Standard',
    'deep': 'Profunda',
    'post_works': 'Pós-obras',
  };
  static const sizes = {
    't0_t1': 'T0/T1',
    't2': 'T2',
    't3': 'T3',
    't4plus': 'T4+',
  };
  static const recurrences = {
    'single': 'Única',
    'weekly': 'Semanal',
    'biweekly': 'Quinzenal',
  };

  static String euro(int cents) =>
      '€${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
}

/// Reserva de limpeza (linha de cleaning_bookings).
class CleaningBooking {
  final String id;
  final String clientUserId;
  final String? cleanerId;
  final String? recurrenceGroupId;
  final String recurrence;
  final String cleaningType;
  final String pricingMode;
  final String? homeSize;
  final int? hours;
  final DateTime scheduledAt;
  final int durationMin;
  final String addressStreet;
  final String addressCity;
  final String addressPostal;
  final String notes;
  final String productsBy;
  final CleaningStatus status;
  final String paymentMethod;
  final String paymentStatus;
  final int baseCents;
  final int typeSurchargeCents;
  final int recurringDiscountCents;
  final int productsFeeCents;
  final int totalCents;
  final int cleanerEarningsCents;
  final int boraFeeCents;
  final int cancelFeeCents;
  final String? cancelReason;
  final String? cancelledBy;
  final String? offerCleanerId;
  final DateTime? offerExpiresAt;
  final DateTime? doneAt;
  final DateTime? completedAt;

  const CleaningBooking({
    required this.id,
    required this.clientUserId,
    this.cleanerId,
    this.recurrenceGroupId,
    required this.recurrence,
    required this.cleaningType,
    required this.pricingMode,
    this.homeSize,
    this.hours,
    required this.scheduledAt,
    required this.durationMin,
    required this.addressStreet,
    required this.addressCity,
    required this.addressPostal,
    required this.notes,
    required this.productsBy,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.baseCents,
    required this.typeSurchargeCents,
    required this.recurringDiscountCents,
    required this.productsFeeCents,
    required this.totalCents,
    required this.cleanerEarningsCents,
    required this.boraFeeCents,
    required this.cancelFeeCents,
    this.cancelReason,
    this.cancelledBy,
    this.offerCleanerId,
    this.offerExpiresAt,
    this.doneAt,
    this.completedAt,
  });

  factory CleaningBooking.fromSupabase(Map<String, dynamic> m) {
    DateTime? ts(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    return CleaningBooking(
      id: m['id'] as String,
      clientUserId: m['client_user_id'] as String? ?? '',
      cleanerId: m['cleaner_id'] as String?,
      recurrenceGroupId: m['recurrence_group_id'] as String?,
      recurrence: m['recurrence'] as String? ?? 'single',
      cleaningType: m['cleaning_type'] as String? ?? 'standard',
      pricingMode: m['pricing_mode'] as String? ?? 'fixed',
      homeSize: m['home_size'] as String?,
      hours: (m['hours'] as num?)?.toInt(),
      scheduledAt: ts(m['scheduled_at']) ?? DateTime.now(),
      durationMin: i(m['duration_min']),
      addressStreet: m['address_street'] as String? ?? '',
      addressCity: m['address_city'] as String? ?? '',
      addressPostal: m['address_postal'] as String? ?? '',
      notes: m['notes'] as String? ?? '',
      productsBy: m['products_by'] as String? ?? 'client',
      status: CleaningStatus.fromDb(m['status'] as String?),
      paymentMethod: m['payment_method'] as String? ?? 'cash',
      paymentStatus: m['payment_status'] as String? ?? 'unpaid',
      baseCents: i(m['base_cents']),
      typeSurchargeCents: i(m['type_surcharge_cents']),
      recurringDiscountCents: i(m['recurring_discount_cents']),
      productsFeeCents: i(m['products_fee_cents']),
      totalCents: i(m['total_cents']),
      cleanerEarningsCents: i(m['cleaner_earnings_cents']),
      boraFeeCents: i(m['bora_fee_cents']),
      cancelFeeCents: i(m['cancel_fee_cents']),
      cancelReason: m['cancel_reason'] as String?,
      cancelledBy: m['cancelled_by'] as String?,
      offerCleanerId: m['offer_cleaner_id'] as String?,
      offerExpiresAt: ts(m['offer_expires_at']),
      doneAt: ts(m['done_at']),
      completedAt: ts(m['completed_at']),
    );
  }

  String get typeLabel => CleaningLabels.types[cleaningType] ?? cleaningType;
  String get sizeLabel => pricingMode == 'hourly'
      ? '${hours ?? 0}h à hora'
      : (CleaningLabels.sizes[homeSize] ?? '');
  String get recurrenceLabel =>
      CleaningLabels.recurrences[recurrence] ?? recurrence;
  bool get isRecurring => recurrence != 'single';
}

/// Orçamento devolvido pela RPC cleaning_quote (preço live no wizard).
class CleaningQuote {
  final int baseCents;
  final int typeSurchargeCents;
  final int recurringDiscountCents;
  final int productsFeeCents;
  final int totalCents;
  final int durationMin;

  const CleaningQuote({
    required this.baseCents,
    required this.typeSurchargeCents,
    required this.recurringDiscountCents,
    required this.productsFeeCents,
    required this.totalCents,
    required this.durationMin,
  });

  factory CleaningQuote.fromJson(Map<String, dynamic> m) => CleaningQuote(
        baseCents: (m['base_cents'] as num?)?.toInt() ?? 0,
        typeSurchargeCents: (m['type_surcharge_cents'] as num?)?.toInt() ?? 0,
        recurringDiscountCents:
            (m['recurring_discount_cents'] as num?)?.toInt() ?? 0,
        productsFeeCents: (m['products_fee_cents'] as num?)?.toInt() ?? 0,
        totalCents: (m['total_cents'] as num?)?.toInt() ?? 0,
        durationMin: (m['duration_min'] as num?)?.toInt() ?? 180,
      );
}

/// Perfil público de profissional disponível (Passo 3 do wizard).
class AvailableCleaner {
  final String id;
  final String name;
  final String photoUrl;
  final String bio;
  final double ratingAvg;
  final int ratingsCount;
  final int cleaningsDone;
  final bool isFavorite;

  const AvailableCleaner({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.bio,
    required this.ratingAvg,
    required this.ratingsCount,
    required this.cleaningsDone,
    required this.isFavorite,
  });

  factory AvailableCleaner.fromJson(Map<String, dynamic> m) => AvailableCleaner(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        photoUrl: m['photo_url'] as String? ?? '',
        bio: m['bio'] as String? ?? '',
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingsCount: (m['ratings_count'] as num?)?.toInt() ?? 0,
        cleaningsDone: (m['cleanings_done'] as num?)?.toInt() ?? 0,
        isFavorite: m['is_favorite'] == true,
      );
}

/// Registo da própria profissional (linha de cleaners — app da profissional).
class CleanerProfile {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String bio;
  final String photoUrl;
  final String approvalStatus; // pending | approved | rejected | suspended
  final bool isActive;
  final double serviceRadiusKm;
  final String baseAddress;
  final double? baseLat;
  final double? baseLng;
  final double ratingAvg;
  final int ratingsCount;
  final int cleaningsDone;
  final String? rejectionReason;

  const CleanerProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    required this.bio,
    required this.photoUrl,
    required this.approvalStatus,
    required this.isActive,
    required this.serviceRadiusKm,
    required this.baseAddress,
    this.baseLat,
    this.baseLng,
    required this.ratingAvg,
    required this.ratingsCount,
    required this.cleaningsDone,
    this.rejectionReason,
  });

  factory CleanerProfile.fromSupabase(Map<String, dynamic> m) => CleanerProfile(
        id: m['id'] as String,
        userId: m['user_id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        bio: m['bio'] as String? ?? '',
        photoUrl: m['photo_url'] as String? ?? '',
        approvalStatus: m['approval_status'] as String? ?? 'pending',
        isActive: m['is_active'] == true,
        serviceRadiusKm: (m['service_radius_km'] as num?)?.toDouble() ?? 10,
        baseAddress: m['base_address'] as String? ?? '',
        baseLat: (m['base_lat'] as num?)?.toDouble(),
        baseLng: (m['base_lng'] as num?)?.toDouble(),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingsCount: (m['ratings_count'] as num?)?.toInt() ?? 0,
        cleaningsDone: (m['cleanings_done'] as num?)?.toInt() ?? 0,
        rejectionReason: m['rejection_reason'] as String?,
      );

  bool get isApproved => approvalStatus == 'approved';
}

/// Janela de disponibilidade semanal da profissional.
class CleanerSlot {
  final int weekday; // 0=domingo … 6=sábado
  final String start; // 'HH:mm'
  final String end;

  const CleanerSlot(
      {required this.weekday, required this.start, required this.end});

  Map<String, dynamic> toJson() =>
      {'weekday': weekday, 'start': start, 'end': end};

  factory CleanerSlot.fromSupabase(Map<String, dynamic> m) => CleanerSlot(
        weekday: (m['weekday'] as num).toInt(),
        start: (m['start_time'] as String).substring(0, 5),
        end: (m['end_time'] as String).substring(0, 5),
      );

  static const weekdaysPt = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
}
