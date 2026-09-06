import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora.dart';

/// PAINEL ADMIN — Ofertas de limpeza e lavagem (PT-BR, só o Danilo).
///
/// Nasceu do teste ao vivo de 2026-08-29: a rodada ofereceu o trabalho a
/// prestadores **sem nenhum aparelho registrado**, esperou a janela inteira e
/// só depois passou adiante. Não havia nenhum lugar onde ver isso — foi
/// preciso ir na mão nas tabelas para descobrir.
///
/// Agora cada oferta deixa uma linha: para quem foi, se essa pessoa tinha
/// aparelho, quanto tempo teve, e como acabou.
class AdminOfertasLogScreen extends StatefulWidget {
  const AdminOfertasLogScreen({super.key});

  @override
  State<AdminOfertasLogScreen> createState() => _AdminOfertasLogScreenState();
}

class _AdminOfertasLogScreenState extends State<AdminOfertasLogScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _erro;
  String? _categoria; // null = todas
  int _dias = 7;
  Map<String, dynamic> _resumo = const {};
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
      final res = await _sb.rpc('admin_ofertas_log', params: {
        'p_categoria': _categoria,
        'p_dias': _dias,
        'p_limite': 300,
      });
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _resumo = (m['resumo'] as Map?)?.cast<String, dynamic>() ?? {};
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

  Future<void> _exportar() async {
    if (_itens.isEmpty) return;
    await AdminExportService.instance.exportCsv(
      filename: 'bora_ofertas_${_categoria ?? 'todas'}_${_dias}d.csv',
      headers: const [
        'categoria', 'booking_id', 'nome', 'tem_aparelho',
        'janela_min', 'oferecida_em', 'desfecho', 'fechada_em',
      ],
      rows: _itens
          .map((i) => [
                i['categoria'] ?? '',
                i['booking_id'] ?? '',
                i['nome'] ?? '',
                i['tem_aparelho'] == true ? 'sim' : 'nao',
                i['janela_min'] ?? '',
                i['oferecida_em'] ?? '',
                i['desfecho'] ?? '',
                i['fechada_em'] ?? '',
              ])
          .toList(),
      subject: 'Bora — Ofertas de prestadores',
    );
  }

  @override
  Widget build(BuildContext context) {
    final semAparelho = (_resumo['sem_aparelho'] as num?)?.toInt() ?? 0;
    final total = (_resumo['total'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Ofertas de prestadores',
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
                          DropdownButton<String?>(
                            value: _categoria,
                            hint: const Text('Todas'),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('Todas')),
                              DropdownMenuItem(
                                  value: 'limpeza', child: Text('Limpeza')),
                              DropdownMenuItem(
                                  value: 'lavagem', child: Text('Lavagem')),
                            ],
                            onChanged: (v) {
                              setState(() => _categoria = v);
                              _load();
                            },
                          ),
                          const SizedBox(width: Spacing.md),
                          DropdownButton<int>(
                            value: _dias,
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('24 h')),
                              DropdownMenuItem(value: 7, child: Text('7 dias')),
                              DropdownMenuItem(value: 30, child: Text('30 dias')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _dias = v);
                              _load();
                            },
                          ),
                        ],
                      ),
                    ),
                    // O número que interessa: quantas ofertas foram para quem
                    // não tinha como ser avisado.
                    if (total > 0)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(
                            horizontal: Spacing.md),
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: semAparelho > 0
                              ? AppColors.warning.withValues(alpha: .12)
                              : AppColors.primaryWash,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Text(
                          '$total oferta(s) · $semAparelho para quem não tinha '
                          'aparelho · ${_resumo['aceites'] ?? 0} aceita(s)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    const SizedBox(height: Spacing.sm),
                    Expanded(
                      child: _itens.isEmpty
                          ? const Center(
                              child: Text('Nenhuma oferta nesse período.',
                                  style:
                                      TextStyle(color: AppColors.textSubtle)))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.md),
                              itemCount: _itens.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final o = _itens[i];
                                final semApp = o['tem_aparelho'] != true;
                                final desfecho =
                                    (o['desfecho'] ?? '').toString();
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    semApp
                                        ? Icons.phonelink_erase
                                        : Icons.smartphone,
                                    color: semApp
                                        ? AppColors.error
                                        : AppColors.primary,
                                  ),
                                  title: Text(
                                    '${o['nome']} · ${o['categoria']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${(o['oferecida_em'] ?? '').toString().replaceAll('T', ' ').split('.').first}'
                                    ' · janela ${o['janela_min']} min'
                                    '${semApp ? ' · SEM APARELHO' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    desfecho,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: desfecho == 'aceite'
                                          ? AppColors.primary
                                          : AppColors.textSubtle,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
