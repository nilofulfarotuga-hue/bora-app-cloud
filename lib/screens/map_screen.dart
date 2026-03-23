import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/maps_config.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../services/location_service.dart';
import '../services/place_autocomplete_service.dart';
import '../services/pricing_service.dart';
import '../stores/order_store.dart';
import '../utils/map_utils.dart';



enum _LocationField { pickup, destination }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
    final DirectionsService _directionsService = DirectionsService();
  late final PlaceAutocompleteService _autocompleteService;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();


  _LocationField _selectedField = _LocationField.destination;

  ll.LatLng? _pickupLocation;
  ll.LatLng? _destinationLocation;

  _AddressLabel? _pickupAddress;
  _AddressLabel? _destinationAddress;

  List<ll.LatLng> _routePoints = <ll.LatLng>[];
  String? _activeRouteKey;
  int _routeRequestId = 0;

    double? price;
  double? distanceKm;
  OrderPricingBreakdown? pricingBreakdown;
  String? _loadingError;
  bool _isSearchingAddress = false;
  bool _isFetchingRoute = false;

  Timer? _autocompleteDebounce;
  List<PlacePrediction> _predictions = const <PlacePrediction>[];



    @override
  void initState() {
    super.initState();
    _autocompleteService = createPlaceAutocompleteService(googleApiKey);
    loadLocation();
  }


      @override
  void dispose() {
    _autocompleteDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _autocompleteService.dispose();
    _directionsService.dispose();
    super.dispose();
  }



  Future<void> loadLocation() async {
    if (!mounted) return;
    setState(() {
      _loadingError = null;
    });

    try {
      final location = await LocationService.getCurrentLocation();
      final label = await _reverseGeocode(location);
      if (!mounted) return;
      setState(() {
        _pickupLocation = location;
        _pickupAddress = label;
      });
      await _moveCamera(location);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingError = 'Não foi possível obter a sua localização.';
      });
      debugPrint('Erro ao obter localização: $error');
    }
  }

  Future<_AddressLabel?> _reverseGeocode(ll.LatLng coordinate) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coordinate.latitude,
        coordinate.longitude,
        localeIdentifier: 'pt_PT',
      );
      if (placemarks.isEmpty) {
        return null;
      }
      return _AddressLabel.fromPlacemark(placemarks.first);
    } catch (error) {
      debugPrint('Reverse geocoding failed: $error');
      return null;
    }
  }

  Future<void> _moveCamera(ll.LatLng target) async {
    if (!_mapController.isCompleted) {
      return;
    }
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newLatLng(target.toGMaps()),
    );
  }

  Future<void> _onTapMap(LatLng point) async {
    await _selectCoordinate(
      _selectedField,
      ll.LatLng(point.latitude, point.longitude),
      moveCamera: true,
    );
  }

        void _onSearchTextChanged(String value) {
    _autocompleteDebounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 3) {
      _autocompleteService.resetSession();
      setState(() {
        _predictions = const <PlacePrediction>[];
      });
      return;
    }

    _autocompleteDebounce = Timer(const Duration(milliseconds: 300), () async {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        return;
      }

      final predictions = await _autocompleteService.fetchPredictions(query);
      if (!mounted) return;
      if (_searchController.text.trim() != query) {
        return;
      }
      setState(() {
        _predictions = predictions;
      });
    });
  }

  Future<void> _onPredictionSelected(PlacePrediction prediction) async {
    _autocompleteDebounce?.cancel();
    _searchController.text = prediction.description;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );

    setState(() {
      _predictions = const <PlacePrediction>[];
      _isSearchingAddress = true;
    });

    try {
      final location =
          await _autocompleteService.resolvePlaceLocation(prediction.placeId);
      if (location == null) {
        _showPlaceSelectionError();
        return;
      }

      await _selectCoordinate(
        _selectedField,
        location,
        moveCamera: true,
      );
      _searchFocusNode.unfocus();
    } catch (error) {
      debugPrint('Places details error: $error');
      _showPlaceSelectionError();
    } finally {
      _autocompleteService.resetSession();
      if (mounted) {
        setState(() {
          _isSearchingAddress = false;
        });
      }
    }
  }

  void _clearSearchField() {
    _autocompleteDebounce?.cancel();
    _autocompleteService.resetSession();
    setState(() {
      _searchController.clear();
      _predictions = const <PlacePrediction>[];
    });
  }

  void _showPlaceSelectionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível obter o local selecionado.'),
      ),
    );
  }

  Future<void> _onSearchSubmitted(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      _clearSearchField();
      return;
    }

    if (_predictions.isNotEmpty) {
      await _onPredictionSelected(_predictions.first);
      return;
    }

    final predictions = await _autocompleteService.fetchPredictions(query);
    if (!mounted) return;

    if (predictions.isEmpty) {
      _showPlaceSelectionError();
      return;
    }

    setState(() {
      _predictions = predictions;
    });

    await _onPredictionSelected(predictions.first);
  }


  Future<void> _selectCoordinate(

    _LocationField field,
    ll.LatLng coordinate, {
    bool moveCamera = false,
    bool manageLoader = true,
  }) async {
    if (manageLoader) {
      setState(() {
        _isSearchingAddress = true;
      });
    }

    final address = await _reverseGeocode(coordinate);

    if (!mounted) return;
    if (manageLoader) {
      setState(() {
        _isSearchingAddress = false;
      });
    }

    setState(() {
      if (field == _LocationField.pickup) {
        _pickupLocation = coordinate;
        _pickupAddress = address;
      } else {
        _destinationLocation = coordinate;
        _destinationAddress = address;
      }
    });

    if (moveCamera) {
      await _moveCamera(coordinate);
    }

    _updateRouteAndPricing();
  }

  void _updateRouteAndPricing() {
    final origin = _pickupLocation;
    final destination = _destinationLocation;

    if (origin == null || destination == null) {
      setState(() {
        if (destination == null) {
          _routePoints = <ll.LatLng>[];
          price = null;
          distanceKm = null;
          pricingBreakdown = null;
        }
      });
      return;
    }

    final key =
        '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}|${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';
    if (_activeRouteKey == key && _routePoints.isNotEmpty) {
      return;
    }

    _activeRouteKey = key;
    final requestId = ++_routeRequestId;

    setState(() {
      _isFetchingRoute = true;
    });

    _directionsService
        .fetchRoute(origin: origin, destination: destination)
        .then((route) async {
      if (!mounted || _routeRequestId != requestId) {
        return;
      }

      List<ll.LatLng> points;
      double computedKm;

      if (route != null && route.points.isNotEmpty) {
        points = route.points;
        computedKm = route.distanceKm;
      } else {
        points = <ll.LatLng>[origin, destination];
        computedKm = const ll.Distance()
            .as(ll.LengthUnit.Kilometer, origin, destination);
      }

      final breakdown = PricingService.calculateBreakdown(
        serviceType: OrderServiceType.sendPackage,
        subtotal: 0,
        distanceKm: computedKm,
      );

      setState(() {
        _isFetchingRoute = false;
        _routePoints = points;
        distanceKm = breakdown.distanceKm;
        pricingBreakdown = breakdown;
        price = breakdown.customerTotal;
      });

      await _fitToRoute(points);
    }).catchError((error) async {
      debugPrint('Erro ao obter rota: $error');
      if (!mounted || _routeRequestId != requestId) {
        return;
      }

      final computedKm = const ll.Distance()
          .as(ll.LengthUnit.Kilometer, origin, destination);
      final breakdown = PricingService.calculateBreakdown(
        serviceType: OrderServiceType.sendPackage,
        subtotal: 0,
        distanceKm: computedKm,
      );

      setState(() {
        _isFetchingRoute = false;
        _routePoints = <ll.LatLng>[origin, destination];
        distanceKm = breakdown.distanceKm;
        pricingBreakdown = breakdown;
        price = breakdown.customerTotal;
      });

      await _fitToRoute(<ll.LatLng>[origin, destination]);
    });
  }

  Future<void> _fitToRoute(List<ll.LatLng> points) async {
    if (!_mapController.isCompleted || points.isEmpty) {
      return;
    }
    final bounds = boundsFromPoints(points);
    if (bounds == null) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  String _hintForField(_LocationField field) {
    return field == _LocationField.pickup
        ? 'Pesquisar ponto de recolha'
        : 'Pesquisar destino';
  }

  void createOrder() {
    final origin = _pickupLocation;
    final target = _destinationLocation;

    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o ponto de recolha.')),
      );
      return;
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um destino.')),
      );
      return;
    }

    final breakdown = pricingBreakdown ??
        PricingService.calculateBreakdown(
          serviceType: OrderServiceType.sendPackage,
          subtotal: 0,
          distanceKm: distanceKm ?? PricingService.defaultDistanceKm,
        );

    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();

    final pickupAddressLabel =
        _pickupAddress?.full ?? _formatCoordinate(origin);
    final dropoffAddressLabel =
        _destinationAddress?.full ?? _formatCoordinate(target);

    orderStore.createOrder(
      serviceType: OrderServiceType.sendPackage,
      itemsSubtotal: breakdown.subtotal,
      destination: target,
      paymentMethod: PaymentMethod.cash,
      pickupLocation: origin,
      distanceKm: breakdown.distanceKm,
      isPartnerStore: false,
      pickupAddress: pickupAddressLabel,
      pickupStreet: _pickupAddress?.street ?? pickupAddressLabel,
      pickupCity: _pickupAddress?.city,
      dropoffAddress: dropoffAddressLabel,
      dropoffStreet: _destinationAddress?.street ?? dropoffAddressLabel,
      dropoffCity: _destinationAddress?.city,
      clientPhone: authStore.currentClient?.phone,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pedido criado')),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pickupLocation = _pickupLocation;

    if (pickupLocation == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Escolher destino'),
        ),
        body: Center(
          child: _loadingError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _loadingError!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: loadLocation,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    final destinationLocation = _destinationLocation;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickupLocation.toGMaps(),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        infoWindow: const InfoWindow(title: 'Recolha'),
      ),
    };

    if (destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationLocation.toGMaps(),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      );
    }

    final polylines = <Polyline>{};
    if (_routePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: Colors.blueAccent,
          width: 5,
          points: _routePoints.toGMaps(),
        ),
      );
    } else if (destinationLocation != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: Colors.blueAccent,
          width: 4,
          points: [pickupLocation.toGMaps(), destinationLocation.toGMaps()],
        ),
      );
    }

    final showProgress = _isSearchingAddress || _isFetchingRoute;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolher destino'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
  setState(() {}); // força rebuild do campo
  _onSearchTextChanged(value);
},
                        onSubmitted: _onSearchSubmitted,
                        decoration: InputDecoration(
                          labelText: _hintForField(_selectedField),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _clearSearchField,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<_LocationField>(
                      value: _selectedField,
                                            onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedField = value;
                            _predictions = const <PlacePrediction>[];
                          });
                          _autocompleteService.resetSession();
                        }
                      },

                      items: const [
                        DropdownMenuItem(
                          value: _LocationField.pickup,
                          child: Text('Recolha'),
                        ),
                        DropdownMenuItem(
                          value: _LocationField.destination,
                          child: Text('Destino'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_predictions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                                        child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(

                        constraints: const BoxConstraints(maxHeight: 240),
                                                child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: _predictions.length,
                          itemBuilder: (context, index) {

                            final prediction = _predictions[index];
                            return ListTile(
                              leading:
                                  const Icon(Icons.location_on_outlined),
                              title: Text(
                                prediction.primaryText ?? prediction.description,
                              ),
                              subtitle: prediction.secondaryText == null
                                  ? null
                                  : Text(prediction.secondaryText!),
                              onTap: () => _onPredictionSelected(prediction),
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _AddressDisplay(

                  icon: Icons.my_location,
                  title: 'Recolha',
                  value: _pickupAddress?.full ?? _formatCoordinate(pickupLocation),
                ),
                const SizedBox(height: 8),
                _AddressDisplay(
                  icon: Icons.flag,
                  title: 'Destino',
                  value: destinationLocation == null
                      ? 'Toque no mapa ou pesquise um endereço'
                      : (_destinationAddress?.full ??
                          _formatCoordinate(destinationLocation)),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pickupLocation.toGMaps(),
                zoom: 14,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              markers: markers,
              polylines: polylines,
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
              },
              onTap: _onTapMap,
            ),
          ),
          if (price != null)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (distanceKm != null)
                    Text(
                      'Distância estimada: ${distanceKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 16),
                    ),
                  if (pricingBreakdown != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Entrega: €${pricingBreakdown!.deliveryFee.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Total: €${price!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AddressDisplay(
                    icon: Icons.my_location,
                    title: 'Recolha',
                    value: _pickupAddress?.full ??
                        _formatCoordinate(pickupLocation),
                  ),
                  const SizedBox(height: 4),
                  _AddressDisplay(
                    icon: Icons.flag,
                    title: 'Destino',
                    value: _destinationAddress?.full ??
                        _formatCoordinate(destinationLocation!),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: createOrder,
                      child: const Text('Confirmar pedido'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatCoordinate(ll.LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }
}

class _AddressLabel {

  const _AddressLabel({required this.street, this.city});


  final String street;
  final String? city;

  String get full {
    if (street.isEmpty && (city == null || city!.isEmpty)) {
      return 'Endereço selecionado';
    }
    if (street.isEmpty) {
      return city ?? 'Endereço selecionado';
    }
    if (city == null || city!.isEmpty) {
      return street;
    }
    return '$street, $city';
  }

  static _AddressLabel fromPlacemark(Placemark placemark) {
    final streetCandidates = <String?>[
      placemark.street,
      placemark.thoroughfare,
      placemark.name,
      placemark.subLocality,
    ];

    final cityCandidates = <String?>[
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country,
    ];

    final street = streetCandidates.firstWhere(
      (value) => value != null && value.trim().isNotEmpty,
      orElse: () => '',
    );

    final city = cityCandidates.firstWhere(
      (value) => value != null && value.trim().isNotEmpty,
      orElse: () => null,
    );

    return _AddressLabel(
      street: street?.trim() ?? '',
      city: city?.trim(),
    );
  }
}

class _AddressDisplay extends StatelessWidget {
  const _AddressDisplay({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}