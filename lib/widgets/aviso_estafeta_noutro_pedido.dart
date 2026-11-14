// Adenda 1 do Danilo (14/11/2026): a entrega do cliente ficou na fila do
// estafeta (ele está a acabar outro pedido). O cliente vê-o aqui e recebe o
// mesmo aviso por notificação (gatilho trg_fila_avisar_cliente, um por pedido).
// Só pedidos de ENTREGA — o Favor nunca avisa (o cliente escolheu a janela de
// até 3 h). Lê `cliente_fila_do_meu_pedido`; sem resposta não desenha nada.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';

class AvisoEstafetaNoutroPedido extends StatefulWidget {
  const AvisoEstafetaNoutroPedido({super.key, required this.order});

  final OrderModel order;

  @override
  State<AvisoEstafetaNoutroPedido> createState() =>
      _AvisoEstafetaNoutroPedidoState();
}

class _AvisoEstafetaNoutroPedidoState extends State<AvisoEstafetaNoutroPedido> {
  bool _emEspera = false;
  String? _chaveLida;

  /// O pedido continua driverAccepted quando o estafeta acaba o outro e vem
  /// para este: enquanto o aviso está à vista, volta a perguntar a cada minuto.
  Timer? _reler;

  @override
  void dispose() {
    _reler?.cancel();
    super.dispose();
  }

  void _acertarReleitura() {
    if (_emEspera && _aplicavel) {
      _reler ??= Timer.periodic(const Duration(seconds: 60), (_) {
        _chaveLida = null;
        _ler();
      });
    } else {
      _reler?.cancel();
      _reler = null;
    }
  }

  bool get _aplicavel =>
      widget.order.serviceType != OrderServiceType.errand &&
      widget.order.status == OrderStatus.driverAccepted;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  @override
  void didUpdateWidget(covariant AvisoEstafetaNoutroPedido oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ler();
  }

  Future<void> _ler() async {
    // Uma leitura por estado do pedido (o realtime reconstrói muitas vezes).
    final chave = '${widget.order.id}|${widget.order.status.name}';
    if (_chaveLida == chave) return;
    _chaveLida = chave;
    if (!_aplicavel) {
      if (_emEspera && mounted) setState(() => _emEspera = false);
      _acertarReleitura();
      return;
    }
    try {
      final res = await Supabase.instance.client.rpc(
          'cliente_fila_do_meu_pedido',
          params: {'p_order_id': widget.order.id});
      final v = res is Map && res['em_espera'] == true;
      if (mounted && v != _emEspera) setState(() => _emEspera = v);
    } catch (_) {
      // Sem rede ou função por publicar: não mostra nada.
    }
    if (mounted) _acertarReleitura();
  }

  @override
  Widget build(BuildContext context) {
    if (!_emEspera || !_aplicavel) return const SizedBox.shrink();
    return Container(
      key: const Key('aviso_estafeta_noutro_pedido'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.delivery_dining, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'O estafeta está noutro pedido perto de si. Assim que o '
              'terminar, segue para o seu.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
