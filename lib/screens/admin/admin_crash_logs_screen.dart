// Paridade 3 plataformas (2026-09-21) — quadro "Erros da app (crashes)".
//
// Lê `debug_crash_logs` (a tabela onde o `_logCrashToSupabase` do main.dart
// grava cada erro não tratado da app). Até hoje não havia ecrã nenhum: 511
// linhas (288 Android + 223 "iOS") só se viam por SQL, e nas de iPhone
// nenhuma trazia versão nem modelo — impossível dizer a que build pertencia
// um crash. A migration 20260921190000 deu à tabela a policy de leitura
// só-admin (`is_admin()`), igual à de `notification_failures`.
//
// O que se vê: filtro por plataforma (Android / iPhone / Web / todas) e por
// janela, contagem por plataforma no topo, e por linha: erro, data, versão da
// app, modelo, sistema, rota. Toque abre o erro inteiro com o stack trace,
// seleccionável para copiar.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminCrashLogsScreen extends StatefulWidget {
  const AdminCrashLogsScreen({super.key});

  @override
  State<AdminCrashLogsScreen> createState() => _AdminCrashLogsScreenState();
}

class _AdminCrashLogsScreenState extends State<AdminCrashLogsScreen> {
  /// Janela por defeito: 7 dias. Crashes são raros o suficiente para 24h
  /// aparecer quase sempre vazio e esconder um problema de ontem.
  int _hours = 24 * 7;

  /// null = todas as plataformas.
  String? _platform;

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var query = Supabase.instance.client.from('debug_crash_logs').select(
        'id, created_at, screen, route, error_message, stack_trace, platform, '
        'app_version, device_model, android_version, gms_status, user_id');
    if (_hours > 0) {
      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: _hours))
          .toIso8601String();
      query = query.gte('created_at', since);
    }
    if (_platform != null) {
      query = query.eq('platform', _platform!);
    }
    final rows = await query.order('created_at', ascending: false).limit(300);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _setPlatform(String? p) {
    setState(() => _platform = p);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Erros da app (crashes)',
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Janela',
            icon: const Icon(Icons.timer_outlined),
            initialValue: _hours,
            onSelected: (v) {
              setState(() => _hours = v);
              _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 24, child: Text('Últimas 24h')),
              PopupMenuItem(value: 24 * 7, child: Text('Últimos 7 dias')),
              PopupMenuItem(value: 24 * 30, child: Text('Últimos 30 dias')),
              PopupMenuItem(value: 0, child: Text('Tudo')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('Todas', null),
                  _chip('Android', 'android'),
                  _chip('iPhone', 'ios'),
                  _chip('Web', 'web'),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.error_outline,
                            size: 44, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Erro ao carregar: ${snap.error}',
                            textAlign: TextAlign.center),
                      ],
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 100),
                        Icon(Icons.check_circle_outline,
                            size: 44,
                            color: AppColors.primary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text(
                            'Nenhum erro registrado neste período. 👍',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == 0) return _Resumo(rows: rows, hours: _hours);
                      return _CrashCard(row: rows[i - 1]);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final selected = _platform == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _setPlatform(value),
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
      ),
    );
  }
}

/// Contagem por plataforma dentro do que foi carregado (até 300 linhas).
class _Resumo extends StatelessWidget {
  const _Resumo({required this.rows, required this.hours});
  final List<Map<String, dynamic>> rows;
  final int hours;

  @override
  Widget build(BuildContext context) {
    final porPlataforma = <String, int>{};
    var semVersao = 0;
    for (final r in rows) {
      final p = (r['platform'] as String?) ?? '?';
      porPlataforma[p] = (porPlataforma[p] ?? 0) + 1;
      if ((r['app_version'] as String?)?.isNotEmpty != true) semVersao++;
    }
    final partes = porPlataforma.entries
        .map((e) => '${_nomePlataforma(e.key)} ${e.value}')
        .join(' · ');
    final janela = hours == 0
        ? 'tudo'
        : hours <= 24
            ? 'últimas 24h'
            : 'últimos ${hours ~/ 24} dias';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${rows.length} erro(s) · $janela'
              '${rows.length >= 300 ? ' (mostrando os 300 mais recentes)' : ''}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 4),
          Text(partes,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          if (semVersao > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$semVersao sem versão da app (builds anteriores a 21/09/2026 '
              'não a enviavam no iPhone nem na web).',
              style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
          ],
        ],
      ),
    );
  }
}

class _CrashCard extends StatelessWidget {
  const _CrashCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final platform = (row['platform'] as String?) ?? '?';
    final erro = ((row['error_message'] as String?) ?? 'sem mensagem').trim();
    final resumo = erro.split('\n').first;
    final versao = (row['app_version'] as String?) ?? '—';
    final modelo = (row['device_model'] as String?) ?? '—';
    final sistema = (row['android_version'] as String?) ?? '—';
    final rota = (row['route'] as String?) ?? (row['screen'] as String?) ?? '—';
    final created = _fmtDateTime(row['created_at']);

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => _abrirDetalhe(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BadgePlataforma(platform),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(rota,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Text(created,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSubtle)),
                ],
              ),
              const SizedBox(height: 6),
              Text(resumo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('versão $versao · $modelo · $sistema',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirDetalhe(BuildContext context) {
    final erro = (row['error_message'] as String?) ?? '';
    final stack = (row['stack_trace'] as String?) ?? '';
    final linhas = <String>[
      'Plataforma: ${_nomePlataforma((row['platform'] as String?) ?? '?')}',
      'Versão: ${row['app_version'] ?? '—'}',
      'Aparelho: ${row['device_model'] ?? '—'}',
      'Sistema: ${row['android_version'] ?? '—'}',
      'Rota: ${row['route'] ?? '—'} · Ecrã: ${row['screen'] ?? '—'}',
      'Push (GMS): ${row['gms_status'] ?? '—'}',
      'Utilizador: ${row['user_id'] ?? '—'}',
      'Quando: ${_fmtDateTime(row['created_at'])}',
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detalhe do erro'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              '${linhas.join('\n')}\n\n$erro\n\n$stack',
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _BadgePlataforma extends StatelessWidget {
  const _BadgePlataforma(this.platform);
  final String platform;

  @override
  Widget build(BuildContext context) {
    final (cor, icone) = switch (platform) {
      'android' => (Colors.green.shade700, Icons.android),
      'ios' => (Colors.grey.shade800, Icons.phone_iphone),
      'web' => (Colors.blue.shade700, Icons.language),
      _ => (AppColors.textSubtle, Icons.help_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: cor),
          const SizedBox(width: 3),
          Text(_nomePlataforma(platform),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
        ],
      ),
    );
  }
}

String _nomePlataforma(String p) => switch (p) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'web' => 'Web',
      _ => p,
    };

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
