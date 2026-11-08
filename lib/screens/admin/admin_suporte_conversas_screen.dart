// Suporte — conversas do chat da app (adendo 1 da missão m4, pedido do Danilo 08/11/2026).
//
// O aviso "CLIENTE ESCREVEU AO SUPORTE" abria /admin/support-escalations, que só mostra sessões
// escaladas: o Danilo tocou num aviso real e não viu o que o cliente escreveu. Agora:
//   • /admin/support/conversas — TODAS as conversas, as mais recentes primeiro, com marca de não lida;
//   • /admin/support/sessions/<id> — a conversa (cliente e robô; ferramentas recolhidas), nome,
//     telefone (ligar e WhatsApp), email, últimos pedidos, ao vivo (Realtime), e caixa para
//     responder como "Equipa Bora". Ao responder, o robô fica calado nessa conversa até
//     "Devolver ao robô". Ao cliente nunca aparece o nome de quem responde.
// RPCs: admin_suporte_sessoes / admin_suporte_conversa / admin_suporte_responder /
// admin_suporte_devolver (migração 20261108220000, só admin). Textos em PT-BR (painel).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Rota da conversa (o aviso e o push levam este link).
String rotaConversaSuporte(String sessionId) => '/admin/support/sessions/$sessionId';

/// Prefixo reconhecido pelo `onGenerateRoute` do main.dart.
const String kPrefixoConversaSuporte = '/admin/support/sessions/';

/// Id da sessão num link `/admin/support/sessions/<id>` (ou null).
String? sessaoDoLink(String? link) {
  if (link == null || !link.startsWith(kPrefixoConversaSuporte)) return null;
  final id = Uri.decodeComponent(
      link.substring(kPrefixoConversaSuporte.length).split(RegExp(r'[?#/]')).first);
  return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null;
}

/// "937501673" / "+351 937 501 673" → número para wa.me (com 351).
String? numeroWhatsApp(String? telefone) {
  final d = (telefone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.length == 9) return '351$d';
  return d;
}

class AdminSuporteConversasScreen extends StatefulWidget {
  const AdminSuporteConversasScreen({super.key});

  @override
  State<AdminSuporteConversasScreen> createState() =>
      _AdminSuporteConversasScreenState();
}

class _AdminSuporteConversasScreenState
    extends State<AdminSuporteConversasScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _erro;
  bool _soNaoLidas = false;
  RealtimeChannel? _canal;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    // Mensagem nova em qualquer conversa → recarrega a lista (com folga de 1 s).
    _canal = _c.channel('admin_suporte_lista')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'support_chatbot_messages',
        callback: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 1), _load);
        },
      )
      ..subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _canal?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _rows.isEmpty;
      _erro = null;
    });
    try {
      final res = await _c.rpc('admin_suporte_sessoes',
          params: {'p_limite': 200, 'p_so_nao_lidas': _soNaoLidas});
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminSuporteConversas] $e');
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui carregar as conversas do suporte.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final naoLidas = _rows.where((r) => r['nao_lida'] == true).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Conversas do suporte',
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                FilterChip(
                  label: Text(naoLidas > 0 && !_soNaoLidas
                      ? 'Só não lidas ($naoLidas)'
                      : 'Só não lidas'),
                  selected: _soNaoLidas,
                  onSelected: (v) {
                    setState(() => _soNaoLidas = v);
                    _load();
                  },
                ),
                const Spacer(),
                Text('${_rows.length} conversas',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(child: _corpo()),
        ],
      ),
    );
  }

  Widget _corpo() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro!),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
        ]),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('Nenhuma conversa por aqui.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final naoLida = r['nao_lida'] == true;
          final nome = (r['nome'] ?? '').toString().trim();
          final tel = (r['telefone'] ?? '').toString().trim();
          final papelUltima = (r['ultima_msg_papel'] ?? '').toString();
          final prefixo = switch (papelUltima) {
            'user' => 'Cliente: ',
            'admin' => 'Equipa: ',
            'assistant' => 'Robô: ',
            _ => '',
          };
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  naoLida ? AppColors.accent : AppColors.primaryWash,
              foregroundColor: naoLida ? Colors.white : AppColors.primaryDark,
              child: Icon(r['modo'] == 'admin'
                  ? Icons.support_agent
                  : Icons.smart_toy_outlined),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    nome.isEmpty ? 'Cliente sem nome' : nome,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            naoLida ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
                if (r['escalada'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text('Escalada', style: TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${tel.isEmpty ? '' : '$tel · '}${dataHoraLisboa(r['ultima_msg_em'])}\n'
              '$prefixo${(r['ultima_msg'] ?? '').toString()}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: naoLida
                ? const Icon(Icons.circle, size: 12, color: AppColors.accent)
                : null,
            onTap: () async {
              await Navigator.of(context).pushNamed(
                  rotaConversaSuporte(r['session_id'].toString()));
              _load();
            },
          );
        },
      ),
    );
  }
}

class AdminSuporteConversaScreen extends StatefulWidget {
  const AdminSuporteConversaScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<AdminSuporteConversaScreen> createState() =>
      _AdminSuporteConversaScreenState();
}

class _AdminSuporteConversaScreenState
    extends State<AdminSuporteConversaScreen> {
  final _c = Supabase.instance.client;
  final _resposta = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _dados;
  bool _loading = true;
  bool _aEnviar = false;
  String? _erro;
  bool _verFerramentas = false;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _load();
    _canal = _c.channel('admin_suporte_${widget.sessionId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'support_chatbot_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: widget.sessionId,
        ),
        callback: (_) => _load(),
      )
      ..subscribe();
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    _resposta.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _c.rpc('admin_suporte_conversa',
          params: {'p_session_id': widget.sessionId});
      if (!mounted) return;
      final m = res is Map ? Map<String, dynamic>.from(res) : null;
      setState(() {
        _dados = m;
        _erro = (m == null || m['ok'] != true)
            ? (m?['erro']?.toString() ?? 'Não consegui abrir a conversa.')
            : null;
        _loading = false;
      });
      _irAoFim();
    } catch (e) {
      debugPrint('[AdminSuporteConversa] $e');
      if (!mounted) return;
      setState(() {
        _erro = 'Não consegui abrir a conversa.';
        _loading = false;
      });
    }
  }

  void _irAoFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _enviar() async {
    final t = _resposta.text.trim();
    if (t.isEmpty || _aEnviar) return;
    setState(() => _aEnviar = true);
    try {
      final r = await _c.rpc('admin_suporte_responder',
          params: {'p_session_id': widget.sessionId, 'p_texto': t});
      final ok = r is Map && r['ok'] == true;
      if (!mounted) return;
      if (ok) {
        _resposta.clear();
        await _load();
      } else {
        _aviso('Não enviei: ${r is Map ? r['erro'] : 'erro'}');
      }
    } catch (e) {
      if (mounted) _aviso('Erro ao enviar: $e');
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  Future<void> _devolver() async {
    try {
      await _c.rpc('admin_suporte_devolver',
          params: {'p_session_id': widget.sessionId});
      if (!mounted) return;
      _aviso('Conversa devolvida ao robô.');
      await _load();
    } catch (e) {
      if (mounted) _aviso('Erro: $e');
    }
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _aviso('Não consegui abrir $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = _dados?['cliente'] is Map
        ? Map<String, dynamic>.from(_dados!['cliente'] as Map)
        : const <String, dynamic>{};
    final sessao = _dados?['sessao'] is Map
        ? Map<String, dynamic>.from(_dados!['sessao'] as Map)
        : const <String, dynamic>{};
    final nome = (cliente['nome'] ?? '').toString().trim();
    final modoAdmin = sessao['modo'] == 'admin';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: nome.isEmpty ? 'Conversa do suporte' : nome,
        actions: [
          IconButton(
            tooltip: _verFerramentas
                ? 'Esconder ferramentas do robô'
                : 'Mostrar ferramentas do robô',
            icon: Icon(_verFerramentas ? Icons.build_circle : Icons.build_outlined),
            onPressed: () => setState(() => _verFerramentas = !_verFerramentas),
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : Column(
                  children: [
                    _Cabecalho(
                      cliente: cliente,
                      sessao: sessao,
                      pedidos: (_dados?['pedidos'] as List?) ?? const [],
                      onUrl: _abrirUrl,
                    ),
                    if (modoAdmin)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFFFF7ED),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.pan_tool_alt_outlined,
                                size: 18, color: AppColors.accentDark),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                  'Você assumiu esta conversa: o robô está calado.',
                                  style: TextStyle(fontSize: 13)),
                            ),
                            TextButton(
                              onPressed: _devolver,
                              child: const Text('Devolver ao robô'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: _mensagens()),
                    _Caixa(
                      controller: _resposta,
                      aEnviar: _aEnviar,
                      onEnviar: _enviar,
                    ),
                  ],
                ),
    );
  }

  Widget _mensagens() {
    final lista = ((_dados?['mensagens'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final visiveis = <Map<String, dynamic>>[];
    var ferramentasSeguidas = 0;
    for (final m in lista) {
      if (m['papel'] == 'tool') {
        if (_verFerramentas) {
          visiveis.add(m);
        } else {
          ferramentasSeguidas++;
        }
        continue;
      }
      if (ferramentasSeguidas > 0) {
        visiveis.add({'papel': '_ferramentas', 'n': ferramentasSeguidas});
        ferramentasSeguidas = 0;
      }
      visiveis.add(m);
    }
    if (visiveis.isEmpty) {
      return const Center(child: Text('Sem mensagens.'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: visiveis.length,
      itemBuilder: (_, i) => _Bolha(m: visiveis[i]),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.cliente,
    required this.sessao,
    required this.pedidos,
    required this.onUrl,
  });

  final Map<String, dynamic> cliente;
  final Map<String, dynamic> sessao;
  final List pedidos;
  final void Function(String url) onUrl;

  @override
  Widget build(BuildContext context) {
    final tel = (cliente['telefone'] ?? '').toString().trim();
    final email = (cliente['email'] ?? '').toString().trim();
    final wa = numeroWhatsApp(tel);
    return Material(
      color: AppColors.surface,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (tel.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.call, size: 16),
                label: Text(tel),
                onPressed: () => onUrl('tel:$tel'),
              ),
            if (wa != null)
              ActionChip(
                avatar: const Icon(Icons.chat, size: 16),
                label: const Text('WhatsApp'),
                onPressed: () => onUrl('https://wa.me/$wa'),
              ),
            if (email.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.mail_outline, size: 16),
                label: Text(email, overflow: TextOverflow.ellipsis),
                onPressed: () => onUrl('mailto:$email'),
              ),
          ],
        ),
        subtitle: Text(
          'Início ${dataHoraLisboa(sessao['iniciada_em'])}'
          '${sessao['escalada'] == true ? ' · escalada (${sessao['motivo'] ?? '-'})' : ''}'
          ' · ${pedidos.length} pedidos recentes',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          for (final p in pedidos.whereType<Map>().take(10))
            ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long_outlined, size: 20),
              title: Text('${p['loja'] ?? '-'} · ${p['status'] ?? '-'}'),
              subtitle: Text(
                  '${dataHoraLisboa(p['quando'])} · ${p['tipo'] ?? ''} · '
                  '${p['total'] == null ? '-' : '${p['total']} €'}'),
              onTap: () => Navigator.of(context)
                  .pushNamed('/admin/orders/${p['id']}'),
            ),
        ],
      ),
    );
  }
}

class _Bolha extends StatelessWidget {
  const _Bolha({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final papel = (m['papel'] ?? '').toString();
    if (papel == '_ferramentas') {
      final n = m['n'] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text('· o robô consultou $n ferramenta${n == 1 ? '' : 's'} ·',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ),
      );
    }
    if (papel == 'tool') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('🔧 ${m['ferramenta'] ?? 'ferramenta'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      );
    }
    final doCliente = papel == 'user';
    final daEquipa = papel == 'admin';
    final cor = doCliente
        ? AppColors.surface
        : daEquipa
            ? const Color(0xFFFFF7ED)
            : AppColors.primaryWash;
    final quem = doCliente
        ? 'Cliente'
        : daEquipa
            ? 'Equipa Bora (você)'
            : 'Robô';
    return Align(
      alignment: doCliente ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$quem · ${dataHoraLisboa(m['quando'])}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            SelectableText((m['texto'] ?? '').toString(),
                style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({
    required this.controller,
    required this.aEnviar,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final bool aEnviar;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        color: AppColors.surface,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Responder como Equipa Bora (o cliente vê na app)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Enviar ao cliente',
              onPressed: aEnviar ? null : onEnviar,
              icon: aEnviar
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
