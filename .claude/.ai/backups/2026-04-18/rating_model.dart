class RatingModel {
  RatingModel({
    required this.orderId,
    required this.driverId,
    required this.rating,
    this.comment,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String orderId;
  final String driverId;
  final int rating;
  final String? comment;
  final DateTime timestamp;
}
