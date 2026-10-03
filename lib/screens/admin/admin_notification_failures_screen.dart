// BLOCO D5 (2026-09-04) — quadro "Avisos que falharam".
//
// Lê `notification_failures` (criada em 20260718003000, já usada por
// _cleaning_notify_user e pelas funções do carwash — nenhuma tabela nova).
// Migration 20260904230000 fechou um buraco de segurança que a tabela tinha
// desde a criação (RLS desligada + grant total a anon/authenticated) e deu
// policy de leitura só-admin (`is_admin()`).
//
// Cobertura hoje: só limpeza e lavagem auto gravam aqui quando o envio
// falha. Os `notify-*` (cliente/driver/partner/tvde/...) em
// `supabase/functions/` ainda só fazem `console.error` — não persistem a
// falha nesta tabela. Ver relatório BLOCO-D5 para o gap documentado.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminNotificationFailuresScreen extends StatefulWidget {
  const AdminNotificationFailuresScreen({super.key});

  @override
  State<AdminNotificationFailuresScreen> createState() =>
      _AdminNotificationFailuresScreenState();
}

class _AdminNotificationFailuresScreenState
    extends State<AdminNotificationFailuresScreen> {
  /// Janela por defeito: últimas 24h (pedido explícito). PopupMenu deixa
  /// alargar para 7 dias ou tudo, para investigar um problema mais antigo.
  int _hours = 24;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var query = Supabase.instance.client
        .from('notification_failures')
        .select('id, user_id, kind, source, erro, created_at');
    if (_hours > 0) {
      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(hours: _hours))
          .toIso8601String();
      query = query.gte('created_at', since);
    }
    final rows = await query.order('created_at', ascending: false).limit(300);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Avisos que falharam',
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
      body: RefreshIndicator(
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
                  Icon(Icons.notifications_active_outlined,
                      size: 44, color: AppColors.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _hours == 24
                          ? 'Nenhum aviso falhou nas últimas 24h. 👍'
                          : 'Nenhum aviso falhou neste período.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Cobertura actual: limpeza doméstica e lavagem auto. '
                      'Cliente/estafeta/parceiro/TVDE ainda não gravam aqui '
                      'quando o push falha (ver relatório BLOCO-D5).',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSubtle),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _FailureCard(row: rows[i]),
            );
          },
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final kind = (row['kind'] as String?) ?? '—';
    final source = (row['source'] as String?) ?? '—';
    final erro = (row['erro'] as String?) ?? 'sem detalhe';
    final userId = (row['user_id'] as String?) ?? '—';
    final created = _fmtDateTime(row['created_at']);

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 18, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(source,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                Text(created,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
              ],
            ),
            const SizedBox(height: 6),
            Text('tipo: $kind · utilizador: $userId',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(erro,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
