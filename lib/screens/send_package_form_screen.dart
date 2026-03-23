import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../models/order_model.dart';
import '../data/postal_coordinates.dart';
import '../stores/order_store.dart';




class SendPackageFormScreen extends StatefulWidget {

  const SendPackageFormScreen({super.key});

  @override
  State<SendPackageFormScreen> createState() => _SendPackageFormScreenState();
}

class _SendPackageFormScreenState extends State<SendPackageFormScreen> {
  final pickupStreetController = TextEditingController();
  final pickupCityController = TextEditingController(text: "Lisboa");
  final pickupPostalController = TextEditingController();

  final destinationStreetController = TextEditingController();
  final destinationCityController = TextEditingController(text: "Lisboa");
  final destinationPostalController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    pickupStreetController.dispose();
    pickupCityController.dispose();
    pickupPostalController.dispose();
    destinationStreetController.dispose();
    destinationCityController.dispose();
    destinationPostalController.dispose();
    super.dispose();
  }

  Future<void> createOrder() async {
    final pickupStreet = pickupStreetController.text.trim();
    final pickupCity = pickupCityController.text.trim();
    final pickupPostal = pickupPostalController.text.trim();
    final destinationStreet = destinationStreetController.text.trim();
    final destinationCity = destinationCityController.text.trim();
    final destinationPostal = destinationPostalController.text.trim();

    if (pickupStreet.isEmpty || destinationStreet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha todos os campos obrigatórios.")),
      );
      return;
    }

    final pickupLocation = _locationForPostal(pickupPostal);
    final dropoffLocation = _locationForPostal(destinationPostal);

    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();

    setState(() => _isLoading = true);

    final success = await orderStore.createOrder(
      serviceType: OrderServiceType.sendPackage,
      itemsSubtotal: 0,
      destination: dropoffLocation,
      paymentMethod: PaymentMethod.cash,
      pickupLocation: pickupLocation,
      isPartnerStore: false,
      pickupAddress: "$pickupStreet, $pickupCity",
      pickupStreet: pickupStreet,
      pickupCity: pickupCity,
      pickupPostalCode: pickupPostal,
      dropoffAddress: "$destinationStreet, $destinationCity",
      dropoffStreet: destinationStreet,
      dropoffCity: destinationCity,
      dropoffPostalCode: destinationPostal,
      clientPhone: authStore.currentClient?.phone,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Não foi possível criar o pedido. Verifique os logs para mais detalhes."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pedido criado com sucesso!")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enviar pacote")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              "Endereço de recolha",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pickupStreetController,
              decoration: const InputDecoration(
                labelText: "Rua e número",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pickupCityController,
              decoration: const InputDecoration(
                labelText: "Cidade",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pickupPostalController,
              decoration: const InputDecoration(
                labelText: "Código postal",
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Endereço de entrega",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: destinationStreetController,
              decoration: const InputDecoration(
                labelText: "Rua e número",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: destinationCityController,
              decoration: const InputDecoration(
                labelText: "Cidade",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: destinationPostalController,
              decoration: const InputDecoration(
                labelText: "Código postal",
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : createOrder,
              child: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Criar pedido"),
            ),
          ],
        ),
      ),
    );
  }

    LatLng _locationForPostal(String postal) {
    return PostalCoordinateHelper.coordinateFor(postal);
  }
}