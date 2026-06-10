import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// M11 — Viewer READ-ONLY de conversas de um pedido (admin).
/// Usa a RPC `admin_list_order_messages` (gate `_admin_op_guard` + audit log
/// `chat_viewed` registado server-side a cada acesso). PT-BR.
class AdminChatViewerScreen extends StatefulWidget {
  const AdminChatViewerScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminChatViewerScreen> createState() => _AdminChatViewerScreenState();
}

class _AdminChatViewerScreenState extends State<AdminChatViewerScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'admin_list_order_messages',
      params: {'p_order_id': widget.orderId},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  Color _senderColor(String sender) => switch (sender) {
        'client' => AppColors.info,
        'driver' => AppColors.accent,
        'partner' => AppColors.primary,
        _ => AppColors.textSubtle,
      };

  String _senderLabel(String sender) => switch (sender) {
        'client' => 'Cliente',
        'driver' => 'Entregador',
        'partner' => 'Parceiro',
        _ => sender,
      };

  @override
  Widget build(BuildContext context) {
    final shortId =
        widget.orderId.length > 8 ? widget.orderId.substring(0, 8) : widget.orderId;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Conversa · #$shortId'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro: ${snap.error}',
                    style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          final msgs = snap.data ?? const [];
          if (msgs.isEmpty) {
            return const Center(
              child: Text('Sem mensagens neste pedido.',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              final m = msgs[i];
              final sender = (m['sender_type'] as String?) ?? '?';
              final created = (m['created_at'] as String?) ?? '';
              final ts = created.length >= 16
                  ? created.substring(0, 16).replaceFirst('T', ' ')
                  : created;
              final conv = (m['conversation_type'] as String?) ?? '—';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: _senderColor(sender).withValues(alpha: .15),
                    child: Icon(Icons.person,
                        size: 16, color: _senderColor(sender)),
                  ),
                  title: Text(m['message']?.toString() ?? ''),
                  subtitle: Text(
                    '${_senderLabel(sender)} · $ts · $conv'
                    '${m['read'] == true ? ' · lida' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
