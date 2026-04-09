import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentService {
  static const String _baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

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
      body: {'orderId': orderId, 'amount': amount},
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
        // Wallet payments — Stripe routes these through the SAME PaymentIntent,
        // so the webhook-based server-trusted flow remains intact.
        applePay: const PaymentSheetApplePay(
          merchantCountryCode: 'PT',
        ),
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'PT',
          currencyCode: 'EUR',
          testEnv: kDebugMode,
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
    _checkBackend();

    final response = await http.post(
      Uri.parse('$_baseUrl/refund'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'paymentIntentId': paymentIntentId, 'amount': amount}),
    );

    _assertOk(response, 'refund');

    final refundId =
        (jsonDecode(response.body) as Map<String, dynamic>)['refundId'];
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
    _checkBackend();

    final payload = <String, dynamic>{'amount': amount};
    if (customerId != null) payload['customerId'] = customerId;

    final response = await http.post(
      Uri.parse('$_baseUrl/charge-extra'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    _assertOk(response, 'charge-extra');

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final id = result['paymentIntentId'] as String;
    debugPrint('[PaymentService] extra-charge intent: $id (€${amount.toStringAsFixed(2)})');
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

  Future<bool> payWithMBWay(double amount) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  /// Server-trusted MBWay confirmation. Invokes the `confirm-mbway-payment`
  /// Edge Function which flips `orders.payment_status` to `paid` using the
  /// service-role key. The client is NEVER allowed to write this field.
  /// Temporary stub for the real MBWay webhook.
  Future<bool> confirmMbwayPayment(String orderId) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'confirm-mbway-payment',
        body: {'orderId': orderId},
      );
      final body = response.data as Map<String, dynamic>?;
      final ok = body?['ok'] == true;
      debugPrint('[PaymentService] confirmMbwayPayment($orderId) → $ok');
      return ok;
    } catch (e) {
      debugPrint('[PaymentService] confirmMbwayPayment error: $e');
      return false;
    }
  }

  Future<bool> payWithCash(double amount) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return true;
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  void _checkBackend() {
    if (_baseUrl.trim().isEmpty) {
      throw StateError(
        'BACKEND_BASE_URL is not set. '
        'Run Flutter with --dart-define=BACKEND_BASE_URL=http://localhost:3000',
      );
    }
  }

  void _assertOk(http.Response response, String endpoint) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          '[PaymentService] $endpoint HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
