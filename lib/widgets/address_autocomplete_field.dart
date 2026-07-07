import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import '../services/place_autocomplete_service.dart';

/// A [TextFormField] that shows Google Places autocomplete suggestions
/// as the user types in a floating overlay (not inline), so it is always
/// visible regardless of the parent scroll context.
///
/// When the user picks a suggestion the widget resolves the place to
/// coordinates and calls [onSelected].
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.onChanged,
    this.labelText = 'Endereço',
    this.prefixIcon,
    this.validator,
  });

  final TextEditingController controller;

  /// Called when the user selects a suggestion.
  /// [address] is the human-readable string; [coords] is the resolved
  /// location (null when the API key is not configured or the call fails).
  final void Function(String address, ll.LatLng? coords) onSelected;

  /// Called when the user TYPES (not when a suggestion is selected
  /// programmatically). Use this to detect manual edits and reset any
  /// "address confirmed" state in the parent.
  final ValueChanged<String>? onChanged;

  final String labelText;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  late final PlaceAutocompleteService _service;
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  Timer? _focusLossTimer;
  List<PlacePrediction> _predictions = const [];
  bool _resolving = false;
  bool _isSelecting = false;

  // ── Programmatic-change guards ─────────────────────────────────────────
  // GUARD 1 (sync): true while _onSelect is setting controller.text in the
  // same call stack.  Blocks the synchronous onChanged callback.
  bool _isProgrammaticChange = false;

  // GUARD 2 (async): stores the text we just set programmatically.
  // On Android/iOS the platform IME echoes the new text back via the
  // platform channel AFTER the synchronous frame, so _isProgrammaticChange
  // is already false when the echo arrives.  Comparing against this value
  // lets us discard that echo without touching the parent's reset callback.
  String? _lastSelectedText;
  // ────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _service = createPlaceAutocompleteService(googleApiKey);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusLossTimer?.cancel();
    _removeOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _debounce?.cancel();
      _focusLossTimer?.cancel();
      _focusLossTimer = Timer(const Duration(milliseconds: 200), () {
        if (_isSelecting) return;
        _removeOverlay();
        if (_predictions.isNotEmpty && mounted) {
          setState(() => _predictions = const []);
        }
      });
    }
  }

  void _onChanged(String value) {
    // Guard 1: synchronous programmatic change still in progress.
    if (_isProgrammaticChange) {
      debugPrint(
          '[ACF._onChanged] BLOCKED guard1 (programmatic) value="$value"');
      return;
    }

    // Guard 2: async IME echo of the text we programmatically set.
    // The echo carries the exact text we assigned, so it is NOT a user edit.
    if (value == _lastSelectedText) {
      debugPrint('[ACF._onChanged] BLOCKED guard2 (IME echo) value="$value"');
      return;
    }

    // Genuine user keystroke — discard the selection memory so future
    // edits (even to the same string) propagate normally.
    debugPrint('[ACF._onChanged] PASS — genuine user input value="$value"');
    _lastSelectedText = null;

    // Notify parent that the user is typing (NOT a programmatic selection).
    widget.onChanged?.call(value);

    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      _service.resetSession();
      _updatePredictions(const []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = widget.controller.text.trim();
      if (query.isEmpty || !mounted) return;
      final predictions = await _service.fetchPredictions(query);
      if (!mounted) return;
      // Discard stale result if the user typed more while we were fetching.
      if (widget.controller.text.trim() != query) return;
      _updatePredictions(predictions);
    });
  }

  void _updatePredictions(List<PlacePrediction> predictions) {
    setState(() => _predictions = predictions);
    if (predictions.isEmpty) {
      _removeOverlay();
    } else if (_overlayEntry == null) {
      _insertOverlay();
    } else {
      // Refresh the existing entry with the new predictions list.
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _insertOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlayContent(BuildContext context) {
    final RenderBox? box =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final double width = box?.size.width ?? 280.0;

    // Abrir para CIMA quando o espaço abaixo do campo (já descontado o
    // teclado) não chega — senão a lista fica escondida atrás do teclado em
    // campos a meio da página (ex.: destino do TVDE). Campos perto do topo
    // (ex.: wizard da limpeza) continuam a abrir para baixo como antes.
    final media = MediaQuery.of(context);
    bool openUp = false;
    double maxH = 220.0;
    if (box != null && box.attached) {
      final fieldTop = box.localToGlobal(Offset.zero).dy;
      final fieldBottom = fieldTop + box.size.height;
      final spaceBelow =
          media.size.height - media.viewInsets.bottom - fieldBottom - 8;
      final spaceAbove = fieldTop - media.padding.top - 8;
      openUp = spaceBelow < 180 && spaceAbove > spaceBelow;
      maxH = (openUp ? spaceAbove : spaceBelow).clamp(96.0, 220.0);
    }

    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined, size: 20),
                  title: Text(
                    p.primaryText ?? p.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: p.secondaryText == null
                      ? null
                      : Text(
                          p.secondaryText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => _onSelect(p),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSelect(PlacePrediction prediction) async {
    _isSelecting = true;
    _focusLossTimer?.cancel();
    _debounce?.cancel();
    _removeOverlay();
    setState(() {
      _predictions = const [];
      _resolving = true;
    });

    // Arm both guards BEFORE touching the controller so that neither the
    // synchronous callback nor the async IME echo calls widget.onChanged.
    _lastSelectedText = prediction.description;
    _isProgrammaticChange = true;
    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: prediction.description.length),
    );
    _isProgrammaticChange = false;
    // _lastSelectedText intentionally kept set — cleared only when the user
    // makes a genuine edit (see _onChanged guard 2).

    debugPrint(
        'AddressAutocomplete: SELECTED "${prediction.description}" placeId=${prediction.placeId}');

    ll.LatLng? coords;
    try {
      coords = await _service.resolvePlaceLocation(prediction.placeId);
    } catch (e) {
      debugPrint('AddressAutocomplete: resolvePlaceLocation threw => $e');
    }

    // Fallback: if Place Details failed, try Geocoding API.
    if (coords == null && prediction.description.isNotEmpty) {
      debugPrint(
          'AddressAutocomplete: Place Details returned null — trying Geocoding fallback');
      try {
        coords = await _service.geocodeAddress(prediction.description);
      } catch (e) {
        debugPrint('AddressAutocomplete: geocodeAddress threw => $e');
      }
    }

    debugPrint('AddressAutocomplete: COORDS => $coords');

    _service.resetSession();

    if (!mounted) return;
    _isSelecting = false;
    setState(() => _resolving = false);
    widget.onSelected(prediction.description, coords);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
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
    );
  }
}
