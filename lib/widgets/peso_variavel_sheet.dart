// Folha "Quanto custou na etiqueta da balança?" — lista de compras do
// estafeta, produtos ao quilo dos mercados não-parceiros (31/10/2026).
// O servidor decide (estafeta_ajustar_peso); esta folha só lê o valor, mostra
// o intervalo e o erro real, e nunca deixa enviar duas vezes seguidas.

import 'package:flutter/material.dart';

import '../services/peso_variavel_estafeta_service.dart';
import '../utils/valor_em_centimos.dart';
import 'bora/bora_bottom_action_bar.dart';

class PesoVariavelSheet extends StatefulWidget {
  const PesoVariavelSheet({
    super.key,
    required this.nomeLinha,
    required this.estimadoCaixaCents,
    required this.enviar,
    this.valorAtualCents,
  });

  /// Ex.: "Banana × 4".
  final String nomeLinha;

  /// Preço previsto da linha toda na caixa (sem margem), em cêntimos.
  final int estimadoCaixaCents;

  /// Valor já escrito antes (corrigir um ajuste).
  final int? valorAtualCents;

  /// Chama o servidor. Injetado para os testes não precisarem de rede.
  final Future<PesoVariavelResultado> Function(int realCaixaCents) enviar;

  static Future<AjustePesoEstafeta?> abrir(
    BuildContext context, {
    required String nomeLinha,
    required int estimadoCaixaCents,
    required Future<PesoVariavelResultado> Function(int realCaixaCents) enviar,
    int? valorAtualCents,
  }) {
    return showModalBottomSheet<AjustePesoEstafeta>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PesoVariavelSheet(
        nomeLinha: nomeLinha,
        estimadoCaixaCents: estimadoCaixaCents,
        enviar: enviar,
        valorAtualCents: valorAtualCents,
      ),
    );
  }

  @override
  State<PesoVariavelSheet> createState() => _PesoVariavelSheetState();
}

class _PesoVariavelSheetState extends State<PesoVariavelSheet> {
  late final TextEditingController _ctrl;
  late int _minimo;
  late int _maximo;
  bool _aEnviar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final atual = widget.valorAtualCents;
    _ctrl = TextEditingController(
      text: atual == null
          ? ''
          : '${atual ~/ 100},${(atual % 100).toString().padLeft(2, '0')}',
    );
    final (minimo, maximo) =
        PesoVariavelEstafetaService.intervalo(widget.estimadoCaixaCents);
    _minimo = minimo;
    _maximo = maximo;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_aEnviar) return;
    final cents = valorEmCentimos(_ctrl.text);
    if (cents == null) {
      setState(() =>
          _erro = PesoVariavelEstafetaService.mensagemErro('valor_invalido'));
      return;
    }
    setState(() {
      _aEnviar = true;
      _erro = null;
    });
    final r = await widget.enviar(cents);
    if (!mounted) return;
    if (r.ok && r.ajuste != null) {
      Navigator.of(context).pop(r.ajuste);
      return;
    }
    setState(() {
      _aEnviar = false;
      // P5 (01/11/2026): peça ao quilo ("Melancia (~4 kg)") recusada pelo
      // limite → a mensagem diz o peso a procurar. Só texto.
      final pesoMedio = r.codigo == 'fora_do_limite'
          ? PesoVariavelEstafetaService.pesoMedioDoNome(widget.nomeLinha)
          : null;
      _erro = pesoMedio == null
          ? r.mensagem
          : PesoVariavelEstafetaService.mensagemErro('fora_do_limite',
              minimoCents: r.minimoCents,
              maximoCents: r.maximoCents,
              pesoMedioKg: pesoMedio);
      if (r.minimoCents != null && r.maximoCents != null) {
        _minimo = r.minimoCents!;
        _maximo = r.maximoCents!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const euros = PesoVariavelEstafetaService.euros;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, BoraBottomActionBar.folgaInferior(context, base: 20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.scale_outlined, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Quanto custou na etiqueta da balança?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.nomeLinha,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Previsto: ${euros(widget.estimadoCaixaCents)} · '
            'aceite de ${euros(_minimo)} a ${euros(_maximo)}',
            key: const Key('peso_intervalo'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('peso_campo'),
            controller: _ctrl,
            autofocus: true,
            enabled: !_aEnviar,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ValorEmEurosInputFormatter()],
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              labelText: 'Total da etiqueta (€)',
              hintText: '1,20',
              suffixText: '€',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Escreve o total da etiqueta desta linha (ex.: as 4 bananas '
            'juntas).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 10),
            Text(
              _erro!,
              key: const Key('peso_erro'),
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('peso_confirmar'),
              onPressed: _aEnviar ? null : _confirmar,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _aEnviar
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Confirmar',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
