import 'package:flutter/material.dart';
import 'carry_groceries_form_screen.dart';

class CarryGroceriesScreen extends StatelessWidget {
  const CarryGroceriesScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Entregamos sua compra"),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text("Solicitar entrega"),
          onPressed: () {

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const CarryGroceriesFormScreen(),
              ),
            );

          },
        ),
      ),
    );
  }
}