// lib/screens/admin/tvde_conformidade/_comum.dart
//
// [tvde-conformidade-lei-59-2026] Peças partilhadas pelos separadores do ecrã
// admin "Conformidade TVDE (IMT/AMT)" (PT-BR).
//
// Regras que estas peças garantem:
//  · Toda a leitura e escrita passa por RPCs `admin_tvde_*` (nunca UPDATE
//    direto). A função que chama a RPC é injetável ([TvdeRpc]) para os testes
//    não precisarem de Supabase.
//  · Cada botão trava-se pelo SEU pedido (PADRÃO BORA §3.13): os separadores
//    guardam um conjunto local de chaves "a gravar", nunca um `busy` global.
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_export_service.dart';
import '../_admin_rpc_errors.dart';

/// Chama uma RPC pelo nome, com parâmetros. Por defeito vai ao Supabase.
typedef TvdeRpc = Future<dynamic> Function(String funcao,
    [Map<String, dynamic>? params]);

/// Entrega um CSV já construído (nome do ficheiro, texto).
typedef TvdeGuardarCsv = Future<void> Function(String nome, String csv);

/// Entrega um PDF de tabela (título, cabeçalho, linhas, subtítulo).
typedef TvdeGuardarPdf = Future<void> Function(String titulo,
    List<String> cabecalho, List<List<String>> linhas, String? subtitulo);

Future<dynamic> tvdeRpcPadrao(String funcao,
    [Map<String, dynamic>? params]) async {
  return await Supabase.instance.client.rpc(funcao, params: params);
}

Future<void> tvdeGuardarCsvPadrao(String nome, String csv) =>
    AdminExportService.instance
        .exportCsvText(filename: nome, csv: csv, subject: 'Bora TVDE — $nome');

Future<void> tvdeGuardarPdfPadrao(String titulo, List<String> cabecalho,
        List<List<String>> linhas, String? subtitulo) =>
    AdminExportService.instance.exportPdfTable(
      title: titulo,
      headers: cabecalho,
      rows: linhas,
      subtitle: subtitulo,
    );

// ─────────────────────────── leitura de valores ────────────────────────────

dynamic _json(dynamic v) {
  if (v is String) {
    final t = v.trim();
    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        return jsonDecode(t);
      } catch (_) {
        return v;
      }
    }
  }
  return v;
}

List<Map<String, dynamic>> tvdeLista(dynamic v) => (_json(v) is List
        ? _json(v) as List
        : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

Map<String, dynamic> tvdeMapa(dynamic v) {
  final j = _json(v);
  return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
}

int tvdeInt(dynamic v) =>
    v is num ? v.toInt() : int.tryParse('$v') ?? double.tryParse('$v')?.round() ?? 0;

double? tvdeNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

/// jsonb pode chegar como bool, "true", "\"true\"" ou 1.
bool? tvdeBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().replaceAll('"', '').toLowerCase();
    if (t == 'true') return true;
    if (t == 'false') return false;
  }
  return null;
}

String tvdeTexto(dynamic v) {
  if (v == null) return '—';
  final s = v.toString().trim();
  return s.isEmpty ? '—' : s;
}

String _d2(int n) => n.toString().padLeft(2, '0');

/// "2026-09-30" ou ISO → "30/09/2026".
String tvdeData(dynamic v) {
  if (v == null || '$v'.isEmpty) return '—';
  final dt = DateTime.tryParse('$v');
  if (dt == null) return '$v';
  final l = '$v'.length <= 10 ? dt : dt.toLocal();
  return '${_d2(l.day)}/${_d2(l.month)}/${l.year}';
}

/// ISO → "30/09/2026 14:05" (hora local do navegador).
String tvdeDataHora(dynamic v) {
  if (v == null || '$v'.isEmpty) return '—';
  final dt = DateTime.tryParse('$v');
  if (dt == null) return '$v';
  final l = dt.toLocal();
  return '${_d2(l.day)}/${_d2(l.month)}/${l.year} ${_d2(l.hour)}:${_d2(l.minute)}';
}

/// "2026-09-30" (primeiros 10 caracteres) para preencher campos de data.
String tvdeDataIso(dynamic v) {
  if (v == null) return '';
  final s = '$v';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String tvdeHoje() {
  final n = DateTime.now();
  return '${n.year}-${_d2(n.month)}-${_d2(n.day)}';
}

/// Cêntimos inteiros → "121,68 €" (sem vírgula flutuante).
String tvdeEuros(dynamic cents) {
  final n = tvdeInt(cents);
  final a = n.abs();
  return '${n < 0 ? '-' : ''}${a ~/ 100},${(a % 100).toString().padLeft(2, '0')} €';
}

String tvdeHoras(dynamic v) {
  final n = tvdeNum(v);
  if (n == null) return '—';
  return '${n.toStringAsFixed(1).replaceAll('.', ',')} h';
}

/// CSV com ';' (abre direito no Excel em PT).
String tvdeCsv(List<String> cabecalho, List<List<dynamic>> linhas) =>
    const ListToCsvConverter(fieldDelimiter: ';', eol: '\n').convert([
      cabecalho,
      ...linhas.map((l) => l.map((c) => c ?? '').toList()),
    ]);

// ───────────────────────────────── erros ───────────────────────────────────

/// Códigos das RPCs `admin_tvde_*` em PT-BR; o resto cai no helper comum.
String tvdeErro(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    const mapa = {
      'forbidden': 'Sem permissão de administrador (a sessão não é de admin).',
      'chave_nao_permitida':
          'Essa configuração não pode ser mudada aqui (só as da conformidade TVDE).',
      'nif_invalido': 'O NIF tem de ter 9 dígitos.',
      'estado_invalido': 'Estado inválido.',
      'motivo_obrigatorio': 'Escreva o motivo (mínimo 3 letras).',
      'operador_nao_encontrado': 'Operador não encontrado. Atualize a lista.',
      'veiculo_nao_encontrado': 'Veículo não encontrado. Atualize a lista.',
      'motorista_nao_encontrado': 'Motorista não encontrado. Atualize a lista.',
      'queixa_nao_encontrada': 'Queixa não encontrada. Atualize a lista.',
      'requisito_nao_encontrado': 'Requisito não encontrado. Atualize a lista.',
      'entidade_e_finalidade_obrigatorias':
          'Preencha a entidade e a finalidade do acesso.',
    };
    for (final k in mapa.keys) {
      if (m.startsWith(k)) return mapa[k]!;
    }
    if (m.contains('duplicate key')) {
      return 'Já existe um registo com esse valor (ex.: NIPC ou matrícula repetidos).';
    }
    if (m.contains('check constraint')) {
      return 'Um valor não passou na validação do servidor (restrição da tabela): $m';
    }
    if (m.contains('invalid input syntax')) {
      return 'Formato inválido num dos campos (datas em AAAA-MM-DD, números sem letras).';
    }
  }
  return humanizeAdminRpcError(e);
}

void tvdeAvisar(BuildContext context, String msg, {bool erro = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: erro ? AppColors.error : AppColors.success,
  ));
}

// ───────────────────────────── peças visuais ───────────────────────────────

Widget tvdeChip(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(texto,
          style: TextStyle(
              color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
    );

/// pendente / aprovado / suspenso / rejeitado → rótulo e cor.
(String, Color) tvdeEstado(String? e) => switch (e) {
      'aprovado' => ('Aprovado', AppColors.success),
      'pendente' => ('Pendente', AppColors.warning),
      'suspenso' => ('Suspenso', AppColors.error),
      'rejeitado' => ('Rejeitado', AppColors.error),
      _ => (e ?? '—', AppColors.textSecondary),
    };

/// Corpo padrão: a carregar / erro com "Tentar de novo" / conteúdo.
Widget tvdeCorpo({
  required bool carregando,
  required String? erro,
  required VoidCallback tentar,
  required Widget Function() conteudo,
}) {
  if (carregando) return const Center(child: CircularProgressIndicator());
  if (erro != null) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: 8),
          Text(erro, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: tentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ]),
      ),
    );
  }
  return conteudo();
}

Widget tvdeVazio(String texto) => Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
          child: Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary))),
    );

Widget tvdeNota(String texto, {Color cor = AppColors.info, IconData icone = Icons.info_outline}) =>
    Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, color: cor, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
      ]),
    );

/// Botão que só se trava pelo seu próprio pedido (§3.13).
Widget tvdeBotao({
  required String rotulo,
  required IconData icone,
  required bool aGravar,
  required VoidCallback onPressed,
  Color? cor,
  Key? key,
}) =>
    OutlinedButton.icon(
      key: key,
      style: cor == null
          ? null
          : OutlinedButton.styleFrom(
              foregroundColor: cor, side: BorderSide(color: cor)),
      onPressed: aGravar ? null : onPressed,
      icon: aGravar
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icone, size: 16),
      label: Text(rotulo),
    );

// ───────────────────────────────── diálogos ────────────────────────────────

/// Pede um texto (motivo, nota). Com [obrigatorio], exige ≥3 letras.
Future<String?> tvdePedirTexto(
  BuildContext context, {
  required String titulo,
  String rotulo = 'Motivo',
  String? explicacao,
  bool obrigatorio = true,
  String inicial = '',
  String confirmar = 'Confirmar',
}) {
  final c = TextEditingController(text: inicial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (explicacao != null) ...[
            Text(explicacao, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
          ],
          TextFormField(
            key: const Key('tvde-dialogo-texto'),
            controller: c,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
                labelText: obrigatorio ? '$rotulo (obrigatório)' : rotulo),
            validator: (v) => obrigatorio && (v ?? '').trim().length < 3
                ? 'Escreva pelo menos 3 letras.'
                : null,
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, c.text.trim());
            }
          },
          child: Text(confirmar),
        ),
      ],
    ),
  );
}

Future<bool> tvdeConfirmar(BuildContext context,
    {required String titulo, required String texto, bool perigo = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: perigo
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ───────────────────────────── formulário genérico ─────────────────────────

enum TvdeCampoTipo { texto, numero, data, sim, escolha, longo }

class TvdeCampo {
  const TvdeCampo(
    this.chave,
    this.rotulo, {
    this.tipo = TvdeCampoTipo.texto,
    this.obrigatorio = false,
    this.validar,
    this.ajuda,
    this.opcoes = const [],
  });

  final String chave;
  final String rotulo;
  final TvdeCampoTipo tipo;
  final bool obrigatorio;
  final String? Function(String valor)? validar;
  final String? ajuda;

  /// (valor, rótulo) — só para [TvdeCampoTipo.escolha]. '' = nenhum.
  final List<(String, String)> opcoes;
}

final RegExp _reData = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Abre um formulário e devolve {chave: valor}. Texto/número/data voltam como
/// String ('' = apagar); "sim" volta como bool; escolha como String.
Future<Map<String, dynamic>?> tvdeFormulario(
  BuildContext context, {
  required String titulo,
  required List<TvdeCampo> campos,
  Map<String, dynamic> inicial = const {},
  String? nota,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TvdeFormDialog(
          titulo: titulo, campos: campos, inicial: inicial, nota: nota),
    );

class _TvdeFormDialog extends StatefulWidget {
  const _TvdeFormDialog(
      {required this.titulo,
      required this.campos,
      required this.inicial,
      this.nota});

  final String titulo;
  final List<TvdeCampo> campos;
  final Map<String, dynamic> inicial;
  final String? nota;

  @override
  State<_TvdeFormDialog> createState() => _TvdeFormDialogState();
}

class _TvdeFormDialogState extends State<_TvdeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _txt = {};
  final Map<String, bool> _sim = {};
  final Map<String, String> _esc = {};

  @override
  void initState() {
    super.initState();
    for (final c in widget.campos) {
      final v = widget.inicial[c.chave];
      switch (c.tipo) {
        case TvdeCampoTipo.sim:
          _sim[c.chave] = tvdeBool(v) ?? false;
        case TvdeCampoTipo.escolha:
          final s = v?.toString() ?? '';
          _esc[c.chave] = c.opcoes.any((o) => o.$1 == s) ? s : '';
        case TvdeCampoTipo.data:
          _txt[c.chave] = TextEditingController(text: tvdeDataIso(v));
        default:
          _txt[c.chave] = TextEditingController(text: v?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _txt.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validar(TvdeCampo c, String? bruto) {
    final v = (bruto ?? '').trim();
    if (c.obrigatorio && v.isEmpty) return 'Obrigatório.';
    if (v.isEmpty) return null;
    if (c.tipo == TvdeCampoTipo.data && !_reData.hasMatch(v)) {
      return 'Use AAAA-MM-DD.';
    }
    if (c.tipo == TvdeCampoTipo.numero && int.tryParse(v) == null) {
      return 'Só números inteiros.';
    }
    return c.validar?.call(v);
  }

  Future<void> _escolherData(TvdeCampo c) async {
    final atual = DateTime.tryParse(_txt[c.chave]!.text) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      _txt[c.chave]!.text = '${d.year}-${_d2(d.month)}-${_d2(d.day)}';
    }
  }

  Widget _campo(TvdeCampo c) {
    final rot = c.obrigatorio ? '${c.rotulo} *' : c.rotulo;
    switch (c.tipo) {
      case TvdeCampoTipo.sim:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.rotulo),
          subtitle: c.ajuda == null ? null : Text(c.ajuda!),
          value: _sim[c.chave] ?? false,
          onChanged: (v) => setState(() => _sim[c.chave] = v),
        );
      case TvdeCampoTipo.escolha:
        return DropdownButtonFormField<String>(
          initialValue: _esc[c.chave],
          isExpanded: true,
          decoration: InputDecoration(labelText: rot, helperText: c.ajuda),
          items: [
            if (!c.opcoes.any((o) => o.$1 == ''))
              const DropdownMenuItem(value: '', child: Text('— nenhum —')),
            for (final o in c.opcoes)
              DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2, overflow: TextOverflow.ellipsis)),
          ],
          validator: (v) =>
              c.obrigatorio && (v ?? '').isEmpty ? 'Obrigatório.' : null,
          onChanged: (v) => setState(() => _esc[c.chave] = v ?? ''),
        );
      case TvdeCampoTipo.data:
        return TextFormField(
          controller: _txt[c.chave],
          decoration: InputDecoration(
            labelText: rot,
            helperText: c.ajuda ?? 'AAAA-MM-DD',
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () => _escolherData(c),
            ),
          ),
          validator: (v) => _validar(c, v),
        );
      default:
        return TextFormField(
          controller: _txt[c.chave],
          keyboardType: c.tipo == TvdeCampoTipo.numero
              ? TextInputType.number
              : TextInputType.text,
          maxLines: c.tipo == TvdeCampoTipo.longo ? 4 : 1,
          minLines: 1,
          decoration: InputDecoration(labelText: rot, helperText: c.ajuda),
          validator: (v) => _validar(c, v),
        );
    }
  }

  void _gravar() {
    if (!_formKey.currentState!.validate()) return;
    final out = <String, dynamic>{};
    for (final c in widget.campos) {
      switch (c.tipo) {
        case TvdeCampoTipo.sim:
          out[c.chave] = _sim[c.chave] ?? false;
        case TvdeCampoTipo.escolha:
          out[c.chave] = _esc[c.chave] ?? '';
        default:
          out[c.chave] = _txt[c.chave]!.text.trim();
      }
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.nota != null) tvdeNota(widget.nota!),
              for (final c in widget.campos)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _campo(c)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _gravar, child: const Text('Gravar')),
      ],
    );
  }
}

/// Lista de separadores com filtro de "a gravar" por chave (§3.13).
mixin TvdeAGravar<T extends StatefulWidget> on State<T> {
  final Set<String> aGravar = {};

  /// Corre [acao] com a chave [k] marcada; mostra o erro humanizado.
  Future<bool> correr(String k, Future<dynamic> Function() acao,
      {String? ok}) async {
    if (aGravar.contains(k)) return false;
    setState(() => aGravar.add(k));
    try {
      await acao();
      if (mounted && ok != null) tvdeAvisar(context, ok);
      return true;
    } catch (e) {
      if (mounted) tvdeAvisar(context, tvdeErro(e), erro: true);
      return false;
    } finally {
      if (mounted) setState(() => aGravar.remove(k));
    }
  }
}
