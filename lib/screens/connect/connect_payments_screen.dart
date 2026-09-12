import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// "Receber pagamentos" — Stripe Connect Express, Fase 1 (2026-08-06).
///
/// Mostra o estado da conta de recebimentos do próprio utilizador e abre o
/// onboarding (ou o painel de pagamentos) no browser externo. Para o parceiro
/// isto é "receber pelo Bora" — a palavra Stripe aparece o mínimo possível.
///
/// [connectRole]: 'partner' | 'provider' | 'driver' | 'cleaner'.
class ConnectPaymentsScreen extends StatefulWidget {
  const ConnectPaymentsScreen({super.key, required this.connectRole});

  final String connectRole;

  @override
  State<ConnectPaymentsScreen> createState() => _ConnectPaymentsScreenState();
}

class _ConnectPaymentsScreenState extends State<ConnectPaymentsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'get_my_connect_status',
        params: {'p_role': widget.connectRole},
      );
      if (!mounted) return;
      setState(() {
        _status = res is Map ? Map<String, dynamic>.from(res) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o estado. Tenta novamente.';
        _loading = false;
      });
      debugPrint('[ConnectPayments] load error: $e');
    }
  }

  Future<void> _openOnboarding() async {
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'stripe-connect-onboard',
        body: {'role': widget.connectRole},
      );
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      final url = data?['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception(data?['error'] ?? 'sem url');
      }
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Não foi possível abrir. Verifica a ligação e tenta de novo.'),
          ),
        );
      }
      debugPrint('[ConnectPayments] onboarding error: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Ao voltar do browser o estado pode já ter mudado via webhook.
        _load();
      }
    }
  }

  String get _statusCode => (_status?['status'] as String?) ?? 'none';

  bool get _isEnabled => _statusCode == 'enabled';

  List<String> get _currentlyDue {
    final req = _status?['requirements'];
    if (req is Map && req['currently_due'] is List) {
      return (req['currently_due'] as List).map((e) => e.toString()).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Receber pagamentos',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: AppColors.error.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.error)),
                      ),
                    )
                  else ...[
                    _statusCard(),
                    const SizedBox(height: 16),
                    if (_currentlyDue.isNotEmpty && !_isEnabled) ...[
                      _missingDataCard(),
                      const SizedBox(height: 16),
                    ],
                    _actionButton(),
                    const SizedBox(height: 24),
                    const Text(
                      'Os pagamentos são processados por uma entidade '
                      'certificada. Depois de configurado, o dinheiro das '
                      'tuas vendas cai diretamente na tua conta bancária, '
                      'todas as semanas.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statusCard() {
    final (label, color, icon) = switch (_statusCode) {
      'enabled' => (
          'A receber normalmente',
          AppColors.success,
          Icons.check_circle
        ),
      'pending' => (
          'Em verificação',
          AppColors.warning,
          Icons.hourglass_top
        ),
      'restricted' => (
          'Bloqueado — faltam dados',
          AppColors.error,
          Icons.error_outline
        ),
      'disabled' => (
          'Bloqueado — faltam dados',
          AppColors.error,
          Icons.block
        ),
      _ => (
          'Ainda não configurado',
          AppColors.textSecondary,
          Icons.account_balance_outlined
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (_statusCode == 'none') ...[
              const SizedBox(height: 8),
              const Text(
                'Configura uma vez e recebe as tuas vendas '
                'diretamente na tua conta.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _missingDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O que falta:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._currentlyDue.map(
              (key) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textSecondary),
                    Expanded(child: Text(_ptRequirement(key))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toca em "Continuar" para completar.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton() {
    final label = _isEnabled
        ? 'Ver os meus pagamentos'
        : _statusCode == 'none'
            ? 'Começar'
            : 'Continuar';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _busy ? null : _openOnboarding,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(_isEnabled ? Icons.open_in_new : Icons.arrow_forward),
        label: Text(label),
      ),
    );
  }

  /// Traduz as chaves de requisitos da Stripe para PT-PT simples.
  String _ptRequirement(String key) {
    if (key.contains('external_account')) {
      return 'IBAN da tua conta bancária';
    }
    if (key.contains('verification.document') || key.contains('document')) {
      return 'Documento de identificação (frente e verso)';
    }
    if (key.contains('dob')) return 'Data de nascimento';
    if (key.contains('address')) return 'Morada';
    if (key.contains('phone')) return 'Número de telemóvel';
    if (key.contains('email')) return 'Email';
    if (key.contains('tos_acceptance')) return 'Aceitar os termos de utilização';
    if (key.contains('business_profile')) return 'Dados do negócio';
    if (key.contains('tax') || key.contains('vat')) return 'NIF / dados fiscais';
    if (key.contains('bank_account')) return 'Conta bancária';
    return 'Dados adicionais pedidos na verificação';
  }
}
