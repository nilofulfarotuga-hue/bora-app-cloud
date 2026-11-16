import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/auth_admin_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Vigia do servidor (PT-BR) — missão servidor-nao-travar-2026-11-16, B3.3.
///
/// A 16/11 a app de uma só cliente (canais de tempo real que se acumulavam)
/// fez 23 890 leituras de pedidos em 80 min e ocupou 90% do servidor: login,
/// painel e estafetas deram erro 504. De 5 em 5 min o banco (pg_cron
/// `vigia-servidor`) mede quanto tempo do servidor cada consulta gastou e
/// quantos canais de tempo real cada conta tem abertos. Se uma consulta levar
/// 40% de um servidor 50% ocupado, ou uma conta tiver 10+ canais na mesma
/// tabela, chega o aviso "🚨 SERVIDOR CARREGADO" no sininho, push e Telegram —
/// o toque nesse aviso abre este ecrã (`/admin/vigia-servidor`).
///
/// Fonte: RPC `admin_vigia_servidor(p_horas)` (só admin).
class AdminVigiaServidorScreen extends StatefulWidget {
  const AdminVigiaServidorScreen({super.key});

  @override
  State<AdminVigiaServidorScreen> createState() =>
      _AdminVigiaServidorScreenState();
}

class _AdminVigiaServidorScreenState extends State<AdminVigiaServidorScreen> {
  int _horas = 24;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_vigia_servidor', params: {'p_horas': _horas});
    if (res is! List) return const [];
    return [for (final e in res) Map<String, dynamic>.from(e as Map)];
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthAdminService.isAdmin()) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Vigia do servidor'),
        body: Center(child: Text('Acesso negado.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Vigia do servidor',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            final topo = <Widget>[
              const Text(
                'De 5 em 5 minutos o banco mede quanto do servidor ficou ocupado '
                '(soma do tempo das consultas ÷ tempo que passou) e qual consulta '
                'pesou mais. Também conta os canais de tempo real (realtime) '
                'abertos por cada conta. Vermelho = gerou aviso.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in const [6, 24, 72, 168])
                    ChoiceChip(
                      label: Text(h < 48 ? '${h}h' : '${h ~/ 24} dias'),
                      selected: _horas == h,
                      onSelected: (_) {
                        _horas = h;
                        _refresh();
                      },
                    ),
                ],
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
                Text('Erro a carregar (admin_vigia_servidor): ${snap.error}'),
              ]);
            }
            final linhas = snap.data ?? const [];
            final avisos = linhas.where((l) => l['alertou'] == true).length;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...topo,
                Text(
                  linhas.isEmpty
                      ? 'Ainda não há medições neste período.'
                      : '${linhas.length} medições · $avisos com aviso',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final l in linhas) _MedicaoCard(linha: l),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MedicaoCard extends StatelessWidget {
  const _MedicaoCard({required this.linha});
  final Map<String, dynamic> linha;

  @override
  Widget build(BuildContext context) {
    final alertou = linha['alertou'] == true;
    final ocupado = num.tryParse('${linha['ocupado_pct']}') ?? 0;
    final cor = alertou
        ? AppColors.error
        : (ocupado >= 50 ? Colors.orange : AppColors.success);
    final canais = (linha['canais_top'] is List)
        ? (linha['canais_top'] as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList()
        : const <Map<String, dynamic>>[];
    final motivo = switch (linha['motivo']) {
      'consulta_pesada' => 'Uma consulta pesou demais',
      'canais_acumulados' => 'Uma conta com canais a mais',
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: cor, width: alertou ? 2 : 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: alertou,
        leading: Icon(alertou ? Icons.warning_amber : Icons.speed, color: cor),
        title: Text(
            '${dataHoraLisboa(linha['criado_em'])} · servidor $ocupado% ocupado'),
        subtitle: Text(
          [
            if (motivo != null) motivo,
            if (linha['top_pct'] != null)
              'consulta mais pesada: ${linha['top_pct']}% '
                  '(${linha['top_vezes'] ?? '—'} vezes, '
                  '${linha['top_media_ms'] ?? '—'} ms em média)',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Papel (role): ${linha['top_papel'] ?? '—'}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText('${linha['top_consulta'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 8),
                const Text('Contas com mais canais de tempo real:',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (canais.isEmpty)
                  const Text('nenhuma', style: TextStyle(fontSize: 12)),
                for (final c in canais)
                  Text(
                    '${c['nome'] ?? c['user_id'] ?? '?'} — '
                    '${c['canais']} canais em ${c['tabela']}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
