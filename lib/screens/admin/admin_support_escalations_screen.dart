// Suporte — pedidos para falar com o Danilo (ronda 04/10/2026, admin-geral).
// O aviso "Cliente precisa de ti — suporte" (support-human-chat →
// notify-admin-urgent) apontava para /admin/support-escalations, rota que não
// existia ("Página não encontrada"). Aqui: lista (pendentes primeiro), conversa
// do assistente com a pessoa e "Responder" — a resposta entra na conversa do
// suporte e no sininho da pessoa (admin_support_escalation_responder, auditado).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminSupportEscalationsScreen extends StatefulWidget {
  const AdminSupportEscalationsScreen({super.key});

  @override
  State<AdminSupportEscalationsScreen> createState() =>
      _AdminSupportEscalationsScreenState();
}

class _AdminSupportEscalationsScreenState
    extends State<AdminSupportEscalationsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _status = 'pending'; // null = todos

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
          'admin_support_escalations_list',
          params: {'p_status': _status, 'p_limit': 300});
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminSupportEscalations] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar os pedidos de suporte.';
        _loading = false;
      });
    }
  }

  Future<void> _abrir(Map<String, dynamic> r) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EscalamentoDetalhe(linha: r)),
    );
    if (mudou == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Suporte — falar com o Danilo',
        actions: [
          AdminCsvButton(
            nome: 'suporte_escalamentos',
            colunas: const [
              ('created_at', 'pedido (Lisboa)'),
              ('status', 'estado'),
              ('nome', 'nome'),
              ('email', 'email'),
              ('user_role', 'papel'),
              ('question', 'pergunta'),
              ('danilo_reply', 'resposta'),
              ('answered_at', 'respondido (Lisboa)'),
            ],
            linhas: () => _rows,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(spacing: 6, children: [
            for (final o in const [
              ('pending', 'Por responder'),
              ('answered', 'Respondidos'),
              (null, 'Todos'),
            ])
              ChoiceChip(
                label: Text(o.$2),
                selected: _status == o.$1,
                onSelected: (_) {
                  setState(() => _status = o.$1);
                  _load();
                },
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _rows.isEmpty
                      ? const Center(child: Text('Nada por aqui.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: AppColors.divider),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final pendente = r['status'] == 'pending';
                              return ListTile(
                                leading: Icon(
                                  pendente
                                      ? Icons.mark_chat_unread
                                      : Icons.mark_chat_read,
                                  color: pendente
                                      ? AppColors.warning
                                      : AppColors.success,
                                ),
                                title: Text('${r['nome'] ?? 'Sem nome'}'),
                                subtitle: Text(
                                  '${dataHoraLisboa(r['created_at'])} · ${r['question'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _abrir(r),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _EscalamentoDetalhe extends StatefulWidget {
  const _EscalamentoDetalhe({required this.linha});
  final Map<String, dynamic> linha;

  @override
  State<_EscalamentoDetalhe> createState() => _EscalamentoDetalheState();
}

class _EscalamentoDetalheState extends State<_EscalamentoDetalhe> {
  late final Future<List<Map<String, dynamic>>> _conversa = _loadConversa();
  final _resposta = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _resposta.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadConversa() async {
    final res = await Supabase.instance.client.rpc(
        'admin_support_escalation_conversa',
        params: {'p_id': widget.linha['id']});
    return ((res as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _responder() async {
    if (_enviando) return;
    final txt = _resposta.text.trim();
    if (txt.length < 2) return;
    setState(() => _enviando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client.rpc(
          'admin_support_escalation_responder',
          params: {'p_id': widget.linha['id'], 'p_resposta': txt});
      if (!mounted) return;
      final m = (res is Map) ? res : const {};
      if (m['ok'] == true) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Resposta enviada (conversa + sininho).')));
        Navigator.of(context).pop(true);
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text(m['erro']?.toString() ?? 'Não consegui enviar.')));
      }
    } catch (e) {
      debugPrint('[AdminSupportEscalations] responder: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui enviar a resposta.')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linha;
    final respondido = l['status'] == 'answered';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: '${l['nome'] ?? 'Suporte'}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${l['email'] ?? ''}  ${l['phone'] ?? ''}',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Pediu em ${dataHoraLisboa(l['created_at'])} (Lisboa):',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SelectableText('${l['question'] ?? ''}'),
          if (respondido) ...[
            const SizedBox(height: 12),
            Text('Respondido em ${dataHoraLisboa(l['answered_at'])}:',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            SelectableText('${l['danilo_reply'] ?? ''}'),
          ],
          const Divider(height: 32),
          const Text('Conversa com o assistente',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _conversa,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final msgs = snap.data ?? const [];
              if (msgs.isEmpty) return const Text('Sem mensagens.');
              return Column(children: [
                for (final m in msgs)
                  Align(
                    alignment: m['role'] == 'user'
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: BoxDecoration(
                        color: m['role'] == 'user'
                            ? AppColors.card
                            : AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${m['content'] ?? ''}'),
                    ),
                  ),
              ]);
            },
          ),
          const Divider(height: 32),
          TextField(
            controller: _resposta,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: respondido ? 'Responder de novo' : 'Sua resposta',
              helperText:
                  'Vai para a conversa do suporte e para o sininho da pessoa.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _enviando ? null : _responder,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Enviar resposta'),
          ),
        ],
      ),
    );
  }
}
