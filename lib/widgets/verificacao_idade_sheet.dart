// Missão maiores-18 (07/10/2026) — o passo obrigatório do estafeta antes de
// concluir a entrega de um pedido com tabaco ou álcool (igual à Glovo e à
// Uber Eats): folha não dispensável com duas escolhas.
//
//   "Vi o documento, tem 18 ou mais"   → driver_confirm_age_check(id, true)
//   "Não mostrou documento / é menor"  → confirmação → (id, false): o servidor
//                                        abre o pedido de cancelamento pelo
//                                        caminho que já existe; a app não mexe
//                                        em dinheiro.
//
// Sem escolha não há "entregar": o gatilho trg_orders_maior_18_guarda recusa
// o 'delivered' sem verificação confirmada, por isso o passo vem ANTES da
// foto e do PIN nos dois ecrãs do estafeta (home e mapa).
import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/maior_18_service.dart';
import 'bora/bora_bottom_action_bar.dart';
import 'bora/maior_18.dart';

/// O que o estafeta decidiu na folha.
enum VerificacaoIdadeDecisao {
  /// Documento visto (ou o pedido afinal não exige): pode concluir a entrega.
  seguir,

  /// Cliente sem documento / menor: pedido enviado para cancelamento.
  recusado,

  /// Nada foi decidido (sem contexto montado, etc.) — não se entrega.
  abortado,
}

class VerificacaoIdade {
  VerificacaoIdade._();

  /// Pedidos já confirmados nesta sessão — o retry do PIN não volta a pedir.
  static final Set<String> _confirmados = <String>{};

  /// Para testes: injecta a chamada ao servidor.
  @visibleForTesting
  static ConfirmarIdadeFn? confirmarOverride;

  /// Para testes: esquece os pedidos já confirmados nesta sessão.
  @visibleForTesting
  static void limparParaTestes() => _confirmados.clear();

  /// Garante o passo da idade antes de concluir. Devolve [seguir] quando o
  /// pedido não é +18, já estava confirmado, ou o estafeta confirmou agora.
  static Future<VerificacaoIdadeDecisao> garantir(
      BuildContext context, OrderModel order) async {
    if (!order.hasAgeRestricted) return VerificacaoIdadeDecisao.seguir;
    if (_confirmados.contains(order.id)) return VerificacaoIdadeDecisao.seguir;

    final decisao = await showModalBottomSheet<VerificacaoIdadeDecisao>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VerificacaoIdadeSheet(
        orderId: order.id,
        confirmar: confirmarOverride ?? Maior18Service.confirmar,
      ),
    );
    final d = decisao ?? VerificacaoIdadeDecisao.abortado;
    if (d == VerificacaoIdadeDecisao.seguir) _confirmados.add(order.id);
    if (d == VerificacaoIdadeDecisao.recusado && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Pedido enviado para cancelamento; o suporte trata do resto.'.tr),
        duration: const Duration(seconds: 5),
      ));
    }
    return d;
  }
}

/// A folha em si. Pública para o teste de widget; a app usa
/// [VerificacaoIdade.garantir].
class VerificacaoIdadeSheet extends StatefulWidget {
  const VerificacaoIdadeSheet({
    super.key,
    required this.orderId,
    required this.confirmar,
  });

  final String orderId;
  final ConfirmarIdadeFn confirmar;

  @override
  State<VerificacaoIdadeSheet> createState() => _VerificacaoIdadeSheetState();
}

class _VerificacaoIdadeSheetState extends State<VerificacaoIdadeSheet> {
  bool _aEnviar = false;
  String? _erro;

  Future<void> _enviar(bool ok) async {
    if (_aEnviar) return;
    setState(() {
      _aEnviar = true;
      _erro = null;
    });
    final r = await widget.confirmar(widget.orderId, ok);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _aEnviar = false;
        _erro = r.mensagem.tr;
      });
      return;
    }
    // ok: 'confirmado' | 'recusado'; `already` devolve o estado anterior;
    // `not_required` = o pedido afinal não é +18.
    final recusado = !r.naoExigida && r.status == 'recusado';
    Navigator.of(context).pop(recusado
        ? VerificacaoIdadeDecisao.recusado
        : VerificacaoIdadeDecisao.seguir);
  }

  Future<void> _recusar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Não entregar os artigos +18?'.tr),
        content: Text(
          'O pedido vai para cancelamento e o suporte trata do resto. Não entregues os artigos +18 ao cliente.'
              .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Voltar'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Confirmar recusa'.tr),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) await _enviar(false);
  }

  @override
  Widget build(BuildContext context) {
    // Não dispensável: nem o botão/gesto de voltar fecha a folha.
    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, BoraBottomActionBar.folgaInferior(context, base: 20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Maior18Badge(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pedido +18 — verificar idade'.tr,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Este pedido tem tabaco ou bebidas alcoólicas. Pede o documento de identificação ao cliente antes de entregar.'
                  .tr,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey.shade800,
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _erro!,
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _aEnviar ? null : () => _enviar(true),
              icon: _aEnviar
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text('Vi o documento, tem 18 ou mais'.tr),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _aEnviar ? null : _recusar,
              icon: const Icon(Icons.block_outlined),
              label: Text('Não mostrou documento / é menor'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
