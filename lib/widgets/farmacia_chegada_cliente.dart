// Cliente — "um produto só chega às HH:MM" (missão farmacias-loja-2026-11-14, bloco 3).
// Aparece no acompanhamento do pedido quando a farmácia marcou uma hora. O cliente escolhe:
// esperar (o pedido fica agendado para essa hora), tirar o produto (a farmácia tira-o pela
// edição de pedido de sempre) ou cancelar sem custo (cancelamento de sempre, taxa 0).
// Texto direto em PT-PT, como os outros ecrãs da farmácia do cliente.
import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/farmacia_chegada.dart';
import '../models/order_model.dart';
import '../services/farmacia_chegada_service.dart';
import 'partner/farmacia_painel.dart' show hhmmFarmacia;

class ClienteChegadaTardiaCartao extends StatefulWidget {
  const ClienteChegadaTardiaCartao({super.key, required this.order});

  final OrderModel order;

  /// Só pedidos de lojas parceiras com entrega podem ter hora marcada (igual ao servidor).
  static bool podeTer(OrderModel o) =>
      o.isPartnerStore &&
      o.serviceType == OrderServiceType.restaurant &&
      o.status != OrderStatus.delivered &&
      o.status != OrderStatus.cancelled &&
      o.status != OrderStatus.rejected;

  @override
  State<ClienteChegadaTardiaCartao> createState() => _ClienteChegadaTardiaCartaoState();
}

class _ClienteChegadaTardiaCartaoState extends State<ClienteChegadaTardiaCartao> {
  Stream<List<FarmaciaChegada>>? _stream;
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    if (ClienteChegadaTardiaCartao.podeTer(widget.order)) {
      try {
        _stream = FarmaciaChegadaService.instance.doPedido(widget.order.id);
      } catch (e) {
        // Sem Supabase (ex.: testes) não se mostra nada.
        debugPrint('[ClienteChegadaTardia] $e');
      }
    }
  }

  bool get _semEstafeta =>
      widget.order.assignedDriverId == null &&
      (widget.order.status == OrderStatus.created ||
          widget.order.status == OrderStatus.preparing);

  Future<void> _responder(FarmaciaChegada c, EscolhaChegada escolha) async {
    if (_aEnviar) return;
    if (escolha == EscolhaChegada.cancelar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar o pedido?'),
          content: const Text(
              'Não paga nada por cancelar. Se já pagou, o dinheiro volta pelo mesmo meio.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar pedido'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FarmaciaChegadaService.instance.responder(c.id, escolha);
      messenger.showSnackBar(SnackBar(
        content: Text(switch (escolha) {
          EscolhaChegada.esperar =>
            'Combinado. O pedido fica para as ${hhmmFarmacia(c.chegaAs)}.',
          EscolhaChegada.tirar =>
            'Combinado. A farmácia tira o produto e a diferença volta para si.',
          EscolhaChegada.cancelar => 'Pedido cancelado sem custo.',
        }),
      ));
    } on FarmaciaChegadaErro catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stream;
    if (s == null) return const SizedBox.shrink();
    return StreamBuilder<List<FarmaciaChegada>>(
      stream: s,
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final c = FarmaciaChegada.maisRecente(snap.data!);
        if (c == null) return const SizedBox.shrink();
        final hora = hhmmFarmacia(c.chegaAs);
        switch (c.estado) {
          case EstadoChegada.pendente:
            return _pergunta(c, hora);
          case EstadoChegada.esperar:
            return _nota(
              'Pedido agendado para as $hora. A farmácia prepara-o quando o produto chegar e o estafeta é chamado perto da hora.',
              Icons.event_available,
              AppColors.primary,
            );
          case EstadoChegada.tirar:
            return _nota(
              'Pediu sem ${c.produtoNome != null ? '"${c.produtoNome}"' : 'o produto'}. A farmácia tira-o do pedido e a diferença volta para si.',
              Icons.remove_shopping_cart_outlined,
              AppColors.primary,
            );
          case EstadoChegada.cancelar:
          case EstadoChegada.anulado:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _nota(String texto, IconData icone, Color cor) => Container(
        key: const Key('cliente_chegada_nota'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, style: const TextStyle(height: 1.3))),
          ],
        ),
      );

  Widget _pergunta(FarmaciaChegada c, String hora) {
    final titulo = c.produtoNome != null
        ? '"${c.produtoNome}" só chega à farmácia às $hora'
        : 'O seu pedido só fica pronto às $hora';
    final podeCancelar = _semEstafeta;
    return Container(
      key: const Key('cliente_chegada_pergunta'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.schedule, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(titulo,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('O que prefere?', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('cliente_chegada_esperar'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _aEnviar ? null : () => _responder(c, EscolhaChegada.esperar),
            child: Text('Esperar — receber depois das $hora'),
          ),
          if (c.eUmProduto) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('cliente_chegada_tirar'),
              onPressed: _aEnviar ? null : () => _responder(c, EscolhaChegada.tirar),
              child: const Text('Tirar este produto e receber já o resto'),
            ),
          ],
          if (podeCancelar) ...[
            const SizedBox(height: 4),
            TextButton(
              key: const Key('cliente_chegada_cancelar'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _aEnviar ? null : () => _responder(c, EscolhaChegada.cancelar),
              child: const Text('Cancelar sem custo'),
            ),
          ],
          if (!podeCancelar)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'O estafeta já foi chamado: para cancelar, fale com a farmácia pelo chat.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
