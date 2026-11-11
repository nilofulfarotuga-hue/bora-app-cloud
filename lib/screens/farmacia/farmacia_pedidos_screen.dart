// Os pedidos do cliente a uma farmácia (missão farmacias-2026-11-11).
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/prescricao_service.dart';
import 'prescricao_estado_screen.dart';

String rotuloEstadoPrescricao(PrescricaoEstado e) {
  switch (e) {
    case PrescricaoEstado.enviado:
      return 'À espera da farmácia';
    case PrescricaoEstado.aceite:
      return 'A farmácia tem — falta confirmar';
    case PrescricaoEstado.aceiteParcial:
      return 'A farmácia tem parte — falta confirmar';
    case PrescricaoEstado.recusado:
      return 'A farmácia não tem';
    case PrescricaoEstado.expirado:
      return 'Sem resposta a tempo';
    case PrescricaoEstado.cancelado:
      return 'Cancelado';
    case PrescricaoEstado.confirmado:
      return 'Confirmado';
    case PrescricaoEstado.entregue:
      return 'Entregue';
  }
}

class FarmaciaPedidosScreen extends StatefulWidget {
  const FarmaciaPedidosScreen({super.key, required this.restaurantId, required this.farmaciaNome});
  final String restaurantId;
  final String farmaciaNome;

  @override
  State<FarmaciaPedidosScreen> createState() => _FarmaciaPedidosScreenState();
}

class _FarmaciaPedidosScreenState extends State<FarmaciaPedidosScreen> {
  late Future<List<PedidoPrescricao>> _f = PrescricaoService().meus(restaurantId: widget.restaurantId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Pedidos à ${widget.farmaciaNome}')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _f = PrescricaoService().meus(restaurantId: widget.restaurantId));
          await _f;
        },
        child: FutureBuilder<List<PedidoPrescricao>>(
          future: _f,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final l = s.data ?? const [];
            if (l.isEmpty) {
              return ListView(children: const [
                Padding(padding: EdgeInsets.all(32), child: Text('Ainda não fez pedidos a esta farmácia.', textAlign: TextAlign.center)),
              ]);
            }
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: l.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = l[i];
                final d = p.createdAt;
                final quando = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    leading: Icon(p.eReceita ? Icons.receipt_long : Icons.search, color: AppColors.primary),
                    title: Text(p.eReceita ? 'Receita' : (p.descricao ?? 'Pedido especial'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('$quando · ${rotuloEstadoPrescricao(p.estado)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PrescricaoEstadoScreen(prescricaoId: p.id)),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
