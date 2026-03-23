import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as latlng;

extension LatLngGoogleMapper on latlng.LatLng {
  gmaps.LatLng toGMaps() => gmaps.LatLng(latitude, longitude);
}

extension LatLngListGoogleMapper on List<latlng.LatLng> {
  List<gmaps.LatLng> toGMaps() => map((point) => point.toGMaps()).toList();
}

gmaps.LatLngBounds? toBounds({
  latlng.LatLng? a,
  latlng.LatLng? b,
}) {
  final pointA = a;
  final pointB = b;
  if (pointA == null && pointB == null) {
    return null;
  }
  if (pointA != null && pointB == null) {
    return gmaps.LatLngBounds(
      southwest: pointA.toGMaps(),
      northeast: pointA.toGMaps(),
    );
  }
  if (pointA == null && pointB != null) {
    return gmaps.LatLngBounds(
      southwest: pointB.toGMaps(),
      northeast: pointB.toGMaps(),
    );
  }

  final south = pointA!.latitude < pointB!.latitude ? pointA.latitude : pointB.latitude;
  final north = pointA.latitude > pointB.latitude ? pointA.latitude : pointB.latitude;
  final west = pointA.longitude < pointB.longitude ? pointA.longitude : pointB.longitude;
  final east = pointA.longitude > pointB.longitude ? pointA.longitude : pointB.longitude;

  return gmaps.LatLngBounds(
    southwest: gmaps.LatLng(south, west),
    northeast: gmaps.LatLng(north, east),
  );
}

/// Computes map bounds that enclose all provided [points].
gmaps.LatLngBounds? boundsFromPoints(Iterable<latlng.LatLng> points) {
  final iterator = points.iterator;
  if (!iterator.moveNext()) {
    return null;
  }

  var minLat = iterator.current.latitude;
  var maxLat = iterator.current.latitude;
  var minLng = iterator.current.longitude;
  var maxLng = iterator.current.longitude;

  while (iterator.moveNext()) {
    final point = iterator.current;
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLng) minLng = point.longitude;
    if (point.longitude > maxLng) maxLng = point.longitude;
  }

  return gmaps.LatLngBounds(
    southwest: gmaps.LatLng(minLat, minLng),
    northeast: gmaps.LatLng(maxLat, maxLng),
  );
}
