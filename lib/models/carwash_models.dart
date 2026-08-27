import 'package:flutter/foundation.dart';

/// LAVAGEM AUTO — modelos do cliente e do lavador.
/// Espelha o padrão de `cleaning_models.dart`. O preço NUNCA se calcula aqui:
/// vem sempre da RPC `carwash_quote` no servidor.

// ══════════════════════════════════════════════════════════════════════════
// SERVIÇO
// ══════════════════════════════════════════════════════════════════════════

enum CarwashServiceType { exterior, full, interior }

extension CarwashServiceTypeX on CarwashServiceType {
  String get wire => switch (this) {
        CarwashServiceType.exterior => 'exterior',
        CarwashServiceType.full => 'full',
        CarwashServiceType.interior => 'interior',
      };

  String get label => switch (this) {
        CarwashServiceType.exterior => 'Lavagem exterior',
        CarwashServiceType.full => 'Lavagem completa',
        CarwashServiceType.interior => 'Só interior',
      };

  /// Texto PT-PT tal como aparece ao cliente (Bloco B da ordem).
  String get description => switch (this) {
        CarwashServiceType.exterior =>
          'Lavagem do carro por fora, jantes e vidros. Vamos buscar o carro '
              'onde estiver e entregamos lavado. Recolha e entrega incluídas.',
        CarwashServiceType.full =>
          'Lavagem por fora e limpeza por dentro: aspiração completa, tapetes, '
              'e pano por todo o interior para tirar o pó. Vamos buscar o carro '
              'e entregamos lavado por dentro e por fora. Recolha e entrega incluídas.',
        CarwashServiceType.interior =>
          'Limpeza só por dentro: aspiração completa, tapetes e pano por todo '
              'o interior. Vamos buscar o carro e entregamos limpo por dentro. '
              'Recolha e entrega incluídas.',
      };

  static CarwashServiceType fromWire(String? s) => switch (s) {
        'full' => CarwashServiceType.full,
        'interior' => CarwashServiceType.interior,
        _ => CarwashServiceType.exterior,
      };
}

// ══════════════════════════════════════════════════════════════════════════
// ESTADOS
// ══════════════════════════════════════════════════════════════════════════

enum CarwashStatus {
  scheduled,
  accepted,
  onTheWay,
  pickedUp,
  inProgress,
  delivering,
  delivered,
  completed,
  cancelled,
}

extension CarwashStatusX on CarwashStatus {
  String get wire => switch (this) {
        CarwashStatus.scheduled => 'scheduled',
        CarwashStatus.accepted => 'accepted',
        CarwashStatus.onTheWay => 'on_the_way',
        CarwashStatus.pickedUp => 'picked_up',
        CarwashStatus.inProgress => 'in_progress',
        CarwashStatus.delivering => 'delivering',
        CarwashStatus.delivered => 'delivered',
        CarwashStatus.completed => 'completed',
        CarwashStatus.cancelled => 'cancelled_client',
      };

  /// Texto da barra de estados no ecrã do cliente (PT-PT).
  String get clientLabel => switch (this) {
        CarwashStatus.scheduled => 'À procura de lavador',
        CarwashStatus.accepted => 'Aceite',
        CarwashStatus.onTheWay => 'A caminho',
        CarwashStatus.pickedUp => 'Carro recolhido',
        CarwashStatus.inProgress => 'A lavar',
        CarwashStatus.delivering => 'A entregar',
        CarwashStatus.delivered => 'Entregue',
        CarwashStatus.completed => 'Concluído',
        CarwashStatus.cancelled => 'Cancelado',
      };

  bool get isActive => switch (this) {
        CarwashStatus.completed || CarwashStatus.cancelled => false,
        _ => true,
      };

  /// Posição na barra de progresso (0..6). -1 quando cancelado.
  int get step => switch (this) {
        CarwashStatus.scheduled => 0,
        CarwashStatus.accepted => 1,
        CarwashStatus.onTheWay => 2,
        CarwashStatus.pickedUp => 3,
        CarwashStatus.inProgress => 4,
        CarwashStatus.delivering => 5,
        CarwashStatus.delivered || CarwashStatus.completed => 6,
        CarwashStatus.cancelled => -1,
      };

  static CarwashStatus fromWire(String? s) => switch (s) {
        'accepted' => CarwashStatus.accepted,
        'on_the_way' => CarwashStatus.onTheWay,
        'picked_up' => CarwashStatus.pickedUp,
        'in_progress' => CarwashStatus.inProgress,
        'delivering' => CarwashStatus.delivering,
        'delivered' => CarwashStatus.delivered,
        'completed' => CarwashStatus.completed,
        'cancelled_client' => CarwashStatus.cancelled,
        _ => CarwashStatus.scheduled,
      };
}

/// Os 6 passos mostrados ao cliente, por ordem.
const kCarwashSteps = <String>[
  'À procura de lavador',
  'Aceite',
  'A caminho',
  'Carro recolhido',
  'A lavar',
  'A entregar',
  'Entregue',
];

// ══════════════════════════════════════════════════════════════════════════
// FOTOS
// ══════════════════════════════════════════════════════════════════════════

/// Os 4 ângulos obrigatórios na recolha. As chaves têm de bater CERTO com o
/// que a RPC `carwash_mark_picked_up` valida no servidor.
enum CarwashAngle { frente, tras, esquerda, direita }

extension CarwashAngleX on CarwashAngle {
  String get wire => name; // frente | tras | esquerda | direita

  String get label => switch (this) {
        CarwashAngle.frente => 'Frente',
        CarwashAngle.tras => 'Trás',
        CarwashAngle.esquerda => 'Lateral esquerda',
        CarwashAngle.direita => 'Lateral direita',
      };

  String get hint => switch (this) {
        CarwashAngle.frente => 'Aponte à frente do carro',
        CarwashAngle.tras => 'Aponte à traseira do carro',
        CarwashAngle.esquerda => 'Aponte à lateral esquerda',
        CarwashAngle.direita => 'Aponte à lateral direita',
      };
}

@immutable
class CarwashPhoto {
  final String angle; // '' para fotos livres (cliente / depois)
  final String url; // path no bucket privado carwash-photos

  const CarwashPhoto({required this.angle, required this.url});

  Map<String, dynamic> toJson() => {'angle': angle, 'url': url};

  factory CarwashPhoto.fromJson(Map<String, dynamic> j) => CarwashPhoto(
        angle: (j['angle'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
      );

  static List<CarwashPhoto> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => CarwashPhoto.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.url.isNotEmpty)
        .toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ORÇAMENTO
// ══════════════════════════════════════════════════════════════════════════

@immutable
class CarwashQuote {
  final CarwashServiceType serviceType;
  final int totalCents;
  final int washerEarningsCents;
  final int boraFeeCents;
  final int durationMin;

  const CarwashQuote({
    required this.serviceType,
    required this.totalCents,
    required this.washerEarningsCents,
    required this.boraFeeCents,
    required this.durationMin,
  });

  double get totalEur => totalCents / 100.0;

  factory CarwashQuote.fromJson(Map<String, dynamic> j) => CarwashQuote(
        serviceType: CarwashServiceTypeX.fromWire(j['service_type'] as String?),
        totalCents: (j['total_cents'] as num?)?.toInt() ?? 0,
        washerEarningsCents: (j['washer_earnings_cents'] as num?)?.toInt() ?? 0,
        boraFeeCents: (j['bora_fee_cents'] as num?)?.toInt() ?? 0,
        durationMin: (j['duration_min'] as num?)?.toInt() ?? 60,
      );
}

// ══════════════════════════════════════════════════════════════════════════
// PEDIDO
// ══════════════════════════════════════════════════════════════════════════

@immutable
class CarwashBooking {
  final String id;
  final String clientUserId;
  final String? washerId;
  final CarwashServiceType serviceType;
  final CarwashStatus status;

  final String plate;
  final String carMakeModel;
  final String carColor;
  final String pickupNotes;
  final String clientPhone;

  final String whenMode; // now | later
  final DateTime scheduledAt;
  final int durationMin;
  final int? etaMinutes;
  final DateTime? etaAt;

  final String addressStreet;
  final String addressCity;
  final String addressPostal;
  final double? lat;
  final double? lng;
  final String notes;

  final String paymentMethod;
  final String paymentStatus;
  final int totalCents;
  final int washerEarningsCents;
  final int boraFeeCents;

  final List<CarwashPhoto> photosClient;
  final List<CarwashPhoto> photosBefore;
  final List<CarwashPhoto> photosAfter;

  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  final int? rating;

  const CarwashBooking({
    required this.id,
    required this.clientUserId,
    required this.washerId,
    required this.serviceType,
    required this.status,
    required this.plate,
    required this.carMakeModel,
    required this.carColor,
    required this.pickupNotes,
    required this.clientPhone,
    required this.whenMode,
    required this.scheduledAt,
    required this.durationMin,
    required this.etaMinutes,
    required this.etaAt,
    required this.addressStreet,
    required this.addressCity,
    required this.addressPostal,
    required this.lat,
    required this.lng,
    required this.notes,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalCents,
    required this.washerEarningsCents,
    required this.boraFeeCents,
    required this.photosClient,
    required this.photosBefore,
    required this.photosAfter,
    required this.acceptedAt,
    required this.pickedUpAt,
    required this.deliveredAt,
    required this.createdAt,
    required this.rating,
  });

  double get totalEur => totalCents / 100.0;
  double get washerEarningsEur => washerEarningsCents / 100.0;

  /// Morada para mostrar. O autocomplete já devolve a cidade dentro da rua
  /// ("Rua do Torreão 14, Guarda, Portugal"), por isso juntar a cidade outra
  /// vez dava "…, Guarda, Portugal, Guarda". Só se junta quando falta mesmo.
  String get addressLine {
    final rua = addressStreet.trim();
    final cidade = addressCity.trim();
    if (rua.isEmpty) return cidade;
    if (cidade.isEmpty) return rua;
    final jaTemCidade =
        rua.toLowerCase().contains(cidade.toLowerCase());
    return jaTemCidade ? rua : '$rua, $cidade';
  }

  /// "Chega daqui a ~X min" — só faz sentido enquanto vem a caminho.
  bool get showsEta =>
      etaMinutes != null &&
      (status == CarwashStatus.accepted || status == CarwashStatus.onTheWay);

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory CarwashBooking.fromSupabase(Map<String, dynamic> m) => CarwashBooking(
        id: m['id'].toString(),
        clientUserId: (m['client_user_id'] ?? '').toString(),
        washerId: m['washer_id']?.toString(),
        serviceType: CarwashServiceTypeX.fromWire(m['service_type'] as String?),
        status: CarwashStatusX.fromWire(m['status'] as String?),
        plate: (m['plate'] ?? '').toString(),
        carMakeModel: (m['car_make_model'] ?? '').toString(),
        carColor: (m['car_color'] ?? '').toString(),
        pickupNotes: (m['pickup_notes'] ?? '').toString(),
        clientPhone: (m['client_phone'] ?? '').toString(),
        whenMode: (m['when_mode'] ?? 'now').toString(),
        scheduledAt: _dt(m['scheduled_at']) ?? DateTime.now(),
        durationMin: (m['duration_min'] as num?)?.toInt() ?? 60,
        etaMinutes: (m['eta_minutes'] as num?)?.toInt(),
        etaAt: _dt(m['eta_at']),
        addressStreet: (m['address_street'] ?? '').toString(),
        addressCity: (m['address_city'] ?? '').toString(),
        addressPostal: (m['address_postal'] ?? '').toString(),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        notes: (m['notes'] ?? '').toString(),
        paymentMethod: (m['payment_method'] ?? 'cash').toString(),
        paymentStatus: (m['payment_status'] ?? 'unpaid').toString(),
        totalCents: (m['total_cents'] as num?)?.toInt() ?? 0,
        washerEarningsCents: (m['washer_earnings_cents'] as num?)?.toInt() ?? 0,
        boraFeeCents: (m['bora_fee_cents'] as num?)?.toInt() ?? 0,
        photosClient: CarwashPhoto.listFrom(m['photos_client']),
        photosBefore: CarwashPhoto.listFrom(m['photos_before']),
        photosAfter: CarwashPhoto.listFrom(m['photos_after']),
        acceptedAt: _dt(m['accepted_at']),
        pickedUpAt: _dt(m['picked_up_at']),
        deliveredAt: _dt(m['delivered_at']),
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        rating: (m['rating'] as num?)?.toInt(),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// LAVADOR
// ══════════════════════════════════════════════════════════════════════════

@immutable
class WasherProfile {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String photoUrl;
  final double? baseLat;
  final double? baseLng;
  final double serviceRadiusKm;
  final String approvalStatus;
  final bool isActive;
  final bool isBanned;
  final double ratingAvg;
  final int washesDone;

  const WasherProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    required this.photoUrl,
    required this.baseLat,
    required this.baseLng,
    required this.serviceRadiusKm,
    required this.approvalStatus,
    required this.isActive,
    required this.isBanned,
    required this.ratingAvg,
    required this.washesDone,
  });

  bool get isApproved => approvalStatus == 'approved' && isActive && !isBanned;

  factory WasherProfile.fromSupabase(Map<String, dynamic> m) => WasherProfile(
        id: m['id'].toString(),
        userId: (m['user_id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        photoUrl: (m['photo_url'] ?? '').toString(),
        baseLat: (m['base_lat'] as num?)?.toDouble(),
        baseLng: (m['base_lng'] as num?)?.toDouble(),
        serviceRadiusKm: (m['service_radius_km'] as num?)?.toDouble() ?? 8,
        approvalStatus: (m['approval_status'] ?? 'pending').toString(),
        isActive: m['is_active'] == true,
        isBanned: m['is_banned'] == true,
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        washesDone: (m['washes_done'] as num?)?.toInt() ?? 0,
      );
}
