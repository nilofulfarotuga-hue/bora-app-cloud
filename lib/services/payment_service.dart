import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_card.dart';

class PaymentService {
  // ─── Primary API (called by OrderStore) ──────────────────────────────────

  /// Creates a Stripe PaymentIntent via the Supabase Edge Function.
  /// [amount] is in euros — the server converts to cents internally.
  /// The Edge Function re-validates the amount against the DB when a real
  /// [orderId] is provided (not a 'direct-' stub).
  ///
  /// Returns { 'clientSecret': String, 'paymentIntentId': String }
  ///
  /// Throws [Exception] on function / Stripe errors.
  Future<Map<String, dynamic>> createPaymentIntent({
    required String orderId,
    required double amount,
  }) async {
    if (kIsWeb) throw StateError('Card payments are only supported on mobile.');

    final response = await Supabase.instance.client.functions.invoke(
      'create-payment-intent',
      body: {'order_id': orderId, 'amount': amount},
    );

    final body = response.data as Map<String, dynamic>?;
    if (body == null ||
        body['clientSecret'] == null ||
        body['paymentIntentId'] == null) {
      throw Exception(
          '[PaymentService] create-payment-intent: incomplete response: $body');
    }
    debugPrint('[PaymentService] intent created: ${body['paymentIntentId']}');
    return body;
  }

  /// Presents the Stripe payment sheet for [clientSecret] and awaits the user.
  ///
  /// Throws [StripeException] if the user cancels or the card is declined.
  /// Throws [StateError] on web (unsupported).
  Future<void> processPayment(String clientSecret) async {
    if (kIsWeb) throw StateError('Card payments are only supported on mobile.');

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'BORA APP',
        style: ThemeMode.system,
        // 2026-05-14: nome do titular obrigatorio no PaymentSheet.
        // PCI-safe — Stripe UI nativa colecta o nome (NAO TextFormField separado).
        billingDetailsCollectionConfiguration:
            const BillingDetailsCollectionConfiguration(
          name: CollectionMode.always,
          email: CollectionMode.never,
          phone: CollectionMode.never,
          address: AddressCollectionMode.never,
        ),
        // Apple Pay (iOS) — funciona out-of-the-box em Portugal Stripe LIVE.
        applePay: const PaymentSheetApplePay(
          merchantCountryCode: 'PT',
        ),
        // 2026-05-14: Google Pay activado (PT/EUR, live mode).
        // Pre-requisitos operacionais:
        //   1. Stripe Dashboard → Settings → Payment methods → Google Pay ON.
        //   2. AndroidManifest.xml com gms.wallet.api.enabled meta-data.
        //   3. Google Play Console com SHA-1 da release key registado.
        // Stripe degrada graciosamente se nao configurado (sem opcao no sheet,
        // sem crash).
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'PT',
          currencyCode: 'EUR',
          testEnv: false,
        ),
      ),
    );
    await Stripe.instance.presentPaymentSheet();
    debugPrint('[PaymentService] payment sheet completed successfully');
  }

  /// Issues a partial refund against an existing PaymentIntent.
  /// [amount] is in euros.
  ///
  /// Throws on HTTP / backend error.
  Future<void> refund({
    required String paymentIntentId,
    required double amount,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'refund',
      body: {'paymentIntentId': paymentIntentId, 'amount': amount},
    );
    final body = response.data as Map<String, dynamic>?;
    final refundId = body?['refundId'];
    debugPrint(
        '[PaymentService] refund issued: $refundId (€${amount.toStringAsFixed(2)})');
  }

  /// Creates a new PaymentIntent for a shortfall extra charge.
  /// [amount] is in euros.
  ///
  /// Returns the new [paymentIntentId].
  /// Throws on HTTP / backend error.
  Future<String> chargeExtra({
    required double amount,
    String? customerId,
  }) async {
    final payload = <String, dynamic>{'amount': amount};
    if (customerId != null) payload['customerId'] = customerId;

    final response = await Supabase.instance.client.functions.invoke(
      'charge-extra',
      body: payload,
    );
    final result = response.data as Map<String, dynamic>;
    final id = result['paymentIntentId'] as String;
    debugPrint(
        '[PaymentService] extra-charge intent: $id (€${amount.toStringAsFixed(2)})');
    return id;
  }

  /// Quote de preço sem criar pedido — RPC quote_order_pricing.
  /// Devolve o mesmo breakdown que create_order devolveria (delivery_fee,
  /// service_fee, customer_total, payment_buffer_total, …) sem inserir
  /// nada na DB. Usado pelo rodapé live do form (carry/send/errand) para
  /// mostrar o preço exacto antes do checkout.
  ///
  /// Para errand, [input] aceita campos errand_* (speed, home_stop,
  /// has_purchase, estimated_purchase_cents, errand_location_lat/lng, etc.).
  /// O backend força is_partner_store=false e valida distância vs haversine.
  ///
  /// Retorna null em erro (rede, validação, etc.) — o caller deve fallback
  /// para "desde €6" e tentar novamente quando os inputs ficarem completos.
  Future<Map<String, dynamic>?> quoteOrder(Map<String, dynamic> input) async {
    try {
      final data = await Supabase.instance.client
          .rpc('quote_order_pricing', params: {'p_input': input});
      if (data is Map) return Map<String, dynamic>.from(data);
      debugPrint('[PaymentService] quoteOrder: unexpected type: ${data.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('[PaymentService] quoteOrder error: $e');
      return null;
    }
  }

  // ─── Legacy convenience helpers (used by checkout screens) ───────────────

  /// Full card checkout: create intent → present sheet → return [paymentIntentId].
  ///
  /// Returns the confirmed [paymentIntentId] on success, or `null` on
  /// cancellation / decline / error. The caller MUST treat null as failure.
  Future<String?> payWithCard(double amount) async {
    try {
      final data = await createPaymentIntent(
        orderId: 'direct-${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
      );
      await processPayment(data['clientSecret'] as String);
      return data['paymentIntentId'] as String?;
    } on StripeException catch (e) {
      debugPrint(
          '[PaymentService] cancelled/declined: ${e.error.localizedMessage}');
      return null;
    } catch (e) {
      debugPrint('[PaymentService] payWithCard error: $e');
      return null;
    }
  }

  /// Initiates a real MBWay charge via Stripe.
  ///
  /// v21 (2026-05-15) — server-side confirmation. O Edge Function confirma o
  /// PaymentIntent com `payment_method_data.billing_details.phone` e o Stripe
  /// envia imediatamente o push para a app MBWay. O cliente Flutter recebe o
  /// paymentIntentId e mostra o `_MBWayWaitingDialog` que faz poll a
  /// `orders.payment_status` até o webhook marcar como 'paid'.
  ///
  /// Histórico:
  ///   v19 — tentou server-confirm com mb_way.phone (parâmetro inexistente).
  ///   v20 — PaymentSheet client-side, mas presentPaymentSheet() bloqueava
  ///         à espera de confirmação MBWay e utilizadores fechavam → cancel.
  ///   v21 — server-confirm com billing_details.phone (parâmetro correcto).
  ///
  /// Retorna paymentIntentId em sucesso, null em erro do Edge Function.
  Future<String?> initiateMbwayPayment({
    required String orderId,
    required String phone,
  }) async {
    if (kIsWeb) return null;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-mbway-payment-intent',
        body: {'order_id': orderId, 'phone': phone},
      );
      final body = response.data as Map<String, dynamic>?;
      if (body?['ok'] != true) {
        debugPrint('[PaymentService] initiateMbwayPayment failed: $body');
        return null;
      }
      final piId = body!['paymentIntentId'] as String?;
      if (piId == null) {
        debugPrint('[PaymentService] initiateMbwayPayment incomplete: $body');
        return null;
      }
      debugPrint('[PaymentService] MBWay PI confirmed server-side: $piId '
          'status=${body['status']}');
      return piId;
    } catch (e) {
      debugPrint('[PaymentService] initiateMbwayPayment error: $e');
      return null;
    }
  }

  Future<bool> payWithCash(double amount) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return true;
  }

  /// BUG #1 frontend (2026-05-12) — Pagar dívida wallet standalone com Stripe sheet.
  /// Chama Edge Function pay-debt-standalone → recebe clientSecret → presentPaymentSheet.
  /// Webhook stripe-webhook v23 detecta metadata e settle automaticamente (não bloqueia caller).
  /// Retorna paymentIntentId em sucesso, null em cancel/decline.
  Future<String?> payDebtViaSheet({
    required int amountCents,
    required String paymentMethod, // 'card' | 'mbway'
    String? mbwayPhone,
  }) async {
    if (kIsWeb) throw StateError('Card payments are only supported on mobile.');
    try {
      final body = <String, dynamic>{
        'amount_cents': amountCents,
        'payment_method': paymentMethod,
      };
      if (paymentMethod == 'mbway' && mbwayPhone != null) {
        body['mbway_phone'] = mbwayPhone;
      }
      final response = await Supabase.instance.client.functions.invoke(
        'pay-debt-standalone',
        body: body,
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['clientSecret'] == null) {
        debugPrint('[PaymentService] payDebtViaSheet: invalid response: $data');
        return null;
      }
      // MBWay: já confirmado server-side (push enviada). Apenas retorna PI.
      if (paymentMethod == 'mbway') {
        return data['paymentIntentId'] as String?;
      }
      // Card: abre Stripe sheet.
      await processPayment(data['clientSecret'] as String);
      return data['paymentIntentId'] as String?;
    } on StripeException catch (e) {
      debugPrint('[PaymentService] payDebt cancelled/declined: ${e.error.localizedMessage}');
      return null;
    } catch (e) {
      debugPrint('[PaymentService] payDebtViaSheet error: $e');
      return null;
    }
  }

  // ─── Saved cards (2026-05-14) ───────────────────────────────────────────

  /// Lista cartoes guardados do user actual via Edge Fn list-saved-cards.
  /// Retorna [] se user ainda nao tem stripe_customer_id (nunca pagou com cartao).
  Future<List<SavedCard>> fetchSavedCards() async {
    if (kIsWeb) return const [];
    try {
      final res = await Supabase.instance.client.functions
          .invoke('list-saved-cards');
      final data = res.data as Map<String, dynamic>?;
      final raw = (data?['cards'] as List?) ?? const [];
      return raw
          .map((m) => SavedCard.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      debugPrint('[PaymentService] fetchSavedCards error: $e');
      return const [];
    }
  }

  /// Confirma pagamento off-session ja criado pela Edge Fn (cartao guardado).
  /// Se [requiresAction] for true, abre PaymentSheet para resolver 3DS challenge.
  /// Caso contrario retorna true (PI ja foi succeeded server-side).
  Future<bool> confirmSavedCardPayment({
    required String clientSecret,
    required bool requiresAction,
  }) async {
    if (kIsWeb) throw StateError('Card payments are only supported on mobile.');
    if (!requiresAction) return true;
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'BORA APP',
          style: ThemeMode.system,
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'PT'),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'PT',
            currencyCode: 'EUR',
            testEnv: false,
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      debugPrint(
          '[PaymentService] saved card 3DS cancelled: ${e.error.localizedMessage}');
      return false;
    } catch (e) {
      debugPrint('[PaymentService] confirmSavedCardPayment error: $e');
      return false;
    }
  }
}
