import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/address_resolver.dart';

/// Reusable widget that displays a human-readable address for given
/// coordinates. Handles the async reverse-geocoding lookup internally
/// so the parent widget does not need any FutureBuilder boilerplate.
///
/// Behaviour:
///  1. If [rawAddress] is already a real address (not coordinates),
///     it is displayed immediately — no API call.
///  2. If [rawAddress] looks like raw coordinates (e.g. "38.72, -9.14")
///     AND [coords] is provided, it resolves asynchronously via
///     [AddressResolver] and displays the result.
///  3. While resolving, shows [rawAddress] with a subtle loading indicator.
///  4. If resolution fails, keeps showing [rawAddress] (coordinates).
///
/// Usage:
/// ```dart
/// AddressText(
///   rawAddress: order.pickupAddress,
///   coords: order.pickupLocation,
///   style: TextStyle(fontSize: 14),
///   prefix: 'Recolha: ',
/// )
/// ```
class AddressText extends StatefulWidget {
  const AddressText({
    super.key,
    required this.rawAddress,
    this.coords,
    this.style,
    this.prefix,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
  });

  /// The address string as currently stored (may be real address or coords).
  final String? rawAddress;

  /// The coordinates to reverse-geocode if [rawAddress] looks like coords.
  /// If null, the widget just displays [rawAddress] as-is.
  final LatLng? coords;

  /// Text style applied to the final displayed string.
  final TextStyle? style;

  /// Optional prefix prepended to the address (e.g. "Recolha: ").
  final String? prefix;

  final int maxLines;
  final TextOverflow overflow;

  @override
  State<AddressText> createState() => _AddressTextState();
}

class _AddressTextState extends State<AddressText> {
  String? _resolvedAddress;

  @override
  void initState() {
    super.initState();
    _maybeResolve();
  }

  @override
  void didUpdateWidget(AddressText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve if the coordinates changed.
    if (widget.coords != oldWidget.coords ||
        widget.rawAddress != oldWidget.rawAddress) {
      _resolvedAddress = null;
      _maybeResolve();
    }
  }

  Future<void> _maybeResolve() async {
    // BUG 29: NUNCA fazer reverse geocoding. Google Geocoding API retorna a
    // rua MAIS PRÓXIMA das coordenadas, que pode não ser a rua correcta da
    // entrega (ex: "Alexandre Herculano" em vez de "Rua do Torreão"). Cliente
    // e estafeta preferem morada literal gravada no checkout.
    //
    // Comportamento novo:
    //  - rawAddress não-vazio: mostra rawAddress.
    //  - rawAddress vazio + coords disponível: mostra coords como fallback.
    //  - rawAddress vazio + coords null: mostra string vazia.
    final raw = widget.rawAddress?.trim() ?? '';
    if (raw.isNotEmpty) {
      setState(() => _resolvedAddress = raw);
      return;
    }
    if (widget.coords != null) {
      final c = widget.coords!;
      setState(() => _resolvedAddress =
          '${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)}');
      return;
    }
    setState(() => _resolvedAddress = '');
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _resolvedAddress ?? widget.rawAddress ?? '';
    final fullText =
        widget.prefix != null ? '${widget.prefix}$displayText' : displayText;

    return Text(
      fullText,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
