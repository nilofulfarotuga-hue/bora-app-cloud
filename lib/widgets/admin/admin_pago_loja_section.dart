import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/euros.dart';

/// pagar-na-loja (10/11/2026, business_rules 2.4.2) — painel ADMIN (PT-BR).
///
/// Mostra o que o servidor decidiu sobre a loja (`orders.loja_pagamento_estado`
/// e `loja_pagar_valor`) e deixa o admin corrigir "quanto o estafeta pagou de
/// fato à loja" (RPC `admin_corrigir_pago_loja`, que grava no
/// `admin_audit_log` e acerta o fechamento do estafeta e da loja).
class AdminPagoLojaSection extends StatefulWidget {
  const AdminPagoLojaSection({super.key, required this.order, this.onSalvo});

  final Map<String, dynamic> order;

  /// Chamado depois de uma correção gravada (para recarregar o pedido).
  final VoidCallback? onSalvo;

  /// Nome em PT-BR de cada situação, com o termo técnico explicado.
  static String rotulo(String? estado) {
    switch (estado) {
      case 'pagar_loja':
        return 'Pagar na loja (o entregador paga a loja em dinheiro na retirada)';
      case 'ja_pago':
        return 'Já pago (cartão/MB Way pelo app — o entregador não paga nem cobra)';
      case 'fazer_compra':
        return 'Fazer compra (loja não parceira — o entregador compra e fotografa o cupom)';
      case 'parceiro_chamou':
        return 'Parceiro chamou entregador (fluxo 2.4.1 — paga o total à loja)';
      case 'ir_buscar':
        return 'Retirada no balcão (takeaway — sem entregador)';
    }
    return 'Sem loja (Favor, levar/enviar) ou pedido antigo';
  }

  @override
  State<AdminPagoLojaSection> createState() => _AdminPagoLojaSectionState();
}

class _AdminPagoLojaSectionState extends State<AdminPagoLojaSection> {
  final _valor = TextEditingController();
  final _motivo = TextEditingController();
  bool _salvando = false;
  String? _msg;

  @override
  void dispose() {
    _valor.dispose();
    _motivo.dispose();
    super.dispose();
  }

  double? _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  Future<void> _corrigir() async {
    final v = double.tryParse(_valor.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0) {
      setState(() => _msg = 'Escreva um valor válido (ex.: 13,80).');
      return;
    }
    if (_motivo.text.trim().isEmpty) {
      setState(() => _msg = 'Escreva o motivo (fica no registro de auditoria).');
      return;
    }
    setState(() {
      _salvando = true;
      _msg = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('admin_corrigir_pago_loja',
          params: {
            'p_order_id': widget.order['id'],
            'p_valor': v,
            'p_motivo': _motivo.text.trim(),
          });
      final m = (r is Map) ? r : const {};
      setState(() => _msg =
          'Corrigido: antes ${eur(_num(m['antes']) ?? 0)}, agora ${eur(_num(m['agora']) ?? v)}.');
      widget.onSalvo?.call();
    } catch (e) {
      final t = e.toString();
      setState(() => _msg = t.contains('semana_ja_fechada')
          ? 'Não dá: a semana deste pedido já foi paga/recebida.'
          : 'Não foi possível corrigir: $t');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final estado = o['loja_pagamento_estado'] as String?;
    final previsto = _num(o['loja_pagar_valor']) ?? 0;
    final fechado = o['is_purchase_finalized'] == true;
    final pagoDeFato = fechado ? _num(o['final_purchase_value']) : null;
    final ehPagarLoja = estado == 'pagar_loja';

    return Card(
      key: const Key('admin_pago_loja_section'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loja e entregador (pagamento na retirada)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Situação: ${AdminPagoLojaSection.rotulo(estado)}',
                style: const TextStyle(fontSize: 13)),
            if (ehPagarLoja) ...[
              const SizedBox(height: 6),
              Text('Estafeta paga à loja: ${eur(previsto)}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent)),
              Text(
                  pagoDeFato == null
                      ? 'Pago de fato à loja: ainda não registrado (registra na retirada)'
                      : 'Pago de fato à loja (registrado): ${eur(pagoDeFato)}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              const Text(
                  'Corrigir quanto o entregador pagou de fato à loja '
                  '(o fechamento do entregador e da loja passa a usar este valor):',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('admin_pago_loja_valor'),
                    controller: _valor,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Valor (€)', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('admin_pago_loja_motivo'),
                    controller: _motivo,
                    decoration: const InputDecoration(
                        labelText: 'Motivo', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('admin_pago_loja_corrigir'),
                onPressed: _salvando ? null : _corrigir,
                icon: const Icon(Icons.edit_note),
                label: Text(_salvando ? 'Salvando…' : 'Corrigir valor pago'),
              ),
            ],
            if (_msg != null) ...[
              const SizedBox(height: 6),
              Text(_msg!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
