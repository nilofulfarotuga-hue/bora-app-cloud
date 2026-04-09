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
        size: 46,
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
    } catch (e) {
      debugPrint('[MapMarkerHelper] preload failed — using default: $e');
    }
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
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}
