// Painel admin (PT-BR) — "Marcar entregue sem código" (04/11/2026, adendo 1 da
// missão favor-diferenca-mbway-2026-11-03). Quando o entregador esquece de
// pedir o código (PIN) ao cliente, o admin fecha a entrega aqui. Motivo
// obrigatório; fica no log de auditoria (admin_audit_log). Só para pedidos "a
// caminho" (onTheWay). Ganhos, tokens e fatura saem como numa entrega normal.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminEntregueSemCodigoButton extends StatelessWidget {
  const AdminEntregueSemCodigoButton({
    super.key,
    required this.orderId,
    required this.status,
    required this.onDone,
    this.marcar,
  });

  final String orderId;
  final String status;
  final VoidCallback onDone;

  /// Só para testes.
  final Future<Map<String, dynamic>> Function(String orderId, String motivo)? marcar;

  static Future<Map<String, dynamic>> marcarNoServidor(String orderId, String motivo) async {
    final r = await Supabase.instance.client.rpc('admin_marcar_entregue_sem_codigo',
        params: {'p_pedido': orderId, 'p_motivo': motivo});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static String mensagem(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      return r['ja_entregue'] == true ? 'O pedido já estava entregue.' : 'Pedido marcado como entregue.';
    }
    return switch (r['error']) {
      'motivo_obrigatorio' => 'Escreva o motivo (mínimo 5 letras).',
      'estado_invalido' => 'Só dá para pedidos a caminho (status atual: ${r['status']}).',
      'pedido_nao_encontrado' => 'Pedido não encontrado.',
      _ => 'Não foi possível: ${r['error'] ?? 'erro desconhecido'}',
    };
  }

  Future<void> _abrir(BuildContext context) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _MotivoDialog(),
    );
    if (motivo == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (motivo.length < 5) {
      messenger.showSnackBar(const SnackBar(content: Text('Escreva o motivo (mínimo 5 letras).')));
      return;
    }
    String msg;
    bool ok = false;
    try {
      final r = await (marcar ?? marcarNoServidor)(orderId, motivo);
      ok = r['ok'] == true;
      msg = mensagem(r);
    } catch (e) {
      msg = 'Erro: $e';
    }
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    if (ok) onDone();
  }

  @override
  Widget build(BuildContext context) {
    if (status != 'onTheWay') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('btn_entregue_sem_codigo'),
          onPressed: () => _abrir(context),
          icon: const Icon(Icons.verified_outlined, color: AppColors.primary),
          label: const Text('Marcar entregue sem código'),
        ),
      ),
    );
  }
}

/// A janela do motivo é dona do seu campo de texto: o campo só é libertado
/// quando a janela sai do ecrã (fechar a meio da animação rebentava).
class _MotivoDialog extends StatefulWidget {
  const _MotivoDialog();

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Marcar entregue sem código'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Use só quando o cliente já recebeu e o entregador esqueceu de pedir o código (PIN). '
              'Fica registrado no log de auditoria com o seu nome.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('motivo_sem_codigo'),
            controller: _ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatório)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        ElevatedButton(
          key: const Key('confirmar_sem_codigo'),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Marcar entregue'),
        ),
      ],
    );
  }
}
