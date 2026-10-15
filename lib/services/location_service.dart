import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationService {
  static bool _consentGranted = true;

  /// Whether [getCurrentLocation] returned null specifically because the user
  /// has not granted location consent in the GDPR banner.
  /// Use this at call sites to show a targeted SnackBar instead of a generic
  /// error message.
  static bool get isConsentBlocked => !_consentGranted;

  /// Called by [ConsentStore] whenever the user saves their GDPR preferences.
  static void applyLocationConsent(bool allowed) {
    _consentGranted = allowed;
    debugPrint('LocationService: consent = $allowed');
  }

  /// Returns the device's current GPS location, or null when unavailable.
  ///
  /// Handles all permission states including [LocationPermission.deniedForever].
  /// Never throws — returns null on any failure.
  /// Returns null immediately (without requesting OS permission) when the user
  /// has rejected location consent in the GDPR banner.
  static Future<LatLng?> getCurrentLocation() async {
    if (!_consentGranted) {
      debugPrint('LocationService: location consent not granted — returning null');
      return null;
    }
    // On web, isLocationServiceEnabled() always returns true; skip the check.
    // [14/10/2026] Com limite: PADRAO_BORA 1.26 — nenhum `await` sobre
    // hardware/permissões sem `.timeout`, cada um é um ecrã que pode prender.
    if (!kIsWeb) {
      bool serviceEnabled;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('LocationService: service check failed => $e');
        return null;
      }
      if (!serviceEnabled) {
        debugPrint('LocationService: location services disabled');
        return null;
      }
    }

    // CICATRIZ (varredura, corrida 91, 2026-09-10): a promessa deste metodo
    // e' "nunca lanca", mas o pedido de permissao estava fora do try. Quando
    // dois ecras pedem localizacao ao mesmo tempo -- o acompanhamento do
    // pedido abre sozinho e, logo a seguir, o pedido de boleia detecta a
    // recolha -- o geolocator lanca PermissionRequestInProgressException e
    // ninguem a apanhava: erro assincrono por tratar, e a recolha ficava por
    // detectar em silencio. Aqui e' "sem localizacao agora", como qualquer
    // outra falha deste metodo.
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5));
      if (permission == LocationPermission.denied) {
        // 30 s para a pessoa ler e responder ao pedido do sistema; no
        // browser o pedido pode ficar sem resposta para sempre.
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      debugPrint('LocationService: permission request failed => $e');
      return null;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint(
          'LocationService: permission $permission — cannot get location');
      return null;
    }

    try {
      // [4F · 05/09] Forma nova do geolocator 14 — `desiredAccuracy` ficou
      // deprecado na subida de pacote desta missão. Mesma precisão.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('LocationService: getCurrentPosition error => $e');
      return null;
    }
  }

  /// Test seam: um [http.Client] falso para provar que uma resposta lenta da
  /// Google não prende o ecrã. Em produção fica null (usa `http.get`).
  @visibleForTesting
  static http.Client? httpClientParaTestes;

  /// Reverse-geocodes [location] to a human-readable address string via the
  /// Google Geocoding API. Returns null on failure (incl. no reply in 8 s).
  static Future<String?> reverseGeocode(LatLng location, String apiKey) async {
    if (apiKey.isEmpty) return null;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'latlng': '${location.latitude},${location.longitude}',
        'key': apiKey,
        'language': 'pt-PT',
        'result_type': 'street_address',
      },
    );

    try {
      // [14/10/2026, tvde-pedir-nunca-trava] Sem limite, uma rede fraca
      // deixava o ecrã "A obter localização…" à espera para sempre. Aos 8 s
      // desiste: quem chama fica com as coordenadas e põe "Localização atual".
      final cliente = httpClientParaTestes;
      final response = await (cliente != null ? cliente.get(uri) : http.get(uri))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint(
            'LocationService.reverseGeocode: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        debugPrint('LocationService.reverseGeocode: status=$status');
        return null;
      }
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      return (results.first as Map<String, dynamic>)['formatted_address']
          as String?;
    } catch (e) {
      debugPrint('LocationService.reverseGeocode: error => $e');
      return null;
    }
  }
}
