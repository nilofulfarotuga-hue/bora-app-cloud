/// CASA — aba "Exportar" do hub (painel admin, PT-BR): CSV de pedidos,
/// ganhos e profissionais entre duas datas (dias de Lisboa), pelo
/// `admin_casa_exportar` e pelo mesmo serviço de CSV dos outros ecrãs
/// (`AdminExportService`: ';' + BOM, descarrega na web, partilha no
/// telemóvel).
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import 'admin_casa_comum.dart';

/// Tipos que o servidor exporta.
const Map<String, String> kCasaTiposExportar = {
  'pedidos': 'Pedidos',
  'ganhos': 'Ganhos',
  'profissionais': 'Profissionais',
};

/// Linhas planas do servidor → cabeçalho (todas as chaves, pela ordem em que
/// aparecem) e linhas. Objetos e listas vão como JSON numa célula.
({List<String> headers, List<List<dynamic>> rows}) casaLinhasParaCsv(
    List<Map<String, dynamic>> linhas) {
  final headers = <String>[];
  for (final l in linhas) {
    for (final k in l.keys) {
      if (!headers.contains(k)) headers.add(k);
    }
  }
  final rows = [
    for (final l in linhas)
      [
        for (final h in headers)
          switch (l[h]) {
            null => '',
            Map() || List() => jsonEncode(l[h]),
            final v => v,
          },
      ],
  ];
  return (headers: headers, rows: rows);
}

/// Quem grava o CSV (injetável nos testes).
typedef CasaGravarCsv = Future<void> Function({
  required String filename,
  required List<String> headers,
  required List<List<dynamic>> rows,
  String? subject,
});

Future<void> _gravarPadrao({
  required String filename,
  required List<String> headers,
  required List<List<dynamic>> rows,
  String? subject,
}) =>
    AdminExportService.instance.exportCsv(
        filename: filename, headers: headers, rows: rows, subject: subject);

class AdminCasaExportarTab extends StatefulWidget {
  const AdminCasaExportarTab({super.key, this.rpc, this.gravar, this.agora});
  final ChamarRpcPainel? rpc;
  final CasaGravarCsv? gravar;
  final DateTime? agora;

  @override
  State<AdminCasaExportarTab> createState() => _AdminCasaExportarTabState();
}

class _AdminCasaExportarTabState extends State<AdminCasaExportarTab> {
  String _tipo = 'pedidos';
  late final DateTime _hoje = casaHojeLisboa(widget.agora);
  late final _de = TextEditingController(
      text: casaData(casaIsoData(_hoje.subtract(const Duration(days: 30)))));
  late final _ate = TextEditingController(text: casaData(casaIsoData(_hoje)));
  bool _busy = false;
  String? _ultimo;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  @override
  void dispose() {
    _de.dispose();
    _ate.dispose();
    super.dispose();
  }

  Future<void> _exportar() async {
    final de = casaLerValidade(_de.text);
    final ate = casaLerValidade(_ate.text);
    if (!de.ok || de.iso == null || !ate.ok || ate.iso == null) {
      casaMsg(context, 'Datas inválidas (use DD/MM/AAAA).');
      return;
    }
    if (de.iso!.compareTo(ate.iso!) > 0) {
      casaMsg(context, 'A data inicial é depois da final.');
      return;
    }
    setState(() => _busy = true);
    try {
      final linhas = casaLista(casaVerOk(await _rpc('admin_casa_exportar', {
        'p_tipo': _tipo,
        'p_de': de.iso,
        'p_ate': ate.iso,
      })));
      if (linhas.isEmpty) {
        if (mounted) casaMsg(context, 'Nada para exportar nestas datas.');
      } else {
        final csv = casaLinhasParaCsv(linhas);
        final nome = 'bora_casa_${_tipo}_${de.iso}_${ate.iso}.csv';
        await (widget.gravar ?? _gravarPadrao)(
          filename: nome,
          headers: csv.headers,
          rows: csv.rows,
          subject: 'Bora — Casa: ${kCasaTiposExportar[_tipo]} '
              '${casaData(de.iso)} a ${casaData(ate.iso)}',
        );
        if (mounted) {
          setState(() => _ultimo = '$nome · ${linhas.length} linhas');
          casaMsg(context, 'CSV exportado: ${linhas.length} linhas.');
        }
      }
    } catch (e) {
      if (mounted) casaMsg(context, casaErroPtBr(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        const Text('Exportar CSV',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: Spacing.xs),
        const Text(
          'Datas em dias de Lisboa. O arquivo abre no Excel em colunas '
          '(separador ";"). Valores de dinheiro em cêntimos, como vêm do '
          'servidor.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        Wrap(spacing: Spacing.sm, children: [
          for (final e in kCasaTiposExportar.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _tipo == e.key,
              onSelected: (_) => setState(() => _tipo = e.key),
            ),
        ]),
        const SizedBox(height: Spacing.md),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('casa-exportar-de'),
              controller: _de,
              decoration: const InputDecoration(
                  labelText: 'De (DD/MM/AAAA)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: TextField(
              key: const ValueKey('casa-exportar-ate'),
              controller: _ate,
              decoration: const InputDecoration(
                  labelText: 'Até (DD/MM/AAAA)', border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: Spacing.md),
        FilledButton.icon(
          key: const ValueKey('casa-exportar-botao'),
          onPressed: _busy ? null : _exportar,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
          label: Text('Exportar ${kCasaTiposExportar[_tipo]} (CSV)'),
        ),
        if (_ultimo != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text('Última exportação: $_ultimo',
                style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
