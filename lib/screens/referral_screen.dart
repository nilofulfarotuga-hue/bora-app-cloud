import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/bora_support_fab.dart';

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
        'Junta-te ao Bora App e ganhamos os dois €5!\n\n'
        'Usa o meu código: $code\n\n'
        'Faz o teu primeiro pedido na app Bora — entrega em Guarda.';
    try {
      await Share.share(message, subject: 'Convite Bora App');
    } catch (_) {
      // Fallback: copiar para clipboard se o share sheet falhar.
      await Clipboard.setData(ClipboardData(text: message));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensagem copiada — cola no WhatsApp/SMS!')),
      );
    }
  }

  void _copy() {
    final code = _code?['code'] as String?;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convidar amigos')),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error!,
                        style: const TextStyle(color: Colors.red))),
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
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.card_giftcard, size: 48, color: Colors.green),
                const SizedBox(height: 8),
                const Text(
                  'O teu código',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share),
                      label: const Text('Partilhar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Como funciona',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _step(1, 'Partilha o teu código com amigos.'),
                _step(2, 'Eles registam-se na app com o teu código.'),
                _step(3,
                    'Quando fizerem o 1º pedido (≥€20) entregue, vocês recebem 1000 Bora Tokens cada (≈€5).'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statRow('Convites enviados', '$invitesSent'),
                _statRow('Amigos que pediram', '$invitesCompleted'),
                _statRow('Total ganho',
                    '€${(totalEarnedCents / 100).toStringAsFixed(2)}',
                    bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_invites.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('Convites recentes',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ..._invites.map(_inviteTile),
        ],
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Convites expiram após 30 dias. Pedido mínimo €20.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.black45),
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
              backgroundColor: Colors.green,
              child: Text('$n',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _statRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(value,
                style: TextStyle(
                    fontSize: bold ? 18 : 15,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? Colors.green.shade700 : Colors.black87)),
          ],
        ),
      );

  Widget _inviteTile(Map<String, dynamic> inv) {
    final status = inv['status'] as String? ?? 'pending';
    final created = DateTime.parse(inv['created_at'] as String).toLocal();
    final color = status == 'first_order_done'
        ? Colors.green
        : status == 'signed_up'
            ? Colors.orange
            : Colors.grey;
    final label = {
      'pending': 'Convite enviado',
      'signed_up': 'Registou-se',
      'first_order_done': 'Completou 1º pedido',
      'expired': 'Expirado',
    }[status]!;
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.person, color: Colors.white)),
        title: Text(inv['invited_email'] as String? ?? 'Amigo'),
        subtitle: Text('$label · ${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}'),
        trailing: status == 'first_order_done'
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      ),
    );
  }
}
