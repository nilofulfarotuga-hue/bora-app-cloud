import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../models/driver_model.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';


class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authStore = context.watch<AuthStore>();
    final driverStore = context.watch<DriverStore>();

    if (!authStore.isLogged) {
      return const Center(child: Text('Sessão terminada.'));
    }

    final role = authStore.role;
    final user = Supabase.instance.client.auth.currentUser;
    final title = () {
      switch (role) {
        case AuthRole.driver:
          return 'Perfil do estafeta';
        case AuthRole.partner:
          return 'Perfil do parceiro';
        default:
          return 'Perfil do cliente';
      }
    }();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authStore.displayName ?? 'Utilizador',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (role == AuthRole.client) ...[
              _InfoRow(
                label: 'Email',
                value: authStore.currentClient?.email ?? '-',
              ),
              _InfoRow(
                label: 'Telemóvel',
                value: authStore.currentClient?.phone ?? '-',
              ),
              const SizedBox(height: 12),
              _TokenBalanceRow(),
            ] else if (role == AuthRole.driver) ...[
              _InfoRow(
                label: 'Telemóvel',
                value: authStore.currentDriver?.phone ?? '-',
              ),
              _InfoRow(
                label: 'Veículo',
                value: driverStore.currentVehicleType.label,
              ),
              _InfoRow(
                label: 'Matrícula',
                value: authStore.currentDriver?.licensePlate ?? '-',
              ),
              const SizedBox(height: 12),
              _TokenBalanceRow(),
              const SizedBox(height: 4),
              const Text(
                'Serviços disponíveis',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ..._vehicleCapabilities(driverStore.currentVehicleType)
                  .map((capability) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.check, size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(child: Text(capability)),
                          ],
                        ),
                      )),
            ] else if (role == AuthRole.partner) ...[
              _InfoRow(
                label: 'Email',
                value: authStore.currentPartner?.email ?? '-',
              ),
              _InfoRow(
                label: 'Telefone',
                value: authStore.currentPartner?.phone ?? '-',
              ),
              _InfoRow(
                label: 'Endereço',
                value: authStore.currentPartner?.address ?? '-',
              ),
              _InfoRow(
                label: 'Tipo de cozinha',
                value: authStore.currentPartner?.cuisineType ?? '-',
              ),
            ],
            if (user?.email == 'nilofulfarotuga@gmail.com') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/admin');
                  },
                  child: const Text('Painel Admin'),
                ),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                                onPressed: () async {
                  authStore.logout();
                  await context.read<SessionStore>().clearRole();
                  if (!context.mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },

                icon: const Icon(Icons.logout),
                label: const Text('Terminar sessão'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _vehicleCapabilities(VehicleType type) {
    if (type == VehicleType.motorcycle) {
      return const [
        'Restaurantes parceiros e não parceiros',
        'Pequenas compras em loja',
      ];
    }
    return const [
      'Restaurantes',
      'Compras em loja',
      'Entregar compras',
      'Enviar pacotes e caixas',
    ];
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }
}

// ─── Token balance row ────────────────────────────────────────────────────────
// Fetches the active token balance via get_user_tokens() RPC and displays it.
// Works for both client and driver — uses the currently authenticated user ID.

class _TokenBalanceRow extends StatelessWidget {
  _TokenBalanceRow();

  final _client = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: _client
          .rpc('get_user_tokens', params: {'p_user_id': userId})
          .then((v) => (v as int?) ?? 0),
      builder: (context, snapshot) {
        final balance = snapshot.data ?? 0;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bora Tokens',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.amber,
                          ),
                        )
                      : Text(
                          '$balance tokens',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}