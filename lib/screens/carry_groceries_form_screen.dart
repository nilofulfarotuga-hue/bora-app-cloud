import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../models/order_model.dart';
import '../data/postal_coordinates.dart';

import '../stores/order_store.dart';




class CarryGroceriesFormScreen extends StatefulWidget {
  const CarryGroceriesFormScreen({super.key});

  @override
  State<CarryGroceriesFormScreen> createState() => _CarryGroceriesFormScreenState();
}

class _CarryGroceriesFormScreenState extends State<CarryGroceriesFormScreen> {
  final storeStreetController = TextEditingController();
  final storeCityController = TextEditingController(text: "Lisboa");
  final storePostalController = TextEditingController();

  final destinationStreetController = TextEditingController();
  final destinationCityController = TextEditingController(text: "Lisboa");
  final destinationPostalController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    storeStreetController.dispose();
    storeCityController.dispose();
    storePostalController.dispose();
    destinationStreetController.dispose();
    destinationCityController.dispose();
    destinationPostalController.dispose();
    super.dispose();
  }

  Future<void> createOrder() async {
    final storeStreet = storeStreetController.text.trim();
    final storeCity = storeCityController.text.trim();
    final storePostal = storePostalController.text.trim();
    final destinationStreet = destinationStreetController.text.trim();
    final destinationCity = destinationCityController.text.trim();
    final destinationPostal = destinationPostalController.text.trim();

    if (storeStreet.isEmpty || destinationStreet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha todos os campos obrigatórios.")),
      );
      return;
    }

    final pickupLocation = _locationForPostal(storePostal);
    final dropoffLocation = _locationForPostal(destinationPostal);

    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();

    setState(() => _isLoading = true);

    final success = await orderStore.createOrder(
      serviceType: OrderServiceType.carryGroceries,
      itemsSubtotal: 0,
      destination: dropoffLocation,
      paymentMethod: PaymentMethod.cash,
      pickupLocation: pickupLocation,
      isPartnerStore: false,
      pickupAddress: "$storeStreet, $storeCity",
      pickupStreet: storeStreet,
      pickupCity: storeCity,
      pickupPostalCode: storePostal,
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
      appBar: AppBar(title: const Text("Entregar compras")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              "Local da loja",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: storeStreetController,
              decoration: const InputDecoration(
                labelText: "Rua e número",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: storeCityController,
              decoration: const InputDecoration(
                labelText: "Cidade",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: storePostalController,
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