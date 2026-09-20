// Contas claras (20/09/2026) — O VIGIA DO DINHEIRO (painel admin, PT-BR).
//
// Lista os achados do vigia diário (payment_reconciliation_findings): quem, quanto,
// qual arca discorda de qual. O vigia só aponta; aqui o Danilo lê, decide e marca
// como resolvido com uma nota (fica auditado). "Correr agora" chama o vigia à mão.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminVigiaDinheiroScreen extends StatefulWidget {
  const AdminVigiaDinheiroScreen({super.key});

  @override
  State<AdminVigiaDinheiroScreen> createState() => _AdminVigiaDinheiroScreenState();
}

class _AdminVigiaDinheiroScreenState extends State<AdminVigiaDinheiroScreen> {
  bool _soAbertos = true;
  bool _loading = true;
  bool _busy = false;
  String? _erro;
  int _abertos = 0;
  List<Map<String, dynamic>> _lista = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String eur(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt();
    final abs = n.abs();
    return '${n < 0 ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
  }

  static String _kindTxt(String? k) => switch (k) {
        'saldo_vs_historico' => 'Carteira: histórico ≠ saldo',
        'vigia_entregas_saldo' => 'Entregas: histórico ≠ saldo',
        'vigia_tvde_saldo' => 'TVDE: eventos ≠ saldo',
        'vigia_ledger_snapshot' => 'Livro-razão ≠ snapshot',
        'vigia_parceiro_arcas' => 'Parceiro: livro-razão ≠ order_financials',
        'vigia_duplicado_carteira' => 'Carteira: linha repetida',
        'vigia_payout_parado' => 'Payout parado (acerto já pago)',
        'vigia_compensacao_fora_do_acerto' => 'Compensação fora do acerto',
        'pi_metadata_desconhecida' => 'Stripe: pagamento sem pedido ligado',
        'driver_snapshot_longe_do_dropoff' => 'Entrega confirmada longe da morada',
        'refund_prometido_sem_refund' => 'Reembolso prometido sem estorno',
        'ganho_sem_lancamento_no_ledger' => 'Entrega sem ganho no livro-razão',
        _ => k ?? '—',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('admin_vigia_achados',
          params: {'p_so_abertos': _soAbertos, 'p_limit': 300});
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] != true) throw Exception(m['error'] ?? 'sem resposta');
      if (!mounted) return;
      setState(() {
        _abertos = (m['abertos'] as num?)?.toInt() ?? 0;
        _lista = (m['lista'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = e.toString();
      });
    }
  }

  Future<void> _correrAgora() async {
    setState(() => _busy = true);
    try {
      final r = await Supabase.instance.client.rpc('admin_vigia_correr_agora');
      final m = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Vigia: ${m['casos']} casos, ${m['novos']} novos, '
              '${m['conhecidos_calados']} conhecidos (calados)'
              '${m['gritou'] == true ? ' — avisou no Telegram' : ''}')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolver(Map<String, dynamic> f) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como resolvido'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${_kindTxt(f['kind'] as String?)} · ${eur(f['amount_cents'])}'),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Nota (o que foi decidido)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resolvido')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_vigia_resolver',
          params: {'p_id': f['id'], 'p_nota': ctrl.text.trim().isEmpty ? null : ctrl.text.trim()});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Vigia do dinheiro — $_abertos por resolver'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: _soAbertos ? 'Mostrar todos' : 'Só abertos',
              onPressed: () {
                setState(() => _soAbertos = !_soAbertos);
                _load();
              },
              icon: Icon(_soAbertos ? Icons.filter_alt : Icons.filter_alt_off)),
          IconButton(
              tooltip: 'Correr o vigia agora',
              onPressed: _busy ? null : _correrAgora,
              icon: const Icon(Icons.play_circle_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'O vigia corre todos os dias às 06:10, compara histórico com saldo em todas as arcas '
                            '(carteiras, entregas, TVDE, livro-razão, parceiros, payouts) e só avisa no Telegram '
                            'quando aparece caso novo. Ele não corrige nada: você decide e marca aqui.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      if (_lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nada por resolver. As contas batem.')),
                        ),
                      for (final f in _lista) _card(f),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final d = Map<String, dynamic>.from(f['details'] as Map? ?? {});
    final resolvido = f['resolved_at'] != null;
    final sev = f['severity'] as String?;
    final cor = resolvido
        ? AppColors.textSecondary
        : (sev == 'critical' ? AppColors.error : AppColors.warning);
    final quem = d['quem'] ?? f['entity_id'];
    final detalhes = d.entries
        .where((e) => !['quem', 'origem', 'primeira_vez', 'reaberto_em', 'resolvido_por', 'resolvido_em', 'nota_resolucao'].contains(e.key))
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(resolvido ? Icons.check_circle : Icons.warning_amber_rounded, color: cor, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_kindTxt(f['kind'] as String?),
                    style: TextStyle(fontWeight: FontWeight.w800, color: cor))),
            Text(eur(f['amount_cents']),
                style: TextStyle(fontWeight: FontWeight.w800, color: cor)),
          ]),
          const SizedBox(height: 4),
          Text('$quem', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalhes.isNotEmpty)
            Text(detalhes, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (resolvido && d['nota_resolucao'] != null)
            Text('Resolvido: ${d['nota_resolucao']}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          if (!resolvido)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _resolver(f),
                icon: const Icon(Icons.done, size: 18),
                label: const Text('Marcar resolvido'),
              ),
            ),
        ]),
      ),
    );
  }
}
