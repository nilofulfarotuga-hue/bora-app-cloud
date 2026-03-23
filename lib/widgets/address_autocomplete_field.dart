import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import '../services/place_autocomplete_service.dart';

/// A [TextFormField] that shows Google Places autocomplete suggestions
/// as the user types. When the user picks a suggestion the widget resolves
/// the place to coordinates and calls [onSelected].
///
/// Usage:
/// ```dart
/// AddressAutocompleteField(
///   controller: _addressController,
///   onSelected: (address, coords) {
///     _pickupCoords = coords;
///   },
///   labelText: 'Endereço do restaurante',
///   validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
/// )
/// ```
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.labelText = 'Endereço',
    this.prefixIcon,
    this.validator,
  });

  final TextEditingController controller;

  /// Called when the user selects a suggestion.
  /// [address] is the human-readable string; [coords] is the resolved
  /// location (null when the API key is not configured or the call fails).
  final void Function(String address, ll.LatLng? coords) onSelected;

  final String labelText;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  late final PlaceAutocompleteService _service;
  Timer? _debounce;
  List<PlacePrediction> _predictions = const [];
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _service = createPlaceAutocompleteService(googleApiKey);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      _service.resetSession();
      if (_predictions.isNotEmpty) {
        setState(() => _predictions = const []);
      }
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = widget.controller.text.trim();
      if (query.isEmpty || !mounted) return;
      final predictions = await _service.fetchPredictions(query);
      if (!mounted) return;
      // Discard if the text changed while we were fetching.
      if (widget.controller.text.trim() != query) return;
      setState(() => _predictions = predictions);
    });
  }

  Future<void> _onSelect(PlacePrediction prediction) async {
    _debounce?.cancel();
    setState(() {
      _predictions = const [];
      _resolving = true;
    });

    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: prediction.description.length),
    );

    ll.LatLng? coords;
    try {
      coords = await _service.resolvePlaceLocation(prediction.placeId);
    } catch (_) {}

    _service.resetSession();

    if (!mounted) return;
    setState(() => _resolving = false);
    widget.onSelected(prediction.description, coords);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          onChanged: _onChanged,
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixIcon:
                widget.prefixIcon ?? const Icon(Icons.location_on_outlined),
            suffixIcon: _resolving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_predictions.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: _predictions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = _predictions[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(p.primaryText ?? p.description),
                    subtitle: p.secondaryText == null
                        ? null
                        : Text(p.secondaryText!),
                    onTap: () => _onSelect(p),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
