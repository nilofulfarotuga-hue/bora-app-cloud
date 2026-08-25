// CORREÇÃO 4 (2026-08-25, caso real Continente) — rascunho local da ida ao
// mercado.
//
// O estafeta saiu da app a meio da ida ao mercado e perdeu tudo o que já
// tinha marcado, tendo de escolher os artigos outra vez. A lista só existia
// na memória do `_ShoppingListSheetContent` — fechar a folha (ou o Android
// matar o processo enquanto a câmara está aberta, ver F4/2026-08-16) apagava
// o progresso.
//
// Aqui guarda-se, em SharedPreferences, o estado por pedido: cada artigo com
// o seu `purchaseStatus` (comprado / em falta / pendente), os artigos extra
// que o estafeta adicionou e o número de sacos. Só progresso do estafeta —
// nada de dinheiro, nada de preços novos: os preços vêm sempre do pedido.
//
// O rascunho é apagado assim que a compra é finalizada com sucesso, e
// expira sozinho ao fim de [_maxAge] para não ressuscitar listas velhas.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';

class StoreShoppingDraft {
  StoreShoppingDraft({
    required this.items,
    required this.bagCount,
    required this.savedAt,
  });

  final List<CartItem> items;
  final int bagCount;
  final DateTime savedAt;
}

class StoreShoppingDraftService {
  static const String _prefix = 'bora_app.store_shopping_draft.';

  /// Um turno dá e sobra. Passado isto, o rascunho é lixo (o pedido já
  /// terá seguido) e é descartado em silêncio.
  static const Duration _maxAge = Duration(hours: 12);

  static String _key(String orderId) => '$_prefix$orderId';

  /// Grava o progresso. Best-effort — nunca lança para a UI.
  static Future<void> save({
    required String orderId,
    required List<CartItem> items,
    required int bagCount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().toIso8601String(),
        'bag_count': bagCount,
        'items': items.map((i) => i.toJson()).toList(),
      };
      await prefs.setString(_key(orderId), jsonEncode(payload));
    } catch (e) {
      debugPrint('[bora-rascunho] falhou a gravar rascunho de $orderId: $e');
    }
  }

  /// Lê o progresso guardado. Devolve null se não houver, se estiver
  /// expirado ou se estiver corrompido (nesse caso limpa-o).
  static Future<StoreShoppingDraft?> load(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(orderId));
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear(orderId);
        return null;
      }
      final savedAt =
          DateTime.tryParse((decoded['saved_at'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
      if (DateTime.now().difference(savedAt) > _maxAge) {
        await clear(orderId);
        return null;
      }
      final rawItems = decoded['items'];
      if (rawItems is! List) {
        await clear(orderId);
        return null;
      }
      final items = <CartItem>[];
      for (final e in rawItems) {
        if (e is Map) {
          try {
            items.add(CartItem.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Linha corrompida não estraga o resto do rascunho.
          }
        }
      }
      if (items.isEmpty) return null;
      return StoreShoppingDraft(
        items: items,
        bagCount: (decoded['bag_count'] as num?)?.toInt() ?? 1,
        savedAt: savedAt,
      );
    } catch (e) {
      debugPrint('[bora-rascunho] falhou a ler rascunho de $orderId: $e');
      return null;
    }
  }

  /// Apaga o rascunho (compra finalizada ou pedido encerrado).
  static Future<void> clear(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(orderId));
    } catch (e) {
      debugPrint('[bora-rascunho] falhou a apagar rascunho de $orderId: $e');
    }
  }
}
