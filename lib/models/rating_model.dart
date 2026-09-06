/// Subject of a rating (BR §13.1).
/// T2.1: 'partner' added to support cliente avaliando o parceiro (vendor).
enum RatingSubjectType { driver, client, restaurant, partner }

extension RatingSubjectTypeName on RatingSubjectType {
  String get dbName => name; // driver | client | restaurant | partner
}

/// A rating record (BR §13).
///
/// Backwards-compatible: the original fields (orderId, driverId, rating, comment,
/// timestamp) stay. New optional fields add support for:
///   • tags quick-select (BR §13.2)
///   • private ratings (driver→client, BR §13.3)
///   • polymorphic subject (driver | client | restaurant, BR §13.1)
class RatingModel {
  RatingModel({
    required this.orderId,
    required this.driverId,
    required this.rating,
    this.comment,
    DateTime? timestamp,
    this.tags = const <String>[],
    this.isPrivate = false,
    this.subjectType = RatingSubjectType.driver,
    this.subjectId,
    this.raterUserId,
  }) : timestamp = timestamp ?? DateTime.now();

  final String orderId;
  final String driverId;
  final int rating;
  final String? comment;
  final DateTime timestamp;

  // BR §13 additions
  final List<String> tags;
  final bool isPrivate;
  final RatingSubjectType subjectType;
  final String? subjectId;
  final String? raterUserId;

  Map<String, dynamic> toSupabase() => {
        'order_id': orderId,
        'driver_id': driverId,
        'rating': rating,
        'stars': rating,
        if (comment != null) 'comment': comment,
        'tags': tags,
        'is_private': isPrivate,
        'subject_type': subjectType.dbName,
        if (subjectId != null) 'subject_id': subjectId,
        if (raterUserId != null) 'rater_user_id': raterUserId,
      };
}

/// Predefined quick-tags for the rating UI (BR §13.2).
class RatingTags {
  static const List<String> positive = [
    'Simpático',
    'Rápido',
    'Limpo',
    'Profissional',
    'Cuidadoso',
  ];

  static const List<String> negative = [
    'Atrasado',
    'Desarrumado',
    'Mal educado',
    'Denúncia',
  ];
}
