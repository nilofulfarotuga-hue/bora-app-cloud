import 'package:flutter/material.dart';
import 'send_package_form_screen.dart';

class SendPackageScreen extends StatelessWidget {
  const SendPackageScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Enviar caixa"),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text("Criar envio"),
          onPressed: () {

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const SendPackageFormScreen(),
              ),
            );

          },
        ),
      ),
    );
  }
}