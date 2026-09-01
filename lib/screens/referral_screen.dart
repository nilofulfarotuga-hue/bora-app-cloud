import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

import '../l10n/tr.dart';

/// Referral / Convite — Feature 10.
/// Mostra código único do utilizador + botão Share + estatísticas.
/// Backend: RPC `client_get_or_create_referral_code` + tabela `referral_codes`.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  Map<String, dynamic>? _code;
  List<Map<String, dynamic>> _invites = const [];
  bool _loading = true;
  String? _error;

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
      final supa = Supabase.instance.client;
      final code = await supa.rpc('client_get_or_create_referral_code');
      final invites = await supa
          .from('referral_invites')
          .select()
          .eq('referrer_user_id', supa.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _code = (code as Map).cast<String, dynamic>();
        _invites = (invites as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Abre o share sheet nativo (WhatsApp, SMS, Mensagens, etc.) com a
  /// mensagem de convite. Em plataformas onde share_plus não está suportado
  /// (web em alguns browsers), o package faz fallback para Clipboard.
  Future<void> _share() async {
    final code = _code?['code'] as String?;
    if (code == null) return;
    final message =
        'Junta-te ao Bora App e ganhamos os dois €5!\n\nUsa o meu código: {0}\n\nFaz o teu primeiro pedido na app Bora — entrega em Guarda.'.trArgs([code]);
    try {
      await Share.share(message, subject: 'Convite Bora App'.tr);
    } catch (_) {
      // Fallback: copiar para clipboard se o share sheet falhar.
      await Clipboard.setData(ClipboardData(text: message));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mensagem copiada — cola no WhatsApp/SMS!'.tr)),
      );
    }
  }

  void _copy() {
    final code = _code?['code'] as String?;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Código copiado!'.tr)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Convidar amigos'.tr),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error!,
                        style: const TextStyle(color: AppColors.error))),
                  ])
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final c = _code!;
    final code = c['code'] as String? ?? '—';
    final invitesSent = c['invites_sent'] as int? ?? 0;
    final invitesCompleted = c['invites_completed'] as int? ?? 0;
    final totalEarnedCents = c['total_earned_cents'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          child: Column(
            children: [
              const Icon(Icons.card_giftcard,
                  size: 48, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(
                'O teu código'.tr,
                style:
                    const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: Text('Copiar'.tr),
                  ),
                  const SizedBox(width: 8),
                  BoraPrimaryButton(
                    label: 'Partilhar'.tr,
                    icon: Icons.share,
                    onPressed: _share,
                    expanded: false,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como funciona'.tr,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              _step(1, 'Partilha o teu código com amigos.'.tr),
              _step(2, 'Eles registam-se na app com o teu código.'.tr),
              _step(3,
                  'Quando fizerem o 1º pedido (≥€20) entregue, vocês recebem 1000 Bora Tokens cada (≈€5).'.tr),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          child: Column(
            children: [
              _statRow('Convites enviados'.tr, '$invitesSent'),
              _statRow('Amigos que pediram'.tr, '$invitesCompleted'),
              _statRow('Total ganho'.tr,
                  '€${(totalEarnedCents / 100).toStringAsFixed(2)}',
                  bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_invites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('Convites recentes'.tr,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          ..._invites.map(_inviteTile),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Convites expiram após 30 dias. Pedido mínimo €20.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
          ),
        ),
      ],
    );
  }

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.primary,
              child: Text('$n',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary))),
          ],
        ),
      );

  Widget _statRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 18 : 15,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? AppColors.primary : AppColors.textPrimary)),
          ],
        ),
      );

  Widget _inviteTile(Map<String, dynamic> inv) {
    final status = inv['status'] as String? ?? 'pending';
    final created = DateTime.parse(inv['created_at'] as String).toLocal();
    final color = status == 'first_order_done'
        ? AppColors.success
        : status == 'signed_up'
            ? AppColors.warning
            : AppColors.textSubtle;
    final label = {
      'pending': 'Convite enviado',
      'signed_up': 'Registou-se',
      'first_order_done': 'Completou 1º pedido',
      'expired': 'Expirado',
    }[status]!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.person, color: Colors.white)),
        title: Text(inv['invited_email'] as String? ?? 'Amigo'),
        subtitle: Text('$label · ${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}'),
        trailing: status == 'first_order_done'
            ? const Icon(Icons.check_circle, color: AppColors.success)
            : null,
      ),
    );
  }
}
