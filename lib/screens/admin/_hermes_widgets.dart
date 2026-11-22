// Missão hermes-diretor-2026-11-20 (B10) — pedaços comuns dos ecrãs do Hermes no painel (PT-BR).

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Faixa calma para "a tabela ou função ainda não existe no servidor". Nunca vermelha.
class FaixaNaoLigado extends StatelessWidget {
  const FaixaNaoLigado({super.key, this.detalhe});

  /// O que falta, em palavras simples (opcional).
  final String? detalhe;

  static const String texto = 'Esta parte ainda não foi ligada no servidor';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.hourglass_empty, size: 20, color: AppColors.textSubtle),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(texto, style: TextStyle(fontWeight: FontWeight.w700)),
            if (detalhe != null) ...[
              const SizedBox(height: 4),
              Text(detalhe!, style: const TextStyle(fontSize: 13, color: AppColors.textSubtle)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Etiqueta pequena e arredondada (estado, gravidade, "TESTE"...).
class EtiquetaHermes extends StatelessWidget {
  const EtiquetaHermes(this.texto, {super.key, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
    );
  }
}

/// Erro de leitura em texto simples (vermelho só para erros de verdade).
class ErroLeitura extends StatelessWidget {
  const ErroLeitura(this.mensagem, {super.key});

  final String mensagem;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Não foi possível carregar. $mensagem', style: const TextStyle(color: AppColors.error)),
      );
}

/// 12,50 € (vírgula decimal); "sem valor" quando não há.
String euros(double? v) => v == null ? 'sem valor' : '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

/// US$ 1,23 (4 casas quando é menos de 1).
String dolares(double v) {
  final casas = (v != 0 && v.abs() < 1) ? 4 : 2;
  return 'US\$ ${v.toStringAsFixed(casas).replaceAll('.', ',')}';
}
