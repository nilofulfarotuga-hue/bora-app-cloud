// "Como o Bora decide" — quem já leu e quem falta (missão fechar-tudo-2026-11-10,
// bloco E4). Diretiva (UE) 2024/2831, art. 9.º: cada prestador recebe por
// escrito a informação sobre os sistemas automáticos; prazo 02/12/2026.
// A app mostra o aviso ao próprio prestador (botão "Li e percebi") — este ecrã
// só LÊ o registo (`admin_avisos_prestadores`) e exporta CSV. Não envia
// mensagens nem push a ninguém.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../prestador/como_o_bora_decide_screen.dart';

/// Contas por papel (função pura, testada em
/// `test/como_o_bora_decide_aviso_test.dart`).
class LeiturasAviso {
  const LeiturasAviso._();

  static const Map<String, String> nomesPapel = {
    'estafeta': 'Entregador',
    'motorista': 'Motorista',
    'limpeza': 'Limpeza',
    'lavagem': 'Lavagem',
    'casa': 'Casa',
  };

  static String nomePapel(Object? papel) =>
      nomesPapel['${papel ?? ''}'] ?? '${papel ?? '—'}';

  static bool leu(Map<String, dynamic> r) => r['lido_em'] != null;

  static bool aprovado(Map<String, dynamic> r) =>
      r['aprovacao'] == 'approved' && r['ativo'] != false;

  /// papel → (leram, total), na ordem em que os papéis aparecem.
  static Map<String, (int, int)> porPapel(
    Iterable<Map<String, dynamic>> linhas, {
    bool soAprovados = true,
  }) {
    final out = <String, (int, int)>{};
    for (final r in linhas) {
      if (soAprovados && !aprovado(r)) continue;
      final p = '${r['papel'] ?? '—'}';
      final (lidos, total) = out[p] ?? (0, 0);
      out[p] = (lidos + (leu(r) ? 1 : 0), total + 1);
    }
    return out;
  }
}

class AdminAvisosPrestadoresScreen extends StatefulWidget {
  const AdminAvisosPrestadoresScreen({super.key});

  @override
  State<AdminAvisosPrestadoresScreen> createState() =>
      _AdminAvisosPrestadoresScreenState();
}

class _AdminAvisosPrestadoresScreenState
    extends State<AdminAvisosPrestadoresScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _papel; // null = todos
  bool _soAprovados = true;
  bool _soFalta = false;

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
      final res = await Supabase.instance.client.rpc(
        'admin_avisos_prestadores',
        params: {
          'p_aviso': ComoOBoraDecide.aviso,
          'p_versao': ComoOBoraDecide.versaoId,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminAvisosPrestadores] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar as leituras. Se a migração '
            '20261110190000_prestador_avisos_lidos ainda não foi aplicada, '
            'esta lista fica vazia.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtradas => [
        for (final r in _rows)
          if ((_papel == null || r['papel'] == _papel) &&
              (!_soAprovados || LeiturasAviso.aprovado(r)) &&
              (!_soFalta || !LeiturasAviso.leu(r)))
            {
              ...r,
              'papel_nome': LeiturasAviso.nomePapel(r['papel']),
              'situacao': LeiturasAviso.leu(r) ? 'leu' : 'falta ler',
              'ativo_txt': r['ativo'] == false ? 'não' : 'sim',
            },
      ];

  @override
  Widget build(BuildContext context) {
    final resumo = LeiturasAviso.porPapel(_rows, soAprovados: _soAprovados);
    final linhas = _filtradas;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Como o Bora decide — leituras',
        actions: [
          AdminCsvButton(
            nome: 'como_o_bora_decide_leituras',
            colunas: const [
              ('papel_nome', 'papel'),
              ('nome', 'nome'),
              ('email', 'email'),
              ('telefone', 'telefone'),
              ('aprovacao', 'aprovação'),
              ('ativo_txt', 'ativo'),
              ('situacao', 'situação'),
              ('versao_lida', 'versão lida'),
              ('lido_em', 'leu em (Lisboa)'),
              ('ultima_versao_lida', 'última versão lida'),
              ('ultima_lida_em', 'última leitura (Lisboa)'),
            ],
            linhas: () => linhas,
          ),
          IconButton(
            tooltip: 'Ver o texto que o prestador vê',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => ComoOBoraDecideScreen.abrir(context),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _cabecalho(resumo),
                      const SizedBox(height: 8),
                      _filtros(resumo.keys),
                      const SizedBox(height: 8),
                      if (linhas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Ninguém nesta lista.',
                              textAlign: TextAlign.center),
                        )
                      else
                        for (final r in linhas) _linha(r),
                    ],
                  ),
                ),
    );
  }

  Widget _cabecalho(Map<String, (int, int)> resumo) => Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Versão em vigor: ${ComoOBoraDecide.versaoId}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Diretiva (UE) 2024/2831 (prazo 02/12/2026): cada prestador '
                'tem de receber por escrito "Como o Bora decide". O aviso '
                'aparece sozinho na app quando a pessoa abre, com o botão '
                '"Li e percebi" — ninguém recebe mensagem nem push por causa '
                'disto. Quando o texto muda, a versão muda e todos voltam a '
                'ler.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in resumo.entries)
                    Chip(
                      label: Text('${LeiturasAviso.nomePapel(e.key)}: '
                          '${e.value.$1} de ${e.value.$2} leram'),
                      backgroundColor: e.value.$1 == e.value.$2
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.15),
                    ),
                  if (resumo.isEmpty)
                    const Text('Nenhum prestador nesta seleção.'),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _filtros(Iterable<String> papeis) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: _papel == null,
            onSelected: (_) => setState(() => _papel = null),
          ),
          for (final p in {...papeis, ..._rows.map((r) => '${r['papel']}')})
            ChoiceChip(
              label: Text(LeiturasAviso.nomePapel(p)),
              selected: _papel == p,
              onSelected: (_) => setState(() => _papel = p),
            ),
          FilterChip(
            label: const Text('Só aprovados e ativos'),
            selected: _soAprovados,
            onSelected: (v) => setState(() => _soAprovados = v),
          ),
          FilterChip(
            label: const Text('Só quem falta'),
            selected: _soFalta,
            onSelected: (v) => setState(() => _soFalta = v),
          ),
        ],
      );

  Widget _linha(Map<String, dynamic> r) {
    final leu = LeiturasAviso.leu(r);
    final antiga = r['ultima_versao_lida'];
    final partes = <String>[
      LeiturasAviso.nomePapel(r['papel']),
      leu
          ? 'leu em ${dataHoraLisboa(r['lido_em'])}'
          : (antiga != null
              ? 'falta ler (leu a versão $antiga em ${dataHoraLisboa(r['ultima_lida_em'])})'
              : 'falta ler'),
      if (!LeiturasAviso.aprovado(r))
        'cadastro: ${r['aprovacao'] ?? '—'}${r['ativo'] == false ? ', inativo' : ''}',
    ];
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(
          leu ? Icons.check_circle : Icons.schedule,
          color: leu ? AppColors.primary : AppColors.warning,
        ),
        title: Text('${r['nome'] ?? '(sem nome)'}'),
        subtitle: Text(partes.join(' · ')),
      ),
    );
  }
}
