import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/tvde/filtro_tipo_tvde.dart';

/// Painel admin (PT-BR) — 21/10/2026 (fechar-pendencias A1).
///
/// O acerto da semana do Bora Motorista partido por tipo: passageiros e
/// encomendas. SÓ LEITURA (`admin_tvde_acertos_por_tipo`): usa a mesma regra
/// do `compute_driver_settlement` para a parte TVDE (corridas finalizadas na
/// semana, ganho do motorista, dinheiro em mão, pago online, compensações de
/// cancelamento) + as gorjetas online das corridas (ronda 1 do revisor, 21/10). O acerto oficial continua a ser o "Acerto da semana" — este
/// separador só mostra de onde vem o dinheiro.
///
/// 30/10/2026 (gorjetas-taxa): as gorjetas vêm do servidor já líquidas
/// (`tips.liquido_prestador_cents`), ver [kRotuloGorjetasLiquidas].
class AdminTvdeAcertosTipoTab extends StatefulWidget {
  const AdminTvdeAcertosTipoTab({super.key});

  @override
  State<AdminTvdeAcertosTipoTab> createState() => _AdminTvdeAcertosTipoTabState();
}

/// Rótulo das gorjetas no acerto (30/10/2026, regra do Danilo): a gorjeta paga
/// depois com cartão/MB Way chega ao motorista sem a taxa exata da Stripe desse
/// pagamento; a do carrinho e a em dinheiro vêm inteiras.
const String kRotuloGorjetasLiquidas = 'Gorjetas (já sem a taxa da Stripe)';

/// Soma por tipo das linhas do RPC (função pura, testada).
/// `ganho` já inclui compensações e gorjetas online (vem assim do servidor).
Map<String, ({int corridas, int ganho, int dinheiro, int online, int gorjetas})>
    somarAcertosPorTipo(List<Map<String, dynamic>> linhas) {
  final out = <String, ({int corridas, int ganho, int dinheiro, int online, int gorjetas})>{};
  for (final l in linhas) {
    final t = tipoDaLinhaTvde(l);
    final a = out[t] ?? (corridas: 0, ganho: 0, dinheiro: 0, online: 0, gorjetas: 0);
    int n(String k) => (l[k] as num?)?.toInt() ?? 0;
    out[t] = (
      corridas: a.corridas + n('corridas'),
      ganho: a.ganho + n('ganho_cents'),
      dinheiro: a.dinheiro + n('dinheiro_em_mao_cents'),
      online: a.online + n('online_cents'),
      gorjetas: a.gorjetas + n('gorjetas_online_cents'),
    );
  }
  return out;
}

class _AdminTvdeAcertosTipoTabState extends State<AdminTvdeAcertosTipoTab>
    with AutomaticKeepAliveClientMixin {
  bool _semanaPassada = false;
  String _tipo = 'todos';
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = const [];
  String _semana = '';

  @override
  bool get wantKeepAlive => true;

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
      final ancora = _semanaPassada
          ? DateTime.now().toUtc().subtract(const Duration(days: 7))
          : DateTime.now().toUtc();
      final res = await Supabase.instance.client.rpc('admin_tvde_acertos_por_tipo',
          params: {'p_week_start': ancora.toIso8601String()});
      final m = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
      final linhas = ((m['linhas'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      String dia(Object? v) {
        final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
        return d == null
            ? '?'
            : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      }

      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _semana = '${dia(m['week_start'])} a ${dia(m['week_end'])}';
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

  String _eur(int c) => '€${(c / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _exportar(List<Map<String, dynamic>> linhas) async {
    if (linhas.isEmpty) return;
    await AdminExportService.instance.exportCsv(
      filename: 'bora_motorista_acerto_por_tipo_${_semana.replaceAll('/', '-').replaceAll(' ', '')}.csv',
      headers: const [
        'Motorista',
        'Tipo',
        'Corridas',
        'Ganho do motorista (€)',
        'Dinheiro em mão (€)',
        'Pago online (€)',
        'Compensações (€)',
        '$kRotuloGorjetasLiquidas (€)',
      ],
      rows: [
        for (final l in linhas)
          [
            l['driver_name'] ?? '',
            rotuloTipoTvde(tipoDaLinhaTvde(l)),
            l['corridas'] ?? 0,
            (((l['ganho_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            (((l['dinheiro_em_mao_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            (((l['online_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            (((l['compensacao_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            (((l['gorjetas_online_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
          ],
      ],
      subject: 'Bora Motorista — acerto por tipo ($_semana)',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Erro:\n$_erro', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo')),
          ]),
        ),
      );
    }
    final visiveis = filtrarPorTipoTvde(_linhas, _tipo);
    final somas = somarAcertosPorTipo(_linhas);
    Widget resumo(String tipo) {
      final s = somas[tipo];
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tipo == 'encomendas' ? '📦 Encomendas' : '🚗 Passageiros',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${s?.corridas ?? 0} corridas · ganho ${_eur(s?.ganho ?? 0)}'),
              Text('em mão ${_eur(s?.dinheiro ?? 0)} · online ${_eur(s?.online ?? 0)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text('$kRotuloGorjetasLiquidas: ${_eur(s?.gorjetas ?? 0)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Esta semana')),
                  ButtonSegment(value: true, label: Text('Semana passada')),
                ],
                selected: {_semanaPassada},
                onSelectionChanged: (s) {
                  setState(() => _semanaPassada = s.first);
                  _load();
                },
              ),
            ),
            IconButton(
              tooltip: 'Exportar CSV',
              onPressed: visiveis.isEmpty ? null : () => _exportar(visiveis),
              icon: const Icon(Icons.download),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Semana $_semana (hora de Lisboa). Só leitura — o acerto oficial é o "Acerto da semana".',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [resumo('passageiros'), resumo('encomendas')]),
          const SizedBox(height: 8),
          FiltroTipoTvde(
              linhas: _linhas,
              valor: _tipo,
              onChanged: (v) => setState(() => _tipo = v)),
          const SizedBox(height: 8),
          if (visiveis.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                  child: Text('Nada nesta semana com este filtro.',
                      style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            for (final l in visiveis)
              Card(
                child: ListTile(
                  title: Row(children: [
                    Expanded(child: Text(l['driver_name']?.toString() ?? '(sem nome)')),
                    EtiquetaEncomendaTvde(linha: l),
                  ]),
                  subtitle: Text(
                      '${l['corridas'] ?? 0} ${tipoDaLinhaTvde(l) == 'encomendas' ? 'encomendas' : 'corridas'}'
                      ' · em mão ${_eur((l['dinheiro_em_mao_cents'] as num?)?.toInt() ?? 0)}'
                      ' · online ${_eur((l['online_cents'] as num?)?.toInt() ?? 0)}'
                      '${((l['compensacao_cents'] as num?)?.toInt() ?? 0) > 0 ? ' · compensações ${_eur((l['compensacao_cents'] as num).toInt())}' : ''}'
                      '${((l['gorjetas_online_cents'] as num?)?.toInt() ?? 0) > 0 ? ' · $kRotuloGorjetasLiquidas: ${_eur((l['gorjetas_online_cents'] as num).toInt())}' : ''}'),
                  trailing: Text(_eur((l['ganho_cents'] as num?)?.toInt() ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
        ],
      ),
    );
  }
}
