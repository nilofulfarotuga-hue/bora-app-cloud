import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — "Marcações por confirmar" e "Dinheiro retido por falta".
///
/// 2026-09-14 (missão painel-admin-limpo). Cicatriz: a 07/09 o robô marcou
/// falta automática à marcação do Cristiano na Ouro e Prata (12 € pagos) só
/// porque o barbeiro se esqueceu do botão, e o dinheiro ficou retido sem
/// ninguém saber. Agora a falta nunca é automática: fica "por confirmar" e
/// aparece aqui. Cada linha tem botões de UM toque:
///  · por confirmar: "Foi feita" · "Faltou" · "Perguntar de novo ao parceiro"
///  · retido por falta: "Reverter" (passa a feita e o valor volta ao acerto)
/// Depois de qualquer decisão que mexa no acerto, o ecrã recalcula o payout
/// semanal do parceiro (RPC já existente) e mostra o resultado.
class AdminMarcacoesConfirmacaoScreen extends StatefulWidget {
  const AdminMarcacoesConfirmacaoScreen({super.key, this.abaInicial = 0});

  /// 0 = por confirmar · 1 = dinheiro retido por falta.
  final int abaInicial;

  @override
  State<AdminMarcacoesConfirmacaoScreen> createState() =>
      _AdminMarcacoesConfirmacaoScreenState();
}

class _AdminMarcacoesConfirmacaoScreenState
    extends State<AdminMarcacoesConfirmacaoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _busy = false;
  List<Map<String, dynamic>> _porConfirmar = const [];
  List<Map<String, dynamic>> _retidas = const [];
  int _retidoTotalCents = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.abaInicial);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        _client.rpc('admin_list_appointments_awaiting_confirmation'),
        _client.rpc('admin_list_appointments_retained'),
      ]);
      final a = (res[0] as Map).cast<String, dynamic>();
      final r = (res[1] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _porConfirmar = ((a['items'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _retidas = ((r['items'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _retidoTotalCents = ((r['total_cents'] as num?) ?? 0).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar as marcações: $e';
        _loading = false;
      });
    }
  }

  String _eur(num cents) => '${(cents / 100).toStringAsFixed(2)} €';

  void _aviso(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  /// Chama o RPC de decisão e, se devolver a semana, recalcula o payout do
  /// parceiro para essa semana — é isso que põe o valor no acerto.
  Future<void> _decidir(String rpc, Map<String, dynamic> r,
      {String? nota, bool recalcular = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await _client.rpc(rpc, params: {
        'p_appointment_id': r['id'],
        if (nota != null) 'p_note': nota,
      });
      final m = res is Map ? res.cast<String, dynamic>() : const <String, dynamic>{};
      var extra = '';
      if (recalcular && m['week_start'] != null && m['provider_id'] != null) {
        try {
          final p = await _client.rpc('compute_provider_weekly_payout', params: {
            'p_provider_id': m['provider_id'],
            'p_week_start': m['week_start'],
            'p_persist': true,
          });
          final pm = p is Map ? p.cast<String, dynamic>() : const <String, dynamic>{};
          final net = (pm['net_payout_cents'] as num?) ?? 0;
          extra = ' Acerto do parceiro nessa semana: ${_eur(net)}.';
        } catch (e) {
          extra = ' (Não consegui recalcular o acerto: $e)';
        }
      }
      _aviso('Feito.$extra');
      await _load();
    } catch (e) {
      _aviso('Não deu: $e', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportar() async {
    final linhas = [
      ..._porConfirmar.map((r) => ['por confirmar', r]),
      ..._retidas.map((r) => ['retido por falta', r]),
    ];
    try {
      await AdminExportService.instance.exportCsv(
        filename: 'marcacoes-por-confirmar-e-retidas.csv',
        headers: const [
          'Situação',
          'Parceiro',
          'Cliente',
          'Telefone',
          'Marcada para',
          'Preço (EUR)',
          'Pago (EUR)',
          'Estado do pagamento',
          'Decidido por',
          'Perguntas ao parceiro',
        ],
        rows: linhas.map((l) {
          final r = l[1] as Map<String, dynamic>;
          return [
            l[0] as String,
            r['provider_name'] ?? '',
            r['client_name'] ?? '',
            r['client_phone'] ?? '',
            r['scheduled_label'] ?? '',
            (((r['service_price_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            (((r['deposit_cents'] as num?) ?? 0) / 100).toStringAsFixed(2),
            r['deposit_status'] ?? '',
            r['no_show_decided_by'] ?? '',
            (r['confirm_asked_count'] ?? '').toString(),
          ];
        }).toList(),
      );
    } catch (e) {
      _aviso('Não consegui exportar: $e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Marcações — confirmar e faltas',
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: (_porConfirmar.isEmpty && _retidas.isEmpty) ? null : _exportar,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Por confirmar (${_porConfirmar.length})'),
            Tab(text: 'Retido por falta (${_retidas.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Tentar de novo')),
                    ]),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _lista(
                      _porConfirmar,
                      vazio:
                          'Nenhuma marcação por confirmar. Quando um serviço acaba e o parceiro não diz se foi feito, aparece aqui — o dinheiro nunca é retido sozinho.',
                      cabecalho:
                          'O robô perguntou ao parceiro "feito ou faltou?". Sem resposta, fica aqui. Só você ou o parceiro podem marcar falta.',
                      acoes: (r) => [
                        _botao('Foi feita', Icons.check_circle_outline, AppColors.success,
                            () => _decidir('admin_appointment_confirm_done', r)),
                        _botao('Faltou', Icons.person_off_outlined, AppColors.error,
                            () => _confirmarFalta(r)),
                        _botao('Perguntar de novo', Icons.notifications_active_outlined,
                            AppColors.info,
                            () => _decidir('admin_appointment_ask_partner_again', r,
                                recalcular: false)),
                      ],
                    ),
                    _lista(
                      _retidas,
                      vazio: 'Nenhum dinheiro retido por falta. Bom sinal.',
                      cabecalho:
                          'Total retido: ${_eur(_retidoTotalCents)}. Reverter passa a marcação a feita e manda o valor para o acerto do parceiro (preço menos a taxa da Bora).',
                      acoes: (r) => [
                        _botao('Reverter — foi feita', Icons.undo, AppColors.success,
                            () => _decidir('admin_appointment_revert_no_show', r)),
                      ],
                    ),
                  ],
                ),
    );
  }

  Future<void> _confirmarFalta(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar falta?'),
        content: Text(
            '${r['client_name'] ?? 'O cliente'} às ${r['scheduled_label'] ?? ''} na ${r['provider_name'] ?? 'barbearia'}. '
            'Os ${_eur((r['deposit_cents'] as num?) ?? 0)} pagos ficam retidos até o fecho da semana. Dá para reverter depois.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar falta'),
          ),
        ],
      ),
    );
    if (ok == true) await _decidir('admin_appointment_mark_no_show', r);
  }

  Widget _botao(String label, IconData icon, Color cor, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 16, color: cor),
        label: Text(label, style: TextStyle(color: cor)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cor.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _lista(
    List<Map<String, dynamic>> rows, {
    required String vazio,
    required String cabecalho,
    required List<Widget> Function(Map<String, dynamic>) acoes,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(cabecalho,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(vazio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ...rows.map((r) => _card(r, acoes(r))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r, List<Widget> acoes) {
    final isDemo = r['is_demo'] == true;
    final asked = (r['confirm_asked_count'] as num?)?.toInt() ?? 0;
    final decidedBy = r['no_show_decided_by'] as String?;
    final status = (r['status'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${r['provider_name'] ?? 'Parceiro'} · ${r['scheduled_label'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(_eur((r['deposit_cents'] as num?) ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(
            '${r['client_name'] ?? 'Cliente'}'
            '${(r['client_phone'] ?? '').toString().isNotEmpty ? ' · ${r['client_phone']}' : ''}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(switch (status) {
              'awaiting_confirmation' => 'por confirmar',
              'confirmed' => 'confirmada, serviço já acabou',
              'no_show' => 'falta',
              'cancelled' => 'cancelada',
              _ => status,
            }),
            _chip('pagamento: ${r['deposit_status'] ?? '—'}'),
            if (asked > 0) _chip('perguntado ${asked}x ao parceiro'),
            if (decidedBy != null)
              _chip(decidedBy == 'partner' ? 'falta marcada pelo parceiro' : 'falta decidida por você'),
            if (isDemo) _chip('DEMO', cor: AppColors.warning),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: acoes),
        ]),
      ),
    );
  }

  Widget _chip(String t, {Color? cor}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (cor ?? AppColors.textSecondary).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 11, color: cor ?? AppColors.textSecondary)),
      );
}
