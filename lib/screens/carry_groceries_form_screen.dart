import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/maps_config.dart';
import '../services/auto_address.dart';
import '../widgets/auto_address_hint.dart';
import '../models/order_model.dart';
import '../services/place_autocomplete_service.dart';
import '../stores/cart_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/business_autocomplete_field.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/quote_price_footer.dart';
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

  // BUG #8 (2026-05-13) — BR §7.6 deprecated. Foto obrigatória removida em
  // carryGroceries por decisão do Danilo. Fluxo: loja + endereço + pagamento.

  late final PlaceAutocompleteService _geocoder;

  final _bodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _geocoder = createPlaceAutocompleteService(googleApiKey);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preencherMoradaSozinho());
  }

  bool _autoLocating = false;

  /// Morada de entrega preenchida sozinha ao abrir (padrão da app do motorista).
  /// REGRA DE 24/08: nunca trava — falhar deixa o campo vazio e escrevível.
  Future<void> _preencherMoradaSozinho() async {
    if (!mounted || _dropoffController.text.trim().isNotEmpty) return;
    setState(() => _autoLocating = true);
    final s = await AutoAddress.descobrir();
    if (!mounted) return;
    setState(() {
      _autoLocating = false;
      if (s != null && _dropoffController.text.trim().isEmpty) {
        _dropoffController.text = s.morada;
      }
    });
  }


  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _geocoder.dispose();
    super.dispose();
  }

  Future<LatLng?> _geocodeOrNull(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return await _geocoder.geocodeAddress(t);
    } catch (_) {
      return null;
    }
  }

  Future<void> _goToPayment() async {
    final pickupAddress = _pickupController.text.trim();
    final dropoffAddress = _dropoffController.text.trim();

    if (pickupAddress.isEmpty || dropoffAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Preencha os endereços da loja e de entrega.')),
      );
      return;
    }

    // Fallback: texto livre sem seleção → geocodifica antes de submeter para
    // garantir coordenadas (o servidor exige-as).
    _pickupLocation ??= await _geocodeOrNull(pickupAddress);
    _dropoffLocation ??= await _geocodeOrNull(dropoffAddress);
    if (!mounted) return;

    if (_pickupLocation == null || _dropoffLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Não consegui localizar a loja ou a entrega. Escolhe uma sugestão da lista.')),
      );
      return;
    }

    // Configure CartStore so PaymentMethodScreen can show the breakdown
    // and call cartStore.finishOrder() — same flow as sendPackage.
    final cart = context.read<CartStore>();
    cart.configureSession(
      serviceType: OrderServiceType.carryGroceries,
      isPartnerStore: false,
      pickupLocation: _pickupLocation,
      deliveryLocation: _dropoffLocation,
      pickupStreet: pickupAddress,
      dropoffStreet: dropoffAddress,
    );
    cart.setGroceriesPhotoUrl(null);

    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaymentMethodScreen()),
    ).then((ordered) {
      if (ordered == true && mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    // [TELA BRANCA 2026-07-01] blindagem: viewInsets absurdos (Android 16
    // edge-to-edge) esmagam o body para altura ~0 → tela branca. Teclado real
    // nunca passa ~60% do ecrã; acima disso é lixo do sistema → ignora-se.
    final mq = MediaQuery.of(context);
    final bogusInsets = mq.viewInsets.bottom > mq.size.height * 0.6;
    final mqData = bogusInsets
        ? mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: 0))
        : mq;
    return MediaQuery(
      data: mqData,
      child: Scaffold(
        appBar: const BoraScreenAppBar(title: 'Levar Compras'),
        bottomNavigationBar: QuotePriceFooter(
          serviceType: OrderServiceType.carryGroceries,
          pickup: _pickupLocation,
          dropoff: _dropoffLocation,
        ),
        body: ListView(
          key: _bodyKey,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Local da loja',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            // A.2 — campo da loja com pré-preenchimento por GPS: se o cliente
            // estiver dentro/junto de uma loja (≤ 0,15 km) já aparece preenchida.
            BusinessAutocompleteField(
              controller: _pickupController,
              labelText: 'Pesquisar loja ou supermercado',
              prefixIcon: const Icon(Icons.store_outlined),
              autofillNearestWithinKm: 0.15,
              onSelected: (name, coords) {
                setState(() => _pickupLocation = coords);
              },
              onChanged: (_) {
                if (_pickupLocation != null) {
                  setState(() => _pickupLocation = null);
                }
              },
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
              onChanged: (_) {
                if (_dropoffLocation != null) {
                  setState(() => _dropoffLocation = null);
                }
              },
            ),
            AutoAddressHint(visible: _autoLocating),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _goToPayment,
              child: const Text('Continuar para pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}
