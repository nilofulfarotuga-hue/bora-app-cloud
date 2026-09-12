// ⚠️ ARQUIVADA (F5, 2026-08-16 — decisão CEO da MISSÃO TOTAL): este era o
// fluxo LEGACY de reserva de mesa. O tile "Reservar Mesa" aponta agora para
// a implementação NOVA em client/reservation/ (ReservationAvailabilityScreen,
// slots reais + estados completos). Ficheiro preservado sem rota — NÃO ligar
// de volta sem decisão explícita do Danilo.
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/restaurant_model.dart';
import '../services/payment_service.dart';
import '../services/saved_card_checkout.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import 'client/reservation/reservation_mbway_waiting_dialog.dart';
import 'client/reservation/reservation_payment_method_sheet.dart';

/// Client-facing screen to reserve a table at a partner restaurant (BR §14).
///
/// MVP: date + time + people + notes + create row with status='pending'.
/// Pre-payment €3 (BR §14.5) is stored as intent in the DB — actual Stripe
/// charge is a follow-up task (zona protegida Stripe).
class ReservationFlowScreen extends StatefulWidget {
  const ReservationFlowScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<ReservationFlowScreen> createState() => _ReservationFlowScreenState();
}

class _ReservationFlowScreenState extends State<ReservationFlowScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  int _people = 2;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  DateTime get _combined => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  static const double _kReservationPrepaymentEur = 3.0;

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preenche nome e telefone.')),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirou.')),
      );
      return;
    }

    // 1) Bottom sheet: escolha de método (Card | MBWay), sem Cash.
    final choice = await showModalBottomSheet<ReservationPaymentChoice>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ReservationPaymentMethodSheet(
        amountEur: _kReservationPrepaymentEur,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      if (choice.method == ReservationPaymentMethod.card) {
        await _payWithCard();
      } else {
        await _payWithMbway(choice.mbwayPhone!);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _payWithCard() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final client = Supabase.instance.client;
    String? reservationId;
    String? paymentIntentId;
    try {
      // Carteira Unica (2026-07-21): cartao padrao + digital/rosto antes de
      // criar o PaymentIntent. Recusar a biometria nao cobra nada.
      final auth =
          await SavedCardCheckout.instance
              .authorize(amountEur: _kReservationPrepaymentEur);
      if (auth.cancelled) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('Pagamento cancelado. Não foi cobrado nada.')));
        return;
      }

      // T2.E (BR §18): Edge Fn v9 cria reservation pending_payment + PI card-only.
      final res = await client.functions.invoke(
        'create-reservation-payment-intent',
        body: {
          'restaurant_id': widget.restaurant.id,
          'people': _people,
          'reserved_for': _combined.toUtc().toIso8601String(),
          'client_name': _nameController.text.trim(),
          'client_phone': _phoneController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          if (auth.savedPmId != null) 'saved_pm_id': auth.savedPmId,
        },
      );
      if (res.status >= 400) {
        throw Exception('reservation_intent_failed: ${res.data}');
      }
      final data = (res.data as Map).cast<String, dynamic>();
      final clientSecret = data['clientSecret'] as String;
      reservationId = data['reservation_id'] as String;
      // Stripe clientSecret format: pi_xxx_secret_yyy → extract PI id for cleanup.
      paymentIntentId = clientSecret.split('_secret_').first;

      if (auth.usesSavedCard) {
        // PI ja confirmado off_session no servidor; so abre sheet se 3DS.
        final ok = await PaymentService().confirmSavedCardPayment(
          clientSecret: clientSecret,
          requiresAction: (data['requiresAction'] as bool?) ?? false,
        );
        if (!ok) {
          if (!mounted) return;
          messenger.showSnackBar(const SnackBar(
              content: Text(
                  'Pagamento com cartão guardado não foi concluído. Tenta de novo.')));
          return;
        }
      } else {
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'Bora App',
            billingDetailsCollectionConfiguration:
                const BillingDetailsCollectionConfiguration(
              name: CollectionMode.always,
            ),
            applePay: const PaymentSheetApplePay(merchantCountryCode: 'PT'),
            googlePay: const PaymentSheetGooglePay(
              merchantCountryCode: 'PT',
              currencyCode: 'EUR',
              testEnv: false,
            ),
          ),
        );
        await Stripe.instance.presentPaymentSheet();
      }

      await client.rpc('client_confirm_reservation_payment',
          params: {'p_reservation_id': reservationId});

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'Reserva criada (€3 ringfenced). Aguarda confirmação do restaurante.')),
      );
      navigator.pop(true);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        // Cancelamento intencional — limpar reserva órfã pending_payment.
        if (reservationId != null && paymentIntentId != null) {
          try {
            await client.rpc('cancel_orphan_reservation', params: {
              'p_reservation_id': reservationId,
              'p_payment_intent_id': paymentIntentId,
              'p_reason': 'user_canceled',
            });
          } catch (_) {
            // Best-effort. Webhook fará cleanup quando Stripe cancelar o PI.
          }
        }
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Pagamento cancelado.')),
        );
        return;
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              e.error.localizedMessage ?? 'Erro no pagamento. Tenta de novo.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erro ao reservar. Tenta de novo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _payWithMbway(String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final client = Supabase.instance.client;

      final res = await client.functions.invoke(
        'create-mbway-reservation-payment-intent',
        body: {
          'restaurant_id': widget.restaurant.id,
          'people': _people,
          'reserved_for': _combined.toUtc().toIso8601String(),
          'client_name': _nameController.text.trim(),
          'client_phone': _phoneController.text.trim(),
          'phone': phone,
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        },
      );
      if (res.status >= 400) {
        throw Exception('mbway_reservation_failed: ${res.data}');
      }
      final data = (res.data as Map).cast<String, dynamic>();
      final reservationId = data['reservation_id'] as String;
      final amountCents = (data['amount_cents'] as num?)?.toInt() ?? 300;

      if (!mounted) return;

      final paid = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ReservationMBWayWaitingDialog(
              reservationId: reservationId,
              amount: amountCents / 100.0,
            ),
          ) ??
          false;

      if (!mounted) return;
      if (!paid) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Pagamento MBWay não confirmado ou expirou.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await client.rpc('client_confirm_reservation_payment',
          params: {'p_reservation_id': reservationId});

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'Reserva criada (€3 ringfenced). Aguarda confirmação do restaurante.')),
      );
      navigator.pop(true);
    } on StripeException catch (e) {
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Pagamento cancelado.')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              e.error.localizedMessage ?? 'Erro no pagamento. Tenta de novo.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erro ao reservar. Tenta de novo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Reservar — ${widget.restaurant.name}'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                          '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickTime,
                      icon: const Icon(Icons.access_time),
                      label: Text(
                          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Pessoas:', style: TextStyle(fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    onPressed: _submitting || _people <= 1
                        ? null
                        : () => setState(() => _people--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_people', style: const TextStyle(fontSize: 18)),
                  IconButton(
                    onPressed: _submitting || _people >= 20
                        ? null
                        : () => setState(() => _people++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _notesController,
                maxLines: 3,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  hintText: 'Aniversário, alergias, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text(
                          'Pré-pagamento €3 (anti-no-show)',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '€3 cobrados agora. Quando chegares ao restaurante:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '· €2 descontados da tua conta (próximo pedido neste restaurante)\n'
                      '· €1 taxa de serviço Bora',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Cancelamento gratuito até 2h antes. Dentro de 2h ou '
                        'no-show: €3 não devolvidos.',
                        style: TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar reserva'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
