// Painel admin (PT-BR) — Central do robô do suporte (05/11/2026, missão
// robo-suporte-inteligente-2026-11-05, bloco E). Autoridade total sobre o robô:
//  - Conversas: cada conversa com as ferramentas (funções de consulta) que o
//    robô usou e o que elas devolveram; exportar CSV.
//  - Sem resposta: o que o robô passou à equipa ou disse que não sabia, com
//    botão para propor uma skill (guia de atendimento) nova.
//  - Ajustes: trocar o modelo (a IA que responde) e ligar/desligar cada
//    ferramenta e cada skill. Tudo fica no log de auditoria.
// Lê as RPCs admin_suporte_*. Sem elas no servidor, mostra o erro de carregar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';

/// Ferramentas de leitura e ação do robô, com o que cada uma faz (PT-BR).
const Map<String, String> kFerramentasSuporte = {
  'agent_get_order_full': 'Conta completa do pedido (produtos, taxas, tokens, cobrado)',
  'agent_get_order_status': 'Estado do pedido e tempo previsto',
  'agent_get_user_orders_summary': 'Últimos pedidos da pessoa',
  'agent_get_refund_status': 'Estado do reembolso',
  'agent_get_my_tokens_history': 'Tokens: saldo, quanto pode usar, a expirar',
  'agent_get_user_tokens_summary': 'Tokens: resumo curto',
  'agent_get_my_wallet_history': 'Carteira Bora: saldo e movimentos',
  'agent_get_user_wallet_summary': 'Carteira Bora: resumo curto',
  'agent_get_my_bookings': 'Marcações: limpeza, lavagem, mesa, serviços, Favores',
  'agent_get_my_tvde_reservations': 'Corridas de carro marcadas',
  'agent_get_store_info': 'Loja: aberta agora, horário, entrega grátis',
  'agent_search_products': 'Produtos e preço da app',
  'agent_get_my_driver_summary': 'Entregador: ganhos dele e pedido em curso',
  'agent_get_my_partner_today': 'Parceiro: loja dele e como fazer na app',
};

/// Modelos do suporte. Vazio = o que o porteiro (regra do crédito) escolher.
const Map<String, String> kModelosSuporte = {
  'gemini-3.5-flash-lite': 'Automático (Sonnet pelo porteiro, Haiku e Gemini de reserva)',
  'claude-sonnet-5-5': 'Claude Sonnet fixo',
  'claude-haiku-5-5': 'Claude Haiku fixo (mais barato)',
};

class SuporteCentralApi {
  const SuporteCentralApi();

  Future<Object?> _rpc(String nome, [Map<String, dynamic>? p]) =>
      Supabase.instance.client.rpc(nome, params: p ?? const {});

  static List<Map<String, dynamic>> _lista(Object? r) => r is List
      ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> conversas(int dias) async =>
      _lista(await _rpc('admin_suporte_conversas', {'p_dias': dias}));
  Future<List<Map<String, dynamic>>> conversa(String id) async =>
      _lista(await _rpc('admin_suporte_conversa', {'p_sessao': id}));
  Future<List<Map<String, dynamic>>> semResposta(int dias) async =>
      _lista(await _rpc('admin_suporte_sem_resposta', {'p_dias': dias}));
  Future<Map<String, dynamic>> config() async {
    final r = await _rpc('admin_suporte_config');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<bool> definir(String tipo, String nome, String valor) async {
    final r = await _rpc('admin_suporte_definir', {'p_tipo': tipo, 'p_nome': nome, 'p_valor': valor});
    return r is Map && r['ok'] == true;
  }

  Future<bool> proporSkill(String pergunta, String nome, String guia) async {
    final r = await _rpc('admin_suporte_propor_skill', {'p_pergunta': pergunta, 'p_nome': nome, 'p_guia': guia});
    return r is Map && r['ok'] == true;
  }
}

class AdminSuporteCentralScreen extends StatelessWidget {
  const AdminSuporteCentralScreen({super.key, this.api = const SuporteCentralApi()});

  final SuporteCentralApi api;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Central do robô do suporte'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Conversas'),
            Tab(text: 'Sem resposta'),
            Tab(text: 'Ajustes'),
          ]),
        ),
        body: TabBarView(children: [
          _Conversas(api: api),
          _SemResposta(api: api),
          _Ajustes(api: api),
        ]),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro(this.erro);
  final Object erro;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Não foi possível carregar: $erro', style: const TextStyle(color: AppColors.error)),
      );
}

class _Conversas extends StatefulWidget {
  const _Conversas({required this.api});
  final SuporteCentralApi api;

  @override
  State<_Conversas> createState() => _ConversasState();
}

class _ConversasState extends State<_Conversas> {
  late Future<List<Map<String, dynamic>>> _f = widget.api.conversas(30);
  List<Map<String, dynamic>> _linhas = const [];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (_, s) {
        if (s.hasError) return _Erro(s.error!);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        _linhas = s.data!;
        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AdminCsvButton(
              nome: 'conversas_suporte',
              colunas: const [
                ('quando', 'Quando'), ('papel', 'Papel'), ('nome', 'Pessoa'), ('primeira', 'Primeira mensagem'),
                ('mensagens', 'Mensagens'), ('passou_a_equipa', 'Passou à equipe'), ('ferramentas', 'Ferramentas'),
              ],
              linhas: () => _linhas,
            ),
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _f = widget.api.conversas(30);
              }),
            ),
          ]),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma conversa nos últimos 30 dias.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (_, i) {
                      final l = _linhas[i];
                      final ferr = (l['ferramentas'] as List?)?.length ?? 0;
                      return ListTile(
                        key: Key('conversa_${l['id']}'),
                        leading: Icon(l['passou_a_equipa'] == true ? Icons.support_agent : Icons.smart_toy_outlined),
                        title: Text('${l['nome'] ?? '—'} · ${l['papel'] ?? ''}'),
                        subtitle: Text('${dataHoraLisboa(l['quando'])} · ${l['primeira'] ?? ''}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text('$ferr ferr.'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _Conversa(api: widget.api, id: '${l['id']}', titulo: '${l['nome'] ?? 'Conversa'}'),
                        )),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

class _Conversa extends StatelessWidget {
  const _Conversa({required this.api, required this.id, required this.titulo});
  final SuporteCentralApi api;
  final String id;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: api.conversa(id),
        builder: (_, s) {
          if (s.hasError) return _Erro(s.error!);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final m = s.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: m.length,
            itemBuilder: (_, i) {
              final l = m[i];
              if (l['papel'] == 'tool') {
                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.build_outlined, size: 18),
                    title: Text('Ferramenta: ${l['ferramenta'] ?? '?'}', style: const TextStyle(fontSize: 13)),
                    childrenPadding: const EdgeInsets.all(12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('Pediu: ${jsonEncode(l['entrada'])}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      SelectableText('Devolveu: ${const JsonEncoder.withIndent('  ').convert(l['saida'])}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }
              final eu = l['papel'] == 'user';
              return Align(
                alignment: eu ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: eu ? Colors.grey.shade100 : AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText('${l['texto'] ?? ''}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SemResposta extends StatefulWidget {
  const _SemResposta({required this.api});
  final SuporteCentralApi api;

  @override
  State<_SemResposta> createState() => _SemRespostaState();
}

class _SemRespostaState extends State<_SemResposta> {
  late Future<List<Map<String, dynamic>>> _f = widget.api.semResposta(30);

  Future<void> _propor(String pergunta) async {
    final nome = TextEditingController();
    final guia = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propor skill (guia de atendimento)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(pergunta, maxLines: 3, overflow: TextOverflow.ellipsis),
          TextField(key: const Key('skill_nome'), controller: nome, decoration: const InputDecoration(labelText: 'Nome da skill')),
          TextField(
            key: const Key('skill_guia'),
            controller: guia,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'O que o robô deve fazer'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Propor')),
        ],
      ),
    );
    final n = nome.text.trim();
    final g = guia.text.trim();
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var feito = false;
    try {
      feito = await widget.api.proporSkill(pergunta, n, g);
    } catch (_) {
      feito = false;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(feito
          ? 'Proposta criada. Aprove em Sugestões de skills.'
          : 'Não foi criada: escreva o nome e o que o robô deve fazer.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (_, s) {
        if (s.hasError) return _Erro(s.error!);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final l = s.data!;
        if (l.isEmpty) return const Center(child: Text('Nenhuma pergunta sem resposta nos últimos 30 dias.'));
        return ListView.builder(
          itemCount: l.length,
          itemBuilder: (_, i) {
            final x = l[i];
            return ListTile(
              title: Text('${x['pergunta'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${dataHoraLisboa(x['quando'])} · ${x['motivo'] ?? ''}\n${x['resposta'] ?? ''}',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              isThreeLine: true,
              trailing: IconButton(
                key: Key('propor_$i'),
                tooltip: 'Propor skill',
                icon: const Icon(Icons.add_task),
                onPressed: () => _propor('${x['pergunta'] ?? ''}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _Ajustes extends StatefulWidget {
  const _Ajustes({required this.api});
  final SuporteCentralApi api;

  @override
  State<_Ajustes> createState() => _AjustesState();
}

class _AjustesState extends State<_Ajustes> {
  late Future<Map<String, dynamic>> _f = widget.api.config();

  Future<void> _definir(String tipo, String nome, String valor) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await widget.api.definir(tipo, nome, valor);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Não foi possível guardar.')));
    setState(() {
      _f = widget.api.config();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (_, s) {
        if (s.hasError) return _Erro(s.error!);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final c = s.data!;
        final desligadas = ((c['ferramentas_desligadas'] as List?) ?? const []).map((e) => '$e').toSet();
        final skills = ((c['skills'] as List?) ?? const []).whereType<Map>().toList();
        final modelo = '${c['modelo'] ?? ''}';
        return ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Modelo (a IA que responde)', style: TextStyle(fontWeight: FontWeight.w700)),
          DropdownButton<String>(
            key: const Key('modelo_suporte'),
            isExpanded: true,
            value: kModelosSuporte.containsKey(modelo) ? modelo : null,
            hint: Text(modelo),
            items: [
              for (final e in kModelosSuporte.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) _definir('modelo', 'modelo', v);
            },
          ),
          const SizedBox(height: 12),
          const Text('Ferramentas (consultas que o robô pode fazer)', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final e in kFerramentasSuporte.entries)
            SwitchListTile(
              key: Key('ferramenta_${e.key}'),
              dense: true,
              title: Text(e.value),
              subtitle: Text(e.key, style: const TextStyle(fontSize: 11)),
              value: !desligadas.contains(e.key),
              onChanged: (v) => _definir('ferramenta', e.key, v ? 'ligar' : 'desligar'),
            ),
          const SizedBox(height: 12),
          const Text('Skills (guias de atendimento)', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final k in skills)
            SwitchListTile(
              key: Key('skill_${k['nome']}'),
              dense: true,
              title: Text('${k['nome']}'),
              subtitle: Text('${k['modo'] ?? ''}', style: const TextStyle(fontSize: 11)),
              value: k['ativa'] == true,
              onChanged: (v) => _definir('skill', '${k['nome']}', v ? 'ligar' : 'desligar'),
            ),
        ]);
      },
    );
  }
}
