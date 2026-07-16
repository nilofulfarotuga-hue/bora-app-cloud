import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// 🤖 Robot B v4 — inbox de sugestões do "Motor de Perfeição Contínua".
/// Tab 1: sugestões por nível (🟢 N1 auto / 🟡 N2 1-clique / 🔴 N3 proposta)
///   com Aprovar e aplicar (payload via RPC robot_apply_suggestion),
///   Rejeitar (motivo obrigatório — ensina o robô) e Marcar feita (nível 3).
/// Tab 2: histórico de auto-execuções (robot_audit_log).
/// Kill switches robot_b_* editam-se em Configurações da Plataforma.
class AdminRobotSuggestionsScreen extends StatefulWidget {
  const AdminRobotSuggestionsScreen({super.key});
  @override
  State<AdminRobotSuggestionsScreen> createState() => _S();
}

class _S extends State<AdminRobotSuggestionsScreen> {
  String? _statusFilter = 'nova';
  int? _nivelFilter;
  List<Map<String, dynamic>> _rows = const [];
  List<Map<String, dynamic>> _audit = const [];
  Map<String, dynamic> _metrics = const {};
  Map<String, dynamic> _autonomy = const {};
  List<Map<String, dynamic>> _backlog = const [];
  bool _loading = true;
  String? _error;

  // Córtex 🔴 — propostas zona-vermelha (cortex-mcp), fila SEPARADA de robot_suggestions,
  // sem ligação nenhuma ao loop automático. Só revisão humana; nunca executa nada.
  String? _cortexStatusFilter = 'nova';
  List<Map<String, dynamic>> _cortexProposals = const [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sugs = await Supabase.instance.client.rpc('admin_list_robot_suggestions', params: {
        'p_status': _statusFilter,
        'p_nivel': _nivelFilter,
        'p_limit': 200, 'p_offset': 0,
      });
      final audit = await Supabase.instance.client.rpc('admin_list_robot_audit', params: {
        'p_limit': 200, 'p_offset': 0,
      });
      final metrics = await Supabase.instance.client.rpc('admin_robot_metrics');
      final autonomy = await Supabase.instance.client.rpc('admin_autonomy_dashboard');
      // Backlog do loop autónomo — para a "Prova da auto-cura" (nota/olhos/histórico).
      final backlog = await Supabase.instance.client.rpc('admin_list_autonomy_backlog', params: {
        'p_goal_slug': 'paridade-admin-360',
        'p_limit': 200, 'p_offset': 0,
      });
      final cortex = await Supabase.instance.client.rpc('cortex_list_red_proposals', params: {
        'p_status': _cortexStatusFilter,
        'p_limit': 200, 'p_offset': 0,
      });
      if (mounted) {
        setState(() {
          _rows = ((sugs as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
          _audit = ((audit as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
          _metrics = ((metrics as Map?) ?? {}).cast<String, dynamic>();
          _autonomy = ((autonomy as Map?) ?? {}).cast<String, dynamic>();
          _backlog = ((backlog as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
          _cortexProposals =
              ((cortex as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Tipos que a RPC robot_apply_suggestion sabe EXECUTAR (whitelist fechada
  // no SQL). Payload sem um destes tipos é evidência — vai por
  // robot_mark_suggestion_done, nunca por _apply.
  static const _executablePayloadTypes = {
    'update_setting',
    'hide_store',
    'disable_products',
    'flag_products_review',
  };

  /// Traduz erros de RPC (PostgrestException cru) para PT-BR amigável.
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('payload_type_fora_da_whitelist') ||
        msg.contains('sugestao_sem_payload_execucao')) {
      return 'Esta sugestão não tem ação executável — usa "Marcar como feita".';
    }
    if (msg.contains('nivel_3_nao_executavel')) {
      return 'Planos (nível 3) não se executam daqui — aprova o plano e implementa fora.';
    }
    if (msg.contains('sugestao_nao_esta_aberta') ||
        msg.contains('sugestao_nao_encontrada_ou_fechada')) {
      return 'Esta sugestão já foi tratada (aplicada, rejeitada ou expirada).';
    }
    if (msg.contains('sugestao_nao_encontrada')) {
      return 'Sugestão não encontrada — atualiza a lista.';
    }
    if (msg.contains('setting_fora_da_whitelist_robot')) {
      return 'Esta configuração é protegida — altera em Configurações da Plataforma.';
    }
    if (msg.contains('motivo_rejeicao_obrigatorio')) {
      return 'Motivo obrigatório (mín. 3 caracteres).';
    }
    if (msg.contains('proposta_nao_encontrada_ou_ja_decidida')) {
      return 'Esta proposta já foi decidida ou não existe mais — atualiza a lista.';
    }
    if (msg.contains('proposta_nao_encontrada')) {
      return 'Proposta não encontrada — atualiza a lista.';
    }
    if (msg.contains('ordem_ja_despachada_em')) {
      return 'Já foi criada uma ordem para esta proposta — reverter aqui não a cancela.';
    }
    return 'Não foi possível concluir. Detalhe técnico: $msg';
  }

  Future<void> _apply(Map<String, dynamic> s) async {
    final payload = s['payload_execucao'] as Map?;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar e aplicar'),
        content: Text(
            'Executar agora o payload "${payload?['type']}" desta sugestão?\n\n'
            'A ação é registrada em auditoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await Supabase.instance.client
          .rpc('robot_apply_suggestion', params: {'p_suggestion_id': s['id']});
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.settings.name != '_robotDetail');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Aplicado: ${(res as Map?)?['rows_affected'] ?? '?'} registro(s) afetado(s)')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> s) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar sugestão'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Motivo (obrigatório)',
            helperText: 'O robô aprende: este tipo não volta a ser sugerido.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.trim().length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Motivo obrigatório (mín. 3 caracteres)')));
      }
      return;
    }
    try {
      await Supabase.instance.client.rpc('robot_reject_suggestion',
          params: {'p_suggestion_id': s['id'], 'p_motivo': ctrl.text.trim()});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  Future<void> _markDone(Map<String, dynamic> s) async {
    try {
      await Supabase.instance.client
          .rpc('robot_mark_suggestion_done', params: {'p_suggestion_id': s['id']});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  /// Nível 3 (plano): aprovar = aceitar o plano (status 'aprovada'), SEM
  /// executar nada. A implementação acontece fora (Claude Code) e depois
  /// marca-se como feita.
  Future<void> _approvePlan(Map<String, dynamic> s) async {
    try {
      await Supabase.instance.client
          .rpc('robot_approve_plan', params: {'p_suggestion_id': s['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Plano aprovado — implementação segue fora do app.')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  // ── Córtex 🔴 — marcar revisão (nunca executa nada) ──────────────────────────
  Future<void> _markCortexStatus(String pid, String status, {String? nota}) async {
    try {
      await Supabase.instance.client.rpc('cortex_proposal_mark_status', params: {
        'p_pid': pid, 'p_status': status, 'p_nota': nota,
      });
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  // Aprovação real: exige a tua sessão autenticada com app_metadata.role='admin' — a RPC
  // recusa qualquer chamada sem esse JWT. Só marca (quem/quando/audit id); a ordem entra na
  // fila separadamente (sync da VPS) e passa pela zona_vermelha() própria do carteiro — texto
  // de dinheiro volta a exigir "vai <id>" no Telegram mesmo depois de aprovado aqui.
  Future<void> _confirmCortexApprove(String pid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar e enviar para a fila'),
        content: const Text(
            'Esta proposta vai ser marcada como aprovada por ti e entra na fila normal de '
            'orquestração (próxima sincronização, até 10 min). Se o texto ainda tocar em '
            'dinheiro/tokens, o carteiro volta a pedir a tua confirmação no Telegram — isto '
            'não contorna essa barreira.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await Supabase.instance.client
          .rpc('cortex_proposal_approve', params: {'p_pid': pid});
      if (mounted) {
        final auditId = (res is Map) ? res['audit_id'] : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Aprovada — audit id ${auditId ?? '?'}. Entra na fila em até 10 min.')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  Future<void> _confirmCortexDecidido(String pid) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como decidida fora'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Nota (opcional)',
            helperText: 'Ex.: já resolvido noutro fluxo, duplicado, não aplicável.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) {
      await _markCortexStatus(pid, 'decidida_fora', nota: ctrl.text.trim());
    }
  }

  // ── controlo da autonomia (kill switch + dial) — Fase 5 ──────────────────────
  Future<void> _setSwitch(String key, bool enabled) async {
    try {
      await Supabase.instance.client.rpc('admin_autonomy_set_switch',
          params: {'p_key': key, 'p_enabled': enabled});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _confirmKill(bool parar) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(parar ? 'PARAR TUDO?' : 'Retomar o loop?'),
        content: Text(parar
            ? 'Suspende o loop autónomo já. Nenhum item novo é pego até retomares.'
            : 'O loop volta a poder pegar itens (respeitando o dial e o Juiz).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: parar ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(parar ? 'PARAR TUDO' : 'Retomar'),
          ),
        ],
      ),
    );
    if (ok == true) await _setSwitch('robot_b_enabled', !parar);
  }

  // ── helpers visuais ─────────────────────────────────────────────────────────

  Color _nivelColor(int n) => n == 1
      ? AppColors.primary
      : n == 2
          ? const Color(0xFFFF8F00)
          : AppColors.error;

  String _nivelLabel(int n) =>
      n == 1 ? 'N1 AUTO' : n == 2 ? 'N2 1-CLIQUE' : 'N3 PROPOSTA';

  Widget _statusChip(String status) {
    final (color, label) = switch (status) {
      'nova' => (Colors.blueGrey, 'NOVA'),
      'aprovada' => (AppColors.primary, 'APROVADA'),
      'aplicada' => (AppColors.primary, 'APLICADA'),
      'rejeitada' => (AppColors.error, 'REJEITADA'),
      _ => (Colors.grey, 'EXPIRADA'),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _cortexStatusChip(String status) {
    final (color, label) = switch (status) {
      'nova' => (AppColors.error, 'NOVA'),
      'vista' => (const Color(0xFFFF8F00), 'VISTA'),
      'aprovada_danilo' => (AppColors.primary, 'APROVADA — NA FILA'),
      _ => (Colors.grey, 'DECIDIDA FORA'),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  String _fmtDate(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _pretty(dynamic v) {
    if (v == null) return '—';
    try { return const JsonEncoder.withIndent('  ').convert(v); } catch (_) { return v.toString(); }
  }

  // ── detalhe ─────────────────────────────────────────────────────────────────

  void _showDetail(Map<String, dynamic> s) {
    final nivel = (s['nivel'] as num?)?.toInt() ?? 3;
    final status = s['status']?.toString() ?? 'nova';
    final payload = s['payload_execucao'];
    final actionable = status == 'nova' || status == 'aprovada';
    // Só payloads da whitelist executável vão para robot_apply_suggestion;
    // payload de evidência (sem 'type' executável) fecha-se com "feita".
    final payloadType = (payload is Map) ? payload['type']?.toString() : null;
    final executable = nivel <= 2 &&
        payloadType != null &&
        _executablePayloadTypes.contains(payloadType);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      routeSettings: const RouteSettings(name: '_robotDetail'),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scroll,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _nivelColor(nivel),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_nivelLabel(nivel),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                _statusChip(status),
                const Spacer(),
                Text('sev ${s['severidade'] ?? '-'} / 5',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 10),
              Text(s['titulo']?.toString() ?? '',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${s['categoria']} · criada ${_fmtDate(s['created_at'])} · expira ${_fmtDate(s['expires_at'])}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Divider(height: 22),
              Text(s['proposta']?.toString() ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
              const SizedBox(height: 12),
              Text('📊 Benchmark: ${s['benchmark'] ?? '—'}',
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              const Text('Evidência', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_pretty(s['evidencia']),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
              if (payload != null) ...[
                const SizedBox(height: 12),
                const Text('Payload de execução', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_pretty(payload),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
              if (s['motivo_rejeicao'] != null) ...[
                const SizedBox(height: 12),
                Text('Motivo: ${s['motivo_rejeicao']}',
                    style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              if (actionable) ...[
                if (executable)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Aprovar e aplicar'),
                    onPressed: () { Navigator.pop(ctx); _apply(s); },
                  ),
                if (nivel == 3 && status == 'nova') ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                    label: const Text('Aprovar plano (sem executar)'),
                    onPressed: () { Navigator.pop(ctx); _approvePlan(s); },
                  ),
                  const SizedBox(height: 8),
                ],
                if (!executable)
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Marcar como feita'),
                    onPressed: () { Navigator.pop(ctx); _markDone(s); },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.close, color: AppColors.error),
                  label: const Text('Rejeitar (com motivo)',
                      style: TextStyle(color: AppColors.error)),
                  onPressed: () { Navigator.pop(ctx); _reject(s); },
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showAuditDetail(Map<String, dynamic> a) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a['operation']?.toString() ?? ''),
        content: SingleChildScrollView(
          child: Text('Params:\n${_pretty(a['params'])}\n\nResultado:\n${_pretty(a['result'])}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  void _showCortexDetail(Map<String, dynamic> p) {
    final status = p['status']?.toString() ?? 'nova';
    final pid = p['pid']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scroll,
            children: [
              Row(children: [
                _cortexStatusChip(status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(pid,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12,
                          color: AppColors.textSecondary)),
                ),
              ]),
              const SizedBox(height: 8),
              Text('${p['ordem_id'] ?? '—'} · criada ${_fmtDate(p['criada_em'])} · ${p['who'] ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Divider(height: 22),
              const Text('Tarefa completa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(p['tarefa']?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
              if (p['nota_revisao'] != null && (p['nota_revisao'] as String).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Nota: ${p['nota_revisao']}', style: const TextStyle(fontSize: 13)),
                Text('por ${p['revisada_por_email'] ?? '—'} em ${_fmtDate(p['revisada_em'])}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),
              const Text('Marcar vista/decidida fora nunca executa nada. "Aprovar e enviar '
                  'para a fila" entra no loop normal — se o texto ainda tocar dinheiro/tokens, '
                  'o carteiro volta a pedir a tua confirmação no Telegram.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              if (status == 'nova' || status == 'vista') ...[
                FilledButton.icon(
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: const Text('Aprovar e enviar para a fila'),
                  onPressed: () { Navigator.pop(ctx); _confirmCortexApprove(pid); },
                ),
                const SizedBox(height: 8),
              ],
              if (status == 'nova') ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Marcar vista'),
                  onPressed: () { Navigator.pop(ctx); _markCortexStatus(pid, 'vista'); },
                ),
                const SizedBox(height: 8),
              ],
              if (status != 'decidida_fora' && status != 'aprovada_danilo')
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Marcar decidida fora'),
                  onPressed: () { Navigator.pop(ctx); _confirmCortexDecidido(pid); },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── métricas ────────────────────────────────────────────────────────────────

  Widget _metricsCard() {
    final taxa = _metrics['taxa_aprovacao_pct'];
    final on = _metrics['robot_b_enabled'] == true;
    final auto1 = _metrics['robot_b_auto_level1_enabled'] == true;
    Widget item(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ]),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            item('Abertas', '${_metrics['abertas'] ?? '—'}'),
            item('Sugestões 7d', '${_metrics['sugestoes_7d'] ?? '—'}'),
            item('Auto-fixes 7d', '${_metrics['auto_fixes_7d'] ?? '—'}'),
            item('Aprovação', taxa == null ? '—' : '$taxa%'),
          ]),
          const Divider(height: 16),
          Row(children: [
            Icon(Icons.power_settings_new, size: 16, color: on ? AppColors.primary : Colors.grey),
            Text(' Robô ${on ? 'LIGADO' : 'DESLIGADO'}', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 14),
            Icon(Icons.bolt, size: 16, color: auto1 ? AppColors.primary : Colors.grey),
            Text(' Nível 1 ${auto1 ? 'AUTO' : 'MANUAL'}', style: const TextStyle(fontSize: 12)),
            const Spacer(),
            const Text('Alterar em Configurações',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ]),
        ]),
      ),
    );
  }

  // ── cabeçalho de progresso da autonomia (Fase 5) ─────────────────────────────
  // autonomy_goals = SÓ o cabeçalho (barra + placar + kill switch + dial).
  // A aprovação continua a ser esta MESMA superfície (uma só caixa).
  Widget _parityHeader() {
    final goals = ((_autonomy['goals'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (goals.isEmpty) return const SizedBox.shrink();
    final g = goals.first;
    final alvo = (g['metrica_alvo'] as num?)?.toDouble() ?? 1;
    final atual = (g['metrica_atual'] as num?)?.toDouble() ?? 0;
    final pct = alvo > 0 ? (atual / alvo).clamp(0.0, 1.0) : 0.0;
    final parado = _autonomy['kill_switch_parado'] == true;
    final dialAuto = _autonomy['dial_auto_l1'] == true;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hub_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('🎛️ ${g['titulo'] ?? 'Autonomia'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            Text('${atual.toInt()}/${alvo.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: pct, minHeight: 8, color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: parado ? AppColors.primary : AppColors.error),
              icon: Icon(parado ? Icons.play_arrow : Icons.stop_circle, size: 18),
              label: Text(parado ? 'Retomar loop' : 'PARAR TUDO'),
              onPressed: () => _confirmKill(!parado),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: dialAuto,
            onChanged: (v) => _setSwitch('robot_b_auto_level1_enabled', v),
            title: const Text('Dial de confiança', style: TextStyle(fontSize: 13)),
            subtitle: Text(
                dialAuto
                    ? '🟢 Automático — L1 reversível aplica após o Juiz'
                    : '🔒 Cauteloso — tudo passa por ti (1 toque)',
                style: const TextStyle(fontSize: 11)),
          ),
        ]),
      ),
    );
  }

  // ── prova da auto-cura (Fase 5) ──────────────────────────────────────────────
  // Cada item mostra: nota do Juiz (badge grande), nº de tentativas, a linha do
  // tempo das notas (a subida volta a volta), 👁 tem_visual e a referência usada.
  Color _notaColor(double n) => n >= 9
      ? AppColors.primary
      : n >= 7
          ? const Color(0xFFFF8F00)
          : AppColors.error;

  Widget _notaBadge(double n, {double size = 15}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _notaColor(n),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('${n.toStringAsFixed(1)}/10',
            style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.bold)),
      );

  // "6.5 → 8.0 → 9.5" a partir de historico_avaliacoes.
  Widget _notaTimeline(List hist) {
    if (hist.isEmpty) return const SizedBox.shrink();
    final spans = <InlineSpan>[];
    for (var i = 0; i < hist.length; i++) {
      final m = (hist[i] as Map);
      final n = (m['nota'] as num?)?.toDouble() ?? 0;
      final visual = m['visual'] == true;
      if (i > 0) {
        spans.add(const TextSpan(text: '  →  ',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)));
      }
      spans.add(TextSpan(
        text: '${n.toStringAsFixed(1)}${visual ? '👁' : ''}',
        style: TextStyle(
            color: _notaColor(n), fontWeight: FontWeight.bold, fontSize: 12),
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }

  void _showItemProof(Map<String, dynamic> b) {
    final hist = (b['historico_avaliacoes'] as List?) ?? const [];
    final ref = b['referencia_benchmark'];
    final det = b['juiz_detalhe'];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(controller: scroll, children: [
            Text(b['dominio']?.toString() ?? '',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              if (b['juiz_nota'] != null) _notaBadge((b['juiz_nota'] as num).toDouble()),
              const SizedBox(width: 8),
              Text('${b['tentativas'] ?? 0} tentativa(s)',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Icon(b['tem_visual'] == true ? Icons.visibility : Icons.visibility_off,
                  size: 16, color: b['tem_visual'] == true ? AppColors.primary : Colors.grey),
              Text(b['tem_visual'] == true ? ' com olhos' : ' sem olhos (teto 8)',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
            const Divider(height: 22),
            const Text('Evolução das notas (volta a volta)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            _notaTimeline(hist),
            const SizedBox(height: 14),
            const Text('O que faltou / rubrica do Juiz',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
              child: Text(_pretty(det),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
            const SizedBox(height: 14),
            const Text('Referência dos melhores usada',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
              child: Text(_pretty(ref),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  // Card só aparece quando há itens já avaliados pelo loop (nota != null).
  Widget _proofSection() {
    final avaliados = _backlog
        .where((b) => b['juiz_nota'] != null || (b['tentativas'] as num?) != null && (b['tentativas'] as num) > 0)
        .toList();
    if (avaliados.isEmpty) return const SizedBox.shrink();
    String estadoLabel(String e) => switch (e) {
          'aguarda_ti' => 'na Central (aguarda ✅)',
          'em_correcao' => 'em correção',
          'travado_pediu_ajuda' => 'pediu ajuda',
          'feito' => 'feito',
          'a_correr' => 'a correr',
          _ => e,
        };
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.biotech_outlined, size: 18, color: AppColors.primary),
            SizedBox(width: 6),
            Text('🔬 Prova da auto-cura (Juiz ↔ maestro)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          const Text('Nota do Juiz (0-10), quantas voltas levou, se teve olhos (👁 = viu a própria tela).',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ...avaliados.take(6).map((b) {
            final nota = (b['juiz_nota'] as num?)?.toDouble();
            final hist = (b['historico_avaliacoes'] as List?) ?? const [];
            final estado = b['estado']?.toString() ?? '';
            return InkWell(
              onTap: () => _showItemProof(b),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  if (nota != null) _notaBadge(nota) else const SizedBox(width: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b['dominio']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text('${b['tentativas'] ?? 0}× · ${estadoLabel(estado)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        Icon(b['tem_visual'] == true ? Icons.visibility : Icons.visibility_off,
                            size: 13,
                            color: b['tem_visual'] == true ? AppColors.primary : Colors.grey),
                      ]),
                      if (hist.length > 1) ...[
                        const SizedBox(height: 3),
                        _notaTimeline(hist),
                      ],
                    ]),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const BoraScreenAppBar(title: 'Sugestões do Robot'),
        body: Column(children: [
          const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            isScrollable: true,
            tabs: [Tab(text: 'Sugestões'), Tab(text: 'Auto-execuções'), Tab(text: 'Córtex 🔴')],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, style: const TextStyle(color: AppColors.error)),
                        TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                      ]))
                    : TabBarView(children: [_suggestionsTab(), _auditTab(), _cortexTab()]),
          ),
        ]),
      ),
    );
  }

  Widget _suggestionsTab() {
    return Column(children: [
      _parityHeader(),
      _proofSection(),
      _metricsCard(),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _statusFilter,
              decoration: const InputDecoration(
                  labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todas')),
                DropdownMenuItem(value: 'nova', child: Text('Novas')),
                DropdownMenuItem(value: 'aplicada', child: Text('Aplicadas')),
                DropdownMenuItem(value: 'rejeitada', child: Text('Rejeitadas')),
                DropdownMenuItem(value: 'expirada', child: Text('Expiradas')),
              ],
              onChanged: (v) { setState(() => _statusFilter = v); _load(); },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int?>(
              value: _nivelFilter,
              decoration: const InputDecoration(
                  labelText: 'Nível', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 1, child: Text('🟢 Nível 1')),
                DropdownMenuItem(value: 2, child: Text('🟡 Nível 2')),
                DropdownMenuItem(value: 3, child: Text('🔴 Nível 3')),
              ],
              onChanged: (v) { setState(() => _nivelFilter = v); _load(); },
            ),
          ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _rows.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Center(child: Text('Sem sugestões — o robô está em dia 🤖',
                      style: TextStyle(color: AppColors.textSecondary))),
                ])
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) {
                    final s = _rows[i];
                    final nivel = (s['nivel'] as num?)?.toInt() ?? 3;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                          decoration: BoxDecoration(
                            color: _nivelColor(nivel),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('N$nivel',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      title: Text(s['titulo']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          '${s['categoria']} · sev ${s['severidade']} · ${_fmtDate(s['created_at'])}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: _statusChip(s['status']?.toString() ?? 'nova'),
                      onTap: () => _showDetail(s),
                    );
                  },
                ),
        ),
      ),
    ]);
  }

  Widget _auditTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: _audit.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              Center(child: Text('Sem auto-execuções registradas',
                  style: TextStyle(color: AppColors.textSecondary))),
            ])
          : ListView.separated(
              itemCount: _audit.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (_, i) {
                final a = _audit[i];
                final byRobot = a['executed_by'] == 'robot';
                final rows = (a['result'] as Map?)?['rows_affected'];
                return ListTile(
                  leading: const Icon(Icons.settings_suggest_outlined),
                  title: Text(a['operation']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${rows ?? '?'} registro(s) · ${_fmtDate(a['created_at'])}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Chip(
                    label: Text(byRobot ? 'ROBÔ' : (a['executed_by']?.toString() ?? '?'),
                        style: const TextStyle(fontSize: 9, color: Colors.white)),
                    backgroundColor: byRobot ? AppColors.primary : Colors.blueGrey,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onTap: () => _showAuditDetail(a),
                );
              },
            ),
    );
  }

  Widget _cortexTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          const Expanded(
            child: Text(
              'Propostas zona-vermelha do Córtex (dinheiro/escrita sensível). '
              'Fila separada — rever aqui nunca executa nada sozinho.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: DropdownButtonFormField<String?>(
          value: _cortexStatusFilter,
          decoration: const InputDecoration(
              labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'nova', child: Text('Novas (por rever)')),
            DropdownMenuItem(value: 'vista', child: Text('Vistas')),
            DropdownMenuItem(value: 'aprovada_danilo', child: Text('Aprovadas — na fila')),
            DropdownMenuItem(value: 'decidida_fora', child: Text('Decididas fora')),
            DropdownMenuItem(value: null, child: Text('Todas')),
          ],
          onChanged: (v) { setState(() => _cortexStatusFilter = v); _load(); },
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _cortexProposals.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Center(child: Text('Sem propostas nesta vista',
                      style: TextStyle(color: AppColors.textSecondary))),
                ])
              : ListView.separated(
                  itemCount: _cortexProposals.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) {
                    final p = _cortexProposals[i];
                    return ListTile(
                      leading: const Icon(Icons.shield_outlined, color: AppColors.error),
                      title: Text(p['tarefa']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${p['ordem_id'] ?? '—'} · ${_fmtDate(p['criada_em'])}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: _cortexStatusChip(p['status']?.toString() ?? 'nova'),
                      onTap: () => _showCortexDetail(p),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
