import 'package:flutter/material.dart';
// `flutter_stripe` exporta `Card` que colide com Material `Card`.
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../stores/reservation_store.dart';

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

  Future<void> _onConfirmAndPay() async {
    if (_processing) return;
    setState(() => _processing = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // a) Criar PaymentIntent (notes combinado).
      final pi =
          await context.read<ReservationStore>().createReservationPaymentIntent(
                restaurantId: widget.restaurantId,
                people: widget.partySize,
                reservedFor: widget.selectedDateTime,
                combinedNotes: _buildCombinedNotes(),
              );

      // Edge Fn shape: clientSecret (camel) + reservation_id (snake).
      final clientSecret = pi['clientSecret'] as String?;
      final reservationId = pi['reservation_id'] as String?;
      if (clientSecret == null || reservationId == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      // b) Inicializar Payment Sheet — PADRÃO CANÓNICO BORA APP.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'BORA APP',
          style: ThemeMode.system,
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'PT'),
          // 2026-05-14 — Google Pay activado (PT/EUR live), alinhado com
          // payment_service. AndroidManifest gms.wallet.api.enabled meta-data
          // adicionado no mesmo commit.
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'PT',
            currencyCode: 'EUR',
            testEnv: false,
          ),
        ),
      );

      // c) Apresentar Payment Sheet.
      await Stripe.instance.presentPaymentSheet();

      // d) Sucesso — confirmar via RPC fallback.
      if (!mounted) return;
      await context
          .read<ReservationStore>()
          .confirmReservationPayment(reservationId);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Reserva pendente! O parceiro confirma em breve.'),
          backgroundColor: AppTheme.primary,
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
          backgroundColor: isCanceled ? AppTheme.secondary : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar reserva')),
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
                    backgroundColor: AppTheme.primary,
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
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTimePt(widget.selectedDateTime),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.partySize == 1
                        ? '1 pessoa'
                        : '${widget.partySize} pessoas',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
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
        color: AppTheme.surface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.restaurant_outlined,
          color: AppTheme.primary,
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
                color: AppTheme.textPrimary,
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
      color: AppTheme.surface,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como funciona o pré-pagamento',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            _TermLine(text: '€3 retidos no cartão para garantir reserva.'),
            _TermLine(text: '   • €1 taxa de serviço Bora App.'),
            _TermLine(text: '   • €2 crédito para usar no restaurante.'),
            _TermLine(text: 'Reembolso 100% se cancelares até 2h antes.'),
            _TermLine(
                text:
                    'Após esse limite, €3 não reembolsável (política do restaurante).'),
            _TermLine(
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
  const _TermLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
