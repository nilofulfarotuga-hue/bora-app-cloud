import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Avaliações que não conseguiram sair — guardadas para irem mais tarde.
///
/// **Cicatriz (corrida real, 05/09/2026):** o passageiro ficou preso no ecrã
/// de avaliação. A regra que ficou é que a avaliação nunca segura ninguém: se
/// o envio não fechar em poucos segundos, guarda-se aqui e o ecrã fecha na
/// mesma. A corrida já acabou e o dinheiro já está resolvido — uma estrela
/// não pode ser uma porta fechada.
///
/// A nova tentativa acontece quando um ecrã de avaliação voltar a abrir
/// ([flush]). É de propósito modesta: não há temporizador de fundo nem
/// insistência, porque uma avaliação atrasada não faz mal a ninguém.
class PendingRatingQueue {
  PendingRatingQueue._();

  /// Avaliação do motorista feita pelo passageiro.
  static const String kindDriver = 'driver';

  /// Avaliação do passageiro feita pelo motorista.
  static const String kindPassenger = 'passenger';

  static const String _prefsKey = 'bora_rating.pending';

  /// Tecto da fila. Sem isto, um telemóvel sempre sem rede juntaria
  /// avaliações para sempre dentro das preferências.
  static const int _max = 20;

  /// Tecto de espera de cada reenvio. A fila corre em fundo; se o servidor
  /// não responder, fica para a próxima abertura em vez de pendurar.
  static const Duration _timeoutReenvio = Duration(seconds: 8);

  /// Guarda uma avaliação por enviar.
  ///
  /// Nunca lança. Devolve `false` se nem sequer conseguiu guardar — nesse
  /// caso o ecrã diz a verdade ao utilizador em vez de prometer um envio.
  static Future<bool> save({
    required String kind,
    required String rideId,
    required int stars,
    String? comment,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fila = _ler(prefs);
      // A mesma corrida entra uma vez só: reavaliar substitui o que lá estava.
      fila.removeWhere((e) => e['kind'] == kind && e['rideId'] == rideId);
      fila.add(<String, dynamic>{
        'kind': kind,
        'rideId': rideId,
        'stars': stars,
        'comment': comment,
      });
      while (fila.length > _max) {
        fila.removeAt(0);
      }
      await prefs.setString(_prefsKey, jsonEncode(fila));
      return true;
    } catch (e) {
      debugPrint('PendingRatingQueue.save erro => $e');
      return false;
    }
  }

  /// Tenta reenviar as avaliações de [kind] com [enviar].
  ///
  /// As que passam saem da fila; as que falham ficam para a próxima. Nunca
  /// lança — quem chama pode esquecer o resultado.
  static Future<void> flush(
    String kind,
    Future<void> Function(String rideId, int stars, String? comment) enviar,
  ) async {
    final SharedPreferences prefs;
    final List<Map<String, dynamic>> fila;
    try {
      prefs = await SharedPreferences.getInstance();
      fila = _ler(prefs);
    } catch (e) {
      debugPrint('PendingRatingQueue.flush leitura => $e');
      return;
    }
    if (fila.isEmpty) return;

    final sobram = <Map<String, dynamic>>[];
    for (final e in fila) {
      if (e['kind'] != kind) {
        sobram.add(e);
        continue;
      }
      try {
        await enviar(
          e['rideId'] as String,
          e['stars'] as int,
          e['comment'] as String?,
        ).timeout(_timeoutReenvio);
      } catch (err) {
        debugPrint('PendingRatingQueue.flush envio => $err');
        // Erro definitivo (a avaliação JÁ lá está, ou nunca vai poder
        // entrar) sai da fila. Sem isto, o caso mais provável de todos —
        // a RPC chegou ao servidor e nós é que desistimos de esperar —
        // ficava a bater no `already_rated` para sempre.
        if (!_definitivo(err)) sobram.add(e);
      }
    }
    if (sobram.length == fila.length) return;

    try {
      if (sobram.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, jsonEncode(sobram));
      }
    } catch (e) {
      debugPrint('PendingRatingQueue.flush escrita => $e');
    }
  }

  /// Recusas que a RPC `tvde_rate` levanta e que nunca mudam de ideias.
  /// Tudo o resto (rede, timeout, servidor em baixo) merece nova tentativa.
  static const List<String> _recusasDefinitivas = <String>[
    'already_rated',
    'invalid_stars',
    'ride_not_found',
    'ride_not_finished',
    'not_ride_party',
  ];

  static bool _definitivo(Object err) {
    final texto = err.toString();
    return _recusasDefinitivas.any((r) => texto.contains(r));
  }

  static List<Map<String, dynamic>> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final lista = jsonDecode(raw);
      if (lista is! List) return <Map<String, dynamic>>[];
      return lista
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('PendingRatingQueue._ler erro => $e');
      return <Map<String, dynamic>>[];
    }
  }
}
