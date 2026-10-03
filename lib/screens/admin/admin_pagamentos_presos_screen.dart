// Pagamentos presos (2026-10-03) — painel admin, PT-BR.
//
// Nasceu do cartão no iPhone que ficava só a rodar (Divan, 02/10): a corrida
// ficou em `requires_payment_method` e ninguém via porquê. Este ecrã mostra,
// para os últimos N dias, todo o pagamento com cartão parado em
// requires_payment_method / requires_action (TVDE, entregas, limpeza,
// lavagem), com a plataforma do cliente e o último erro que a app gravou em
// `payment_client_failures` — e também as falhas da app que nem chegaram a
// ter pedido. Fonte: RPC `admin_pagamentos_presos(p_dias)` (só admin).
//
// Só leitura: nada aqui cobra, estorna ou muda valores.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminPagamentosPresosScreen extends StatefulWidget {
  const AdminPagamentosPresosScreen({super.key});

  @override
  State<AdminPagamentosPresosScreen> createState() =>
      _AdminPagamentosPresosScreenState();
}

class _AdminPagamentosPresosScreenState
    extends State<AdminPagamentosPresosScreen> {
  int _dias = 14;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .rpc('admin_pagamentos_presos', params: {'p_dias': _dias});
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
        title: 'Pagamentos presos',
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Período',
            icon: const Icon(Icons.timer_outlined),
            initialValue: _dias,
            onSelected: (v) {
              setState(() => _dias = v);
              _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Últimas 24h')),
              PopupMenuItem(value: 7, child: Text('Últimos 7 dias')),
              PopupMenuItem(value: 14, child: Text('Últimos 14 dias')),
              PopupMenuItem(value: 30, child: Text('Últimos 30 dias')),
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
                children: const [
                  SizedBox(height: 100),
                  Center(
                    child: Text(
                      'Nenhum pagamento com cartão preso neste período. 👍',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            final porPlataforma = <String, int>{};
            for (final r in rows) {
              final p = (r['plataforma'] as String?) ?? '?';
              porPlataforma[p] = (porPlataforma[p] ?? 0) + 1;
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Text(
                      '${rows.length} pagamento(s) preso(s) ou falha(s) da app · '
                      '${porPlataforma.entries.map((e) => '${_nomePlataforma(e.key)} ${e.value}').join(' · ')}\n'
                      'Nada disto foi cobrado: são pagamentos que não chegaram ao fim.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  );
                }
                return _Linha(row: rows[i - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final vertical = (row['vertical'] as String?) ?? '?';
    final estadoPg = (row['payment_status'] as String?) ?? '—';
    final estado = (row['status'] as String?) ?? '—';
    final nome = (row['cliente_nome'] as String?) ?? 'cliente sem nome';
    final contacto = (row['cliente_contacto'] as String?) ?? '';
    final plataforma = (row['plataforma'] as String?) ?? '?';
    final valor = row['valor_cents'] is num
        ? '€${((row['valor_cents'] as num) / 100).toStringAsFixed(2).replaceAll('.', ',')}'
        : '—';
    final erro = (row['ultimo_erro'] as String?) ?? '';
    final ref = (row['referencia_id'] as String?) ?? '';

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
                Text('${_nomeVertical(vertical)} · $valor',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                const Spacer(),
                Text(_fmt(row['created_at']),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
              ],
            ),
            const SizedBox(height: 4),
            Text('$nome${contacto.isEmpty ? '' : ' · $contacto'} · ${_nomePlataforma(plataforma)}',
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Pagamento: ${_nomeEstadoPg(estadoPg)} · Pedido: $estado',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            if (erro.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Erro na app: $erro',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            if (ref.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copiar código'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: ref));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código copiado.')));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _nomeVertical(String v) => switch (v) {
      'tvde' => 'Corrida TVDE',
      'entrega' => 'Entrega',
      'limpeza' => 'Limpeza',
      'lavagem' => 'Lavagem',
      'reserva_mesa' => 'Reserva de mesa',
      'marcacao' => 'Marcação',
      _ => v,
    };

String _nomeEstadoPg(String s) => switch (s) {
      'requires_payment_method' => 'cartão não chegou a ser pago',
      'requires_action' => 'banco não confirmou (3D Secure)',
      'requires_confirmation' => 'à espera de confirmação',
      'falha_app' => 'o ecrã do cartão falhou na app',
      _ => s,
    };

String _nomePlataforma(String p) => switch (p) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'web' => 'Web',
      _ => p,
    };

String _fmt(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
