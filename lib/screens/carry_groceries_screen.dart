import 'package:flutter/material.dart';

import '../widgets/bora/bora_screen_app_bar.dart';
import 'carry_groceries_form_screen.dart';

import '../l10n/tr.dart';

class CarryGroceriesScreen extends StatelessWidget {
  const CarryGroceriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Levar Compras'.tr),
      body: Center(
        child: ElevatedButton(
          child: Text('Solicitar entrega'.tr),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CarryGroceriesFormScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}
