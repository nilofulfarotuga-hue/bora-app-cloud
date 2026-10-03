import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/maps_config.dart';
import '../models/client_address.dart';
import 'client_address_service.dart';
import 'location_service.dart';

/// Morada preenchida sozinha, em todos os ecrãs onde o cliente escreve uma.
///
/// Extraído do `_detectLocation` do `client_home_screen`, que já fazia isto
/// bem — em vez de cada ecrã reinventar o mecanismo. Mesma cascata:
///
///   1. morada preferida guardada (`client_addresses`, a marcada por defeito)
///   2. morada de "Casa" (`SessionStore`)
///   3. GPS + reverse geocoding
///
/// REGRA DE 24/08, INVIOLÁVEL: **a localização nunca trava**.
/// Isto NUNCA lança e NUNCA bloqueia. Se não houver morada guardada, nem casa,
/// nem GPS (negado, desligado, sem sinal ou lento), devolve simplesmente
/// `null` — e o ecrã fica com o campo vazio e escrevível, sem erro nem
/// pop-up. O preenchimento automático é um presente, nunca uma condição.
@immutable
class MoradaSugerida {
  /// Linha de morada para pôr no campo.
  final String morada;

  /// Coordenadas, quando se souberem. Podem ser null com morada preenchida
  /// (por exemplo uma morada guardada sem lat/lng) — e isso está certo:
  /// o servidor só valida o raio quando há coordenadas.
  final LatLng? coords;

  /// De onde veio — só para diagnóstico/telemetria, não para o utilizador.
  final String origem; // 'guardada' | 'casa' | 'gps'

  const MoradaSugerida({
    required this.morada,
    required this.coords,
    required this.origem,
  });
}

class AutoAddress {
  AutoAddress._();

  /// Tenta descobrir onde o cliente está. Devolve null quando não dá —
  /// e não dar é um resultado perfeitamente normal.
  ///
  /// [homeStreet] / [homeCity] / [homeLocation] vêm do `SessionStore` (o ecrã
  /// passa-os; assim este ficheiro não depende de Provider e dá para testar).
  /// [preferirGps] força ir direto ao GPS, para ecrãs em que interessa mesmo
  /// onde a pessoa está agora (ex.: onde está o carro) e não a morada de casa.
  static Future<MoradaSugerida?> descobrir({
    String? homeStreet,
    String? homeCity,
    LatLng? homeLocation,
    bool preferirGps = false,
  }) async {
    if (!preferirGps) {
      // 1) morada preferida guardada
      try {
        final lista = await ClientAddressService.instance.list();
        ClientAddress? preferida;
        for (final a in lista) {
          if (a.isDefault) {
            preferida = a;
            break;
          }
        }
        preferida ??= lista.isNotEmpty ? lista.first : null;
        if (preferida != null && preferida.address.trim().isNotEmpty) {
          return MoradaSugerida(
            morada: preferida.address,
            coords: (preferida.lat != null && preferida.lng != null)
                ? LatLng(preferida.lat!, preferida.lng!)
                : null,
            origem: 'guardada',
          );
        }
      } catch (_) {
        // sem rede ou sem sessão — segue para casa/GPS
      }

      // 2) morada de casa
      if ((homeStreet ?? '').trim().isNotEmpty) {
        final linha = [homeStreet!.trim(), (homeCity ?? '').trim()]
            .where((s) => s.isNotEmpty)
            .join(', ');
        return MoradaSugerida(
          morada: linha,
          coords: homeLocation,
          origem: 'casa',
        );
      }
    }

    // 3) GPS. `getCurrentLocation` já devolve null em qualquer falha
    //    (consentimento negado, serviço desligado, permissão recusada) e
    //    nunca lança — por isso não há aqui nada a "tratar".
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null) return null;
      final texto = await LocationService.reverseGeocode(pos, googleApiKey);
      if (texto == null || texto.trim().isEmpty) {
        // Sabemos onde está mas não sabemos o nome da rua: não vale a pena
        // escrever coordenadas no campo — devolve null e o cliente escreve.
        return null;
      }
      return MoradaSugerida(morada: texto, coords: pos, origem: 'gps');
    } catch (e) {
      debugPrint('AutoAddress: $e');
      return null;
    }
  }
}
