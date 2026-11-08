// M1 08/11/2026 — NIF da fatura para o estafeta em loja NÃO-parceira.
//
// Regra do Danilo (08/11): "Não pode esquecer do NIF". Na caixa da loja o
// estafeta pede a fatura com o NIF que o cliente pediu; sem pedido de fatura,
// o talão leva o NIF da Bora. O texto e o NIF vêm do servidor (RPC
// `driver_order_invoice_nif`, docs/propostas/m1-dinheiro-favores-2026-11-08/
// 03_nif_estafeta_e_recibo_cliente.sql) — a app não decide nada.
//
// Na loja parceira (a loja trata da fatura), num erro ou com a função ainda
// fora do servidor, o cartão não aparece (nunca parte o ecrã onde está).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

class DriverInvoiceNifCard extends StatefulWidget {
  const DriverInvoiceNifCard({super.key, required this.orderId});

  final String orderId;

  @override
  State<DriverInvoiceNifCard> createState() => _DriverInvoiceNifCardState();
}

class _DriverInvoiceNifCardState extends State<DriverInvoiceNifCard> {
  Map<String, dynamic>? _dados;
  bool _copiado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant DriverInvoiceNifCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _dados = null;
      _copiado = false;
      _carregar();
    }
  }

  Future<void> _carregar() async {
    final id = widget.orderId;
    try {
      final res = await Supabase.instance.client.rpc(
        'driver_order_invoice_nif',
        params: {'p_order_id': id},
      );
      if (!mounted || id != widget.orderId) return;
      if (res is Map && res['ok'] == true && res['mostrar'] == true) {
        setState(() => _dados = Map<String, dynamic>.from(res));
      }
    } catch (e) {
      // Calado de propósito: sem o NIF o ecrã continua a funcionar.
      debugPrint('[nif-estafeta] $e');
    }
  }

  Future<void> _copiar(String nif) async {
    await Clipboard.setData(ClipboardData(text: nif));
    if (mounted) setState(() => _copiado = true);
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    if (d == null) return const SizedBox.shrink();
    final texto = (d['texto'] as String? ?? '').trim();
    final nif = (d['nif'] as String? ?? '').trim();
    if (texto.isEmpty && nif.isEmpty) return const SizedBox.shrink();
    final nome = (d['nome'] as String? ?? '').trim();
    return Container(
      key: const Key('driver_invoice_nif_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.receipt_long, color: AppColors.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (texto.isNotEmpty)
                  Text(
                    texto,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                if (nome.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Nome na fatura: $nome',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (nif.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          nif,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _copiar(nif),
                        icon: Icon(_copiado ? Icons.check : Icons.copy,
                            size: 18),
                        label: Text(_copiado ? 'Copiado' : 'Copiar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
