// Painel admin (PT-BR) — peso variável de um produto (31/10/2026).
//
// Liga/desliga `products.variable_weight` pela RPC `admin_set_variable_weight`
// (p_product_id, p_on, p_reason), que grava no admin_audit_log o antes, o
// depois e o motivo. Motivo obrigatório.
//
// Peso variável = mercados NÃO-parceiros: o preço da app é uma estimativa; o
// estafeta escreve o valor da etiqueta da balança e o cliente paga o valor
// final, com a mesma margem do produto (limite em weight_adjust_max_pct).
// Não confundir com "Ao peso" (`sold_by_weight`, porções de 200 g dos
// parceiros), que tem o seu próprio diálogo (admin_product_weight_dialog.dart).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '_admin_rpc_errors.dart';

/// Abre o diálogo. Devolve `true` quando gravou.
Future<bool> showAdminProductVariableWeightDialog(
  BuildContext context, {
  required String productId,
  required String productName,
  required bool variableWeight,
  required bool isPartner,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _AdminProductVariableWeightDialog(
      productId: productId,
      productName: productName,
      variableWeight: variableWeight,
      isPartner: isPartner,
    ),
  );
  return saved == true;
}

class _AdminProductVariableWeightDialog extends StatefulWidget {
  const _AdminProductVariableWeightDialog({
    required this.productId,
    required this.productName,
    required this.variableWeight,
    required this.isPartner,
  });

  final String productId;
  final String productName;
  final bool variableWeight;
  final bool isPartner;

  @override
  State<_AdminProductVariableWeightDialog> createState() =>
      _AdminProductVariableWeightDialogState();
}

class _AdminProductVariableWeightDialogState
    extends State<_AdminProductVariableWeightDialog> {
  late bool _on;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _on = widget.variableWeight;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reasonCtrl.text.trim();
    if (_on == widget.variableWeight) {
      setState(() => _error = 'Nada mudou: o interruptor está como já estava.');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Motivo obrigatório (mín. 3 caracteres).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_set_variable_weight',
        params: {
          'p_product_id': widget.productId,
          'p_on': _on,
          'p_reason': reason,
        },
      );
      if (res is! Map || res['ok'] != true) {
        throw StateError('o servidor não confirmou');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is StateError
            ? 'Erro ao salvar: ${e.message}'
            : humanizeAdminRpcError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Peso variável — ${widget.productName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Peso variável (preço pela balança)'),
              subtitle: const Text(
                  'O preço da app passa a ser uma estimativa: o estafeta '
                  'escreve o valor da etiqueta da balança e o cliente paga o '
                  'valor final, com a mesma margem do produto.'),
              value: _on,
              onChanged: _saving ? null : (v) => setState(() => _on = v),
            ),
            const Text(
              'Não é o mesmo que "Ao peso" (porções de 200 g das lojas '
              'parceiras): isso fica no botão da balança, ao lado.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (widget.isPartner) ...[
              const SizedBox(height: 8),
              const Text(
                'Atenção: esta loja é PARCEIRA. O ajuste de peso só funciona '
                'nos mercados não-parceiros — ligar aqui não muda nada nos '
                'pedidos desta loja.',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório, mín. 3)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvando…' : 'Salvar'),
        ),
      ],
    );
  }
}
