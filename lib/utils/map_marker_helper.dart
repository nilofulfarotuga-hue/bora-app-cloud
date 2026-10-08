import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;

/// Pre-builds custom circular map markers using Flutter Canvas.
///
/// Call [preload()] once in initState. Subsequent accesses use the
/// in-memory cache — no re-rendering per rebuild.
/// Falls back to Google Maps default hue markers on Web and on error.
class MapMarkerHelper {
  MapMarkerHelper._();

  static BitmapDescriptor? _driver;
  static BitmapDescriptor? _pickup;
  static BitmapDescriptor? _delivery;
  static BitmapDescriptor? _client;

  // ── Getters (fallback to default if not preloaded) ────────────────────────

  static BitmapDescriptor get driverIcon =>
      _driver ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  static BitmapDescriptor get pickupIcon =>
      _pickup ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

  static BitmapDescriptor get deliveryIcon =>
      _delivery ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

  static BitmapDescriptor get clientIcon =>
      _client ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

  /// Passos do favor (08/10/2026): bolas numeradas 1, 2, 3. O passo atual é
  /// maior e verde-água; os feitos ficam cinzentos; os que faltam, brancos.
  /// Cache por "n|estado"; na web (ou antes de carregar) cai num marcador
  /// normal de cor.
  static final Map<String, BitmapDescriptor> _numerados = {};

  static BitmapDescriptor passoIcon(int numero,
      {required bool atual, required bool feito}) {
    final estado = atual ? 'a' : (feito ? 'f' : 'p');
    return _numerados['$numero|$estado'] ??
        BitmapDescriptor.defaultMarkerWithHue(atual
            ? BitmapDescriptor.hueCyan
            : (feito ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueAzure));
  }

  // ── Preload ───────────────────────────────────────────────────────────────

  /// Pre-renders all markers. Safe to call multiple times (cached after first).
  /// No-op on Web (BitmapDescriptor.fromBytes not supported).
  static Future<void> preload() async {
    if (kIsWeb) return;
    if (_driver != null) return; // already loaded

    try {
      _driver = await _circleMarker(
        color: const Color(0xFF1A73E8), // Google blue
        icon: Icons.two_wheeler,
        size: 54,
      );
      _pickup = await _circleMarker(
        color: const Color(0xFFF59E0B), // Amber
        icon: Icons.storefront_outlined,
        size: 72,
      );
      _delivery = await _circleMarker(
        color: const Color(0xFFEF4444), // Red
        icon: Icons.home_outlined,
        size: 46,
      );
      _client = await _circleMarker(
        color: const Color(0xFF10B981), // Green
        icon: Icons.person,
        size: 46,
      );
      for (var n = 1; n <= 3; n++) {
        _numerados['$n|a'] = await _numberMarker(n,
            fill: const Color(0xFF14B8A6), text: Colors.white, size: 76);
        _numerados['$n|p'] = await _numberMarker(n,
            fill: Colors.white, text: const Color(0xFF0F766E), size: 56);
        _numerados['$n|f'] = await _numberMarker(n,
            fill: const Color(0xFF9CA3AF), text: Colors.white, size: 48);
      }
    } catch (e) {
      debugPrint('[MapMarkerHelper] preload failed — using default: $e');
    }
  }

  static Future<BitmapDescriptor> _numberMarker(
    int numero, {
    required Color fill,
    required Color text,
    required double size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = size / 2;
    final center = Offset(r, r);
    canvas.drawCircle(
      Offset(r, r + 2.5),
      r - 3,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(center, r - 3, Paint()..color = fill);
    canvas.drawCircle(
      center,
      r - 3,
      Paint()
        ..color = const Color(0xFF0F766E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final tp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: '$numero',
        style: TextStyle(
          fontSize: size * 0.48,
          fontWeight: FontWeight.w800,
          color: text,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(r - tp.width / 2, r - tp.height / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  // ── Canvas renderer ───────────────────────────────────────────────────────

  static Future<BitmapDescriptor> _circleMarker({
    required Color color,
    required IconData icon,
    required double size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = size / 2;
    final center = Offset(r, r);

    // Drop shadow
    canvas.drawCircle(
      Offset(r, r + 2.5),
      r - 3,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Filled circle
    canvas.drawCircle(center, r - 3, Paint()..color = color);

    // White border
    canvas.drawCircle(
      center,
      r - 3,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );

    // Icon (Material Symbols / Icons)
    final tp = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.44,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(
      canvas,
      Offset(r - tp.width / 2, r - tp.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
