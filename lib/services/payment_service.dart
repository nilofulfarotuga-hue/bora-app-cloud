import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        // Apple Pay (iOS) — funciona out-of-the-box em Portugal Stripe LIVE.
        applePay: const PaymentSheetApplePay(
          merchantCountryCode: 'PT',
        ),
        // BUG 9 (Fase 5 / 2026-04-30): Google Pay desativado até Danilo
        // configurar Stripe Dashboard:
        //   1. Stripe → Settings → Payment methods → activar Google Pay
        //   2. Domain verification (live mode requires a verified domain)
        //   3. Android Play Console: registar SHA-1 da app de produção
        //   4. Re-enable: passar PaymentSheetGooglePay(...) ao retomar.
        // Doc completa: docs/google-pay-setup.md (criada nesta fase).
        googlePay: null,
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
  /// Creates + confirms a PaymentIntent server-side; Stripe sends push to user's MBWay app.
  /// Resolution comes via stripe-webhook (payment_intent.succeeded → payment_status=paid).
  Future<String?> initiateMbwayPayment({
    required String orderId,
    required String phone,
  }) async {
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
      debugPrint('[PaymentService] MBWay intent initiated: $piId');
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
}
