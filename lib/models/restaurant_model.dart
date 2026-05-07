import 'package:latlong2/latlong.dart';

enum BusinessCategory {
  restaurant,
  supermarket,
  store,
  pharmacy,
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
    this.isOnline = true,
    this.lat,
    this.lng,
    this.reservationsEnabled = false,
    this.businessHours = const BusinessHours(),
    this.avgRating,
    this.ratingsCount = 0,
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
  final bool isOnline;
  final double? lat;
  final double? lng;

  /// BR §14.10 — whether this restaurant accepts table reservations.
  /// Default false. Partner toggles it from the dashboard.
  final bool reservationsEnabled;

  final BusinessHours businessHours;

  /// BR §44 — média de avaliações (1.0-5.0) ou null se ainda sem ratings.
  final double? avgRating;

  /// BR §44 — número de avaliações públicas + não flagged que contam para a média.
  final int ratingsCount;

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
    BusinessHours? businessHours,
    double? avgRating,
    int? ratingsCount,
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
      isOnline: isOnline ?? this.isOnline,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
      businessHours: businessHours ?? this.businessHours,
      avgRating: avgRating ?? this.avgRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
    );
  }
}
