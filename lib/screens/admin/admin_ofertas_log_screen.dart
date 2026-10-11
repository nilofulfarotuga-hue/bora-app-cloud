import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart';
import '../../widgets/admin/admin_ofertas_do_pedido_section.dart';
import '../../widgets/bora/bora.dart';

/// PAINEL ADMIN — Ofertas e chamadas (PT-BR, só o Danilo).
///
/// Nasceu do teste ao vivo de 2026-08-29 (limpeza e lavagem): a rodada
/// ofereceu o trabalho a prestadores **sem nenhum aparelho registrado**,
/// esperou a janela inteira e só depois passou adiante. Não havia nenhum
/// lugar onde ver isso.
///
/// Desde 10/10/2026 (migração 20261010063000) o mesmo registro cobre também
/// **entregas, Favores e corridas TVDE**: para quem foi cada oferta, em que
/// fase (online, desligado, chamada de reforço…), se a pessoa estava online,
/// se tinha aparelho, se o toque foi entregue ao FCM (serviço de
/// notificações do Google), quanto tempo teve e como acabou. Tocar numa
/// linha mostra todas as chamadas desse pedido.
class AdminOfertasLogScreen extends StatefulWidget {
  const AdminOfertasLogScreen({super.key});

  @override
  State<AdminOfertasLogScreen> createState() => _AdminOfertasLogScreenState();
}

class _AdminOfertasLogScreenState extends State<AdminOfertasLogScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _erro;
  bool _semServidor = false;
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
      _semServidor = false;
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
        _semServidor = servidorAindaSemIsto(e);
        _erro = _semServidor ? null : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportar() async {
    if (_itens.isEmpty) return;
    await AdminExportService.instance.exportCsv(
      filename: 'bora_ofertas_${_categoria ?? 'todas'}_${_dias}d.csv',
      headers: const [
        'categoria', 'pedido_ref', 'booking_id', 'nome', 'fase',
        'estava_online', 'tem_aparelho', 'janela_s', 'push_enviados',
        'push_aparelhos', 'push_em', 'oferecida_em', 'desfecho', 'fechada_em',
      ],
      rows: _itens
          .map((i) => [
                i['categoria'] ?? '',
                i['pedido_ref'] ?? '',
                i['booking_id'] ?? '',
                i['nome'] ?? '',
                i['fase'] ?? '',
                i['estava_online'] == null
                    ? ''
                    : (i['estava_online'] == true ? 'sim' : 'nao'),
                i['tem_aparelho'] == true ? 'sim' : 'nao',
                i['janela_s'] ?? ((i['janela_min'] as num?) ?? 0) * 60,
                i['push_enviados'] ?? '',
                i['push_aparelhos'] ?? '',
                i['push_em'] ?? '',
                i['oferecida_em'] ?? '',
                i['desfecho'] ?? '',
                i['fechada_em'] ?? '',
              ])
          .toList(),
      subject: 'Bora — Ofertas e chamadas',
    );
  }

  void _abrirPedido(Map<String, dynamic> o) {
    final ref = '${o['pedido_ref'] ?? o['booking_id'] ?? ''}'.trim();
    if (ref.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text(
              '${categoriaEmPalavras(o['categoria'])} · '
              '#${ref.length > 8 ? ref.substring(0, 8) : ref}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.sm),
            AdminOfertasDoPedidoSection(pedidoRef: ref),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semAparelho = (_resumo['sem_aparelho'] as num?)?.toInt() ?? 0;
    final total = (_resumo['total'] as num?)?.toInt() ?? 0;
    final reforco = (_resumo['reforco'] as num?)?.toInt();
    final toqueFalhou = (_resumo['toque_falhou'] as num?)?.toInt();
    final novoAtivo = registroNovoAtivo(_resumo);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Ofertas e chamadas',
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
          : _semServidor
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.xl),
                    child: Text(kAindaNaoAtivo,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSubtle)),
                  ),
                )
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
                                  DropdownMenuItem(
                                      value: null, child: Text('Todas')),
                                  DropdownMenuItem(
                                      value: 'entrega',
                                      child: Text('Entregas')),
                                  DropdownMenuItem(
                                      value: 'favor', child: Text('Favores')),
                                  DropdownMenuItem(
                                      value: 'tvde', child: Text('TVDE')),
                                  DropdownMenuItem(
                                      value: 'limpeza',
                                      child: Text('Limpeza')),
                                  DropdownMenuItem(
                                      value: 'lavagem',
                                      child: Text('Lavagem')),
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
                                  DropdownMenuItem(
                                      value: 1, child: Text('24 h')),
                                  DropdownMenuItem(
                                      value: 7, child: Text('7 dias')),
                                  DropdownMenuItem(
                                      value: 30, child: Text('30 dias')),
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
                        // O servidor antigo só regista limpeza e lavagem.
                        if (!novoAtivo)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                                Spacing.md, 0, Spacing.md, Spacing.sm),
                            child: Text(
                              'Entregas, Favores e TVDE: $kAindaNaoAtivo '
                              '(por enquanto só aparecem limpeza e lavagem).',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSubtle),
                            ),
                          ),
                        // O número que interessa: quantas ofertas foram para
                        // quem não tinha como ser avisado.
                        if (total > 0)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(
                                horizontal: Spacing.md),
                            padding: const EdgeInsets.all(Spacing.md),
                            decoration: BoxDecoration(
                              color: semAparelho > 0 || (toqueFalhou ?? 0) > 0
                                  ? AppColors.warning.withValues(alpha: .12)
                                  : AppColors.primaryWash,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Text(
                              '$total oferta(s) · $semAparelho para quem não '
                              'tinha aparelho · ${_resumo['aceites'] ?? 0} '
                              'aceita(s)'
                              '${reforco == null ? '' : ' · $reforco chamada(s) de reforço'}'
                              '${toqueFalhou == null ? '' : ' · $toqueFalhou toque(s) não entregue(s) ao FCM'}',
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
                                      style: TextStyle(
                                          color: AppColors.textSubtle)))
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.md),
                                  itemCount: _itens.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) =>
                                      _linha(_itens[i]),
                                ),
                        ),
                      ],
                    ),
    );
  }

  Widget _linha(Map<String, dynamic> o) {
    final semApp = o['tem_aparelho'] != true;
    final desfecho = (o['desfecho'] ?? '').toString();
    final temFase = '${o['fase'] ?? ''}'.isNotEmpty;
    final enviados = o['push_enviados'];
    final toqueFalhou = enviados is num && enviados == 0;
    final online = o['estava_online'];
    return ListTile(
      dense: true,
      onTap: () => _abrirPedido(o),
      leading: Icon(
        semApp ? Icons.phonelink_erase : Icons.smartphone,
        color: semApp ? AppColors.error : AppColors.primary,
      ),
      title: Text(
        '${o['nome']} · ${categoriaEmPalavras(o['categoria'])}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${dataHoraLisboa(o['oferecida_em'])}'
        ' · teve ${janelaEmPalavras(o['janela_s'] ?? ((o['janela_min'] as num?) ?? 0) * 60)}'
        '${temFase ? ' · fase: ${faseEmPalavras(o['fase'])}' : ''}'
        '${online == null ? '' : ' · ${online == true ? 'estava online' : 'estava desligado'}'}'
        '${enviados == null ? '' : ' · toque entregue: ${toqueEntregueEmPalavras(enviados, o['push_aparelhos'])}'}'
        '${semApp ? ' · SEM APARELHO' : ''}',
        style: TextStyle(
            fontSize: 12, color: toqueFalhou ? AppColors.error : null),
      ),
      trailing: Text(
        desfechoEmPalavras(desfecho),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: desfecho == 'aceite' ? AppColors.primary : AppColors.textSubtle,
        ),
      ),
    );
  }
}
