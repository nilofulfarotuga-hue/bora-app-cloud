import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
              const SizedBox(height: 16),
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