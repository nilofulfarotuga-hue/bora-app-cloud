import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora.dart';

/// PAINEL ADMIN — Acerto semanal unificado (PT-BR, só o Danilo).
///
/// A diferença para a tela "Acertos da semana" que já existia: aqui **cada
/// pessoa aparece UMA vez só**, com tudo o que ela fez na semana somado —
/// entregas, corridas, limpeza e lavagem — a dívida abatida, e um único número
/// final. A tela antiga listava por papel, e por isso quem faz duas coisas
/// aparecia duas vezes; a lavagem não aparecia de todo.
///
/// Não calcula nada. Lê `admin_acerto_unificado`, que lê a view.
class AdminAcertoUnificadoScreen extends StatefulWidget {
  const AdminAcertoUnificadoScreen({super.key});

  @override
  State<AdminAcertoUnificadoScreen> createState() =>
      _AdminAcertoUnificadoScreenState();
}

class _AdminAcertoUnificadoScreenState
    extends State<AdminAcertoUnificadoScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _busy = false;
  String? _erro;
  String? _semana;
  List<String> _semanas = const [];
  List<Map<String, dynamic>> _itens = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await _sb
          .rpc('admin_acerto_unificado', params: {'p_semana': _semana});
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _semana = m['semana']?.toString();
        _semanas =
            ((m['semanas'] as List?) ?? []).map((e) => e.toString()).toList();
        _itens = ((m['itens'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  String _eur(num cents) =>
      '€${(cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _marcarPago(Map<String, dynamic> item) async {
    if (_busy) return;
    final nome = (item['nome'] ?? '').toString();
    final total = (item['total_cents'] as num?)?.toInt() ?? 0;
    final deve = total < 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como pago'),
        content: Text(
          deve
              ? 'Confirma que $nome já quitou os ${_eur(total)} que devia '
                  'nesta semana?\n\nIsso marca todos os acertos dela na '
                  'semana como pagos. Não altera nenhum valor.'
              : 'Confirma que já pagou ${_eur(total)} a $nome?\n\nIsso marca '
                  'todos os acertos dela na semana como pagos. Não altera '
                  'nenhum valor.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await _sb.rpc('admin_marcar_acerto_pago', params: {
        'p_user_id': item['user_id'],
        'p_semana': _semana,
      });
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${m['linhas']} acerto(s) marcado(s) como pago.'),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falhou: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportar() async {
    if (_itens.isEmpty) return;
    final headers = [
      'semana',
      'nome',
      'email',
      'telefone',
      'trabalhos',
      'a_receber_cents',
      'divida_cents',
      'divida_por_abater_cents',
      'total_cents',
      'sentido',
      'tudo_pago',
      'detalhe_por_papel',
    ];
    final rows = _itens
        .map((i) => [
              _semana ?? '',
              i['nome'] ?? '',
              i['email'] ?? '',
              i['telefone'] ?? '',
              i['trabalhos_total'] ?? 0,
              i['a_receber_cents'] ?? 0,
              i['divida_cents'] ?? 0,
              i['divida_por_abater_cents'] ?? 0,
              i['total_cents'] ?? 0,
              i['sentido'] ?? '',
              i['tudo_pago'] == true ? 'sim' : 'nao',
              (i['detalhe'] ?? {}).toString(),
            ])
        .toList();
    await AdminExportService.instance.exportCsv(
      filename: 'bora_acerto_semanal_${_semana ?? 'atual'}.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Acerto semanal ${_semana ?? ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final aPagar = _itens
        .where((i) => ((i['total_cents'] as num?) ?? 0) > 0)
        .fold<int>(0, (s, i) => s + ((i['total_cents'] as num).toInt()));
    final aReceber = _itens
        .where((i) => ((i['total_cents'] as num?) ?? 0) < 0)
        .fold<int>(0, (s, i) => s + ((i['total_cents'] as num).toInt()));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Acerto semanal',
        actions: [
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar CSV',
              onPressed: _itens.isEmpty ? null : _exportar),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Text('Erro: $_erro',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Row(
                        children: [
                          const Text('Semana:  '),
                          DropdownButton<String>(
                            value: _semanas.contains(_semana) ? _semana : null,
                            hint: const Text('escolher'),
                            items: _semanas
                                .map((s) => DropdownMenuItem(
                                    value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) {
                              setState(() => _semana = v);
                              _load();
                            },
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('A pagar: ${_eur(aPagar)}',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                              Text('A receber: ${_eur(aReceber)}',
                                  style: const TextStyle(
                                      color: AppColors.error, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _itens.isEmpty
                          ? const Center(
                              child: Text(
                                  'Nenhum acerto nesta semana.',
                                  style:
                                      TextStyle(color: AppColors.textSubtle)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(Spacing.md),
                              itemCount: _itens.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: Spacing.sm),
                              itemBuilder: (_, i) => _LinhaPessoa(
                                item: _itens[i],
                                eur: _eur,
                                busy: _busy,
                                onMarcarPago: () => _marcarPago(_itens[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _LinhaPessoa extends StatelessWidget {
  const _LinhaPessoa({
    required this.item,
    required this.eur,
    required this.busy,
    required this.onMarcarPago,
  });

  final Map<String, dynamic> item;
  final String Function(num) eur;
  final bool busy;
  final VoidCallback onMarcarPago;

  static const _titulos = <String, String>{
    'driver': 'Entregas e corridas',
    'cleaner': 'Limpeza',
    'washer': 'Lavagem',
  };

  @override
  Widget build(BuildContext context) {
    final total = (item['total_cents'] as num?)?.toInt() ?? 0;
    final divida = (item['divida_cents'] as num?)?.toInt() ?? 0;
    final porAbater = (item['divida_por_abater_cents'] as num?)?.toInt() ?? 0;
    final pago = item['tudo_pago'] == true;
    final detalhe = (item['detalhe'] as Map?)?.cast<String, dynamic>() ?? {};
    final sentido = (item['sentido'] ?? 'zero').toString();

    final cor = switch (sentido) {
      'bora_paga' => AppColors.primary,
      'pessoa_deve' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
            color: pago ? AppColors.primary : AppColors.divider,
            width: pago ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((item['nome'] ?? '').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(
                      [
                        (item['email'] ?? '').toString(),
                        (item['telefone'] ?? '').toString(),
                      ].where((s) => s.isNotEmpty).join('  ·  '),
                      style: const TextStyle(
                          color: AppColors.textSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(eur(total),
                      style: TextStyle(
                          color: cor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text(
                    switch (sentido) {
                      'bora_paga' => 'Bora paga',
                      'pessoa_deve' => 'deve à Bora',
                      _ => 'zerado',
                    },
                    style: TextStyle(color: cor, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          // O detalhe por tipo de trabalho — é o que prova que a soma é a
          // soma de tudo o que a pessoa fez, e não de um papel só.
          Wrap(
            spacing: Spacing.sm,
            runSpacing: 4,
            children: [
              for (final e in detalhe.entries)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    '${_titulos[e.key] ?? e.key}: '
                    '${eur(((e.value as Map)['liquido_cents'] as num?) ?? 0)}'
                    ' (${(e.value as Map)['trabalhos'] ?? 0})',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textPrimary),
                  ),
                ),
              if (divida > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    porAbater > 0
                        ? 'dívida abatida: ${eur(divida)}'
                        : 'dívida (já dentro do líquido): ${eur(divida)}',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: pago
                ? const Text('Pago',
                    style: TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w700))
                : OutlinedButton.icon(
                    onPressed: busy ? null : onMarcarPago,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Marcar como pago'),
                  ),
          ),
        ],
      ),
    );
  }
}
