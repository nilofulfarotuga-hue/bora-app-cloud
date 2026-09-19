import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

import '../l10n/tr.dart';

/// Ecrã para o cliente resgatar um código promocional → ganha tokens.
/// Chama RPC `client_redeem_promo_tokens(p_code text)`.
/// Retorno: jsonb
///   sucesso: {valid:true, code, tokens_granted, euro_value}
///   erro:    {valid:false, reason:'not_found'|'inactive'|'expired'|'already_used'|'max_uses_reached'}
///
/// NÃO usar `client_apply_promo_code` aqui — essa função aplica desconto a um
/// pedido (modelo errado). A Bora usa tokens, não cupões de desconto directo.
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
      setState(() => _error = 'Introduz um código.'.tr);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('client_redeem_promo_tokens', params: {'p_code': code});
      if (res is! Map) {
        throw Exception('Resposta inesperada do servidor.');
      }
      final m = res.cast<String, dynamic>();
      final valid = (m['valid'] as bool?) ?? false;
      if (!valid) {
        final reason = m['reason'] as String? ?? 'unknown';
        if (mounted) setState(() => _error = _friendlyReason(reason));
        return;
      }
      final tokensGranted = (m['tokens_granted'] as num?)?.toInt() ?? 0;
      final euroValue = (m['euro_value'] as num?)?.toDouble() ??
          (tokensGranted * 0.005);
      final msg =
          'Ganhaste {0} Bora Tokens (≈€{1})! Já estão na tua conta.'.trArgs([tokensGranted, euroValue.toStringAsFixed(2)]);
      if (mounted) {
        setState(() {
          _successMessage = msg;
          _ctrl.clear();
        });
      }
      // Refresh saldo tokens em memória (best-effort, não bloqueia).
      await _refreshTokenBalance();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível resgatar: {0}'.trArgs([e.toString()]));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyReason(String reason) {
    switch (reason) {
      case 'not_found':
        return 'Código inválido.'.tr;
      case 'already_used':
        return 'Já usaste este código.'.tr;
      case 'expired':
        return 'Código expirado.'.tr;
      case 'inactive':
        return 'Código já não está activo.'.tr;
      case 'max_uses_reached':
        return 'Este código atingiu o limite de utilizações.'.tr;
      default:
        return 'Não foi possível resgatar o código.'.tr;
    }
  }

  /// Best-effort: força refresh do saldo de tokens em outros ecrãs.
  /// Usa wallet_get_balance que devolve tokens_balance actualizado.
  Future<void> _refreshTokenBalance() async {
    try {
      await Supabase.instance.client.rpc('wallet_get_balance');
    } catch (_) {/* silencioso */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Resgatar código'.tr),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.redeem, size: 64, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              'Tens um código promocional?'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Introduz o código abaixo para receber Bora Tokens na tua conta.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Código'.tr,
                hintText: 'EX: BORA2026'.tr,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.local_offer_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
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
                  color: AppColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_successMessage!,
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            BoraPrimaryButton(
              label: 'Resgatar'.tr,
              onPressed: _submitting ? null : _apply,
              loading: _submitting,
            ),
            const SizedBox(height: 12),
            Text(
              'Os tokens são creditados na tua carteira Bora e podem ser usados como desconto até 50% no checkout.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}
