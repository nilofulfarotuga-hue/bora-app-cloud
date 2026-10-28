import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nome do cliente em destaque para o estafeta chamar a pessoa pelo nome
/// (pedido do Danilo, 25/10/2026: "tem que ter aqui o nome do cliente").
///
/// [soPrimeiroNome] = true na OFERTA (ainda não aceite, chega a vários
/// estafetas): só o primeiro nome, sem botão de ligar. Depois de aceite:
/// nome completo + botão "Ligar".
class ClienteNomeDestaque extends StatelessWidget {
  const ClienteNomeDestaque({
    super.key,
    required this.nome,
    this.telefone,
    this.soPrimeiroNome = false,
    this.compacto = false,
  });

  final String? nome;
  final String? telefone;
  final bool soPrimeiroNome;
  final bool compacto;

  static String? limpo(String? nome, {bool primeiro = false}) {
    final n = (nome ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return null;
    return primeiro ? n.split(' ').first : n;
  }

  Future<void> _ligar(BuildContext context) async {
    final tel = (telefone ?? '').replaceAll(' ', '').trim();
    if (tel.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:$tel'));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível ligar. Tenta de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = limpo(nome, primeiro: soPrimeiroNome) ?? 'Cliente sem nome';
    final temTel = !soPrimeiroNome && (telefone ?? '').trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compacto ? 6 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFF16A34A), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(soPrimeiroNome ? 'Para' : 'Cliente',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                Text(
                  n,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compacto ? 16 : 19, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (temTel)
            FilledButton.icon(
              onPressed: () => _ligar(context),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Ligar'),
            ),
        ],
      ),
    );
  }
}
