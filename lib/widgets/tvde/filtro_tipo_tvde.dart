import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Painel admin (PT-BR) — 21/10/2026 (fechar-pendencias A1): as corridas do
/// Bora Motorista podem ser de PASSAGEIROS ou ENCOMENDAS (mesmo motor, mesmo
/// dinheiro). Filtro e etiqueta comuns às listas de corridas, reservas e
/// acertos. A linha sem `ride_kind` (lista antiga) conta como passageiros.

/// 'todos' | 'passageiros' | 'encomendas'.
String tipoDaLinhaTvde(Map<String, dynamic> linha) =>
    linha['ride_kind']?.toString() == 'encomendas' ? 'encomendas' : 'passageiros';

/// Filtra as linhas pelo tipo escolhido no painel. Função pura (testada).
List<Map<String, dynamic>> filtrarPorTipoTvde(
    List<Map<String, dynamic>> linhas, String tipo) {
  if (tipo != 'passageiros' && tipo != 'encomendas') return linhas;
  return linhas.where((l) => tipoDaLinhaTvde(l) == tipo).toList();
}

/// Rótulo PT-BR do tipo (exportação e cartões).
String rotuloTipoTvde(String tipo) =>
    tipo == 'encomendas' ? 'Encomenda' : 'Passageiros';

/// As três escolhas, com a contagem de cada uma.
class FiltroTipoTvde extends StatelessWidget {
  const FiltroTipoTvde({
    super.key,
    required this.linhas,
    required this.valor,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> linhas;
  final String valor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final enc = linhas.where((l) => tipoDaLinhaTvde(l) == 'encomendas').length;
    final pas = linhas.length - enc;
    Widget chip(String v, String texto) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            key: Key('filtro_tipo_tvde_$v'),
            label: Text(texto),
            selected: valor == v,
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            onSelected: (_) => onChanged(v),
          ),
        );
    return Wrap(
      children: [
        chip('todos', 'Todos (${linhas.length})'),
        chip('passageiros', 'Passageiros ($pas)'),
        chip('encomendas', 'Encomendas ($enc)'),
      ],
    );
  }
}

/// Etiqueta "Encomenda" no cartão da corrida/reserva (nada para passageiros).
class EtiquetaEncomendaTvde extends StatelessWidget {
  const EtiquetaEncomendaTvde({super.key, required this.linha});

  final Map<String, dynamic> linha;

  @override
  Widget build(BuildContext context) {
    if (tipoDaLinhaTvde(linha) != 'encomendas') return const SizedBox.shrink();
    return Container(
      key: const Key('etiqueta_encomenda_tvde'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('📦 Encomenda',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
  }
}
