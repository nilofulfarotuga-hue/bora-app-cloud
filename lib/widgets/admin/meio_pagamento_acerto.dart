import 'package:flutter/material.dart';

import 'confirmar_dinheiro.dart';

/// Meio de pagamento de um acerto semanal (painel admin, PT-BR).
///
/// Porque existe (09/11/2026, missão pendencias-2026-11-09, Bloco B): o
/// comprovativo que a pessoa recebe dizia sempre "MB Way". O meio escolhido
/// aqui vai no texto de `payment_reference` do acerto; o gatilho
/// `_settlement_receipt_enqueue` copia-o para `settlement_receipts` e a Edge
/// `settlement-receipt` escreve "transferência bancária", "MB Way para …",
/// "Stripe" ou "dinheiro". Com "Não informar" o comprovativo diz só
/// "Pagamento efetuado" — nunca inventa o meio.
enum MeioPagamentoAcerto { naoInformar, mbway, transferencia, dinheiro, stripe }

extension MeioPagamentoAcertoX on MeioPagamentoAcerto {
  /// Texto do botão e início do `payment_reference` (a Edge reconhece-o).
  String get rotulo => switch (this) {
        MeioPagamentoAcerto.naoInformar => 'Não informar',
        MeioPagamentoAcerto.mbway => 'MB Way',
        MeioPagamentoAcerto.transferencia => 'Transferência bancária',
        MeioPagamentoAcerto.dinheiro => 'Dinheiro',
        MeioPagamentoAcerto.stripe => 'Stripe',
      };

  /// Valor para as funções que também guardam `payment_method`.
  String? get codigo => switch (this) {
        MeioPagamentoAcerto.naoInformar => null,
        MeioPagamentoAcerto.mbway => 'mbway',
        MeioPagamentoAcerto.transferencia => 'transferencia',
        MeioPagamentoAcerto.dinheiro => 'dinheiro',
        MeioPagamentoAcerto.stripe => 'stripe',
      };
}

/// Monta o `payment_reference`: "<meio>[ <número MB Way>][ · <observação>]".
/// Sem meio e sem observação devolve null (a função SQL mantém o que lá está).
String? referenciaComMeio(
  MeioPagamentoAcerto meio, {
  String? numeroMbway,
  String? observacao,
}) {
  final obs = observacao?.trim() ?? '';
  final numero = numeroMbway?.trim() ?? '';
  String? base;
  if (meio != MeioPagamentoAcerto.naoInformar) {
    base = meio.rotulo;
    if (meio == MeioPagamentoAcerto.mbway && numero.isNotEmpty) {
      base = '$base $numero';
    }
  }
  if (base == null) return obs.isEmpty ? null : obs;
  return obs.isEmpty ? base : '$base · $obs';
}

/// O que foi escolhido no seletor.
class EscolhaMeioPagamento {
  const EscolhaMeioPagamento(this.meio, {this.numeroMbway});

  final MeioPagamentoAcerto meio;
  final String? numeroMbway;

  String? get codigo => meio.codigo;

  String? referencia({String? observacao}) => referenciaComMeio(meio,
      numeroMbway: numeroMbway, observacao: observacao);
}

/// "Como foi pago?" — um chip por meio. Começa em "Não informar" de
/// propósito: se ninguém escolher, o comprovativo não inventa nada.
/// Com MB Way aparece o número (já preenchido com [numeroMbway] quando a Bora
/// paga e a pessoa tem MB Way registado).
class SeletorMeioPagamento extends StatefulWidget {
  const SeletorMeioPagamento({
    super.key,
    required this.onChanged,
    this.numeroMbway,
  });

  final ValueChanged<EscolhaMeioPagamento> onChanged;
  final String? numeroMbway;

  @override
  State<SeletorMeioPagamento> createState() => _SeletorMeioPagamentoState();
}

class _SeletorMeioPagamentoState extends State<SeletorMeioPagamento> {
  MeioPagamentoAcerto _meio = MeioPagamentoAcerto.naoInformar;
  late final TextEditingController _numero =
      TextEditingController(text: widget.numeroMbway ?? '');

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  void _avisar() => widget.onChanged(EscolhaMeioPagamento(_meio,
      numeroMbway:
          _meio == MeioPagamentoAcerto.mbway ? _numero.text.trim() : null));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Como foi pago? (vai no comprovativo)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in MeioPagamentoAcerto.values)
              ChoiceChip(
                key: ValueKey('meio_${m.name}'),
                label: Text(m.rotulo),
                selected: _meio == m,
                onSelected: (_) {
                  setState(() => _meio = m);
                  _avisar();
                },
              ),
          ],
        ),
        if (_meio == MeioPagamentoAcerto.mbway) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('meio_numero_mbway'),
            controller: _numero,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Número MB Way (opcional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _avisar(),
          ),
        ],
      ],
    );
  }
}

/// [confirmarDinheiro] com o seletor do meio por baixo. Devolve null se o
/// Danilo cancelar; senão o meio escolhido (pode ser "Não informar").
Future<EscolhaMeioPagamento?> confirmarDinheiroComMeio(
  BuildContext context, {
  required String titulo,
  required String nome,
  required String valor,
  String? detalhe,
  String? numeroMbway,
  String botao = 'Confirmar',
}) async {
  var escolha = const EscolhaMeioPagamento(MeioPagamentoAcerto.naoInformar);
  final ok = await confirmarDinheiro(
    context,
    titulo: titulo,
    nome: nome,
    valor: valor,
    detalhe: detalhe,
    botao: botao,
    extra: SeletorMeioPagamento(
      numeroMbway: numeroMbway,
      onChanged: (e) => escolha = e,
    ),
  );
  return ok ? escolha : null;
}
