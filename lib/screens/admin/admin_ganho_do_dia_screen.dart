import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora.dart';

/// PAINEL ADMIN — Ganho do dia por pessoa (PT-BR, só o Danilo).
///
/// A tela "Acerto semanal por pessoa" responde pela SEMANA. Esta responde pelo
/// DIA: quanto é que cada prestador fez hoje (ou em qualquer dia escolhido)
/// somando tudo o que ele faz — entregas, corridas, limpeza e lavagem —, com
/// o detalhe por papel, filtro de data e exportação.
///
/// Não calcula nada. Lê `admin_ganho_do_dia`, que lê a visão diária.
class AdminGanhoDoDiaScreen extends StatefulWidget {
  const AdminGanhoDoDiaScreen({super.key});

  @override
  State<AdminGanhoDoDiaScreen> createState() => _AdminGanhoDoDiaScreenState();
}

class _AdminGanhoDoDiaScreenState extends State<AdminGanhoDoDiaScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _erro;
  DateTime _dia = DateTime.now();
  int _totalCents = 0;
  int _pessoas = 0;
  List<Map<String, dynamic>> _itens = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _diaIso =>
      '${_dia.year.toString().padLeft(4, '0')}-'
      '${_dia.month.toString().padLeft(2, '0')}-'
      '${_dia.day.toString().padLeft(2, '0')}';

  String get _diaBr =>
      '${_dia.day.toString().padLeft(2, '0')}/'
      '${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';

  String _eur(num cents) =>
      '€${(cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res =
          await _sb.rpc('admin_ganho_do_dia', params: {'p_dia': _diaIso});
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _totalCents = (m['total_cents'] as num?)?.toInt() ?? 0;
        _pessoas = (m['pessoas'] as num?)?.toInt() ?? 0;
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

  Future<void> _escolherDia() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Escolha o dia',
    );
    if (d == null) return;
    setState(() => _dia = d);
    await _load();
  }

  Future<void> _exportar() async {
    if (_itens.isEmpty) return;
    final headers = [
      'dia',
      'nome',
      'email',
      'telefone',
      'trabalhos',
      'total_cents',
      'detalhe_por_papel',
    ];
    final rows = _itens
        .map((i) => [
              _diaIso,
              i['nome'] ?? '',
              i['email'] ?? '',
              i['telefone'] ?? '',
              i['trabalhos_total'] ?? 0,
              i['total_cents'] ?? 0,
              ((i['por_papel'] as List?) ?? [])
                  .map((p) =>
                      '${(p as Map)['titulo']}=${((p['cents'] as num?) ?? 0) / 100}')
                  .join(' | '),
            ])
        .toList();
    await AdminExportService.instance.exportCsv(
      filename: 'bora_ganho_do_dia_$_diaIso.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Ganho do dia $_diaBr',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Ganho do dia por pessoa'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: [
                  _Cabecalho(
                    diaBr: _diaBr,
                    total: _eur(_totalCents),
                    pessoas: _pessoas,
                    onTrocarDia: _escolherDia,
                    onExportar: _itens.isEmpty ? null : _exportar,
                  ),
                  const SizedBox(height: Spacing.lg),
                  if (_erro != null)
                    Container(
                      padding: const EdgeInsets.all(Spacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Text('Falhou: $_erro'),
                    )
                  else if (_itens.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                      child: Center(
                        child: Text(
                          'Ninguém trabalhou em $_diaBr.',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 15),
                        ),
                      ),
                    )
                  else
                    for (final i in _itens)
                      _LinhaPessoa(item: i, formatar: _eur),
                ],
              ),
            ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.diaBr,
    required this.total,
    required this.pessoas,
    required this.onTrocarDia,
    required this.onExportar,
  });

  final String diaBr;
  final String total;
  final int pessoas;
  final VoidCallback onTrocarDia;
  final VoidCallback? onExportar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(diaBr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppColors.textPrimary)),
              ),
              TextButton.icon(
                onPressed: onTrocarDia,
                icon: const Icon(Icons.edit_calendar, size: 18),
                label: const Text('Trocar dia'),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text('$total pagos no dia · $pessoas pessoa(s)',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExportar,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Exportar CSV'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaPessoa extends StatelessWidget {
  const _LinhaPessoa({required this.item, required this.formatar});

  final Map<String, dynamic> item;
  final String Function(num) formatar;

  @override
  Widget build(BuildContext context) {
    final papeis = ((item['por_papel'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
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
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary)),
                    Text(
                      [
                        (item['email'] ?? '').toString(),
                        (item['telefone'] ?? '').toString(),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(formatar((item['total_cents'] as num?) ?? 0),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          for (final p in papeis)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: AppColors.textSubtle),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      '${p['titulo']} · ${p['trabalhos']} trabalho(s)',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  Text(formatar((p['cents'] as num?) ?? 0),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
