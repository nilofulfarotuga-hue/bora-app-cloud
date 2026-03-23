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

  static Future<void> _launchUri(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Não foi possível abrir a navegação.")),
      );
    }
  }
}
