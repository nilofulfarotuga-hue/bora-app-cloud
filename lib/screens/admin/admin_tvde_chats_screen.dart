// Chat das corridas TVDE (ronda 04/10/2026, agente admin-geral).
// A tabela `tvde_messages` (conversa cliente ↔ motorista) não tinha ecrã no
// painel. Aqui: lista das corridas com conversa (última mensagem primeiro) e,
// ao tocar, a conversa toda em hora de Lisboa. Só leitura.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminTvdeChatsScreen extends StatefulWidget {
  const AdminTvdeChatsScreen({super.key});

  @override
  State<AdminTvdeChatsScreen> createState() => _AdminTvdeChatsScreenState();
}

class _AdminTvdeChatsScreenState extends State<AdminTvdeChatsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

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
      final res = await Supabase.instance.client
          .rpc('admin_tvde_chats_list', params: {'p_limit': 200});
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminTvdeChats] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar as conversas.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Chat das corridas TVDE',
        actions: [
          AdminCsvButton(
            nome: 'tvde_conversas',
            colunas: const [
              ('ultima_em', 'última mensagem (Lisboa)'),
              ('corrida_em', 'corrida (Lisboa)'),
              ('ride_id', 'corrida'),
              ('status', 'estado'),
              ('cliente', 'cliente'),
              ('motorista', 'motorista'),
              ('mensagens', 'mensagens'),
              ('ultima', 'última'),
            ],
            linhas: () => _rows,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? const Center(child: Text('Nenhuma corrida com conversa.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: Text('${r['mensagens'] ?? 0}',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text(
                                '${r['cliente'] ?? 'Cliente'} ↔ ${r['motorista'] ?? 'sem motorista'}'),
                            subtitle: Text(
                              '${dataHoraLisboa(r['ultima_em'])} · ${r['status'] ?? ''}\n${r['ultima'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ConversaTvde(linha: r),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ConversaTvde extends StatefulWidget {
  const _ConversaTvde({required this.linha});
  final Map<String, dynamic> linha;

  @override
  State<_ConversaTvde> createState() => _ConversaTvdeState();
}

class _ConversaTvdeState extends State<_ConversaTvde> {
  late final Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_tvde_chat_mensagens',
        params: {'p_ride_id': widget.linha['ride_id']});
    return ((res as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linha;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
          title: '${l['cliente'] ?? 'Cliente'} ↔ ${l['motorista'] ?? '—'}'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(
                child: Text('Não consegui carregar a conversa.'));
          }
          final msgs = snap.data ?? const [];
          if (msgs.isEmpty) {
            return const Center(child: Text('Sem mensagens.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              final doCliente = m['sender_role'] == 'client';
              return Align(
                alignment:
                    doCliente ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: doCliente
                        ? AppColors.card
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${doCliente ? 'Cliente' : 'Motorista'} · ${dataHoraLisboa(m['created_at'])}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      SelectableText('${m['message'] ?? ''}'),
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
