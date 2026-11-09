// Painel /admin/assistente — separador "Amigo Bora" (missão m4-amigo-bora-v1, 08/11/2026). PT-BR.
//
// Números (admin_amigo_overview): conversas por dia, % que viraram carrinho, comparações com a
// Glovo/Uber (e quem ganhou), deixas mostradas e clicadas, custo por conversa e por robô, perfis
// (só contagens). Interruptores: assistant_enabled, assistant_personality_enabled,
// deixa_promocoes_enabled (admin_update_setting, auditado). Texto de boas-vindas editável.
// "Ver perfil de um cliente": por email e com motivo obrigatório (admin_amigo_ver_perfil, fica na
// auditoria). Nada aqui mexe em dinheiro.
//
// 09/11/2026 (missão m11-amigo-rosto): secção "Rosto do Amigo" — pré-visualização ao vivo, um botão
// por expressão, teste de voz e boca, variante, interruptores amigo_* e números de uso
// (admin_amigo_rosto_overview). Ver admin_amigo_rosto_secao.dart.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import 'admin_amigo_rosto_secao.dart';

class AdminAssistenteAmigoTab extends StatefulWidget {
  const AdminAssistenteAmigoTab({super.key});

  @override
  State<AdminAssistenteAmigoTab> createState() => _AdminAssistenteAmigoTabState();
}

class _AdminAssistenteAmigoTabState extends State<AdminAssistenteAmigoTab>
    with AutomaticKeepAliveClientMixin {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _v;
  String? _erro;
  bool _loading = true;
  int _dias = 30;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final r = await _c.rpc('admin_amigo_overview', params: {'p_dias': _dias});
      if (!mounted) return;
      setState(() {
        _v = r is Map ? Map<String, dynamic>.from(r) : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminAmigo] $e');
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui carregar o Amigo Bora (a migração 20261108235215 já foi aplicada?).';
        _loading = false;
      });
    }
  }

  Future<void> _gravar(String chave, Object valor) async {
    try {
      await _c.rpc('admin_update_setting', params: {'p_key': chave, 'p_value': valor});
      _aviso('Salvo: $chave');
      await _load();
    } catch (e) {
      _aviso('Não salvei $chave: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editarBoasVindas(String atual) async {
    final ctrl = TextEditingController(text: atual);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Texto de boas-vindas do Amigo Bora'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 220,
          decoration: const InputDecoration(
            helperText: 'Aparece no cartão da home na primeira vez (2 linhas, PT-PT).',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (novo != null && novo.isNotEmpty && novo != atual) {
      await _gravar('assistant_amigo_welcome_text', novo);
    }
  }

  Future<void> _verPerfil() async {
    final email = TextEditingController();
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ver perfil de um cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email do cliente'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivo,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo (obrigatório, fica na auditoria)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ver')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await _c.rpc('admin_amigo_ver_perfil',
          params: {'p_email': email.text.trim(), 'p_motivo': motivo.text.trim()});
      if (!mounted) return;
      final m = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(email.text.trim()),
          content: SingleChildScrollView(
            child: SelectableText(m['ok'] == true
                ? 'Lembrar: ${m['lembrar']} · esquecido em: ${m['esquecido_em'] ?? '-'} · '
                    'atualizado: ${m['atualizado_em'] ?? '-'} · preferências: ${m['memorias']}\n\n'
                    '${_bonito(m['perfil'])}'
                : (m['erro'] ?? 'sem perfil').toString()),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    } catch (e) {
      _aviso(e.toString().contains('motivo_obrigatorio')
          ? 'Escreva o motivo (mínimo 10 letras).'
          : 'Erro: $e');
    }
  }

  static String _bonito(Object? perfil) {
    if (perfil is! Map || perfil.isEmpty) return '(perfil vazio)';
    return perfil.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_erro != null || _v == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erro ?? 'Sem dados.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
          ]),
        ),
      );
    }
    final v = _v!;
    final interruptores = Map<String, dynamic>.from((v['interruptores'] as Map?) ?? const {});
    final cmp = Map<String, dynamic>.from((v['comparacoes'] as Map?) ?? const {});
    final dx = Map<String, dynamic>.from((v['deixas'] as Map?) ?? const {});
    final perfis = Map<String, dynamic>.from((v['perfis'] as Map?) ?? const {});
    final conversas = (v['conversas'] as num?) ?? 0;
    final mostradas = (dx['mostradas'] as num?) ?? 0;
    final clicadas = (dx['clicadas'] as num?) ?? 0;
    final boasVindas = (interruptores['assistant_amigo_welcome_text'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('Período: '),
              DropdownButton<int>(
                value: _dias,
                items: const [7, 30, 90]
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d dias')))
                    .toList(),
                onChanged: (d) {
                  if (d == null) return;
                  setState(() => _dias = d);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Cartao('Conversas', '$conversas', 'com mensagens no período'),
              _Cartao('Viraram carrinho', '${v['pct_carrinho'] ?? 0}%',
                  '${v['com_carrinho'] ?? 0} com carrinho · ${v['virou_pedido'] ?? 0} viraram pedido'),
              _Cartao('Custo por conversa', 'US\$ ${v['custo_medio_conversa_usd'] ?? 0}',
                  'total US\$ ${v['custo_total_usd'] ?? 0}'),
              _Cartao('Comparações', '${cmp['total'] ?? 0}',
                  'Bora ganhou ${cmp['bora_ganhou'] ?? 0} · outra ${cmp['outra_ganhou'] ?? 0} · '
                      'empate ${cmp['empate'] ?? 0} · sem total ${cmp['sem_total'] ?? 0}'),
              _Cartao('Deixas', '$clicadas / $mostradas',
                  mostradas == 0 ? 'clicadas / mostradas' : 'clicadas / mostradas (${(100 * clicadas / mostradas).toStringAsFixed(0)}%)'),
              _Cartao('Perfis', '${perfis['total'] ?? 0}',
                  'com hábitos ${perfis['com_habitos'] ?? 0} · não lembrar ${perfis['nao_lembrar'] ?? 0} · '
                      'esqueceram ${perfis['esquecidos'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 16),
          AdminAmigoRostoSecao(dias: _dias),
          const Divider(height: 28),
          const Text('Interruptores', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          SwitchListTile(
            title: const Text('Assistente ligado (assistant_enabled)'),
            subtitle: const Text('Desligado: some o botão "Ajuda-me a escolher" e o servidor responde 503.'),
            value: interruptores['assistant_enabled'] != false,
            onChanged: (x) => _gravar('assistant_enabled', x),
          ),
          SwitchListTile(
            title: const Text('Personalidade Amigo Bora (assistant_personality_enabled)'),
            subtitle: const Text('Nome, memória por cliente, saudação do costume e conversa livre. Desligada, fica o assistente de compras simples.'),
            value: interruptores['assistant_personality_enabled'] == true,
            onChanged: (x) => _gravar('assistant_personality_enabled', x),
          ),
          SwitchListTile(
            title: const Text('Deixas de promoção (deixa_promocoes_enabled)'),
            subtitle: const Text('Uma linha útil no fim das conversas livres (promoção, parceiro novo, tokens, check-in). Nunca em compras nem no suporte.'),
            value: interruptores['deixa_promocoes_enabled'] == true,
            onChanged: (x) => _gravar('deixa_promocoes_enabled', x),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Texto de boas-vindas'),
            subtitle: Text(boasVindas.isEmpty ? '(padrão da app)' : boasVindas),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editarBoasVindas(boasVindas),
          ),
          Text('Modelo da conversa livre: ${interruptores['assistant_amigo_model'] ?? '-'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Divider(height: 28),
          const Text('Gasto por robô (ia_gastos)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final g in ((v['gastos_por_robo'] as List?) ?? const []).whereType<Map>())
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${g['robo']}'),
              trailing: Text('${g['chamadas']} chamadas · US\$ ${g['usd']}'),
            ),
          const Divider(height: 28),
          const Text('Últimas comparações', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final u in ((cmp['ultimas'] as List?) ?? const []).whereType<Map>())
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                u['vencedor'] == 'bora' ? Icons.emoji_events_outlined : Icons.compare_arrows,
                color: u['vencedor'] == 'bora' ? AppColors.primary : AppColors.textSecondary,
              ),
              title: Text('${u['app']} · ${u['artigos']} artigos · ${u['origem']}'),
              subtitle: Text('Vencedor: ${u['vencedor']} · diferença '
                  '${u['diferenca_cents'] == null ? '-' : '${((u['diferenca_cents'] as num) / 100).toStringAsFixed(2)} €'}'
                  ' · loja Bora: ${u['loja_bora'] ?? '-'}'),
            ),
          const Divider(height: 28),
          OutlinedButton.icon(
            onPressed: _verPerfil,
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Ver perfil de um cliente (com motivo)'),
          ),
          const SizedBox(height: 6),
          const Text(
            'A lista de perfis mostra só contagens. Abrir um perfil pede o email e um motivo, e fica registrado na auditoria.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao(this.titulo, this.valor, this.detalhe);
  final String titulo;
  final String valor;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(detalhe, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
