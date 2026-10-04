import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — Gorjetas (missão 03/10 · bloco 3).
///
/// Todas as gorjetas: quem deu, a quem, quanto, quando, por onde e o estado.
/// Ligar/desligar (`tips_enabled`), exportar CSV e reembolsar (Edge Function
/// `charge-tip`, ação `refund`, idempotente). 100% vai para o prestador.
class AdminGorjetasScreen extends StatefulWidget {
  const AdminGorjetasScreen({super.key});

  @override
  State<AdminGorjetasScreen> createState() => _AdminGorjetasScreenState();
}

class _AdminGorjetasScreenState extends State<AdminGorjetasScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = const [];
  bool? _ligada;
  bool _aMudar = false;
  String? _aReembolsar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_listar_gorjetas');
      final flag = await _sb.rpc('get_setting', params: {'p_key': 'tips_enabled'});
      if (!mounted) return;
      setState(() {
        _linhas = List<Map<String, dynamic>>.from(res as List);
        _ligada = flag?.toString() == 'true';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _mudarLigada(bool v) async {
    if (_aMudar) return;
    setState(() => _aMudar = true);
    try {
      await _sb
          .from('platform_settings')
          .update({'value': v})
          .eq('key', 'tips_enabled');
      if (mounted) setState(() => _ligada = v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu para mudar: $e')));
      }
    } finally {
      if (mounted) setState(() => _aMudar = false);
    }
  }

  Future<void> _reembolsar(Map<String, dynamic> l) async {
    final id = l['id'] as String;
    if (_aReembolsar != null) return;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reembolsar gorjeta?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_eur(l['valor_cents'])} de ${l['cliente_nome']} para ${l['prestador_nome']}. '
                'Volta inteira para o cliente.'),
            TextField(
              controller: motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reembolsar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aReembolsar = id);
    try {
      final r = await _sb.functions.invoke('charge-tip', body: {
        'action': 'refund',
        'tipId': id,
        'reason': motivo.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((r.data as Map)['ok'] == true
              ? 'Gorjeta reembolsada.'
              : 'Não reembolsou: ${r.data}')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro no reembolso: $e')));
      }
    } finally {
      if (mounted) setState(() => _aReembolsar = null);
    }
  }

  Future<void> _exportar() async {
    if (_linhas.isEmpty) return;
    const cols = [
      'id', 'criada_em', 'paga_em', 'alvo', 'pedido', 'corrida', 'cliente_nome',
      'prestador_nome', 'valor_cents', 'metodo', 'momento', 'estado', 'stripe_pi',
      'taxa_stripe_cents', 'reembolsada_em', 'motivo_reembolso',
    ];
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_gorjetas_$stamp.csv',
      headers: cols,
      rows: _linhas.map((l) => cols.map((c) => l[c] ?? '').toList()).toList(),
      subject: 'Bora — Gorjetas $stamp',
    );
  }

  String _eur(dynamic cents) =>
      '€ ${(((cents as num?) ?? 0) / 100).toStringAsFixed(2)}';

  String _estado(String? s) => switch (s) {
        'succeeded' => 'paga',
        'cash_due' => 'em dinheiro (a entregar)',
        'cash_collected' => 'em dinheiro (entregue)',
        'requires_action' => 'à espera do cliente',
        'pending' => 'pendente',
        'failed' => 'falhou',
        'refunded' => 'reembolsada',
        'cancelled' => 'cancelada',
        _ => s ?? '-',
      };

  @override
  Widget build(BuildContext context) {
    final pagas = _linhas.where((l) =>
        l['estado'] == 'succeeded' || l['estado'] == 'cash_collected');
    final total =
        pagas.fold<num>(0, (s, l) => s + ((l['valor_cents'] as num?) ?? 0));
    final taxas = pagas.fold<num>(
        0, (s, l) => s + ((l['taxa_stripe_cents'] as num?) ?? 0));
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Gorjetas',
        actions: [
          IconButton(
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download),
              onPressed: _exportar),
          IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _carregar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro ao carregar: $_erro')))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SwitchListTile(
                        value: _ligada ?? false,
                        onChanged: _aMudar ? null : _mudarLigada,
                        title: const Text('Gorjetas ligadas na app'),
                        subtitle: const Text(
                            'Checkout, avaliação da entrega e fim da corrida TVDE. '
                            'Desligado = o cliente não vê a opção.'),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${pagas.length} gorjetas pagas · ${_eur(total)} para os prestadores'
                            ' · taxas Stripe ${_eur(taxas)} (últimos 90 dias)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (_linhas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhuma gorjeta nos últimos 90 dias.'),
                        ),
                      for (final l in _linhas)
                        Card(
                          child: ListTile(
                            title: Text(
                                '${_eur(l['valor_cents'])} · ${l['cliente_nome']} → ${l['prestador_nome']}'),
                            subtitle: Text(
                                '${l['alvo'] == 'tvde' ? 'Corrida' : 'Pedido'} '
                                '${(l['pedido'] ?? l['corrida'] ?? '').toString().split('-').first}'
                                ' · ${l['metodo']} · ${l['momento'] == 'checkout' ? 'no checkout' : 'depois'}'
                                ' · ${_estado(l['estado'] as String?)}'
                                '\n${(l['criada_em'] ?? '').toString().replaceFirst('T', ' ').split('.').first}'),
                            isThreeLine: true,
                            trailing: l['estado'] == 'succeeded'
                                ? TextButton(
                                    onPressed: _aReembolsar != null
                                        ? null
                                        : () => _reembolsar(l),
                                    child: _aReembolsar == l['id']
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Text('Reembolsar',
                                            style: TextStyle(
                                                color: AppColors.error)),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
