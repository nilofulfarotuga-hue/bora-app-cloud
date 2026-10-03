import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationService {
  const NavigationService._();

  static Future<void> openNavigationOptions(
    BuildContext context,
    LatLng destination,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.directions_car, color: Colors.blue),
                title: const Text("Abrir no Google Maps"),
                onTap: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}',
                  );
                  await _launchUri(context, uri);
                },
              ),
              ListTile(
                leading: const Icon(Icons.navigation, color: Colors.deepPurple),
                title: const Text("Abrir no Waze"),
                onTap: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse(
                    'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes',
                  );
                  await _launchUri(context, uri);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Abre a navegação passo-a-passo DIRETAMENTE (sem folha de escolha).
  /// Regra de 13/09: depois de fechar o talão o estafeta segue logo para a
  /// morada do cliente, sem ecrã intermédio. Tenta a app do Google Maps em
  /// modo condução; se não abrir, cai no endereço web de direcções (que o
  /// sistema entrega à app de mapas instalada). Devolve `false` se nada abriu.
  static Future<bool> openTurnByTurn(LatLng destination) async {
    final lat = destination.latitude;
    final lng = destination.longitude;
    final candidates = <Uri>[
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      ),
    ];
    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {
        // esquema não suportado nesta plataforma: tenta o seguinte
      }
    }
    return false;
  }

  static Future<void> _launchUri(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Não foi possível abrir a navegação.")),
      );
    }
  }
}
