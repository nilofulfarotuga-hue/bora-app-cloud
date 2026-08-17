import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/business_rules.dart' show BRTokens;
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/weekly_settlement_card.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  bool _loading = true;
  String? _error;

  int _tokens = 0;
  int _weeklyTokensConverted = 0;

  /// F6 (2026-08-16): GANHOS UNIFICADOS — vem TUDO da RPC
  /// driver_earnings_summary (TVDE + entregas + favores + tokens, a MESMA
  /// fonte dos acertos). O Flutter só exibe, nunca calcula.
  Map<String, dynamic>? _resumo;
  DateTime? _priorityUntil;
  final Map<String, int> _priorityCosts = {
    '5min': 50,
    '10min': 90,
    '15min': 125,
    '1hour': 400,
  };

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
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Utilizador não autenticado.';
      });
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      final weekStart = _weekStart();
      final conversionRows = await supabase
          .from('driver_transactions')
          .select('amount')
          .eq('driver_id', uid)
          .eq('type', 'token_conversion')
          .gte('created_at', weekStart.toIso8601String());
      final convertedEur = (conversionRows as List).fold(
          0.0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0));
      _weeklyTokensConverted =
          (convertedEur / BRTokens.TOKEN_VALUE_EUR).round();

      final tokenResp = await supabase.rpc(
        'get_user_tokens',
        params: {'p_user_id': uid},
      );
      _tokens = (tokenResp as num?)?.toInt() ?? 0;

      // F6 — resumo unificado servidor (nunca calcular no cliente)
      try {
        final resp = await supabase.rpc('driver_earnings_summary');
        if (resp is Map && resp['ok'] == true) {
          _resumo = Map<String, dynamic>.from(resp);
        }
      } catch (e) {
        debugPrint('[DriverEarnings] driver_earnings_summary: $e');
      }

      // F5.4 (doença id/user_id): era .eq('id', uid) — conta com id≠user_id
      // nunca encontrava a própria linha. Tolerante às duas chaves.
      final driverRow = await supabase
          .from('drivers')
          .select('priority_until')
          .or('id.eq.$uid,user_id.eq.$uid')
          .maybeSingle();
      final pu = driverRow?['priority_until'] as String?;
      _priorityUntil = pu != null ? DateTime.tryParse(pu) : null;

      try {
        final cfgRows = await supabase
            .from('token_config')
            .select('key, value')
            .inFilter('key', [
          'priority_5min_cost',
          'priority_10min_cost',
          'priority_15min_cost',
          'priority_1hour_cost',
        ]);
        for (final row in (cfgRows as List)) {
          final k = row['key'] as String?;
          final v = (row['value'] as num?)?.toInt();
          if (k == null || v == null) continue;
          if (k == 'priority_5min_cost') _priorityCosts['5min'] = v;
          if (k == 'priority_10min_cost') _priorityCosts['10min'] = v;
          if (k == 'priority_15min_cost') _priorityCosts['15min'] = v;
          if (k == 'priority_1hour_cost') _priorityCosts['1hour'] = v;
        }
      } catch (_) {
        // keep defaults
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// F6 — cabeçalho de ganhos unificados + extrato dos últimos 7 dias.
  Widget _resumoUnificado() {
    final r = _resumo!;
    final dia = Map<String, dynamic>.from(r['dia'] as Map? ?? {});
    final semana = Map<String, dynamic>.from(r['semana'] as Map? ?? {});
    final itens = List<Map<String, dynamic>>.from(
        (r['itens'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    String eur(num? cents) =>
        '€${((cents ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoje',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(eur(dia['total_cents'] as num?),
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                if ((dia['tokens'] as num? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('+${dia['tokens']} tokens',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade800)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Esta semana: ${eur(semana['total_cents'] as num?)}'
                '${(semana['tokens'] as num? ?? 0) > 0 ? ' · +${semana['tokens']} tokens' : ''}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            if (itens.isNotEmpty) ...[
              const Divider(height: 24),
              ...itens.take(15).map((i) {
                final tokens = (i['tokens'] as num? ?? 0).toInt();
                final valor = (i['valor_cents'] as num? ?? 0).toInt();
                final icone = switch (i['tipo'] as String? ?? '') {
                  'tvde' => Icons.directions_car_outlined,
                  'tokens' => Icons.monetization_on_outlined,
                  'favor_entrega' => Icons.shopping_bag_outlined,
                  _ => Icons.delivery_dining_outlined,
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(icone, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${i['ts']} · ${i['descricao']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        tokens > 0 ? '+$tokens tk' : '+${eur(valor)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens > 0
                              ? Colors.amber.shade800
                              : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  DateTime _weekStart() {
    final now = DateTime.now().toUtc();
    final weekday = now.weekday;
    return DateTime.utc(now.year, now.month, now.day - (weekday - 1));
  }

  int get _maxConvertibleNow {
    // 50% do saldo de tokens NO MOMENTO
    return (_tokens * 0.5).floor();
  }

  Future<void> _showConvertDialog() async {
    if (_maxConvertibleNow <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem tokens suficientes para converter.')),
      );
      return;
    }

    int amount = _maxConvertibleNow;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final eur = amount * BRTokens.TOKEN_VALUE_EUR;
          return AlertDialog(
            title: const Text('Converter Tokens → €'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo atual: $_tokens tokens'),
                Text('Máximo: $_maxConvertibleNow tokens '
                    '(50% do saldo, limite por semana)'),
                const SizedBox(height: 12),
                Slider(
                  value: amount.toDouble(),
                  min: 1,
                  max: _maxConvertibleNow.toDouble(),
                  divisions:
                      _maxConvertibleNow > 1 ? _maxConvertibleNow - 1 : 1,
                  label: '$amount',
                  onChanged: (v) => setDialog(() => amount = v.round()),
                ),
                Text(
                  '$amount tokens = €${eur.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Será incluído no pagamento semanal.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _convertTokens(amount);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _convertTokens(int tokensToConvert) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final supabase = Supabase.instance.client;
      // B3b (2026-06-12): conversão atómica server-side com cap SEMANAL
      // (token_withdrawal_max_pct_weekly, 50% do saldo por semana).
      // Substitui consume_tokens + inserts manuais — o fluxo antigo permitia
      // sacar 50%+50%+50%… do saldo restante até esvaziar tudo na mesma
      // semana. A RPC valida, consome, regista driver_transactions e credita
      // driver_balances numa única transação.
      final res = await supabase.rpc(
        'driver_convert_tokens',
        params: {'p_amount': tokensToConvert},
      );
      final amountEur =
          ((res as Map)['amount_eur'] as num?)?.toDouble() ??
              tokensToConvert * BRTokens.TOKEN_VALUE_EUR;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Convertidos $tokensToConvert tokens → €${amountEur.toStringAsFixed(2)}'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final String friendly;
      if (msg.contains('token_withdrawal_weekly_cap_exceeded')) {
        friendly =
            'Limite semanal atingido. Podes sacar mais na próxima semana.';
      } else if (msg.contains('INSUFFICIENT_TOKENS')) {
        friendly = 'Tokens insuficientes.';
      } else {
        friendly = 'Erro: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
    }
  }

  Duration? get _priorityRemaining {
    if (_priorityUntil == null) return null;
    final diff = _priorityUntil!.difference(DateTime.now().toUtc());
    return diff.isNegative ? null : diff;
  }

  Future<void> _buyPriority(String key, int minutes, int cost) async {
    if (_tokens < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tokens insuficientes.')),
      );
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final supabase = Supabase.instance.client;
      final consumed = await supabase.rpc(
            'consume_tokens',
            params: {'p_user_id': uid, 'p_amount': cost},
          ) as bool? ??
          false;

      if (!consumed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tokens insuficientes.')),
        );
        return;
      }

      final nowUtc = DateTime.now().toUtc();
      final base = (_priorityUntil != null && _priorityUntil!.isAfter(nowUtc))
          ? _priorityUntil!
          : nowUtc;
      final newUntil = base.add(Duration(minutes: minutes));

      // F5.4 (doença id/user_id): o SELECT acima já tolera as duas chaves mas
      // este UPDATE ficava em .eq('id', uid) — conta com id≠user_id consumia
      // os tokens e o update não encontrava a linha (prioridade nunca ativava).
      await supabase
          .from('drivers')
          .update({'priority_until': newUntil.toIso8601String()})
          .or('id.eq.$uid,user_id.eq.$uid');

      if (!mounted) return;
      final local = newUntil.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prioridade activa até $hh:$mm!')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: BoraScreenAppBar(
        title: 'Ganhos',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _load,
                            child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // F6 (2026-08-16): GANHOS UNIFICADOS (padrão Uber/Bolt)
                      // — total do DIA no topo + extrato TVDE/entregas/tokens,
                      // tudo da RPC driver_earnings_summary (servidor soma).
                      if (_resumo != null) ...[
                        _resumoUnificado(),
                        const SizedBox(height: 20),
                      ],
                      // FASE 4: card semanal (settlement Lisbon TZ) — fonte
                      // única de saldo, ganhos e detalhe por pedido.
                      const WeeklySettlementCard(),
                      const SizedBox(height: 20),
                      _TokenSection(
                        tokens: _tokens,
                        weeklyConverted: _weeklyTokensConverted,
                        maxConvertibleNow: _maxConvertibleNow,
                        onConvert: _showConvertDialog,
                      ),
                      const SizedBox(height: 16),
                      _PrioritySection(
                        tokens: _tokens,
                        priorityRemaining: _priorityRemaining,
                        costs: _priorityCosts,
                        onBuy: _buyPriority,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _TokenSection extends StatelessWidget {
  const _TokenSection({
    required this.tokens,
    required this.weeklyConverted,
    required this.maxConvertibleNow,
    required this.onConvert,
  });

  final int tokens;
  final int weeklyConverted;
  final int maxConvertibleNow;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final eur = tokens * BRTokens.TOKEN_VALUE_EUR;
    final canConvert = maxConvertibleNow > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                '$tokens tokens (€${eur.toStringAsFixed(2)})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Convertidos esta semana: $weeklyConverted tokens',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: canConvert ? onConvert : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(canConvert
                  ? 'Converter Tokens → €'
                  : 'Limite semanal atingido'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrioritySection extends StatelessWidget {
  const _PrioritySection({
    required this.tokens,
    required this.priorityRemaining,
    required this.costs,
    required this.onBuy,
  });

  final int tokens;
  final Duration? priorityRemaining;
  final Map<String, int> costs;
  final void Function(String key, int minutes, int cost) onBuy;

  @override
  Widget build(BuildContext context) {
    final options = <_PriorityOption>[
      _PriorityOption('5min', '5 min', 5, costs['5min'] ?? 50),
      _PriorityOption('10min', '10 min', 10, costs['10min'] ?? 90),
      _PriorityOption('15min', '15 min', 15, costs['15min'] ?? 125),
      _PriorityOption('1hour', '1 hora', 60, costs['1hour'] ?? 400),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.primaryMid.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on, color: AppColors.primaryMid, size: 22),
              SizedBox(width: 8),
              Text(
                'Activar Prioridade',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (priorityRemaining != null) ...[
            const SizedBox(height: 6),
            Text(
              'Prioridade activa: ${_fmt(priorityRemaining!)} restantes',
              style: const TextStyle(
                color: AppColors.primaryMid,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: options.map((opt) {
              final enabled = tokens >= opt.cost;
              return ElevatedButton(
                onPressed: enabled
                    ? () => onBuy(opt.key, opt.minutes, opt.cost)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMid,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      opt.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      '${opt.cost} tokens',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return '${d.inHours}h ${m}min';
    }
    return '${d.inMinutes} min';
  }
}

class _PriorityOption {
  const _PriorityOption(this.key, this.label, this.minutes, this.cost);
  final String key;
  final String label;
  final int minutes;
  final int cost;
}

