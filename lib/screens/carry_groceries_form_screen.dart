import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/maps_config.dart';
import '../models/order_model.dart';
import '../services/location_service.dart';
import '../stores/cart_store.dart';
import '../widgets/address_autocomplete_field.dart';
import 'payment_method_screen.dart';

class CarryGroceriesFormScreen extends StatefulWidget {
  const CarryGroceriesFormScreen({super.key});

  @override
  State<CarryGroceriesFormScreen> createState() =>
      _CarryGroceriesFormScreenState();
}

class _CarryGroceriesFormScreenState extends State<CarryGroceriesFormScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();

  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  bool _loadingLocation = false;

  static const _fallbackAddress = 'Guarda, Portugal';

  @override
  void initState() {
    super.initState();
    _prefillPickupFromGps();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  /// Obtém a localização atual via GPS e preenche o campo de recolha.
  /// Se GPS ou reverse geocoding falharem, usa [_fallbackAddress].
  /// Corre em background — não bloqueia a UI, nunca mostra erro.
  Future<void> _prefillPickupFromGps() async {
    setState(() => _loadingLocation = true);
    try {
      final coords = await LocationService.getCurrentLocation();
      if (!mounted) return;

      if (coords != null) {
        final address = await LocationService.reverseGeocode(coords, googleApiKey);
        if (!mounted) return;
        setState(() {
          _pickupLocation = coords;
          _pickupController.text =
              (address != null && address.isNotEmpty) ? address : _fallbackAddress;
        });
      } else {
        setState(() => _pickupController.text = _fallbackAddress);
      }
    } catch (_) {
      if (mounted) setState(() => _pickupController.text = _fallbackAddress);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _goToPayment() {
    final pickupAddress = _pickupController.text.trim();
    final dropoffAddress = _dropoffController.text.trim();

    if (pickupAddress.isEmpty || dropoffAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Preencha os endereços da loja e de entrega.')),
      );
      return;
    }

    if (_pickupLocation == null || _dropoffLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Selecione um endereço válido nas sugestões para obter coordenadas.')),
      );
      return;
    }

    // Configure CartStore so PaymentMethodScreen can show the breakdown
    // and call cartStore.finishOrder() — same flow as sendPackage.
    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.carryGroceries,
          isPartnerStore: false,
          pickupLocation: _pickupLocation,
          deliveryLocation: _dropoffLocation,
          pickupStreet: pickupAddress,
          dropoffStreet: dropoffAddress,
        );

    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaymentMethodScreen()),
    ).then((ordered) {
      if (ordered == true && mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entregar compras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Local da loja',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              AddressAutocompleteField(
                controller: _pickupController,
                labelText: 'Pesquisar loja ou supermercado',
                prefixIcon: const Icon(Icons.store_outlined),
                onSelected: (address, coords) {
                  setState(() => _pickupLocation = coords);
                },
              ),
              if (_loadingLocation)
                const Positioned(
                  right: 12,
                  top: 14,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Endereço de entrega',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          AddressAutocompleteField(
            controller: _dropoffController,
            labelText: 'Pesquisar endereço de entrega',
            prefixIcon: const Icon(Icons.location_on_outlined),
            onSelected: (address, coords) {
              setState(() => _dropoffLocation = coords);
            },
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _goToPayment,
            child: const Text('Continuar para pagamento'),
          ),
        ],
      ),
    );
  }
}
