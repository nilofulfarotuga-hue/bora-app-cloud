import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/pedido_origem_service.dart';

/// Etiqueta pequena "WhatsApp" para pedidos feitos pelo robô de WhatsApp.
/// Só aparece quando [origem] == 'whatsapp'; com 'app' ou `null` não mostra
/// nada (ocupa zero espaço). Verde Bora, sem laranja.
class OrigemWhatsAppChip extends StatelessWidget {
  const OrigemWhatsAppChip({super.key, required this.origem});

  final String? origem;

  @override
  Widget build(BuildContext context) {
    if (!origemEhWhatsApp(origem)) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat, size: 12, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'WhatsApp',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco "Cliente" do cartão do pedido do parceiro: rótulo, nome e — nos
/// pedidos do robô de WhatsApp — a etiqueta "WhatsApp" junto ao rótulo e o
/// telefone do cliente por baixo do nome (o do pedido; se vier vazio, o de
/// order_origem). Pedidos da app: só rótulo e nome, como sempre.
class ClienteDoPedido extends StatelessWidget {
  const ClienteDoPedido({
    super.key,
    required this.nome,
    this.origem,
    this.telefonePedido,
    this.telefoneOrigem,
  });

  final String? nome;
  final String? origem;
  final String? telefonePedido;
  final String? telefoneOrigem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zap = origemEhWhatsApp(origem);
    final telefone = zap
        ? telefoneDoCliente(doPedido: telefonePedido, daOrigem: telefoneOrigem)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cliente',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            if (zap) ...[
              const SizedBox(width: 8),
              OrigemWhatsAppChip(origem: origem),
            ],
          ],
        ),
        Text(
          nome ?? 'Cliente BORA',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (telefone != null)
          Text(
            telefone,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
            ),
          ),
      ],
    );
  }
}

/// Linha "Origem: App" / "Origem: [WhatsApp]" da lista de pedidos do admin.
class OrigemPedidoLinha extends StatelessWidget {
  const OrigemPedidoLinha({super.key, required this.origem});

  final String? origem;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Origem: ', style: estilo),
        if (origemEhWhatsApp(origem))
          OrigemWhatsAppChip(origem: origem)
        else
          Text(rotuloOrigem(origem),
              style: estilo.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
