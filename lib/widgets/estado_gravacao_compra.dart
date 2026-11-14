// Compra guardada (14/11/2026): o "a guardar… / guardado" discreto da lista
// de compras do estafeta. Sem rede diz que ficou no telemóvel — o estafeta
// sabe que nada se perde e que sobe sozinho.

import 'package:flutter/material.dart';

import '../services/compra_rascunho_service.dart';

class EstadoGravacaoCompraTexto extends StatelessWidget {
  const EstadoGravacaoCompraTexto({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoGravacaoCompra>(
      valueListenable: CompraRascunhoService.estado(orderId),
      builder: (context, estado, _) {
        final (IconData? icone, String texto, Color cor) = switch (estado) {
          EstadoGravacaoCompra.nada => (null, '', Colors.transparent),
          EstadoGravacaoCompra.aGuardar =>
            (Icons.cloud_upload_outlined, 'A guardar…', Colors.grey.shade600),
          EstadoGravacaoCompra.guardado =>
            (Icons.cloud_done_outlined, 'Guardado', Colors.green.shade700),
          EstadoGravacaoCompra.soNoTelemovel => (
              Icons.phone_android,
              'Guardado no telemóvel · envia com rede',
              Colors.orange.shade800
            ),
        };
        if (icone == null) return const SizedBox.shrink();
        return Semantics(
          identifier: 'compra_estado_gravacao',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 14, color: cor),
              const SizedBox(width: 4),
              Text(texto, style: TextStyle(fontSize: 11.5, color: cor)),
            ],
          ),
        );
      },
    );
  }
}
