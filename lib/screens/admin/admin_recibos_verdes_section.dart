import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/recibo_verde_service.dart';
import '_admin_rpc_errors.dart';
import 'admin_casa_comum.dart' show casaAbrirFicheiro;

/// Missão 12 recibos-verdes-15-11 (R2): recibos verdes de TODOS os prestadores
/// no "Fecho do mês" (PT-BR). Um recibo por pessoa com todos os serviços
/// (entregas, limpeza, lavagem, Casa), lido de
/// `prestador_recibo_mensal_resumo(ano, mes)` (admin → todas as pessoas).
///
/// Ações: abrir o PDF (link assinado), marcar à mão (recibo que chegou por
/// email ou WhatsApp, com motivo e o arquivo na pasta da pessoa) e desmarcar
/// (recibo errado). Nenhum valor é calculado aqui.
///
/// Servidor antigo (função ainda não aplicada): mostra [antigo].
class AdminRecibosVerdesSection extends StatefulWidget {
  const AdminRecibosVerdesSection({
    super.key,
    required this.ano,
    required this.mes,
    this.antigo,
  });

  final int ano;
  final int mes;

  /// A lista antiga (só estafetas), usada enquanto o servidor não tem a função.
  final Widget? antigo;

  @override
  State<AdminRecibosVerdesSection> createState() =>
      _AdminRecibosVerdesSectionState();
}

class _AdminRecibosVerdesSectionState extends State<AdminRecibosVerdesSection> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _resumo;
  bool _servidorAntigo = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant AdminRecibosVerdesSection old) {
    super.didUpdateWidget(old);
    if (old.ano != widget.ano || old.mes != widget.mes) _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _sb.rpc('prestador_recibo_mensal_resumo',
          params: {'p_year': widget.ano, 'p_month': widget.mes});
      if (!mounted) return;
      setState(() {
        _resumo = r is Map ? Map<String, dynamic>.from(r) : {};
        _erro = null;
        _servidorAntigo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (ReciboVerdeService.faltaFuncaoNoServidor(e)) {
          _servidorAntigo = true;
        } else {
          _erro = humanizeAdminRpcError(e);
        }
      });
    }
  }

  static String _eur(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    return '€ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static (String, Color, IconData) _estado(String? e) => switch (e) {
        'entregue' => (
            'Entregue (com PDF)',
            AppColors.primary,
            Icons.check_circle
          ),
        'sem_pdf' => (
            'Marcado sem PDF (não conta)',
            Colors.deepOrange,
            Icons.picture_as_pdf_outlined
          ),
        'em_falta' => ('Em falta', Colors.orange, Icons.pending_outlined),
        _ => ('Não precisa', Colors.black45, Icons.remove_circle_outline),
      };

  Future<void> _abrirPdf(Map<String, dynamic> p, String caminho) =>
      casaAbrirFicheiro(context,
          balde: ReciboVerdeService.bucket,
          caminho: caminho,
          titulo: 'Recibo de ${p['nome'] ?? ''}');

  Future<void> _marcarAMao(Map<String, dynamic> p) async {
    final numCtrl = TextEditingController(
        text: ((p['recibo'] as Map?)?['numero'] ?? '').toString());
    final motivoCtrl = TextEditingController();
    Uint8List? bytes;
    String? nome;
    String? erro;
    bool salvando = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> escolher() async {
          try {
            final r = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ReciboVerdeService.extensoes,
                withData: true);
            final f = (r == null || r.files.isEmpty) ? null : r.files.first;
            if (f?.bytes == null) return;
            setD(() {
              bytes = f!.bytes;
              nome = f.name;
            });
          } catch (_) {
            setD(() => erro = 'Não consegui abrir o arquivo.');
          }
        }

        Future<void> salvar() async {
          if (salvando) return;
          if (numCtrl.text.trim().isEmpty) {
            setD(() => erro = 'Escreva o número do recibo.');
            return;
          }
          if (motivoCtrl.text.trim().length < 5) {
            setD(() => erro = 'Escreva o motivo (5 letras ou mais).');
            return;
          }
          setD(() {
            salvando = true;
            erro = null;
          });
          try {
            String? path;
            final b = bytes;
            final n = nome;
            if (b != null && n != null) {
              if (ReciboVerdeService.extensaoOuNull(n) == null) {
                throw StateError('ficheiro_tipo');
              }
              if (b.length > ReciboVerdeService.tamanhoMaximo) {
                throw StateError('ficheiro_grande');
              }
              path = ReciboVerdeService.caminho(
                  '${p['user_id']}', widget.ano, widget.mes, n);
              await _sb.storage.from(ReciboVerdeService.bucket).uploadBinary(
                  path, b,
                  fileOptions: FileOptions(
                      contentType: ReciboVerdeService.tipoMime(
                          ReciboVerdeService.extensao(n)),
                      upsert: true));
            }
            await _sb.rpc('admin_recibo_prestador_marcar', params: {
              'p_user_id': p['user_id'],
              'p_year': widget.ano,
              'p_month': widget.mes,
              'p_numero': numCtrl.text.trim(),
              'p_pdf_path': path,
              'p_motivo': motivoCtrl.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            setD(() {
              salvando = false;
              final t = e.toString();
              erro = t.contains('ficheiro_tipo')
                  ? 'Só PDF, JPG ou PNG.'
                  : t.contains('ficheiro_grande')
                      ? 'Arquivo com mais de 10 MB.'
                      : humanizeAdminRpcError(e);
            });
          }
        }

        return AlertDialog(
          title: Text('Marcar recibo de ${p['nome'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'Use quando o recibo chegou por email ou WhatsApp. Sem o PDF '
                  'anexado o recibo NÃO conta para a trava (retenção do pagamento).',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              TextField(
                  controller: numCtrl,
                  decoration:
                      const InputDecoration(labelText: 'N.º do recibo verde')),
              TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Motivo (fica na auditoria)')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: salvando ? null : escolher,
                icon: const Icon(Icons.attach_file),
                label: Text(nome ?? 'Anexar PDF ou foto do recibo',
                    overflow: TextOverflow.ellipsis),
              ),
              if (erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(erro!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: salvando ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: salvando ? null : salvar,
                child: const Text('Salvar')),
          ],
        );
      }),
    );
    if (ok == true) await _carregar();
  }

  Future<void> _desmarcar(Map<String, dynamic> p) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desmarcar recibo de ${p['nome'] ?? ''}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'O arquivo fica guardado; o recibo só deixa de contar e a pessoa '
              'pode enviar outro na app.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Motivo (5 letras ou mais)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desmarcar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _sb.rpc('admin_recibo_prestador_desmarcar', params: {
        'p_user_id': p['user_id'],
        'p_year': widget.ano,
        'p_month': widget.mes,
        'p_motivo': motivoCtrl.text.trim(),
      });
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_servidorAntigo) return widget.antigo ?? const SizedBox.shrink();
    if (_erro != null) {
      return Text('Não consegui carregar os recibos verdes. $_erro',
          style: const TextStyle(color: Colors.red));
    }
    final r = _resumo;
    if (r == null) return const LinearProgressIndicator();
    final pessoas = ((r['prestadores'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final tot = r['totais'] is Map ? r['totais'] as Map : const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
            'Recibos verdes dos prestadores (um por pessoa, todos os serviços)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        Text(
            'Precisam ${tot['precisam'] ?? 0} · entregues ${tot['entregues'] ?? 0} · '
            'em falta ${tot['em_falta'] ?? 0} · total ${_eur(tot['total'])}',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        if (pessoas.isEmpty)
          const Text('Ninguém trabalhou neste mês.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        for (final p in pessoas) _pessoa(p),
      ],
    );
  }

  Widget _pessoa(Map<String, dynamic> p) {
    final (rotulo, cor, icone) = _estado(p['estado']?.toString());
    final rec = p['recibo'] is Map
        ? Map<String, dynamic>.from(p['recibo'] as Map)
        : const <String, dynamic>{};
    final pdf = (rec['pdf_path'] ?? '').toString();
    final linhas = ((p['linhas'] as List?) ?? const [])
        .whereType<Map>()
        .map((l) => '${l['nome']} ${l['quantidade']} (${_eur(l['valor'])})')
        .join(' · ');
    final verif = rec['verificacao'] is Map ? rec['verificacao'] as Map : null;
    final precisa = p['precisa_recibo'] == true;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icone, color: cor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${p['nome'] ?? '?'} — ${_eur(p['total'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(rotulo, style: TextStyle(color: cor, fontSize: 12)),
            ]),
            Text('NIF ${p['nif'] ?? 'em falta'} · $linhas',
                style: const TextStyle(fontSize: 12)),
            if ((rec['numero'] ?? '').toString().isNotEmpty)
              Text(
                  'Recibo n.º ${rec['numero']}'
                  '${rec['data'] != null ? ' de ${rec['data']}' : ''}',
                  style: const TextStyle(fontSize: 12)),
            if (verif != null)
              Text(
                  verif['ok'] == true
                      ? 'Conferência automática (OCR): ok'
                      : 'Conferência automática (OCR): ${(verif['problemas'] as List?)?.join('; ') ?? 'com problemas'}',
                  style: TextStyle(
                      fontSize: 12,
                      color: verif['ok'] == true
                          ? AppColors.primary
                          : Colors.red)),
            if (p['demo'] == true || p['conta_dono'] == true)
              Text(
                  p['demo'] == true
                      ? 'Conta de teste (fora da trava)'
                      : 'Conta do dono (fora da trava)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Wrap(spacing: 8, children: [
              if (pdf.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _abrirPdf(p, pdf),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Abrir PDF'),
                ),
              if (precisa)
                TextButton.icon(
                  onPressed: () => _marcarAMao(p),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Marcar à mão'),
                ),
              if ((rec['numero'] ?? '').toString().isNotEmpty)
                TextButton.icon(
                  onPressed: () => _desmarcar(p),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Desmarcar'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
