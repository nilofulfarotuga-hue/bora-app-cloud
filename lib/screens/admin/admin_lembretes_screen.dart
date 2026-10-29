import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Um lembrete para o dono (linha da tabela `lembretes_danilo`).
class LembreteDono {
  const LembreteDono({
    required this.id,
    required this.texto,
    required this.quando,
    this.link,
    this.enviadoEm,
    this.feitoEm,
    this.urgente = false,
    this.origem = 'painel',
  });

  final int id;
  final String texto;
  final String? link;
  final DateTime quando;
  final DateTime? enviadoEm;
  final DateTime? feitoEm;
  final bool urgente;
  final String origem;

  factory LembreteDono.fromJson(Map<String, dynamic> j) {
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    final link = (j['link'] as String?)?.trim();
    return LembreteDono(
      id: (j['id'] as num).toInt(),
      texto: (j['texto'] as String?) ?? '',
      link: (link == null || link.isEmpty) ? null : link,
      quando: d(j['quando']) ?? DateTime.now(),
      enviadoEm: d(j['enviado_em']),
      feitoEm: d(j['feito_em']),
      urgente: j['urgente'] == true,
      origem: (j['origem'] as String?) ?? 'painel',
    );
  }
}

/// De onde vêm os lembretes. O ecrã usa o Supabase; o teste usa dados falsos.
abstract class LembretesFonte {
  Future<List<LembreteDono>> listar();
  Future<void> criar(Map<String, dynamic> campos);
  Future<void> atualizar(int id, Map<String, dynamic> campos);
}

class LembretesSupabase implements LembretesFonte {
  const LembretesSupabase();

  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<List<LembreteDono>> listar() async {
    final rows = await _c.from('lembretes_danilo').select().order('quando', ascending: true).limit(500);
    return (rows as List)
        .map((e) => LembreteDono.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> criar(Map<String, dynamic> campos) async {
    await _c.from('lembretes_danilo').insert({...campos, 'origem': 'painel'});
  }

  @override
  Future<void> atualizar(int id, Map<String, dynamic> campos) async {
    await _c.from('lembretes_danilo').update(campos).eq('id', id);
  }
}

enum _Filtro { pendentes, feitos, enviados, todos }

/// Lembretes do dono: o que o robô manda pelo WhatsApp da Bora todos os dias às
/// 9h30 (os urgentes saem a cada 10 minutos). Aqui se vê a lista por dia, se
/// cria, se edita o texto, o link e a data, e se marca como feito.
class AdminLembretesScreen extends StatefulWidget {
  const AdminLembretesScreen({super.key, this.fonte = const LembretesSupabase()});

  final LembretesFonte fonte;

  @override
  State<AdminLembretesScreen> createState() => _AdminLembretesScreenState();
}

class _AdminLembretesScreenState extends State<AdminLembretesScreen> {
  List<LembreteDono> _itens = const [];
  _Filtro _filtro = _Filtro.pendentes;
  bool _loading = true;
  String? _error;

  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lista = await widget.fonte.listar();
      if (mounted) setState(() => _itens = lista);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _dois(int n) => n.toString().padLeft(2, '0');
  static String _hora(DateTime d) => '${_dois(d.hour)}:${_dois(d.minute)}';
  static String _dia(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}';
  static String _cabecalhoDia(DateTime d) => '${_dias[d.weekday - 1]} ${_dia(d)}';

  bool _passa(LembreteDono l) {
    switch (_filtro) {
      case _Filtro.pendentes:
        return l.feitoEm == null;
      case _Filtro.feitos:
        return l.feitoEm != null;
      case _Filtro.enviados:
        return l.enviadoEm != null;
      case _Filtro.todos:
        return true;
    }
  }

  Future<void> _guardar(Future<void> Function() acao, String ok) async {
    try {
      await acao();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não deu para salvar: $e')));
      }
    }
  }

  Future<void> _alternarFeito(LembreteDono l) => _guardar(
        () => widget.fonte.atualizar(l.id, {
          'feito_em': l.feitoEm == null ? DateTime.now().toUtc().toIso8601String() : null,
        }),
        l.feitoEm == null ? 'Marcado como feito.' : 'Voltou para pendente.',
      );

  Future<void> _abrirForm([LembreteDono? existente]) async {
    final agora = DateTime.now();
    var quando = existente?.quando ??
        (agora.hour < 9 || (agora.hour == 9 && agora.minute < 30)
            ? DateTime(agora.year, agora.month, agora.day, 9, 30)
            : DateTime(agora.year, agora.month, agora.day + 1, 9, 30));
    var urgente = existente?.urgente ?? false;
    final texto = TextEditingController(text: existente?.texto ?? '');
    final link = TextEditingController(text: existente?.link ?? '');
    String? erro;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existente == null ? 'Novo lembrete' : 'Editar lembrete'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('lembrete_texto'),
                  controller: texto,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Texto (o que vai no WhatsApp)'),
                ),
                TextField(
                  key: const Key('lembrete_link'),
                  controller: link,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Link (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('lembrete_data'),
                      icon: const Icon(Icons.event),
                      label: Text(_dia(quando)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: quando,
                          firstDate: DateTime(2026),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) {
                          setD(() => quando = DateTime(d.year, d.month, d.day, quando.hour, quando.minute));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('lembrete_hora'),
                      icon: const Icon(Icons.schedule),
                      label: Text(_hora(quando)),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: quando.hour, minute: quando.minute),
                        );
                        if (t != null) {
                          setD(() => quando = DateTime(quando.year, quando.month, quando.day, t.hour, t.minute));
                        }
                      },
                    ),
                  ),
                ]),
                SwitchListTile(
                  key: const Key('lembrete_urgente'),
                  contentPadding: EdgeInsets.zero,
                  value: urgente,
                  onChanged: (v) => setD(() => urgente = v),
                  title: const Text('Urgente'),
                  subtitle: const Text('Sai assim que chega a hora, sem esperar as 9h30.'),
                ),
                if (erro != null) Text(erro!, style: const TextStyle(color: AppColors.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              key: const Key('lembrete_salvar'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                final t = texto.text.trim();
                final l = link.text.trim();
                if (t.isEmpty) {
                  setD(() => erro = 'Escreva o texto do lembrete.');
                } else if (l.isNotEmpty && !l.startsWith('http')) {
                  setD(() => erro = 'O link tem de começar por http.');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    // Os controladores NÃO se descartam aqui: o diálogo ainda está a fechar (animação
    // de saída) e os campos continuam na árvore; descartá-los dava "TextEditingController
    // was used after being disposed". Não guardam nada nativo, o coletor de lixo trata deles.
    final t = texto.text.trim();
    final l = link.text.trim();
    if (salvar != true || !mounted) return;

    final campos = <String, dynamic>{
      'texto': t,
      'link': l.isEmpty ? null : l,
      'quando': quando.toUtc().toIso8601String(),
      'urgente': urgente,
    };
    if (existente == null) {
      await _guardar(() => widget.fonte.criar(campos), 'Lembrete criado.');
    } else {
      await _guardar(() => widget.fonte.atualizar(existente.id, campos), 'Lembrete atualizado.');
    }
  }

  Widget _tile(LembreteDono l) {
    final feito = l.feitoEm != null;
    final partes = <String>[
      _hora(l.quando),
      l.enviadoEm != null ? 'enviado ${_dia(l.enviadoEm!)} ${_hora(l.enviadoEm!)}' : 'ainda não enviado',
      if (l.link != null) l.link!,
    ];
    return ListTile(
      key: Key('lembrete_${l.id}'),
      leading: Checkbox(
        key: Key('lembrete_feito_${l.id}'),
        value: feito,
        activeColor: AppColors.primary,
        onChanged: (_) => _alternarFeito(l),
      ),
      title: Text(
        l.texto,
        style: TextStyle(
          decoration: feito ? TextDecoration.lineThrough : null,
          color: feito ? AppColors.textSecondary : null,
        ),
      ),
      subtitle: Text(partes.join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (l.urgente)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.priority_high, color: AppColors.error, semanticLabel: 'Urgente'),
          ),
        IconButton(
          key: Key('lembrete_editar_${l.id}'),
          icon: const Icon(Icons.edit),
          tooltip: 'Editar lembrete',
          onPressed: () => _abrirForm(l),
        ),
      ]),
    );
  }

  Widget _filtros() {
    const rotulos = {
      _Filtro.pendentes: 'Pendentes',
      _Filtro.feitos: 'Feitos',
      _Filtro.enviados: 'Enviados',
      _Filtro.todos: 'Todos',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in _Filtro.values)
            ChoiceChip(
              key: Key('lembrete_filtro_${f.name}'),
              label: Text(rotulos[f]!),
              selected: _filtro == f,
              selectedColor: AppColors.primary.withValues(alpha: 0.18),
              onSelected: (_) => setState(() => _filtro = f),
            ),
        ],
      ),
    );
  }

  List<Widget> _lista() {
    final visiveis = _itens.where(_passa).toList()..sort((a, b) => a.quando.compareTo(b.quando));
    if (visiveis.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nenhum lembrete aqui.')),
        ),
      ];
    }
    final hoje = DateTime.now();
    final out = <Widget>[];
    DateTime? ultimo;
    for (final l in visiveis) {
      final dia = DateTime(l.quando.year, l.quando.month, l.quando.day);
      if (ultimo != dia) {
        ultimo = dia;
        final eHoje = dia == DateTime(hoje.year, hoje.month, hoje.day);
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            eHoje ? '${_cabecalhoDia(dia)} · hoje' : _cabecalhoDia(dia),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ));
      }
      out.add(_tile(l));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Lembretes'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('lembrete_novo'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _abrirForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novo lembrete'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          'O robô manda estes lembretes pelo WhatsApp da Bora todos os dias às 9h30, '
                          'uma mensagem só com os itens do dia. Os marcados como urgentes saem na hora '
                          '(a cada 10 minutos). Cada lembrete só sai uma vez.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      _filtros(),
                      ..._lista(),
                    ],
                  ),
                ),
    );
  }
}
