// BORA ASSISTENTE — separador "Aprendidas" do painel /admin/assistente
// (missão app-fechar 01/11/2026, bloco B6). PT-BR, só o Danilo usa.
//
// Lista a tabela `assistant_learned`: o que o assistente aprendeu sozinho
// (kind='resposta' → resposta que achou no manual do suporte; kind='licao' →
// lição quando o cliente disse "não era isso"), quando e se está ativa. Cada
// linha tem um interruptor: desligada, deixa de entrar no prompt do assistente
// (a Edge Function `client-assistant` só lê `active = true`).
//
// RLS da tabela: política `assistant_learned_admin` (ALL, `is_admin()`), por
// isso o painel lê e grava direto, como os outros separadores deste ecrã.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';

/// Uma linha de `assistant_learned`.
class AssistenteAprendida {
  const AssistenteAprendida({
    required this.id,
    required this.kind,
    required this.question,
    required this.answer,
    required this.source,
    required this.active,
    required this.hits,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 'resposta' (achou no manual) ou 'licao' (cliente corrigiu).
  final String kind;
  final String question;
  final String answer;
  final String source;
  final bool active;

  /// Quantas vezes a mesma pergunta voltou a precisar desta resposta.
  final int hits;
  final String? createdAt;
  final String? updatedAt;

  bool get eLicao => kind == 'licao';

  /// Rótulo do tipo em PT-BR.
  String get tipoRotulo => eLicao ? 'Lição' : 'Resposta do manual';

  factory AssistenteAprendida.fromMap(Map<String, dynamic> m) {
    final a = m['active'];
    final h = m['hits'];
    return AssistenteAprendida(
      id: '${m['id'] ?? ''}',
      kind: '${m['kind'] ?? 'resposta'}',
      question: '${m['question'] ?? ''}',
      answer: '${m['answer'] ?? ''}',
      source: '${m['source'] ?? ''}',
      active: a is bool ? a : '$a' != 'false',
      hits: h is num ? h.toInt() : int.tryParse('${h ?? ''}') ?? 0,
      createdAt: m['created_at']?.toString(),
      updatedAt: m['updated_at']?.toString(),
    );
  }

  AssistenteAprendida comAtiva(bool v) => AssistenteAprendida(
        id: id,
        kind: kind,
        question: question,
        answer: answer,
        source: source,
        active: v,
        hits: hits,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A porta do separador. Em teste troca-se por uma de mentira.
abstract class AprendidasApi {
  Future<List<AssistenteAprendida>> listar();
  Future<void> definirAtiva(String id, bool ativa);
}

class AprendidasSupabase implements AprendidasApi {
  AprendidasSupabase([SupabaseClient? c]) : _c = c;
  final SupabaseClient? _c;
  SupabaseClient get _sb => _c ?? Supabase.instance.client;

  static const _tempo = Duration(seconds: 15);

  @override
  Future<List<AssistenteAprendida>> listar() async {
    final rows = await _sb
        .from('assistant_learned')
        .select(
            'id, kind, question, answer, source, active, hits, created_at, updated_at')
        .order('created_at', ascending: false)
        .limit(300)
        .timeout(_tempo);
    return rows.map(AssistenteAprendida.fromMap).toList();
  }

  @override
  Future<void> definirAtiva(String id, bool ativa) async {
    // Lê de volta: com a RLS, um UPDATE sem permissão não dá erro, só muda 0
    // linhas — e o interruptor mentiria.
    final r = await _sb
        .from('assistant_learned')
        .update({
          'active': ativa,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id, active')
        .timeout(_tempo);
    if (r.isEmpty || r.first['active'] != ativa) {
      throw Exception('nada foi gravado (sem permissão de admin?)');
    }
  }
}

class AdminAssistenteAprendidasTab extends StatefulWidget {
  const AdminAssistenteAprendidasTab({super.key, this.api});

  /// Só para testes: troca o servidor por uma porta de mentira.
  final AprendidasApi? api;

  @override
  State<AdminAssistenteAprendidasTab> createState() =>
      _AdminAssistenteAprendidasTabState();
}

class _AdminAssistenteAprendidasTabState
    extends State<AdminAssistenteAprendidasTab>
    with AutomaticKeepAliveClientMixin {
  late final AprendidasApi _api = widget.api ?? AprendidasSupabase();
  List<AssistenteAprendida> _linhas = const [];
  bool _carregando = true;
  String? _erro;
  final Set<String> _aGravar = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await _api.listar();
      if (!mounted) return;
      setState(() {
        _linhas = l;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para carregar: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _alternar(AssistenteAprendida a, bool v) async {
    if (_aGravar.contains(a.id)) return;
    setState(() => _aGravar.add(a.id));
    try {
      await _api.definirAtiva(a.id, v);
      if (!mounted) return;
      setState(() {
        _linhas = [
          for (final l in _linhas) l.id == a.id ? l.comAtiva(v) : l,
        ];
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(v
                ? 'Ligada: volta a entrar nas respostas do assistente.'
                : 'Desligada: o assistente deixa de usar isto.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Não deu para gravar: $e'),
            backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _aGravar.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: _carregar, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    final ativas = _linhas.where((l) => l.active).length;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'O que o assistente aprendeu (${_linhas.length}, $ativas ativas)',
                      key: const Key('aprendidas-titulo'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text(
                    'Respostas que ele achou sozinho no manual do suporte e lições de quando o '
                    'cliente disse "não era isso". As ativas entram em todas as conversas. '
                    'Desligue a que estiver errada: ela deixa de ser usada na hora (nada se apaga).',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (_linhas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('O assistente ainda não aprendeu nada.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          for (final a in _linhas) _linha(a),
        ],
      ),
    );
  }

  Widget _linha(AssistenteAprendida a) {
    final quando = dataHoraLisboa(a.createdAt);
    final mudou = a.updatedAt != null &&
        a.updatedAt != a.createdAt &&
        dataHoraLisboa(a.updatedAt) != quando;
    return Card(
      key: Key('aprendida-${a.id}'),
      child: ListTile(
        leading: Icon(
          a.eLicao ? Icons.school_outlined : Icons.menu_book_outlined,
          color: a.active ? AppColors.primary : AppColors.textSecondary,
        ),
        title: Text(a.question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: a.active ? AppColors.textPrimary : AppColors.textSecondary,
            )),
        subtitle: Text(
          '${a.answer}\n'
          '${a.tipoRotulo} · aprendida em $quando'
          '${mudou ? ' · atualizada ${dataHoraLisboa(a.updatedAt)}' : ''}'
          '${a.hits > 1 ? ' · usada ${a.hits}x' : ''}'
          ' · ${a.active ? 'ativa' : 'desligada'}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Switch(
          key: Key('aprendida-switch-${a.id}'),
          value: a.active,
          activeThumbColor: AppColors.primary,
          onChanged: _aGravar.contains(a.id) ? null : (v) => _alternar(a, v),
        ),
      ),
    );
  }
}
