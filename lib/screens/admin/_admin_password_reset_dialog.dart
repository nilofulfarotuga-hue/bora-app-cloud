import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Painel admin (PT-BR) — dispara o e-mail de redefinição de senha para
/// qualquer usuário e mostra quando foi o último envio.
///
/// Leitura: RPC `admin_auth_recovery_status` (SECURITY DEFINER, guardada por
/// `_admin_op_guard`) — o cliente Flutter não pode ler `auth.users` direto.
/// Envio: Edge Fn `support-password-reset`, que também grava em
/// `admin_audit_log` (`action='password_reset_sent'`).
Future<void> showAdminPasswordResetDialog(
  BuildContext context, {
  required String userId,
  required String email,
  String? displayName,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AdminPasswordResetDialog(
      userId: userId,
      email: email,
      displayName: displayName,
    ),
  );
}

class _AdminPasswordResetDialog extends StatefulWidget {
  const _AdminPasswordResetDialog({
    required this.userId,
    required this.email,
    this.displayName,
  });

  final String userId;
  final String email;
  final String? displayName;

  @override
  State<_AdminPasswordResetDialog> createState() =>
      _AdminPasswordResetDialogState();
}

class _AdminPasswordResetDialogState extends State<_AdminPasswordResetDialog> {
  bool _loading = true;
  bool _sending = false;
  String? _loadError;

  DateTime? _recoverySentAt;
  DateTime? _lastAdminSendAt;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_auth_recovery_status',
        params: {'p_user_id': widget.userId},
      );
      final map = (res as Map).cast<String, dynamic>();
      setState(() {
        _recoverySentAt = _parseDate(map['recovery_sent_at']);
        _lastAdminSendAt = _parseDate(map['last_admin_send_at']);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Não foi possível ler o status: $e';
        _loading = false;
      });
    }
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'support-password-reset',
        body: {'user_id': widget.userId, 'email': widget.email},
      );
      final data = res.data;
      final ok = data is Map && data['ok'] == true;
      if (!ok) {
        final detail = data is Map ? (data['detail'] ?? data['error']) : data;
        throw Exception(detail ?? 'resposta inesperada');
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('E-mail de redefinição enviado para ${widget.email}.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Falha ao enviar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'nunca';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} às ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Redefinir senha'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.displayName != null && widget.displayName!.isNotEmpty)
              Text(
                widget.displayName!,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            Text(widget.email, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Text(_loadError!, style: TextStyle(color: theme.colorScheme.error))
            else ...[
              _linha('Último e-mail de recuperação', _formatDate(_recoverySentAt)),
              const SizedBox(height: 4),
              _linha('Último envio pelo painel', _formatDate(_lastAdminSendAt)),
            ],
            const SizedBox(height: 16),
            Text(
              'O usuário recebe um link válido por 1 hora que abre a página de '
              'nova senha. A senha atual continua funcionando até ele trocar. '
              'A ação fica registrada na auditoria.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _sending || _loading ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_reset),
          label: const Text('Enviar link de redefinição de senha'),
        ),
      ],
    );
  }

  Widget _linha(String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          flex: 4,
          child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
