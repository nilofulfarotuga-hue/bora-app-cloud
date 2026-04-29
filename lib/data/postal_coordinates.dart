import 'package:latlong2/latlong.dart';

class PostalCoordinateHelper {
  const PostalCoordinateHelper._();

  static final Map<String, LatLng> _coordinates = {
    // Guarda — área operacional principal Bora App.
    "6300": const LatLng(40.5378, -7.2683),
    // Lisboa — legacy / testes.
    "1050-116": const LatLng(38.7255, -9.1465),
    "1050-020": const LatLng(38.7364, -9.1532),
    "1900-263": const LatLng(38.7239, -9.1178),
    "1100-053": const LatLng(38.7095, -9.1366),
    "1200-360": const LatLng(38.7090, -9.1411),
    "2720-056": const LatLng(38.7601, -9.1821),
    "2800-305": const LatLng(38.7067, -9.1527),
  };

  /// Match exacto primeiro; se falhar, tenta prefixo de 4 dígitos
  /// (ex.: "6300-535" → "6300"). Permite cobrir toda a Guarda
  /// com um único entry sem listar 200+ sub-códigos.
  static LatLng? coordinateFor(String postalCode) {
    final cleaned = postalCode.trim();
    final exact = _coordinates[cleaned];
    if (exact != null) return exact;
    if (cleaned.length >= 4) {
      return _coordinates[cleaned.substring(0, 4)];
    }
    return null;
  }
}
