// Sessão 5A-2 B14 — SupportEmailFormScreen
// Form simples — submete via Edge Fn support-submit-ticket (channel='email').

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../providers/support_settings_provider.dart';

class SupportEmailFormScreen extends StatefulWidget {
  const SupportEmailFormScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<SupportEmailFormScreen> createState() =>
      _SupportEmailFormScreenState();
}

class _SupportEmailFormScreenState extends State<SupportEmailFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'support-submit-ticket',
        body: {
          'channel': 'email',
          'subject': _subjectCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          if (widget.orderId != null) 'order_id': widget.orderId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      final ticketId = data?['ticket_id'] as String?;
      final sla = data?['sla_hours'] as int? ??
          context.read<SupportSettingsProvider>().slaHours;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ticketId == null
                ? 'Recebemos. Resposta em até ${sla}h.'
                : 'Recebemos #${ticketId.substring(0, 8)}. Resposta em até ${sla}h.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on FunctionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.details ?? e.status}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro de comunicação. Tenta novamente.')),
        );
      }
      debugPrint('[SupportEmailFormScreen] $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportSettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar email ao suporte')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.orderId != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Sobre pedido #${widget.orderId}',
                    style: const TextStyle(color: AppColors.accent),
                  ),
                ),
              TextFormField(
                controller: _subjectCtrl,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Assunto',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Assunto obrigatório'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyCtrl,
                maxLength: 5000,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Mensagem obrigatória'
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Resposta em até ${provider.slaHours}h em ${provider.supportEmail}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Text('Enviar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
