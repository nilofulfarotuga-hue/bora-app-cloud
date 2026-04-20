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
  bool _loading = false;

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
    final raw = widget.rawAddress?.trim() ?? '';

    // No address string but coords available — resolve directly from coords.
    if (raw.isEmpty) {
      if (widget.coords != null) {
        setState(() => _loading = true);
        final address = await AddressResolver.resolve(widget.coords!);
        if (mounted) {
          setState(() {
            _resolvedAddress = address;
            _loading = false;
          });
        }
      }
      return;
    }

    // Already a real address — nothing to resolve.
    if (!AddressResolver.looksLikeCoordinates(raw)) {
      setState(() => _resolvedAddress = raw);
      return;
    }

    // No coordinates provided — show raw as-is.
    if (widget.coords == null) {
      setState(() => _resolvedAddress = raw);
      return;
    }

    setState(() => _loading = true);

    final address = await AddressResolver.resolve(widget.coords!);

    if (mounted) {
      setState(() {
        _resolvedAddress = address;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _resolvedAddress ?? widget.rawAddress ?? '';
    final fullText =
        widget.prefix != null ? '${widget.prefix}$displayText' : displayText;

    if (_loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              fullText,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: widget.style?.color ?? Colors.grey,
            ),
          ),
        ],
      );
    }

    return Text(
      fullText,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
