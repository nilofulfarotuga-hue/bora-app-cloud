import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/auth_admin_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Sugestões da lupa (PT-BR) — missão lupa-sugestoes-17-11, bloco 1.5.
///
/// Com 1 ou 2 letras a lupa do app mostra sugestões (palavras do catálogo,
/// produtos mais pedidos, seções e lojas) lidas de uma tabela pequena
/// (`lupa_sugestoes`, ~5 mil linhas), sem pesquisar os 63 mil produtos. O banco
/// recalcula de hora em hora (pg_cron `lupa-sugestoes`) e para se o vigia do
/// servidor passar de 50%.
///
/// Aqui o admin: vê a lista e o peso, filtra, recalcula agora, esconde uma
/// sugestão (o recálculo não a traz de volta) e liga/desliga tudo
/// (`platform_settings.lupa_sugestoes_enabled`).
///
/// Fontes: RPC `admin_lupa_sugestoes_listar`, `admin_lupa_sugestoes_recalcular`,
/// `admin_lupa_sugestoes_esconder` e `admin_update_setting` (só admin).
class AdminLupaSugestoesScreen extends StatefulWidget {
  const AdminLupaSugestoesScreen({super.key});

  @override
  State<AdminLupaSugestoesScreen> createState() =>
      _AdminLupaSugestoesScreenState();
}

class _AdminLupaSugestoesScreenState extends State<AdminLupaSugestoesScreen> {
  static const _tipos = <String?, String>{
    null: 'Todos',
    'palavra': 'Palavras',
    'produto': 'Produtos',
    'seccao': 'Seções',
    'loja': 'Lojas',
  };

  final _busca = TextEditingController();
  String? _tipo;
  bool _soGeral = false;
  bool _aGravar = false;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'admin_lupa_sugestoes_listar',
      params: {
        'p_q': _busca.text.trim().isEmpty ? null : _busca.text.trim(),
        'p_tipo': _tipo,
        'p_so_geral': _soGeral,
        'p_limit': 200,
      },
    );
    if (res is! Map) return const {};
    return Map<String, dynamic>.from(res);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _recalcular() async {
    setState(() => _aGravar = true);
    try {
      final r = await Supabase.instance.client
          .rpc('admin_lupa_sugestoes_recalcular');
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      if (m['parado'] == true) {
        _aviso('Não recalculou: ${m['motivo'] ?? 'parado'}'
            '${m['ocupado_pct'] != null ? ' (servidor em ${m['ocupado_pct']}%)' : ''}. '
            'Tente de novo em alguns minutos.');
      } else {
        _aviso('Recalculado: ${m['total'] ?? '?'} sugestões '
            '(${m['escritas'] ?? '?'} gravadas, ${m['removidas'] ?? '?'} removidas) '
            'em ${m['ms'] ?? '?'} ms.');
      }
    } catch (e) {
      _aviso('Erro ao recalcular: $e');
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
    await _refresh();
  }

  Future<void> _esconder(Map<String, dynamic> linha, bool esconder) async {
    try {
      await Supabase.instance.client.rpc('admin_lupa_sugestoes_esconder',
          params: {'p_id': linha['id'], 'p_escondida': esconder});
      _aviso(esconder
          ? '"${linha['texto']}" escondida da lupa.'
          : '"${linha['texto']}" voltou a aparecer na lupa.');
    } catch (e) {
      _aviso('Erro: $e');
    }
    await _refresh();
  }

  Future<void> _ligar(bool ligado) async {
    try {
      await Supabase.instance.client.rpc('admin_update_setting', params: {
        'p_key': 'lupa_sugestoes_enabled',
        'p_value': ligado,
      });
      _aviso(ligado
          ? 'Sugestões da lupa LIGADAS.'
          : 'Sugestões da lupa DESLIGADAS: a lupa volta a esperar 3 letras.');
    } catch (e) {
      _aviso('Erro ao mudar o interruptor: $e');
    }
    await _refresh();
  }

  IconData _icone(Object? tipo) => switch ('$tipo') {
        'produto' => Icons.shopping_basket_outlined,
        'seccao' => Icons.category_outlined,
        'loja' => Icons.storefront_outlined,
        _ => Icons.search,
      };

  @override
  Widget build(BuildContext context) {
    if (!AuthAdminService.isAdmin()) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Sugestões da lupa'),
        body: Center(child: Text('Acesso negado.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Sugestões da lupa',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            final dados = snap.data ?? const <String, dynamic>{};
            final estado = dados['estado'] is Map
                ? Map<String, dynamic>.from(dados['estado'] as Map)
                : const <String, dynamic>{};
            final contagem = dados['contagem'] is Map
                ? Map<String, dynamic>.from(dados['contagem'] as Map)
                : const <String, dynamic>{};
            final linhas = dados['linhas'] is List
                ? [
                    for (final e in dados['linhas'] as List)
                      Map<String, dynamic>.from(e as Map)
                  ]
                : const <Map<String, dynamic>>[];
            final ligado = dados['ligado'] != false;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Com 1 ou 2 letras a lupa do app mostra estas sugestões '
                  '(como na Uber Eats e no Glovo), lidas de uma tabela pequena — '
                  'não pesquisa os 63 mil produtos, por isso quase não pesa no '
                  'servidor. Peso = ordem (maior aparece primeiro). Recalcula '
                  'sozinho de hora em hora (cron = tarefa agendada no banco) e '
                  'para se o servidor passar de 50% ocupado. Lojas escondidas '
                  '(lista de permissão) nunca aparecem a quem não as vê.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sugestões ligadas'),
                  subtitle: const Text(
                      'Desligado: com 1-2 letras o app só mostra "Escreve mais letras" e a busca completa começa nas 3 letras.'),
                  value: ligado,
                  onChanged: snap.hasData ? _ligar : null,
                ),
                Text(
                  'Último recálculo: ${estado['ultimo_recalculo'] == null ? 'ainda não' : dataHoraLisboa(estado['ultimo_recalculo'])}'
                  '${estado['pendente'] == true ? ' · uma loja mudou, recalcula nos próximos 5 min' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
                if (estado['ultimo_resultado'] is Map &&
                    (estado['ultimo_resultado'] as Map)['parado'] == true)
                  Text(
                    'A última tentativa parou: ${(estado['ultimo_resultado'] as Map)['motivo']}'
                    ' (servidor em ${(estado['ultimo_resultado'] as Map)['ocupado_pct'] ?? '?'}%).',
                    style: const TextStyle(fontSize: 13, color: Colors.red),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Total: ${contagem.values.fold<num>(0, (a, b) => a + (b is num ? b : 0))} · '
                  'palavras ${contagem['palavra'] ?? 0} · produtos ${contagem['produto'] ?? 0} · '
                  'seções ${contagem['seccao'] ?? 0} · lojas ${contagem['loja'] ?? 0}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _aGravar ? null : _recalcular,
                    icon: const Icon(Icons.autorenew),
                    label: Text(_aGravar ? 'Recalculando…' : 'Recalcular agora'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _busca,
                  decoration: const InputDecoration(
                    labelText: 'Começa com… (ex.: a, ag, leite)',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _refresh(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final e in _tipos.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _tipo == e.key,
                        onSelected: (_) {
                          _tipo = e.key;
                          _refresh();
                        },
                      ),
                    FilterChip(
                      label: const Text('Só a lupa da página inicial'),
                      selected: _soGeral,
                      onSelected: (v) {
                        _soGeral = v;
                        _refresh();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (snap.hasError)
                  Text('Erro ao carregar (admin_lupa_sugestoes_listar): ${snap.error}')
                else ...[
                  Text('${dados['total'] ?? 0} sugestões com estes filtros '
                      '(mostrando até 200, por peso).',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  for (final l in linhas)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_icone(l['tipo']),
                          color: l['escondida'] == true
                              ? Colors.grey
                              : AppColors.textSecondary),
                      title: Text(
                        '${l['texto']}',
                        style: TextStyle(
                          decoration: l['escondida'] == true
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${_tipos[l['tipo']] ?? l['tipo']} · peso ${l['peso']} · '
                        '${l['restaurant_id'] == null ? 'página inicial' : 'lupa da loja'}'
                        '${l['loja_nome'] != null ? ' · ${l['loja_nome']}' : ''}'
                        '${l['escondida'] == true ? ' · ESCONDIDA' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: () =>
                            _esconder(l, l['escondida'] != true),
                        child: Text(l['escondida'] == true
                            ? 'Mostrar'
                            : 'Esconder sugestão'),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
