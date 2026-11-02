import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/auth_admin_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Saúde das chaves (PT-BR) — missão chaves-varredura-2026-10-31.
///
/// Todos os dias às 07:00 o banco chama cada Edge Function (função do servidor) que o
/// servidor usa, com a chave antiga (legada) e com a chave nova (sb_secret), só com
/// `{"ping":true}`. Se alguma recusar a chave (401/403) chega o aviso "🔑 CHAVE RECUSADA"
/// no sininho, no push e no Telegram — o deep-link desse aviso abre este ecrã
/// (`/admin/system-health`). Porquê: a 31/10 um cliente pagou e ficou sem pedido porque
/// uma função recusava a chave do servidor havia 15 dias, sem ninguém saber.
///
/// Fonte: RPC `admin_saude_chaves(p_dias)` (só admin). O botão chama
/// `admin_saude_chaves_correr()`; o resultado aparece depois do verificador de hora a
/// hora (minuto 6).
class AdminSaudeChavesScreen extends StatefulWidget {
  const AdminSaudeChavesScreen({super.key});

  @override
  State<AdminSaudeChavesScreen> createState() => _AdminSaudeChavesScreenState();
}

class _Ronda {
  _Ronda(this.id, this.quando);
  final String id;
  final String quando;
  final List<Map<String, dynamic>> linhas = [];
  int get ok => linhas.where((l) => l['resultado'] == 'ok').length;
  int get porVerificar => linhas.where((l) => l['resultado'] == 'por_verificar').length;
  int get expirados => linhas.where((l) => l['resultado'] == 'expirado').length;
  int get problemas => linhas.length - ok - porVerificar - expirados;
}

class _AdminSaudeChavesScreenState extends State<AdminSaudeChavesScreen> {
  late Future<List<_Ronda>> _future;
  bool _aCorrer = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Ronda>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_saude_chaves', params: {'p_dias': 7});
    final rondas = <String, _Ronda>{};
    if (res is List) {
      for (final e in res) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m['ronda']?.toString() ?? '?';
        rondas.putIfAbsent(id, () => _Ronda(id, m['criado_em']?.toString() ?? '')).linhas.add(m);
      }
    }
    return rondas.values.toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _correrAgora() async {
    setState(() => _aCorrer = true);
    String msg;
    try {
      await Supabase.instance.client.rpc('admin_saude_chaves_correr');
      msg = 'Ronda enviada. O resultado aparece depois do verificador (minuto 6 de cada hora).';
    } catch (e) {
      msg = 'Não deu para correr o vigia: $e';
    }
    if (!mounted) return;
    setState(() => _aCorrer = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthAdminService.isAdmin()) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Saúde das chaves'),
        body: Center(child: Text('Acesso negado.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Saúde das chaves',
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<_Ronda>>(
          future: _future,
          builder: (context, snap) {
            final topo = <Widget>[
              const Text(
                'Todos os dias às 07:00 o servidor testa se consegue chamar cada função '
                '(Edge Function) com a chave antiga e com a nova. Verde = passou; '
                'vermelho = a função recusou a chave (avisos, pagamentos ou pedidos podem estar a falhar).',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: _aCorrer
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Correr o vigia agora'),
                  onPressed: _aCorrer ? null : _correrAgora,
                ),
              ),
              const SizedBox(height: 12),
            ];
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(padding: const EdgeInsets.all(12), children: [
                ...topo,
                const Center(child: CircularProgressIndicator()),
              ]);
            }
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(12), children: [
                ...topo,
                Text('Erro a carregar (admin_saude_chaves): ${snap.error}'),
              ]);
            }
            final rondas = snap.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...topo,
                if (rondas.isEmpty) const Text('Ainda não há rondas nos últimos 7 dias.'),
                for (final r in rondas) _RondaCard(ronda: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RondaCard extends StatelessWidget {
  const _RondaCard({required this.ronda});
  final _Ronda ronda;

  @override
  Widget build(BuildContext context) {
    final temProblema = ronda.problemas > 0;
    final cor = temProblema ? AppColors.error : AppColors.success;
    final resumo = [
      '${ronda.ok} ok',
      if (ronda.problemas > 0) '${ronda.problemas} com problema',
      if (ronda.porVerificar > 0) '${ronda.porVerificar} por verificar',
      if (ronda.expirados > 0) '${ronda.expirados} verificadas tarde (sem aviso)',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: cor, width: temProblema ? 2 : 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: temProblema,
        leading: Icon(temProblema ? Icons.key_off : Icons.verified_user, color: cor),
        title: Text('Ronda de ${dataHoraLisboa(ronda.quando)} (Lisboa)'),
        subtitle: Text(resumo, style: const TextStyle(fontSize: 12)),
        children: [
          for (final l in ronda.linhas)
            ListTile(
              dense: true,
              leading: Icon(
                l['resultado'] == 'ok'
                    ? Icons.check_circle
                    : (l['resultado'] == 'por_verificar' || l['resultado'] == 'expirado')
                        ? Icons.schedule
                        : Icons.error,
                color: l['resultado'] == 'ok'
                    ? AppColors.success
                    : (l['resultado'] == 'por_verificar' || l['resultado'] == 'expirado')
                        ? AppColors.textSecondary
                        : AppColors.error,
                size: 18,
              ),
              title: Text('${l['funcao']}', style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${l['modo'] == 'legada_bearer' ? 'chave antiga' : 'chave nova'} · '
                'HTTP ${l['status_code'] ?? '—'} · ${l['resultado']}'
                '${l['alertado'] == true ? ' · aviso enviado' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
