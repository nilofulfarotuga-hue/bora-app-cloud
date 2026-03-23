import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../stores/session_store.dart';


class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BORA"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Escolha seu modo",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

                        ElevatedButton(
              onPressed: () async {
                final authStore = context.read<AuthStore>();
                final sessionStore = context.read<SessionStore>();

                authStore.logout();
                await sessionStore.setRole(UserRole.client);
                // _RootNavigator reacts automatically to SessionStore changes.
              },
              child: const Text("Sou Cliente"),
            ),


            const SizedBox(height: 20),

                        ElevatedButton(
              onPressed: () async {
                final authStore = context.read<AuthStore>();
                final sessionStore = context.read<SessionStore>();

                authStore.logout();
                await sessionStore.setRole(UserRole.driver);
                // _RootNavigator reacts automatically to SessionStore changes.
              },
              child: const Text("Sou Estafeta"),
            ),


            const SizedBox(height: 20),

                        ElevatedButton(
              onPressed: () async {
                final authStore = context.read<AuthStore>();
                final sessionStore = context.read<SessionStore>();

                authStore.logout();
                await sessionStore.setRole(UserRole.partner);
                // _RootNavigator reacts automatically to SessionStore changes.
              },
              child: const Text("Sou Parceiro"),
            ),

          ],
        ),
      ),
    );
  }
}