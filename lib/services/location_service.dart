import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {

  static Future<LatLng> getCurrentLocation() async {

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception("Location services disabled");
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return LatLng(
      position.latitude,
      position.longitude,
    );
  }
}