// lib/widgets/admin/ligado_sem_sinal.dart
//
// [24/10/2026 · geral-sabado-24-10, bloco 1] Painel admin (PT-BR): em vez do
// "Online" falso, "Ligado sem sinal desde [hora]" + botão "Enviar aviso agora"
// (RPC admin_driver_avisar_sem_sinal → push "Estás ligado, mas sem sinal" ao
// telemóvel do motorista; fica no admin_audit_log). O servidor já manda o
// mesmo aviso sozinho (10 min, de 30 em 30 min até 6 h, depois de 6 em 6 h).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/sinal_motorista.dart';

/// Linha vermelha "Ligado sem sinal desde …" com o botão do aviso. Só se
/// desenha quando [ligadoSemSinal] é verdadeiro; senão devolve nada.
class LigadoSemSinalLinha extends StatelessWidget {
  const LigadoSemSinalLinha({
    super.key,
    required this.userId,
    required this.ultimoSinal,
    this.nome,
    this.compacto = false,
  });

  /// `drivers.user_id` (identidade do motorista — regra de 16/08).
  final String? userId;
  final DateTime? ultimoSinal;
  final String? nome;

  /// Numa lista: texto e botão mais pequenos.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final tamanho = compacto ? 12.0 : 13.0;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.signal_wifi_bad, size: tamanho + 1, color: AppColors.error),
              const SizedBox(width: 3),
              Text(
                ligadoSemSinalTexto(ultimoSinal),
                style: TextStyle(
                  fontSize: tamanho,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (userId != null && userId!.isNotEmpty)
            BotaoAvisarSemSinal(userId: userId!, nome: nome, compacto: compacto),
        ],
      ),
    );
  }
}

class BotaoAvisarSemSinal extends StatefulWidget {
  const BotaoAvisarSemSinal({
    super.key,
    required this.userId,
    this.nome,
    this.compacto = false,
  });

  final String userId;
  final String? nome;
  final bool compacto;

  @override
  State<BotaoAvisarSemSinal> createState() => _BotaoAvisarSemSinalState();
}

class _BotaoAvisarSemSinalState extends State<BotaoAvisarSemSinal> {
  bool _aEnviar = false;

  Future<void> _enviar() async {
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    String msg;
    try {
      final r = await Supabase.instance.client.rpc(
        'admin_driver_avisar_sem_sinal',
        params: {'p_user_id': widget.userId},
      );
      final ok = r is Map && r['ok'] == true;
      final quem = (widget.nome ?? '').trim().isEmpty ? 'o motorista' : widget.nome!.trim();
      msg = ok
          ? 'Aviso enviado para $quem. Se o celular dele estiver com internet, a notificação chega agora.'
          : (r is Map && r['motivo'] != null
              ? r['motivo'].toString()
              : 'Não foi possível enviar o aviso.');
    } catch (e) {
      msg = 'Erro ao enviar o aviso: $e';
    }
    if (!mounted) return;
    setState(() => _aEnviar = false);
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final estilo = TextButton.styleFrom(
      foregroundColor: AppColors.error,
      padding: EdgeInsets.symmetric(horizontal: widget.compacto ? 6 : 10),
      minimumSize: Size(0, widget.compacto ? 28 : 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(fontSize: widget.compacto ? 12 : 13, fontWeight: FontWeight.w600),
    );
    return TextButton.icon(
      style: estilo,
      onPressed: _aEnviar ? null : _enviar,
      icon: _aEnviar
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.notifications_active, size: widget.compacto ? 15 : 17),
      label: const Text('Enviar aviso agora'),
    );
  }
}
