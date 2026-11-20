// Painel (PT-BR) — sacola para viagem do pedido (20/11/2026).
//
// Restaurante NÃO-parceiro (McDonald's, Burger King, KFC…): o entregador
// compra no balcão e tem de marcar "Comprei o saco" no app antes de fechar a
// compra. Aqui o Danilo vê se a sacola foi marcada, por quem e quando, e um
// alerta quando a compra foi fechada sem a marca. Lê
// `admin_saco_viagem_do_pedido` (só admin). Não mexe em dinheiro.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSacoViagemSection extends StatefulWidget {
  const AdminSacoViagemSection({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminSacoViagemSection> createState() => _AdminSacoViagemSectionState();
}

class _AdminSacoViagemSectionState extends State<AdminSacoViagemSection> {
  Map<String, dynamic>? _dados;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final res = await Supabase.instance.client.rpc('admin_saco_viagem_do_pedido',
          params: {'p_order_id': widget.orderId});
      if (!mounted) return;
      setState(() {
        _dados = res is Map ? Map<String, dynamic>.from(res) : null;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      final texto = e.toString();
      setState(() => _erro = texto.contains('PGRST202') ||
              texto.contains('does not exist')
          ? 'A função admin_saco_viagem_do_pedido ainda não foi publicada no '
              'servidor (migração 20261120122800).'
          : texto);
    }
  }

  static String _hora(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Sacola para viagem: $_erro'),
        ),
      );
    }
    final d = _dados;
    // Só restaurante não-parceiro com sacola: nos outros não desenha nada.
    if (d == null || d['ok'] != true || d['obrigatorio'] != true) {
      return const SizedBox.shrink();
    }
    final marcado = d['marcado'] == true;
    final fechada = d['compra_fechada'] == true;
    final semSaco = d['fechado_sem_saco'] == true;
    final appPediu = d['app_pediu_saco'] == true;

    final Color cor;
    final IconData icone;
    final String titulo;
    if (marcado) {
      cor = const Color(0xFF16A34A);
      icone = Icons.check_circle;
      titulo = 'Sacola para viagem: marcada pelo entregador';
    } else if (semSaco) {
      cor = Colors.red.shade700;
      icone = Icons.warning_amber_rounded;
      titulo = 'ALERTA: compra fechada SEM marcar a sacola para viagem';
    } else {
      cor = const Color(0xFFF97316);
      icone = Icons.shopping_bag;
      titulo = 'Sacola para viagem: ainda não marcada';
    }

    return Card(
      key: const Key('admin_saco_viagem'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15, color: cor)),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text('Loja: ${d['loja'] ?? '—'} · sacolas no pedido: ${d['sacos'] ?? '—'} '
                '(o cliente já pagou 0,30 € no checkout)'),
            if (marcado)
              Text('Marcada por ${d['marcado_por'] ?? '—'} em ${_hora(d['marcado_em'])}.'),
            if (semSaco)
              Text(
                appPediu
                    ? 'O app pediu a sacola mas a compra foi fechada sem a marca '
                        '(fechamento pelo painel/servidor). Confirmar com o '
                        'entregador se pediu a sacola no balcão.'
                    : 'A compra foi fechada por um app antigo (sem o botão '
                        '"Comprei o saco") ou antes de 20/11/2026.',
                style: TextStyle(color: Colors.red.shade800),
              ),
            if (!marcado && !fechada)
              const Text(
                'O botão "Confirmar compra" do entregador fica bloqueado até ele '
                'marcar "Comprei o saco".',
              ),
            const SizedBox(height: 4),
            Text(
              'Como funciona: em restaurante não-parceiro o entregador compra '
              'no balcão; o app mostra "SACO PARA VIAGEM" no topo e o servidor '
              'recusa fechar a compra (código SACO_VIAGEM_POR_MARCAR) sem a marca. '
              'O valor da sacola entra no cupom fiscal e no reembolso dele.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
