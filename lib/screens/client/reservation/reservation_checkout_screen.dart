import 'package:flutter/material.dart';
// `flutter_stripe` exporta `Card` que colide com Material `Card`.
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../services/payment_service.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../stores/reservation_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'reservation_mbway_waiting_dialog.dart';
import 'reservation_payment_method_sheet.dart';

/// Reservas PRO F3.B — checkout reserva com pré-pagamento Stripe €3.
/// Cria PaymentIntent via Edge Fn `create-reservation-payment-intent` v3,
/// abre Payment Sheet (padrão canónico BORA APP), confirma RPC F2.
class ReservationCheckoutScreen extends StatefulWidget {
  const ReservationCheckoutScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.selectedDateTime,
    required this.partySize,
    this.restaurantPhotoUrl,
  });

  final String restaurantId;
  final String restaurantName;
  final String? restaurantPhotoUrl;
  final DateTime selectedDateTime;
  final int partySize;

  @override
  State<ReservationCheckoutScreen> createState() =>
      _ReservationCheckoutScreenState();
}

/// Mapping ocasiao DB key -> label PT-PT.
/// Omite 'first_date' e 'other' — UX simplification (usa campo `notes`).
const Map<String?, String> kOccasionOptions = <String?, String>{
  null: 'Não especificar',
  'birthday': 'Aniversário',
  'romantic': 'Romântico',
  'business': 'Negócios',
  'family': 'Família',
  'celebration': 'Celebração',
};

class _ReservationCheckoutScreenState extends State<ReservationCheckoutScreen> {
  final _notesCtrl = TextEditingController();
  final _specialRequestsCtrl = TextEditingController();
  String? _selectedOccasion;
  bool _processing = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _specialRequestsCtrl.dispose();
    super.dispose();
  }

  /// Concatena ocasião + pedidos especiais + notas numa única string `notes`
  /// (Edge Fn não aceita campos separados — F3.B ajuste).
  String? _buildCombinedNotes() {
    final parts = <String>[];
    if (_selectedOccasion != null) {
      final label = kOccasionOptions[_selectedOccasion];
      if (label != null) parts.add('Ocasião: $label');
    }
    final special = _specialRequestsCtrl.text.trim();
    if (special.isNotEmpty) {
      parts.add('Pedidos especiais: $special');
    }
    final notes = _notesCtrl.text.trim();
    if (notes.isNotEmpty) {
      parts.add('Notas: $notes');
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  /// Constante hard-coded conservadora — preço default do prepagamento.
  /// Server (Edge Fn) é a fonte de verdade via platform_settings, mas
  /// o bottom sheet é UX-only; o valor real cobrado é o que o servidor decidir.
  static const double _kReservationPrepaymentEur = 3.0;

  Future<void> _onConfirmAndPay() async {
    if (_processing) return;

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

    setState(() => _processing = true);
    try {
      if (choice.method == ReservationPaymentMethod.card) {
        await _payWithCard();
      } else {
        await _payWithMbway(choice.mbwayPhone!);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _payWithCard() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Lido ANTES do primeiro await — o gate biometrico e assincrono e o
    // context nao pode ser usado depois dele.
    final reservationStore = context.read<ReservationStore>();
    try {
      // Carteira Unica (2026-07-21): resolve o cartao padrao e pede
      // digital/rosto ANTES de criar o PaymentIntent — nada e cobrado se o
      // cliente recusar.
      final auth = await SavedCardCheckout.instance
          .authorize(amountEur: _kReservationPrepaymentEur);
      if (auth.cancelled) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('Pagamento cancelado. Não foi cobrado nada.')));
        return;
      }

      // a) Criar PaymentIntent (notes combinado). Edge Fn v9 → payment_method_types: ['card'].
      final pi = await reservationStore.createReservationPaymentIntent(
        restaurantId: widget.restaurantId,
        people: widget.partySize,
        reservedFor: widget.selectedDateTime,
        combinedNotes: _buildCombinedNotes(),
        savedPmId: auth.savedPmId,
      );

      // Edge Fn shape: clientSecret (camel) + reservation_id (snake).
      final clientSecret = pi['clientSecret'] as String?;
      final reservationId = pi['reservation_id'] as String?;
      if (clientSecret == null || reservationId == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      if (auth.usesSavedCard) {
        // Cartao guardado: o PI ja foi confirmado off_session no servidor. So
        // abrimos o sheet se o banco exigir 3DS (requiresAction).
        final ok = await PaymentService().confirmSavedCardPayment(
          clientSecret: clientSecret,
          requiresAction: (pi['requiresAction'] as bool?) ?? false,
        );
        if (!ok) {
          if (!mounted) return;
          messenger.showSnackBar(const SnackBar(
              content: Text(
                  'Pagamento com cartão guardado não foi concluído. Tenta de novo.')));
          return;
        }
      } else {
        // b) Inicializar Payment Sheet — PADRÃO CANÓNICO BORA APP.
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'BORA APP',
            style: ThemeMode.system,
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

        // c) Apresentar Payment Sheet.
        await Stripe.instance.presentPaymentSheet();
      }

      // d) Sucesso — confirmar via RPC fallback.
      if (!mounted) return;
      await context
          .read<ReservationStore>()
          .confirmReservationPayment(reservationId);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Reserva pendente! O parceiro confirma em breve.'),
          backgroundColor: AppColors.primary,
        ),
      );
      navigator.popUntil((route) => route.isFirst);
    } on StripeException catch (e) {
      if (!mounted) return;
      final isCanceled = e.error.code == FailureCode.Canceled;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isCanceled ? 'Pagamento cancelado' : 'Erro no pagamento. Tenta de novo.',
          ),
          backgroundColor: isCanceled ? AppColors.accent : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _payWithMbway(String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // a) Criar reserva pending_payment + PI MBWay server-confirmed.
      //    Stripe envia push à app MBWay imediatamente.
      final pi = await context
          .read<ReservationStore>()
          .createMbwayReservationPaymentIntent(
            restaurantId: widget.restaurantId,
            people: widget.partySize,
            reservedFor: widget.selectedDateTime,
            mbwayPhone: phone,
            combinedNotes: _buildCombinedNotes(),
          );

      final reservationId = pi['reservation_id'] as String?;
      final amountCents = (pi['amount_cents'] as num?)?.toInt() ?? 300;
      if (reservationId == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      if (!mounted) return;

      // b) Dialog de espera: poll a reservations.status até pending ou timeout.
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

      // c) RPC fallback idempotente — webhook pode já ter confirmado,
      //    nesse caso a RPC falha mas o pagamento já foi processado.
      try {
        await context
            .read<ReservationStore>()
            .confirmReservationPayment(reservationId);
      } catch (_) {
        // Webhook já confirmou — não é erro para o utilizador.
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Reserva submetida! O pagamento MB Way está a ser processado.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Confirmar reserva'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    _buildOptionsCard(),
                    const SizedBox(height: 16),
                    _buildTermsCard(),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _processing ? null : _onConfirmAndPay,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock),
                  label: const Text(
                    'Pagar €3 e reservar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: (widget.restaurantPhotoUrl != null &&
                        widget.restaurantPhotoUrl!.isNotEmpty)
                    ? Image.network(
                        widget.restaurantPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _photoFallback(),
                        loadingBuilder: (_, child, prog) =>
                            prog == null ? child : _photoFallback(),
                      )
                    : _photoFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.restaurantName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTimePt(widget.selectedDateTime),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.partySize == 1
                        ? '1 pessoa'
                        : '${widget.partySize} pessoas',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoFallback() => Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.restaurant_outlined,
          color: AppColors.primary,
          size: 28,
        ),
      );

  Widget _buildOptionsCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Detalhes (opcionais)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedOccasion,
              decoration: const InputDecoration(
                labelText: 'Ocasião',
                border: OutlineInputBorder(),
              ),
              items: kOccasionOptions.entries
                  .map((e) => DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedOccasion = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _specialRequestsCtrl,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Pedidos especiais',
                hintText: 'Mesa silenciosa, cadeira bebé...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notas',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsCard() {
    return const Card(
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como funciona o pré-pagamento',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            _TermLine(text: '€3 retidos no cartão para garantir reserva.'),
            _TermLine(text: '   • €1 taxa de serviço Bora App.'),
            _TermLine(text: '   • €2 crédito para usar no restaurante.'),
            _TermLine(text: 'Reembolso 100% se cancelares até 2h antes.'),
            _TermLine(
                isWarning: true,
                text:
                    'Após esse limite, €3 não reembolsável (política do restaurante).'),
            _TermLine(
                isWarning: true,
                text: 'Se não apareceres, €3 ficam para o restaurante.'),
          ],
        ),
      ),
    );
  }

  static String _formatDateTimePt(DateTime dt) {
    const weekdays = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final wd = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final mo = months[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${dt.day} de $mo • $hh:$mm';
  }
}

class _TermLine extends StatelessWidget {
  const _TermLine({required this.text, this.isWarning = false});
  final String text;

  /// Linhas de penalização usam ícone neutro — um visto verde ao lado de
  /// "€3 não reembolsável" comunicava o oposto da política.
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.info_outline : Icons.check_circle,
            size: 16,
            color: isWarning ? AppColors.textSubtle : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
