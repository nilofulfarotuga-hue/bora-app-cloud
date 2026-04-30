import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant_model.dart';

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

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preenche nome e telefone.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Sessão expirou.')),
        );
        setState(() => _submitting = false);
        return;
      }

      // T2.E (BR §18): chama Edge Fn que cria reservation pending_payment +
      // Stripe PaymentIntent €3.
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
        },
      );
      if (res.status >= 400) {
        throw Exception('reservation_intent_failed: ${res.data}');
      }
      final data = (res.data as Map).cast<String, dynamic>();
      final clientSecret = data['clientSecret'] as String;
      final reservationId = data['reservation_id'] as String;

      // Confirm Stripe PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Bora App',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // Mark reservation as paid → notify partner
      await client.rpc('client_confirm_reservation_payment',
          params: {'p_reservation_id': reservationId});

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text(
                'Reserva criada (€3 ringfenced). Aguarda confirmação do restaurante.')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao reservar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reservar — ${widget.restaurant.name}')),
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
                            size: 16, color: Color(0xFFE65100)),
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
                    backgroundColor: const Color(0xFFE65100),
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
