import 'package:latlong2/latlong.dart';

enum BusinessCategory {
  restaurant,
  supermarket,
  store,
  pharmacy,
  beauty,
}

extension BusinessCategoryLabel on BusinessCategory {
  String get label {
    switch (this) {
      case BusinessCategory.restaurant:
        return 'Restaurante';
      case BusinessCategory.supermarket:
        return 'Supermercado';
      case BusinessCategory.store:
        return 'Loja';
      case BusinessCategory.pharmacy:
        return 'Farmácia';
      case BusinessCategory.beauty:
        return 'Beleza';
    }
  }
}

class DayHours {
  const DayHours({
    this.open = '09:00',
    this.close = '22:00',
    this.closed = false,
  });

  final String open;
  final String close;
  final bool closed;

  factory DayHours.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DayHours();
    return DayHours(
      open: (json['open'] as String?) ?? '09:00',
      close: (json['close'] as String?) ?? '22:00',
      closed: (json['closed'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() =>
      {'open': open, 'close': close, 'closed': closed};

  DayHours copyWith({String? open, String? close, bool? closed}) => DayHours(
        open: open ?? this.open,
        close: close ?? this.close,
        closed: closed ?? this.closed,
      );
}

class BusinessHours {
  const BusinessHours({
    this.mon = const DayHours(),
    this.tue = const DayHours(),
    this.wed = const DayHours(),
    this.thu = const DayHours(),
    this.fri = const DayHours(),
    this.sat = const DayHours(),
    this.sun = const DayHours(),
  });

  final DayHours mon;
  final DayHours tue;
  final DayHours wed;
  final DayHours thu;
  final DayHours fri;
  final DayHours sat;
  final DayHours sun;

  static const _defaultKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  factory BusinessHours.fromJson(dynamic raw) {
    if (raw is! Map) return const BusinessHours();
    final m = Map<String, dynamic>.from(raw);
    return BusinessHours(
      mon: DayHours.fromJson(m['mon'] as Map<String, dynamic>?),
      tue: DayHours.fromJson(m['tue'] as Map<String, dynamic>?),
      wed: DayHours.fromJson(m['wed'] as Map<String, dynamic>?),
      thu: DayHours.fromJson(m['thu'] as Map<String, dynamic>?),
      fri: DayHours.fromJson(m['fri'] as Map<String, dynamic>?),
      sat: DayHours.fromJson(m['sat'] as Map<String, dynamic>?),
      sun: DayHours.fromJson(m['sun'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
        'mon': mon.toJson(),
        'tue': tue.toJson(),
        'wed': wed.toJson(),
        'thu': thu.toJson(),
        'fri': fri.toJson(),
        'sat': sat.toJson(),
        'sun': sun.toJson(),
      };

  DayHours dayFor(int weekday) {
    // DateTime.weekday: Mon=1 .. Sun=7
    switch (weekday) {
      case DateTime.monday:
        return mon;
      case DateTime.tuesday:
        return tue;
      case DateTime.wednesday:
        return wed;
      case DateTime.thursday:
        return thu;
      case DateTime.friday:
        return fri;
      case DateTime.saturday:
        return sat;
      case DateTime.sunday:
        return sun;
    }
    return const DayHours();
  }

  BusinessHours copyWithDay(int weekday, DayHours hours) {
    return BusinessHours(
      mon: weekday == DateTime.monday ? hours : mon,
      tue: weekday == DateTime.tuesday ? hours : tue,
      wed: weekday == DateTime.wednesday ? hours : wed,
      thu: weekday == DateTime.thursday ? hours : thu,
      fri: weekday == DateTime.friday ? hours : fri,
      sat: weekday == DateTime.saturday ? hours : sat,
      sun: weekday == DateTime.sunday ? hours : sun,
    );
  }

  static String keyForWeekday(int weekday) {
    final i = (weekday - 1).clamp(0, 6);
    return _defaultKeys[i];
  }
}

class RestaurantModel {
  const RestaurantModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    required this.photoUrl,
    required this.cuisineType,
    required this.isPartner,
    required this.category,
    this.extraCategories = const <BusinessCategory>{},
    this.isOnline = true,
    this.lat,
    this.lng,
    this.reservationsEnabled = false,
    this.takeawayEnabled = false,
    this.curbsideEnabled = false,
    this.takeawayDefaultPrepMinutes = 15,
    this.businessHours = const BusinessHours(),
    this.avgRating,
    this.ratingsCount = 0,
    this.heroImageUrl,
    this.comingSoon = false,
    this.comingSoonText,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String photoUrl;
  final String cuisineType;
  final bool isPartner;
  final BusinessCategory category;

  /// Secções adicionais onde o negócio também aparece (coluna
  /// `restaurants.extra_categories`). A loja é sempre a MESMA (mesmo id, mesmo
  /// catálogo) — só passa a ser listada em mais do que uma secção do cliente.
  final Set<BusinessCategory> extraCategories;

  final bool isOnline;
  final double? lat;
  final double? lng;

  /// BR §14.10 — whether this restaurant accepts table reservations.
  /// Default false. Partner toggles it from the dashboard.
  final bool reservationsEnabled;

  /// BR §14.9 — restaurante aceita pedidos takeaway (cliente levanta no balcão).
  /// Default false. Partner toggles no dashboard.
  final bool takeawayEnabled;

  /// BR §14.9b — restaurante suporta curbside (cliente espera no carro).
  /// Default false. Só efectivo se takeawayEnabled=true.
  final bool curbsideEnabled;

  /// BR §14.9c — ETA default em minutos quando parceiro aceita o pedido sem
  /// escolher manualmente (3/5/10/15/20/30/45/60). Default 15.
  final int takeawayDefaultPrepMinutes;

  final BusinessHours businessHours;

  /// BR §44 — média de avaliações (1.0-5.0) ou null se ainda sem ratings.
  final double? avgRating;

  /// BR §44 — número de avaliações públicas + não flagged que contam para a média.
  final int ratingsCount;

  /// URL da imagem hero (banner largo) do mercado/restaurante.
  /// Gerida via admin → bucket restaurant-assets/hero/<id>.<ext>.
  /// Null quando ainda não configurada — UI usa fallback em cascata.
  final String? heroImageUrl;

  /// `restaurants.coming_soon` — a loja aparece no catálogo com selo "Em breve"
  /// e é totalmente navegável, mas NÃO aceita pedidos. O bloqueio real vive no
  /// servidor (erro `STORE_COMING_SOON`); isto é só a camada de UI.
  final bool comingSoon;

  /// `restaurants.coming_soon_text` — texto do banner na ficha da loja.
  /// Null/vazio → usar [comingSoonLabel].
  final String? comingSoonText;

  /// Texto a mostrar no banner "Em breve" (com fallback).
  String get comingSoonLabel {
    final t = comingSoonText?.trim();
    return (t == null || t.isEmpty) ? 'Em breve' : t;
  }

  /// True quando o negócio pertence à secção [section] — pela sua categoria
  /// principal OU por [extraCategories].
  bool belongsTo(BusinessCategory section) =>
      category == section || extraCategories.contains(section);

  /// Converte o array `extra_categories` do Supabase em categorias válidas
  /// (valores desconhecidos são ignorados; a categoria principal nunca duplica).
  static Set<BusinessCategory> parseExtraCategories(
    dynamic raw,
    BusinessCategory mainCategory,
  ) {
    if (raw is! List) return const <BusinessCategory>{};
    final result = <BusinessCategory>{};
    for (final item in raw) {
      final name = item?.toString().trim();
      if (name == null || name.isEmpty) continue;
      for (final value in BusinessCategory.values) {
        if (value.name == name && value != mainCategory) result.add(value);
      }
    }
    return result;
  }

  /// Returns a [LatLng] when both coordinates are stored; null otherwise.
  LatLng? get location =>
      (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  /// True when the partner is online AND current time is within today's window.
  bool isOpenNow([DateTime? nowOverride]) {
    if (!isOnline) return false;
    final now = nowOverride ?? DateTime.now();
    final day = businessHours.dayFor(now.weekday);
    if (day.closed) return false;
    final openMin = _parseMinutes(day.open);
    final closeMin = _parseMinutes(day.close);
    final nowMin = now.hour * 60 + now.minute;
    if (openMin == null || closeMin == null) return true;
    if (closeMin <= openMin) {
      // Overnight schedule (e.g. 20:00 → 02:00): open window spans midnight.
      return nowMin >= openMin || nowMin < closeMin;
    }
    return nowMin >= openMin && nowMin < closeMin;
  }

  /// Human-readable label for the client UI.
  String statusLabel([DateTime? nowOverride]) {
    if (!isOnline) return 'Indisponível';
    final now = nowOverride ?? DateTime.now();
    final day = businessHours.dayFor(now.weekday);
    if (day.closed) return 'Fechado hoje';
    if (isOpenNow(now)) return 'Aberto';
    return 'Fechado · abre às ${day.open}';
  }

  static int? _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  RestaurantModel copyWith({
    bool? isOnline,
    double? lat,
    double? lng,
    bool? reservationsEnabled,
    bool? takeawayEnabled,
    bool? curbsideEnabled,
    int? takeawayDefaultPrepMinutes,
    BusinessHours? businessHours,
    double? avgRating,
    int? ratingsCount,
    String? heroImageUrl,
    bool? comingSoon,
    String? comingSoonText,
  }) {
    return RestaurantModel(
      id: id,
      name: name,
      phone: phone,
      address: address,
      email: email,
      photoUrl: photoUrl,
      cuisineType: cuisineType,
      isPartner: isPartner,
      category: category,
      extraCategories: extraCategories,
      isOnline: isOnline ?? this.isOnline,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
      takeawayEnabled: takeawayEnabled ?? this.takeawayEnabled,
      curbsideEnabled: curbsideEnabled ?? this.curbsideEnabled,
      takeawayDefaultPrepMinutes:
          takeawayDefaultPrepMinutes ?? this.takeawayDefaultPrepMinutes,
      businessHours: businessHours ?? this.businessHours,
      avgRating: avgRating ?? this.avgRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      comingSoon: comingSoon ?? this.comingSoon,
      comingSoonText: comingSoonText ?? this.comingSoonText,
    );
  }
}
