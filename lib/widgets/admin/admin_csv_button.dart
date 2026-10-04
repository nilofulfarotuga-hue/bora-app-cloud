import 'package:flutter/material.dart';

import '../../services/admin_export_service.dart';
import '../../utils/hora_lisboa.dart';

/// Botão "Descarregar CSV" das listas NÃO-dinheiro do painel (ronda 04/10).
/// Descarrega mesmo o ficheiro (web) ou abre a partilha (telemóvel) pelo
/// [AdminExportService] — nunca "copiar para a área de transferência".
/// Colunas de data (`*_at`, `*_em`, `*_for`) saem em hora de Lisboa.
class AdminCsvButton extends StatelessWidget {
  const AdminCsvButton({
    super.key,
    required this.nome,
    required this.colunas,
    required this.linhas,
  });

  /// Prefixo do ficheiro (ex.: 'tickets_suporte').
  final String nome;

  /// (chave no mapa, título da coluna no CSV).
  final List<(String, String)> colunas;

  /// As linhas visíveis no ecrã, no momento do toque.
  final List<Map<String, dynamic>> Function() linhas;

  static bool _ehData(String k) =>
      k.endsWith('_at') || k.endsWith('_em') || k.endsWith('_for');

  static String valor(String chave, Object? v) {
    if (v == null) return '';
    if (v is DateTime) return dataHoraLisboa(v.toUtc().toIso8601String());
    if (_ehData(chave) && v is String && DateTime.tryParse(v) != null) {
      return dataHoraLisboa(v);
    }
    if (v is List) return v.join(' | ');
    return v.toString();
  }

  Future<void> _exportar(BuildContext context) async {
    final dados = linhas();
    final messenger = ScaffoldMessenger.of(context);
    if (dados.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Nada para exportar nesta lista.')));
      return;
    }
    try {
      await AdminExportService.instance.exportCsv(
        filename: '${nome}_${DateTime.now().millisecondsSinceEpoch}.csv',
        headers: [for (final c in colunas) c.$2],
        rows: [
          for (final l in dados) [for (final c in colunas) valor(c.$1, l[c.$1])],
        ],
      );
    } catch (e) {
      debugPrint('[AdminCsvButton] $nome: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui gerar o CSV.')));
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Descarregar CSV',
        icon: const Icon(Icons.download),
        onPressed: () => _exportar(context),
      );
}
