/// AGENDAR PEDIDOS (item 5, 29/10/2026) — o atalho "Pedidos agendados" do painel
/// do parceiro. Só aparece com o interruptor `scheduled_orders_enabled` ligado;
/// desligado (ou sem rede) não ocupa espaço nenhum.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/restaurant_model.dart';
import '../../screens/partner/partner_agendados_screen.dart';
import '../../services/agendar_pedido.dart';
import '../../services/agendar_pedido_service.dart';

class PartnerAgendadosAtalho extends StatefulWidget {
  const PartnerAgendadosAtalho({
    super.key,
    required this.restaurant,
    this.estado,
    this.relogio,
  });

  final RestaurantModel restaurant;

  /// Só para testes: outro estado (com a sua porta de mentira).
  final AgendarPedidoEstado? estado;
  final DateTime Function()? relogio;

  @override
  State<PartnerAgendadosAtalho> createState() => _PartnerAgendadosAtalhoState();
}

class _PartnerAgendadosAtalhoState extends State<PartnerAgendadosAtalho> {
  late final AgendarPedidoEstado _estado = widget.estado ?? AgendarPedidoEstado.instance;
  bool _ligado = false;
  List<PedidoAgendado> _pedidos = const [];

  DateTime _agora() => (widget.relogio ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_ler());
  }

  Future<void> _ler() async {
    final cfg = await _estado.carregarConfig();
    if (!mounted || !cfg.ligado) return;
    List<PedidoAgendado> lista = const [];
    try {
      lista = await _estado.api.pedidosDoParceiro(widget.restaurant.id);
    } catch (_) {
      // o atalho continua a servir mesmo sem a contagem
    }
    if (!mounted) return;
    setState(() {
      _ligado = true;
      _pedidos = lista;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final agora = _agora();
    final proximo = _pedidos.isEmpty ? null : _pedidos.first;
    final descricao = proximo == null
        ? 'Os pedidos marcados para mais tarde, com o aviso 30 minutos antes.'
        : '${_pedidos.length} agendado${_pedidos.length == 1 ? '' : 's'} · próximo: ${faltaTexto(proximo.quando, agora)}.';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        key: const Key('atalho-agendados'),
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PartnerAgendadosScreen(restaurant: widget.restaurant),
            ),
          );
          if (mounted) unawaited(_ler());
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.event_available, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedidos agendados',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      descricao,
                      key: const Key('atalho-agendados-texto'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
