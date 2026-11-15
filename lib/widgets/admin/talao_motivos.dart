import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Porque é que um talão precisa de ser revisto, em frases para o painel (PT-BR).
///
/// app-15-11 (caixa 18, ponto 5): o robô do talão grava em `receipt_parsed` a
/// conferência da loja (`store_check`) e das linhas (`lines_check`) —
/// supabase/functions/ocr-receipt/talao_regras.ts. O painel não mostrava nada
/// disso; quem revia não sabia porque é que o talão estava marcado.
List<String> motivosParaRever(Object? receiptParsed) {
  if (receiptParsed is! Map) return const [];
  final motivos = <String>[];

  final loja = receiptParsed['store_check'];
  if (loja is Map && loja['ok'] == false) {
    final lida = (loja['lida'] ?? '').toString().trim();
    final pedido = (loja['pedido'] ?? '').toString().trim();
    final outra = (loja['outra_loja_conhecida'] ?? '').toString().trim();
    var frase = 'Loja lida no talão: "${lida.isEmpty ? '?' : lida}" — o pedido é de '
        '"${pedido.isEmpty ? '?' : pedido}".';
    if (outra.isNotEmpty) frase += ' É outra loja que o Bora conhece ($outra).';
    motivos.add(frase);
  }

  final linhas = receiptParsed['lines_check'];
  if (linhas is Map) {
    final antes = _euros(linhas['soma_antes_cents']);
    final depois = _euros(linhas['soma_depois_cents']);
    switch (linhas['aviso']) {
      case 'linha_repetida_tirada':
        motivos.add('Linha repetida contada uma vez (ex.: saco em duas linhas): '
            'soma das linhas $antes → $depois.');
      case 'soma_das_linhas_acima_do_total':
        motivos.add('A soma das linhas ($antes) passa o total impresso.');
    }
  }
  return motivos;
}

String _euros(Object? cents) {
  final c = cents is num ? cents : num.tryParse('${cents ?? ''}');
  if (c == null) return '?';
  return '€${(c / 100).toStringAsFixed(2)}';
}

/// Caixa com os motivos (não desenha nada se não houver motivo).
class TalaoMotivos extends StatelessWidget {
  const TalaoMotivos({super.key, required this.receiptParsed});

  final Object? receiptParsed;

  @override
  Widget build(BuildContext context) {
    final motivos = motivosParaRever(receiptParsed);
    if (motivos.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('talao_motivos'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Motivo para revisar',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final m in motivos)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $m'),
            ),
        ],
      ),
    );
  }
}
