import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/tvde_conformidade_service.dart';

/// Botão de emergência (SOS) durante a viagem TVDE — Lei 45/2018 na versão da
/// Lei 59/2026 (arts. 17.º-A n.º 2 e) e 19.º n.º 1 j)).
///
/// Serve ao passageiro e ao motorista. Abre uma folha com duas ações:
/// **Ligar 112** e **Partilhar a minha localização** (link do mapa pela
/// partilha nativa — SMS, WhatsApp, etc.). Cada ação fica registada no
/// servidor e avisa o admin. O registo nunca atrasa a chamada: o 112 abre
/// primeiro, o registo segue em segundo plano.
class TvdeSosButton extends StatelessWidget {
  const TvdeSosButton({super.key, required this.rideId, this.compacto = false});

  final String rideId;

  /// Só o ícone (para barras apertadas).
  final bool compacto;

  static const _vermelho = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    if (compacto) {
      return IconButton(
        key: const Key('tvde_sos_button'),
        tooltip: 'Emergência (SOS)',
        icon: const Icon(Icons.sos, color: _vermelho),
        onPressed: () => abrirFolhaSos(context, rideId),
      );
    }
    return OutlinedButton.icon(
      key: const Key('tvde_sos_button'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _vermelho,
        side: const BorderSide(color: _vermelho),
      ),
      icon: const Icon(Icons.sos),
      label: const Text('SOS'),
      onPressed: () => abrirFolhaSos(context, rideId),
    );
  }
}

Future<Position?> _posicaoRapida() async {
  try {
    final ultima = await Geolocator.getLastKnownPosition();
    if (ultima != null) return ultima;
  } catch (_) {}
  try {
    return await Geolocator.getCurrentPosition()
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    return null;
  }
}

Future<void> abrirFolhaSos(BuildContext context, String rideId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Emergência',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Se estás em perigo, liga já para o 112. Também podes enviar '
                'a tua localização a alguém de confiança.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('tvde_sos_ligar_112'),
              style: FilledButton.styleFrom(
                  backgroundColor: TvdeSosButton._vermelho,
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.call),
              label: const Text('Ligar 112'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await launchUrl(Uri(scheme: 'tel', path: '112'));
                unawaited(_registar(rideId, ligou112: true));
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('tvde_sos_partilhar'),
              style:
                  OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.share_location),
              label: const Text('Partilhar a minha localização'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final pos = await _posicaoRapida();
                final codigo = rideId.replaceAll('-', '').substring(0, 8).toUpperCase();
                final link = pos == null
                    ? ''
                    : ' https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
                await Share.share(
                    'Preciso de ajuda. Estou numa viagem Bora (código $codigo).$link');
                unawaited(_registar(rideId,
                    partilhou: true, lat: pos?.latitude, lng: pos?.longitude));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _registar(String rideId,
    {bool ligou112 = false, bool partilhou = false, double? lat, double? lng}) async {
  try {
    Position? pos;
    if (lat == null) pos = await _posicaoRapida();
    await TvdeConformidadeService.instance.registarSos(
      rideId: rideId,
      lat: lat ?? pos?.latitude,
      lng: lng ?? pos?.longitude,
      ligou112: ligou112,
      partilhou: partilhou,
    );
  } catch (e) {
    debugPrint('[TvdeSos] registo falhou (a chamada já foi feita): $e');
  }
}
