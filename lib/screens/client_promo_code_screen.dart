import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ecrã para o cliente resgatar um código promocional.
/// Chama RPC `client_apply_promo_code(p_code text)` — função já existe backend.
/// Retorno esperado: jsonb com {tokens_awarded, message} (campos exactos podem
/// variar — defensivamente lidamos com vários shapes).
class ClientPromoCodeScreen extends StatefulWidget {
  const ClientPromoCodeScreen({super.key});

  @override
  State<ClientPromoCodeScreen> createState() => _ClientPromoCodeScreenState();
}

class _ClientPromoCodeScreenState extends State<ClientPromoCodeScreen> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Introduz um código.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('client_apply_promo_code', params: {'p_code': code});
      String msg = 'Código aplicado com sucesso.';
      int? tokensAwarded;
      if (res is Map) {
        final m = res.cast<String, dynamic>();
        tokensAwarded = (m['tokens_awarded'] as num?)?.toInt() ??
            (m['tokens'] as num?)?.toInt() ??
            (m['amount_tokens'] as num?)?.toInt();
        final apiMsg = m['message'] as String?;
        if (apiMsg != null && apiMsg.isNotEmpty) msg = apiMsg;
      } else if (res is num) {
        tokensAwarded = res.toInt();
      }
      if (tokensAwarded != null && tokensAwarded > 0) {
        final eur = (tokensAwarded * 0.005).toStringAsFixed(2);
        msg = 'Recebeste $tokensAwarded Bora Tokens (≈€$eur)!';
      }
      if (mounted) {
        setState(() {
          _successMessage = msg;
          _ctrl.clear();
        });
      }
    } catch (e) {
      final raw = e.toString();
      final friendly = raw.contains('promo_code_not_found') ||
              raw.contains('invalid_code')
          ? 'Código inválido ou inexistente.'
          : raw.contains('already_used')
              ? 'Já usaste este código.'
              : raw.contains('expired')
                  ? 'Este código expirou.'
                  : raw.contains('inactive')
                      ? 'Este código já não está activo.'
                      : 'Não foi possível resgatar: $raw';
      if (mounted) setState(() => _error = friendly);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resgatar código')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.redeem, size: 64, color: Colors.green),
            const SizedBox(height: 8),
            const Text(
              'Tens um código promocional?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Introduz o código abaixo para receber Bora Tokens na tua conta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Código',
                hintText: 'EX: BORA2026',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_offer_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ],
                ),
              ),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_successMessage!,
                          style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _apply,
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resgatar'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Os tokens são creditados na tua carteira Bora e podem ser usados como desconto até 50% no checkout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}
