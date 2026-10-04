import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/maps_config.dart';
import '../models/order_model.dart';
import '../services/location_service.dart';
import '../stores/cart_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/mandatory_photo_picker.dart';
import '../widgets/quote_price_footer.dart';
import 'orders_screen.dart';
import 'payment_method_screen.dart';

import '../l10n/tr.dart';

class SendPackageFormScreen extends StatefulWidget {
  const SendPackageFormScreen({super.key});

  @override
  State<SendPackageFormScreen> createState() => _SendPackageFormScreenState();
}

class _SendPackageFormScreenState extends State<SendPackageFormScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();

  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  // true = motorcycle can carry it → requiresCar = false
  // false = needs car              → requiresCar = true
  bool _motoCanCarry = true;

  // Shows a subtle loading indicator while GPS + reverse geocoding runs.
  bool _loadingLocation = false;

  // Mandatory package photo (BR §7.5).
  String? _packagePhotoUrl;

  final _bodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // [C/adenda] _prefillPickupFromGps faz setState; chamá-lo SÍNCRONO no
    // initState marcava build durante build. Diferido para depois do 1º frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefillPickupFromGps();
    });
  }

  static const _fallbackAddress = 'Guarda, Portugal';

  /// Obtém a localização atual via GPS e preenche o campo de recolha.
  /// Se GPS ou reverse geocoding falharem, usa [_fallbackAddress].
  /// Corre em background — não bloqueia a UI, nunca mostra erro.
  Future<void> _prefillPickupFromGps() async {
    setState(() => _loadingLocation = true);

    try {
      final coords = await LocationService.getCurrentLocation();
      if (!mounted) return;

      if (coords != null) {
        final address = await LocationService.reverseGeocode(
          coords,
          googleApiKey,
        );
        if (!mounted) return;
        setState(() {
          _pickupLocation = coords;
          _pickupController.text = (address != null && address.isNotEmpty)
              ? address
              : _fallbackAddress;
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

  /// [Pedido duplicado · 04/10] Trava PRÓPRIA do botão "Continuar para
  /// pagamento" (mesmo defeito do Favor, 03/10): fica true do 1.º toque até o
  /// ecrã de pagamento fechar. Antes, dois toques abriam dois ecrãs de
  /// pagamento e criavam dois pedidos.
  bool _aAbrirPagamento = false;

  Future<void> _goToPayment() async {
    if (_aAbrirPagamento) return;
    setState(() => _aAbrirPagamento = true);
    try {
      await _goToPaymentInner();
    } finally {
      if (mounted) setState(() => _aAbrirPagamento = false);
    }
  }

  Future<void> _goToPaymentInner() async {
    final pickupAddress = _pickupController.text.trim();
    final dropoffAddress = _dropoffController.text.trim();

    if (pickupAddress.isEmpty || dropoffAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Preenche as moradas de recolha e de entrega.'.tr)),
      );
      return;
    }

    if (_pickupLocation == null || _dropoffLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Escolhe uma morada da lista de sugestões.'.tr)),
      );
      return;
    }

    if (_packagePhotoUrl == null || _packagePhotoUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Adiciona uma foto da encomenda — obrigatório.'.tr)),
      );
      return;
    }

    final cart = context.read<CartStore>();
    cart.configureSession(
      serviceType: OrderServiceType.sendPackage,
      isPartnerStore: false,
      requiresCar: !_motoCanCarry,
      pickupLocation: _pickupLocation,
      deliveryLocation: _dropoffLocation,
      pickupStreet: pickupAddress,
      dropoffStreet: dropoffAddress,
    );
    cart.setPackagePhotoUrl(_packagePhotoUrl);

    final ordered = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaymentMethodScreen()),
    );
    // Pedido criado: sai do formulário para os pedidos (como o Favor), para
    // não ficar à mão um segundo "Continuar para pagamento".
    if (ordered == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrdersScreen()),
      );
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
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
        appBar: BoraScreenAppBar(title: 'Enviar Encomenda'.tr),
        bottomNavigationBar: QuotePriceFooter(
          serviceType: OrderServiceType.sendPackage,
          pickup: _pickupLocation,
          dropoff: _dropoffLocation,
        ),
        body: ListView(
          key: _bodyKey,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Morada de recolha'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            // Mostra um indicador subtil enquanto o GPS resolve o endereço.
            Stack(
              children: [
                AddressAutocompleteField(
                  controller: _pickupController,
                  labelText: 'Pesquisar morada de recolha'.tr,
                  prefixIcon: const Icon(Icons.my_location_outlined),
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
            Text(
              'Morada de entrega'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            AddressAutocompleteField(
              controller: _dropoffController,
              labelText: 'Pesquisar morada de entrega'.tr,
              prefixIcon: const Icon(Icons.location_on_outlined),
              onSelected: (address, coords) {
                setState(() => _dropoffLocation = coords);
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            SwitchListTile(
              title: Text(
                  'Um motociclista consegue transportar esta encomenda?'.tr),
              subtitle: Text(
                _motoCanCarry
                    ? 'Sim — motos e carros elegíveis'.tr
                    : 'Não — apenas carros elegíveis',
              ),
              value: _motoCanCarry,
              onChanged: (value) => setState(() => _motoCanCarry = value),
            ),
            const Divider(),
            const SizedBox(height: 16),
            MandatoryPhotoPicker(
              label: 'Foto da encomenda (obrigatória)'.tr,
              hint:
                  'O estafeta vê a foto antes de aceitar. Evita surpresas de tamanho/peso.'.tr,
              pathPrefix: 'package',
              onUploaded: (url) => setState(() => _packagePhotoUrl = url),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _aAbrirPagamento ? null : _goToPayment,
              child: Text('Continuar para pagamento'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
