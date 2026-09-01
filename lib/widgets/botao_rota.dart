import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';

import '../l10n/tr.dart';

/// ABRIR A ROTA — o botão que faltava à limpeza e à lavagem.
///
/// O motorista tem mapa e rota; quem vai limpar uma casa ou buscar um carro
/// tinha só a morada escrita e ficava a copiá-la à mão para o Google Maps.
/// O Danilo apontou isso a 2026-08-29 e disse que não era urgente — por isso
/// isto é o mínimo honesto: não é um mapa dentro da app, é o botão que leva à
/// aplicação de mapas que a pessoa já tem e já sabe usar.
///
/// Prefere coordenadas quando existem; sem elas, procura pela morada escrita.
class BotaoRota extends StatelessWidget {
  const BotaoRota({
    super.key,
    required this.morada,
    this.lat,
    this.lng,
    this.compacto = false,
  });

  final String morada;
  final double? lat;
  final double? lng;
  final bool compacto;

  Uri? get _uri {
    if (lat != null && lng != null) {
      return Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    }
    final m = morada.trim();
    if (m.isEmpty) return null;
    return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(m)}');
  }

  Future<void> _abrir(BuildContext context) async {
    final u = _uri;
    if (u == null) return;
    // `mode: externalApplication` porque o que se quer é a app de mapas, não
    // uma página dentro da nossa.
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não foi possível abrir os mapas neste telemóvel.'.tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uri == null) return const SizedBox.shrink();
    if (compacto) {
      return IconButton(
        tooltip: 'Abrir rota'.tr,
        icon: const Icon(Icons.directions, color: AppColors.primary),
        onPressed: () => _abrir(context),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _abrir(context),
      icon: const Icon(Icons.directions, size: 18),
      label: Text('Abrir rota'.tr),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
    );
  }
}
