import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/fatura_nif_service.dart';
import '../utils/nif_pt.dart';

/// Aviso do ACOMPANHAMENTO quando o NIF do cliente ainda não ficou no pedido
/// (as 3 tentativas falharam). Só aparece enquanto o pedido está na loja — é
/// quando o servidor ainda aceita o NIF (`client_set_order_invoice` recusa com
/// `TARDE_DEMAIS` depois de o pedido sair).
///
/// O NIF nunca atrasa o pedido: isto é só um aviso com "Tentar de novo".
class FaturaNifAviso extends StatefulWidget {
  const FaturaNifAviso({super.key, required this.order, this.servico});

  final OrderModel order;

  /// Para testes; por defeito é a instância da app.
  final FaturaNifService? servico;

  /// O pedido ainda está na loja (o servidor ainda aceita o NIF)?
  static bool aindaNaLoja(OrderModel o) =>
      o.takeawayPickedUpAt == null &&
      const {
        OrderStatus.created,
        OrderStatus.preparing,
        OrderStatus.callingDriver,
        OrderStatus.driverAccepted,
        OrderStatus.readyForPickup,
      }.contains(o.status);

  @override
  State<FaturaNifAviso> createState() => _FaturaNifAvisoState();
}

class _FaturaNifAvisoState extends State<FaturaNifAviso> {
  bool _aTentar = false;

  FaturaNifService get _servico => widget.servico ?? FaturaNifService.instance;

  Future<void> _tentarDeNovo() async {
    if (_aTentar) return;
    setState(() => _aTentar = true);
    final ok = await _servico.tentarDeNovo(widget.order.id);
    if (!mounted) return;
    setState(() => _aTentar = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'NIF registado na fatura.'.tr
          : 'Ainda não deu. Tenta de novo daqui a pouco.'.tr),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _servico,
      builder: (context, _) {
        final pendente = _servico.pendenteDe(widget.order.id);
        if (pendente == null ||
            pendente.motivo != MotivoFaturaPendente.rede ||
            !FaturaNifAviso.aindaNaLoja(widget.order)) {
          return const SizedBox.shrink();
        }
        return Container(
          key: const Key('fatura_nif_aviso'),
          margin: const EdgeInsets.only(bottom: Spacing.md),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'O NIF ainda não ficou na fatura deste pedido.'.tr,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                key: const Key('fatura_nif_tentar_de_novo'),
                onPressed: _aTentar ? null : _tentarDeNovo,
                child: _aTentar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Tentar de novo'.tr),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Linha do DETALHE do pedido: "Fatura com NIF 123 456 789" (e o nome, se o
/// cliente o deu). Não mostra nada quando o pedido não tem pedido de fatura.
class FaturaNifLinha extends StatefulWidget {
  const FaturaNifLinha({super.key, required this.orderId, this.servico});

  final String orderId;
  final FaturaNifService? servico;

  @override
  State<FaturaNifLinha> createState() => _FaturaNifLinhaState();
}

class _FaturaNifLinhaState extends State<FaturaNifLinha> {
  late Future<DadosFatura?> _dados;

  FaturaNifService get _servico => widget.servico ?? FaturaNifService.instance;

  @override
  void initState() {
    super.initState();
    _dados = _ler();
  }

  @override
  void didUpdateWidget(covariant FaturaNifLinha old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId) _dados = _ler();
  }

  /// Ler nunca estraga o detalhe do pedido: sem leitura, sem linha.
  Future<DadosFatura?> _ler() async {
    try {
      return await _servico.lerDoPedido(widget.orderId);
    } catch (e) {
      debugPrint('[FaturaNif] pedido ${widget.orderId} sem leitura: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DadosFatura?>(
      future: _dados,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        return Padding(
          key: const Key('fatura_nif_linha'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.nome == null
                      ? 'Fatura com NIF {0}'.trArgs([formatarNif(d.nif)])
                      : 'Fatura com NIF {0} · {1}'
                          .trArgs([formatarNif(d.nif), d.nome]),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
