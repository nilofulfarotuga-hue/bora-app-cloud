import 'package:latlong2/latlong.dart';

class PostalCoordinateHelper {
  const PostalCoordinateHelper._();

  static final Map<String, LatLng> _coordinates = {
    "1050-116": const LatLng(38.7255, -9.1465),
    "1050-020": const LatLng(38.7364, -9.1532),
    "1900-263": const LatLng(38.7239, -9.1178),
    "1100-053": const LatLng(38.7095, -9.1366),
    "1200-360": const LatLng(38.7090, -9.1411),
    "2720-056": const LatLng(38.7601, -9.1821),
    "2800-305": const LatLng(38.7067, -9.1527),
  };

  static LatLng coordinateFor(String postalCode) {
    final cleaned = postalCode.trim();
    return _coordinates[cleaned] ?? const LatLng(38.7223, -9.1393);
  }
}
