import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_card.dart';
import 'payment_service.dart';

/// Erro de gestão da carteira de cartões, com mensagem já em PT-PT pronta a
/// mostrar ao cliente.
class CardWalletException implements Exception {
  const CardWalletException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Carteira Única de Cartão — camada Dart sobre os cartões guardados no Stripe.
///
/// Nome deliberadamente `CardWalletService` e não `WalletService`: já existe
/// `wallet_service.dart` para o **saldo Bora** (saldo livre + tokens). São duas
/// carteiras diferentes e não se devem confundir.
///
/// Leitura: Edge Fn `list-saved-cards` (via [PaymentService.fetchSavedCards]).
/// Escrita: Edge Fn `manage-saved-cards` (`detach` / `set_default`).
///
/// O **cartão padrão** é guardado localmente em SharedPreferences e só depois
/// sincronizado com o Stripe. Assim a escolha do cliente vale de imediato neste
/// telemóvel, mesmo que a chamada de rede falhe — é a preferência que o
/// checkout (Partes 2 a 4) lê para pré-seleccionar o cartão.
///
/// Nenhum método aqui cobra, reembolsa ou altera valores.
class CardWalletService {
  CardWalletService({PaymentService? paymentService, SupabaseClient? supabase})
      : _payments = paymentService ?? PaymentService(),
        _supabaseOverride = supabase;

  static final CardWalletService instance = CardWalletService();

  /// Chave da preferência local do cartão padrão.
  static const String defaultCardPrefKey = 'bora_wallet.default_pm_id';

  final PaymentService _payments;
  final SupabaseClient? _supabaseOverride;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  /// Lista os cartões guardados, com [SavedCard.isDefault] já a reflectir a
  /// preferência local (que ganha à do Stripe).
  ///
  /// Devolve lista vazia se o cliente ainda nunca pagou com cartão. Nunca lança
  /// — a leitura é best-effort, tal como [PaymentService.fetchSavedCards].
  Future<List<SavedCard>> listCards() async {
    final cards = await _payments.fetchSavedCards();
    if (cards.isEmpty) return const [];

    final localId = await getDefaultCardId();
    if (localId == null) return cards;

    // Preferência local aponta para um cartão que já não existe (removido
    // noutro dispositivo): limpa e fica com o que o Stripe diz.
    if (!cards.any((c) => c.id == localId)) {
      await clearDefaultCard();
      return cards;
    }

    return [
      for (final c in cards)
        SavedCard(
          id: c.id,
          brand: c.brand,
          last4: c.last4,
          expMonth: c.expMonth,
          expYear: c.expYear,
          isDefault: c.id == localId,
        ),
    ];
  }

  /// Id (`pm_...`) do cartão padrão escolhido neste telemóvel, ou `null`.
  Future<String?> getDefaultCardId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(defaultCardPrefKey);
  }

  /// O cartão padrão a usar no checkout: a preferência local se ainda for
  /// válida, senão o predefinido do Stripe, senão o primeiro da lista.
  ///
  /// `null` significa "não há cartão guardado" — o checkout cai no PaymentSheet.
  Future<SavedCard?> defaultCard() async {
    final cards = await listCards();
    if (cards.isEmpty) return null;
    for (final c in cards) {
      if (c.isDefault) return c;
    }
    return cards.first;
  }

  /// Define o cartão padrão. Grava sempre a preferência local (efeito imediato)
  /// e tenta sincronizar com o Stripe — se a sincronização falhar, a escolha
  /// local mantém-se e o cliente não vê erro.
  Future<void> setDefaultCard(String paymentMethodId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(defaultCardPrefKey, paymentMethodId);
    try {
      await _invoke('set_default', paymentMethodId);
    } catch (e) {
      debugPrint('[CardWalletService] set_default não sincronizou: $e');
    }
  }

  /// Esquece a preferência local (não mexe no Stripe).
  Future<void> clearDefaultCard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(defaultCardPrefKey);
  }

  /// Remove um cartão guardado (detach no Stripe).
  ///
  /// Ao contrário do padrão, isto **não** tem alternativa local: se a Edge Fn
  /// falhar, lança [CardWalletException] para o ecrã poder avisar o cliente em
  /// vez de fingir que removeu.
  Future<void> removeCard(String paymentMethodId) async {
    await _invoke('detach', paymentMethodId);
    final current = await getDefaultCardId();
    if (current == paymentMethodId) await clearDefaultCard();
  }

  Future<void> _invoke(String action, String paymentMethodId) async {
    try {
      final res = await _supabase.functions.invoke(
        'manage-saved-cards',
        body: {'action': action, 'payment_method_id': paymentMethodId},
      );
      if (res.status >= 400) {
        throw CardWalletException(_messageFor(res.status, res.data));
      }
    } on CardWalletException {
      rethrow;
    } catch (e) {
      debugPrint('[CardWalletService] $action falhou: $e');
      throw const CardWalletException(
          'Não foi possível contactar o servidor. Tenta de novo.');
    }
  }

  String _messageFor(int status, dynamic data) {
    final code = (data is Map ? data['error'] : null)?.toString() ?? '';
    switch (code) {
      case 'not_your_card':
        return 'Esse cartão não pertence a esta conta.';
      case 'no_customer':
        return 'Ainda não tens cartões guardados.';
      case 'invalid_payment_method_id':
      case 'invalid_action':
        return 'Pedido inválido.';
      default:
        return 'Não foi possível concluir a operação (erro $status).';
    }
  }
}
