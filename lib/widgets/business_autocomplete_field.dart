import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/maps_config.dart';
import '../services/location_service.dart';
import '../services/place_autocomplete_service.dart';

/// Resultado da RPC `search_businesses` (lojas Bora + comércios OSM da Guarda).
class BusinessPrediction {
  const BusinessPrediction({
    required this.name,
    required this.coords,
    this.address,
    this.category,
    this.source = 'osm',
    this.distanceKm,
  });

  final String name;
  final ll.LatLng coords;
  final String? address;
  final String? category;

  /// 'bora' (loja Bora com catálogo real) | 'osm' (comércio normal).
  final String source;
  final double? distanceKm;

  bool get isBoraStore => source == 'bora';
}

/// Item da lista combinada: comércio (coords já prontas) OU morada livre do
/// Google Places (placeId; coords resolvidas no tap). Só há moradas quando
/// `includeAddresses` está ligado.
class _Suggestion {
  const _Suggestion.business(BusinessPrediction this.business) : place = null;
  const _Suggestion.place(PlacePrediction this.place) : business = null;

  final BusinessPrediction? business;
  final PlacePrediction? place;

  bool get isPlace => place != null;
}

/// Campo de pesquisa de comércio (loja do favor / loja onde está a compra).
/// Chama a RPC `search_businesses(query, lat, lng, limit)` — NÃO o geocoder.
///
/// Ao selecionar uma sugestão, preenche o nome e devolve as coordenadas reais
/// via [onSelected]. Texto livre é permitido — o pai (ex.: wizard dos Favores)
/// geocodifica o texto antes de submeter quando o utilizador não escolhe da
/// lista (ver guard de submissão).
///
/// Espelha o padrão de overlay flutuante e os guards de eco-IME do
/// [AddressAutocompleteField] para herdar a correção do bug de tap-select.
class BusinessAutocompleteField extends StatefulWidget {
  const BusinessAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.onChanged,
    this.labelText = 'Local do favor',
    this.hintText,
    this.prefixIcon,
    this.validator,
    this.autofillNearestWithinKm,
    this.includeAddresses = false,
  });

  final TextEditingController controller;

  /// Chamado quando o utilizador seleciona um comércio da lista.
  final void Function(String name, ll.LatLng coords) onSelected;

  /// Chamado quando o utilizador ESCREVE (não em seleção programática). Usar
  /// para limpar no pai qualquer estado "comércio confirmado".
  final ValueChanged<String>? onChanged;

  final String labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;

  /// Se != null, ao abrir obtém GPS e chama `search_businesses('', lat, lng, 1)`;
  /// se o comércio mais próximo estiver a ≤ este valor (km), pré-preenche o
  /// campo (editável) com nome + coords. Usado em "Leva a tua compra" (0,15).
  final double? autofillNearestWithinKm;

  /// Se true, mostra também moradas livres (Google Places) ABAIXO dos
  /// comércios — mesmo autocomplete do "Onde entregar". Usado no "Local do
  /// favor" dos Favores. Default false mantém o comportamento só-comércios
  /// (ex.: "Leva a tua compra", onde a loja tem de ser real).
  final bool includeAddresses;

  @override
  State<BusinessAutocompleteField> createState() =>
      _BusinessAutocompleteFieldState();
}

class _BusinessAutocompleteFieldState extends State<BusinessAutocompleteField> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  Timer? _focusLossTimer;
  List<_Suggestion> _predictions = const [];
  bool _loading = false;
  bool _isSelecting = false;

  ll.LatLng? _gps;

  // Google Places — só instanciado quando `includeAddresses` está ligado.
  PlaceAutocompleteService? _places;

  // Guards programáticos (iguais ao AddressAutocompleteField).
  bool _isProgrammaticChange = false;
  String? _lastSelectedText;

  @override
  void initState() {
    super.initState();
    if (widget.includeAddresses) {
      _places = createPlaceAutocompleteService(googleApiKey);
    }
    _focusNode.addListener(_onFocusChanged);
    _initGps();
  }

  Future<void> _initGps() async {
    final loc = await LocationService.getCurrentLocation();
    if (!mounted || loc == null) return;
    _gps = loc;
    final within = widget.autofillNearestWithinKm;
    if (within != null && widget.controller.text.trim().isEmpty) {
      await _autofillNearest(within);
    }
  }

  Future<void> _autofillNearest(double withinKm) async {
    final results = await _search('', limit: 1);
    if (!mounted || results.isEmpty) return;
    final nearest = results.first;
    final d = nearest.distanceKm;
    if (d != null && d <= withinKm) {
      _lastSelectedText = nearest.name;
      _isProgrammaticChange = true;
      widget.controller.text = nearest.name;
      _isProgrammaticChange = false;
      widget.onSelected(nearest.name, nearest.coords);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusLossTimer?.cancel();
    _removeOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _places?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // Ao focar com GPS e campo vazio, mostrar os comércios mais próximos.
      if (_gps != null && widget.controller.text.trim().isEmpty) {
        _runSearch('');
      }
      return;
    }
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

  void _onChanged(String value) {
    if (_isProgrammaticChange) return;
    if (value == _lastSelectedText) return; // eco IME da seleção
    _lastSelectedText = null;
    widget.onChanged?.call(value);

    _debounce?.cancel();
    final trimmed = value.trim();
    // Com query vazia só listamos se houver GPS (mais próximos).
    if (trimmed.length < 2 && !(trimmed.isEmpty && _gps != null)) {
      _updatePredictions(const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _runSearch(widget.controller.text.trim());
    });
  }

  Future<List<BusinessPrediction>> _search(String query,
      {int limit = 8}) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'search_businesses',
        params: {
          'p_query': query,
          'p_lat': _gps?.latitude,
          'p_lng': _gps?.longitude,
          'p_limit': limit,
        },
      );
      final list = (res as List<dynamic>? ?? const []);
      return list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final lat = (m['lat'] as num?)?.toDouble();
            final lng = (m['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            return BusinessPrediction(
              name: (m['name'] as String?)?.trim() ?? '',
              coords: ll.LatLng(lat, lng),
              address: m['address'] as String?,
              category: m['category'] as String?,
              source: (m['source'] as String?) ?? 'osm',
              distanceKm: (m['distance_km'] as num?)?.toDouble(),
            );
          })
          .whereType<BusinessPrediction>()
          .where((p) => p.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('BusinessAutocomplete: search error => $e');
      return const [];
    }
  }

  /// Moradas livres (Google Places). Só dispara com `includeAddresses` e
  /// query >= 3 chars. Comércios aparecem sempre primeiro.
  Future<List<PlacePrediction>> _searchPlaces(String query) async {
    final svc = _places;
    if (svc == null) return const [];
    try {
      return await svc.fetchPredictions(query);
    } catch (e) {
      debugPrint('BusinessAutocomplete: places error => $e');
      return const [];
    }
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    final businesses = await _search(query);
    List<PlacePrediction> places = const [];
    if (widget.includeAddresses && query.trim().length >= 3) {
      places = await _searchPlaces(query);
    }
    if (!mounted) return;
    // Descartar resultado obsoleto se o texto mudou entretanto.
    if (widget.controller.text.trim() != query) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = false);
    final combined = <_Suggestion>[
      for (final b in businesses) _Suggestion.business(b),
      for (final p in places) _Suggestion.place(p),
    ];
    _updatePredictions(combined);
  }

  void _updatePredictions(List<_Suggestion> predictions) {
    setState(() => _predictions = predictions);
    if (predictions.isEmpty) {
      _removeOverlay();
    } else if (_overlayEntry == null) {
      _insertOverlay();
    } else {
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

    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _buildTile(_predictions[index]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(_Suggestion s) =>
      s.isPlace ? _buildPlaceTile(s.place!) : _buildBusinessTile(s.business!);

  Widget _buildPlaceTile(PlacePrediction p) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.location_on_outlined,
          size: 20, color: AppColors.textSecondary),
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
      onTap: () => _onSelectPlace(p),
    );
  }

  Widget _buildBusinessTile(BusinessPrediction p) {
    final distance =
        p.distanceKm == null ? null : '${p.distanceKm!.toStringAsFixed(1)} km';
    final subtitleParts = <String>[
      if (p.address != null && p.address!.trim().isNotEmpty) p.address!.trim(),
      if (distance != null) distance,
    ];
    return ListTile(
      dense: true,
      leading: Icon(
        p.isBoraStore ? Icons.storefront : Icons.place_outlined,
        size: 20,
        color: p.isBoraStore ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (p.isBoraStore) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryWash,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Loja Bora',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () => _onSelectBusiness(p),
    );
  }

  /// Morada Google: resolve coords no tap (Place Details → geocode fallback).
  /// Se falhar, deixa o texto livre e o pai geocodifica antes de submeter.
  Future<void> _onSelectPlace(PlacePrediction prediction) async {
    _isSelecting = true;
    _focusLossTimer?.cancel();
    _debounce?.cancel();
    _removeOverlay();
    setState(() {
      _predictions = const [];
      _loading = true;
    });

    _lastSelectedText = prediction.description;
    _isProgrammaticChange = true;
    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: prediction.description.length),
    );
    _isProgrammaticChange = false;

    final svc = _places;
    ll.LatLng? coords;
    if (svc != null) {
      try {
        coords = await svc.resolvePlaceLocation(prediction.placeId);
      } catch (_) {}
      if (coords == null && prediction.description.isNotEmpty) {
        try {
          coords = await svc.geocodeAddress(prediction.description);
        } catch (_) {}
      }
      svc.resetSession();
    }

    if (!mounted) return;
    _focusNode.unfocus();
    _isSelecting = false;
    setState(() => _loading = false);
    // onSelected exige coords reais; se nulas, o guard do pai geocodifica.
    if (coords != null) widget.onSelected(prediction.description, coords);
  }

  void _onSelectBusiness(BusinessPrediction prediction) {
    _isSelecting = true;
    _focusLossTimer?.cancel();
    _debounce?.cancel();
    _removeOverlay();
    setState(() => _predictions = const []);

    _lastSelectedText = prediction.name;
    _isProgrammaticChange = true;
    widget.controller.text = prediction.name;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: prediction.name.length),
    );
    _isProgrammaticChange = false;

    _focusNode.unfocus();
    _isSelecting = false;
    widget.onSelected(prediction.name, prediction.coords);
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
          border: const OutlineInputBorder(),
          labelText: widget.labelText,
          hintText: widget.hintText,
          prefixIcon:
              widget.prefixIcon ?? const Icon(Icons.storefront_outlined),
          suffixIcon: _loading
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
