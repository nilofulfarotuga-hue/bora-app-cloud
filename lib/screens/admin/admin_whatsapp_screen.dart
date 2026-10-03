// Missão 02/09/2026 — WhatsApp da loja no painel admin (PT-BR).
// Lê as tabelas `whatsapp_*` (RLS via is_admin()): conversas com última mensagem e estado do bot,
// abrir conversa, Pausar/Retomar, Assumir/Liberar, leads, lista de espera de estafetas, log de
// ferramentas chamadas, exportar CSV (copia para a área de transferência). O interruptor global
// "Envio ligado" escreve em whatsapp_settings.envio_ligado — o cérebro lê a cada pedido.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminWhatsappScreen extends StatefulWidget {
  const AdminWhatsappScreen({super.key});

  @override
  State<AdminWhatsappScreen> createState() => _AdminWhatsappScreenState();
}

class _AdminWhatsappScreenState extends State<AdminWhatsappScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool? _envioLigado;
  List<Map<String, dynamic>> _contatos = [];
  List<Map<String, dynamic>> _leads = [];
  List<Map<String, dynamic>> _ferramentas = [];
  bool _loading = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final s = await _supabase
          .from('whatsapp_settings')
          .select('key, value')
          .eq('key', 'envio_ligado')
          .maybeSingle();
      final c = await _supabase
          .from('whatsapp_contacts')
          .select('numero, nome, papel, tratamento, lingua, bot_pausado, bot_pausado_ate, '
              'assumido_por_danilo, ultima_msg_em, ultima_resposta_bot_em, prometido, notas')
          .order('ultima_msg_em', ascending: false, nullsFirst: false)
          .limit(300);
      final l = await _supabase
          .from('whatsapp_leads')
          .select('id, numero, tipo, estado, dados, created_at, danilo_avisado_em, lembrete_enviado_em')
          .order('created_at', ascending: false)
          .limit(200);
      final f = await _supabase
          .from('whatsapp_messages')
          .select('numero, modelo, ferramentas, latencia_ms, decisao, created_at, texto')
          .not('ferramentas', 'is', null)
          .order('created_at', ascending: false)
          .limit(150);
      setState(() {
        _envioLigado = s == null ? null : (s['value'] == true);
        _contatos = List<Map<String, dynamic>>.from(c);
        _leads = List<Map<String, dynamic>>.from(l);
        _ferramentas = List<Map<String, dynamic>>.from(f);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _mudarEnvio(bool ligar) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ligar ? 'Ligar o envio do bot?' : 'Desligar o envio do bot?'),
        content: Text(ligar
            ? 'O bot passa a responder sozinho a mensagens NOVAS no WhatsApp da loja.'
            : 'O bot continua a ler e a registrar, mas não envia nada a ninguém.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ligar ? 'Ligar' : 'Desligar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('whatsapp_settings').upsert({'key': 'envio_ligado', 'value': ligar});
      await _supabase.from('whatsapp_settings').upsert({
        'key': ligar ? 'envio_ligado_em' : 'envio_desligado_em',
        'value': DateTime.now().toUtc().toIso8601String(),
      });
      await _carregar();
    } catch (e) {
      _aviso('Erro: $e');
    }
  }

  Future<void> _pausar(Map<String, dynamic> c, {int? minutos, bool assumir = false}) async {
    try {
      await _supabase.from('whatsapp_contacts').update({
        'bot_pausado': true,
        'bot_pausado_ate': minutos == null
            ? null
            : DateTime.now().toUtc().add(Duration(minutes: minutos)).toIso8601String(),
        'bot_pausado_por': assumir ? 'danilo assumiu' : 'admin',
        'assumido_por_danilo': assumir,
      }).eq('numero', c['numero']);
      await _carregar();
    } catch (e) {
      _aviso('Erro: $e');
    }
  }

  Future<void> _retomar(Map<String, dynamic> c) async {
    try {
      await _supabase.from('whatsapp_contacts').update({
        'bot_pausado': false,
        'bot_pausado_ate': null,
        'bot_pausado_por': null,
        'assumido_por_danilo': false,
      }).eq('numero', c['numero']);
      await _carregar();
    } catch (e) {
      _aviso('Erro: $e');
    }
  }

  Future<void> _mudarEstadoLead(Map<String, dynamic> l, String estado) async {
    try {
      await _supabase.from('whatsapp_leads').update({'estado': estado}).eq('id', l['id']);
      await _carregar();
    } catch (e) {
      _aviso('Erro: $e');
    }
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _csv(List<Map<String, dynamic>> rows, List<String> cols) {
    String esc(dynamic v) {
      final s = (v ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }
    final b = StringBuffer(cols.join(';'));
    for (final r in rows) {
      b.write('\n${cols.map((c) => esc(r[c])).join(';')}');
    }
    return b.toString();
  }

  Future<void> _exportar() async {
    final csv = _csv(_contatos, [
      'numero', 'nome', 'papel', 'tratamento', 'lingua', 'bot_pausado', 'assumido_por_danilo',
      'ultima_msg_em', 'ultima_resposta_bot_em'
    ]);
    await Clipboard.setData(ClipboardData(text: csv));
    _aviso('CSV de ${_contatos.length} contatos copiado para a área de transferência.');
  }

  String _mask(String n) => n.length > 6 ? '${n.substring(0, 3)} *** ${n.substring(n.length - 3)}' : n;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'WhatsApp da loja',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
          IconButton(onPressed: _exportar, icon: const Icon(Icons.download), tooltip: 'Exportar CSV'),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/admin/motores'),
            icon: const Icon(Icons.bolt),
            tooltip: 'Motores (roteador)',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Conversas'),
            Tab(text: 'Leads'),
            Tab(text: 'Lista de espera'),
            Tab(text: 'Ferramentas'),
          ],
        ),
      ),
      body: Column(
        children: [
          _barraEnvio(),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [_conversas(), _leadsTab(), _listaEspera(), _ferramentasTab()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _barraEnvio() {
    final ligado = _envioLigado == true;
    return Container(
      color: ligado ? AppColors.primary.withValues(alpha: 0.10) : AppColors.error.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(ligado ? Icons.smart_toy : Icons.pause_circle_outline,
              color: ligado ? AppColors.primary : AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ligado ? 'Bot LIGADO — responde sozinho a mensagens novas' : 'Bot DESLIGADO — só lê e registra',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Switch(value: ligado, onChanged: _envioLigado == null ? null : _mudarEnvio),
        ],
      ),
    );
  }

  Widget _conversas() {
    if (_contatos.isEmpty) return const Center(child: Text('Sem conversas registradas ainda.'));
    return ListView.separated(
      itemCount: _contatos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _contatos[i];
        final numero = (c['numero'] ?? '').toString();
        final pausado = c['bot_pausado'] == true;
        final assumido = c['assumido_por_danilo'] == true;
        final estado = assumido ? 'ASSUMIDO por você' : (pausado ? 'bot pausado' : 'bot ativo');
        final cor = assumido ? AppColors.accent : (pausado ? AppColors.textSubtle : AppColors.primary);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: cor.withValues(alpha: 0.15),
            child: Icon(assumido ? Icons.person : (pausado ? Icons.pause : Icons.smart_toy), color: cor, size: 20),
          ),
          title: Text(c['nome']?.toString().isNotEmpty == true ? '${c['nome']} · ${_mask(numero)}' : '+$numero'),
          subtitle: Text('${c['papel'] ?? 'desconhecido'} · ${c['lingua'] ?? ''} · $estado\n'
              'última msg: ${(c['ultima_msg_em'] ?? '—').toString().replaceFirst('T', ' ').split('.').first}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'pausar1h':
                  _pausar(c, minutos: 60);
                case 'pausar':
                  _pausar(c);
                case 'assumir':
                  _pausar(c, assumir: true);
                case 'retomar':
                  _retomar(c);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pausar1h', child: Text('Pausar bot 1 hora')),
              PopupMenuItem(value: 'pausar', child: Text('Pausar bot neste contato')),
              PopupMenuItem(value: 'assumir', child: Text('Assumir (eu respondo)')),
              PopupMenuItem(value: 'retomar', child: Text('Retomar / Liberar bot')),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _ConversaScreen(contato: c)),
          ).then((_) => _carregar()),
        );
      },
    );
  }

  Widget _leadsTab() {
    final leads = _leads.where((l) => l['tipo'] != 'estafeta').toList();
    if (leads.isEmpty) return const Center(child: Text('Sem leads ainda.'));
    return ListView.builder(
      itemCount: leads.length,
      itemBuilder: (_, i) => _leadTile(leads[i]),
    );
  }

  Widget _listaEspera() {
    final leads = _leads.where((l) => l['tipo'] == 'estafeta').toList();
    return Column(
      children: [
        // 02/09 (noite): abrir vaga = o bot avisa a lista de espera pela ordem de chegada (cron do cérebro, 5 em 5 min)
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(child: Text('${leads.length} na lista de espera de estafetas', style: const TextStyle(fontWeight: FontWeight.w600))),
              FilledButton.icon(
                onPressed: leads.isEmpty ? null : _abrirVaga,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Abrir vaga (avisar lista)'),
              ),
            ],
          ),
        ),
        Expanded(
          child: leads.isEmpty
              ? const Center(child: Text('Ninguém na lista de espera de estafetas.'))
              : ListView.builder(
                  itemCount: leads.length,
                  itemBuilder: (_, i) => _leadTile(leads[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _abrirVaga() async {
    final ctrl = TextEditingController(
      text: 'Olá! Abriu uma vaga de estafeta no Bora e você está na nossa lista de espera. Ainda tem interesse? Responda por aqui e eu passo ao Danilo.',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir vaga de estafeta?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('O bot avisa a lista de espera pela ordem de chegada (5 por ciclo de 5 min) e fecha a vaga sozinho quando acabar.'),
            const SizedBox(height: 10),
            TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Mensagem (PT-PT)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir vaga')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('whatsapp_settings').upsert({
        'key': 'vaga_estafeta',
        'value': {'aberta': true, 'texto': ctrl.text.trim(), 'max': 5, 'aberta_em': DateTime.now().toUtc().toIso8601String()},
      });
      _aviso('Vaga aberta: o bot começa a avisar a lista no próximo ciclo.');
    } catch (e) {
      _aviso('Erro: $e');
    }
  }

  Widget _leadTile(Map<String, dynamic> l) {
    final dados = (l['dados'] as Map?)?.entries.map((e) => '${e.key}: ${e.value}').join(' · ') ?? '';
    return ListTile(
      leading: Icon(l['tipo'] == 'estafeta' ? Icons.two_wheeler : Icons.storefront, color: AppColors.primary),
      title: Text('${l['tipo']} · +${l['numero']}'),
      subtitle: Text('${l['estado']} · ${(l['created_at'] ?? '').toString().split('T').first}\n$dados'),
      isThreeLine: true,
      trailing: DropdownButton<String>(
        value: l['estado'],
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'novo', child: Text('novo')),
          DropdownMenuItem(value: 'em_recolha', child: Text('em recolha')),
          DropdownMenuItem(value: 'minimo_recolhido', child: Text('mínimo recolhido')),
          DropdownMenuItem(value: 'montado', child: Text('montado')),
          DropdownMenuItem(value: 'fechado', child: Text('fechado')),
          DropdownMenuItem(value: 'perdido', child: Text('perdido')),
        ],
        onChanged: (v) => v == null ? null : _mudarEstadoLead(l, v),
      ),
    );
  }

  Widget _ferramentasTab() {
    if (_ferramentas.isEmpty) return const Center(child: Text('Nenhuma ferramenta chamada ainda.'));
    return ListView.builder(
      itemCount: _ferramentas.length,
      itemBuilder: (_, i) {
        final f = _ferramentas[i];
        final nomes = (f['ferramentas'] as List?)?.map((x) => (x as Map)['nome']).join(', ') ?? '';
        return ListTile(
          dense: true,
          leading: const Icon(Icons.build_outlined, size: 18),
          title: Text('+${_mask((f['numero'] ?? '').toString())} · ${f['modelo'] ?? '—'} · ${f['latencia_ms'] ?? 0} ms'),
          subtitle: Text('$nomes\n${(f['texto'] ?? '').toString()}', maxLines: 3, overflow: TextOverflow.ellipsis),
          isThreeLine: true,
        );
      },
    );
  }
}

class _ConversaScreen extends StatefulWidget {
  const _ConversaScreen({required this.contato});
  final Map<String, dynamic> contato;

  @override
  State<_ConversaScreen> createState() => _ConversaScreenState();
}

class _ConversaScreenState extends State<_ConversaScreen> {
  late final Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('whatsapp_messages')
        .select('id, direcao, tipo, texto, transcricao, modelo, decisao, enviada, entrega_estado, entrega_tentativas, entrega_erro, latencia_ms, created_at, porta')
        .eq('numero', widget.contato['numero'])
        .order('created_at', ascending: true)
        .limit(300);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contato;
    final titulo = c['nome']?.toString().isNotEmpty == true ? c['nome'].toString() : '+${c['numero']}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Conversa · $titulo',
        actions: [
          IconButton(
            tooltip: 'Exportar CSV desta conversa',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final rows = await _future;
              final b = StringBuffer('quando;direcao;tipo;texto;decisao;enviada');
              for (final r in rows) {
                b.write('\n"${r['created_at']}";"${r['direcao']}";"${r['tipo']}";"${(r['texto'] ?? r['transcricao'] ?? '').toString().replaceAll('"', '""')}";"${r['decisao'] ?? ''}";"${r['enviada']}"');
              }
              await Clipboard.setData(ClipboardData(text: b.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copiado.')));
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: AppColors.error)));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const Center(child: Text('Sem mensagens registradas.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final saida = r['direcao'] == 'saida';
              final texto = (r['texto'] ?? r['transcricao'] ?? '').toString();
              // "entregue" = visto REAL lido pela extensão na conversa (falha F, 02/09): nunca "mandei para a extensão"
              final entrega = r['enviada'] == true
                  ? 'entregue (${r['entrega_estado'] ?? 'visto'})'
                  : (r['entrega_estado'] == 'falhou'
                      ? 'FALHOU a entrega${r['entrega_erro'] != null ? ' · ${r['entrega_erro']}' : ''}'
                      : 'NÃO entregue');
              final meta = '${(r['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}'
                  '${saida ? ' · modelo: ${r['modelo'] ?? 'bot'} · ${r['latencia_ms'] ?? 0} ms · $entrega' : ' · ${r['tipo']}'}';
              return Align(
                alignment: saida ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: saida ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(texto),
                      const SizedBox(height: 4),
                      Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
