// 2026-05-21 — A8: Fila offline de transições de estado do estafeta.
// Quando o estafeta perde rede a meio de uma entrega, _advanceStatus()
// falha. Em vez de perder a transição, persistimos {orderId, target} em
// SharedPreferences. Quando a rede voltar (drain via subscribeToOrders ou
// próxima transição bem-sucedida), reprocessamos a fila.
//
// Crítico em zonas rurais da Guarda. Padrão Uber/Glovo.
//
// Aplica-se SÓ a transições do estafeta: pickedUp, onTheWay, delivered.
// pagamentos, criação de ordem, dispatch — não passam por esta fila.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStatusQueue {
  OfflineStatusQueue._();

  static const _key = 'bora.offline_status_queue.v1';

  // Estados elegíveis para fila offline.
  static const _allowedTargets = <String>{
    'pickedUp',
    'onTheWay',
    'delivered',
  };

  /// Acrescenta entrada se ainda não existir.
  static Future<void> enqueue({
    required String orderId,
    required String targetStatusName,
  }) async {
    if (!_allowedTargets.contains(targetStatusName)) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    final entry = '$orderId|$targetStatusName';
    if (list.any((e) => e.startsWith('$entry|'))) return;
    list.add('$entry|${DateTime.now().toUtc().toIso8601String()}');
    await prefs.setStringList(_key, list);
    debugPrint('[OfflineQueue] enqueued: $entry');
  }

  /// Retorna entradas pendentes (ordem FIFO).
  static Future<List<({String orderId, String targetStatusName})>>
      peek() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const <String>[];
    final out = <({String orderId, String targetStatusName})>[];
    for (final s in list) {
      final parts = s.split('|');
      if (parts.length >= 2) {
        out.add((orderId: parts[0], targetStatusName: parts[1]));
      }
    }
    return out;
  }

  /// Remove uma entrada específica (chamado após retry com sucesso).
  static Future<void> remove({
    required String orderId,
    required String targetStatusName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    final prefix = '$orderId|$targetStatusName|';
    list.removeWhere((s) => s.startsWith(prefix));
    await prefs.setStringList(_key, list);
  }

  static Future<int> size() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const <String>[]).length;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
