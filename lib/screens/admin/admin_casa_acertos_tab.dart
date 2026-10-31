/// CASA — aba "Acertos semanais" do hub (painel admin, PT-BR). Só lista o
/// que o servidor calculou (`admin_casa_acertos`), manda calcular a semana
/// (`admin_casa_calcular_acertos`) e marca pago/recebido
/// (`admin_casa_acerto_marcar`). Nenhum valor é calculado aqui. Semana de
/// segunda a domingo na hora de Lisboa. Enquanto os valores não tiverem o
/// "autorizo" do Danilo, o servidor recusa calcular a comissão.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';

/// Formas de pagamento do acerto (texto livre no servidor).
const Map<String, String> kCasaFormasAcerto = {
  'transferencia': 'Transferência bancária',
  'mbway': 'MB Way',
  'dinheiro': 'Dinheiro em mão',
};

/// Que botão o acerto tem: 'paid' (Bora paga), 'received' (Bora recebe) ou
/// null (já fechado ou nada a acertar).
String? casaAcertoAcao(Map<String, dynamic> a) {
  if (a['status'] != 'pending') return null;
  return switch (a['direction']) {
    'bora_to_handyman' => 'paid',
    'handyman_to_bora' => 'received',
    _ => null,
  };
}

class AdminCasaAcertosTab extends StatefulWidget {
  const AdminCasaAcertosTab({super.key, this.rpc, this.agora});
  final ChamarRpcPainel? rpc;

  /// Relógio injetável (testes).
  final DateTime? agora;

  @override
  State<AdminCasaAcertosTab> createState() => _AdminCasaAcertosTabState();
}

class _AdminCasaAcertosTabState extends State<AdminCasaAcertosTab> {
  // Por defeito a última semana FECHADA (a anterior à de hoje, em Lisboa).
  late DateTime _segunda = casaSegundaLisboa(widget.agora)
      .subtract(const Duration(days: 7));
  late Future<List<Map<String, dynamic>>> _future = _load();
  bool _busy = false;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<List<Map<String, dynamic>>> _load() async => casaLista(casaVerOk(
      await _rpc('admin_casa_acertos', {'p_week_start': casaIsoData(_segunda)})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _mudarSemana(int dias) {
    _segunda = _segunda.add(Duration(days: dias));
    _refresh();
  }

  Future<void> _calcular() async {
    if (_busy) return;
    final ok = await casaConfirmar(
      context,
      titulo: 'Calcular os acertos de ${casaRotuloSemana(_segunda)}?',
      texto: 'O servidor junta os trabalhos confirmados da semana (Lisboa, '
          'sem pedidos de teste) e cria uma linha por profissional. Linhas já '
          'pagas não mudam. Com os valores ainda em PROPOSTA o servidor '
          'recusa calcular a comissão.',
      botao: 'Calcular',
    );
    if (ok == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = casaMapa(casaVerOk(await _rpc('admin_casa_calcular_acertos',
          {'p_week_start': casaIsoData(_segunda)})));
      if (mounted) {
        casaMsg(context, '${casaInt(r['criados'])} acerto(s) criado(s).');
      }
    } catch (e) {
      if (mounted) casaMsg(context, casaErroPtBr(e));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _marcar(Map<String, dynamic> a, String status) async {
    final r = await showDialog<({String metodo, String referencia})>(
      context: context,
      builder: (_) => _MarcarAcertoDialog(acerto: a, status: status),
    );
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    await casaExecutar(
      context,
      () => _rpc('admin_casa_acerto_marcar', {
        'p_id': a['id'],
        'p_status': status,
        'p_payment_method': r.metodo,
        'p_reference': r.referencia,
      }),
      status == 'paid' ? 'Acerto marcado como pago.' : 'Acerto marcado como recebido.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.xs),
          child: Row(children: [
            IconButton(
              tooltip: 'Semana anterior',
              onPressed: _busy ? null : () => _mudarSemana(-7),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                'Semana ${casaRotuloSemana(_segunda)}',
                key: const ValueKey('casa-acertos-semana'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Semana seguinte',
              onPressed: _busy ? null : () => _mudarSemana(7),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('casa-acertos-calcular'),
              onPressed: _busy ? null : _calcular,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Calcular acertos desta semana'),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
              }
              final lista = snap.data ?? const <Map<String, dynamic>>[];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: lista.isEmpty
                    ? ListView(children: const [
                        CasaVazio('Sem acertos nesta semana. Use "Calcular" '
                            'depois de a semana fechar.'),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: Spacing.huge),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _linha(lista[i]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _linha(Map<String, dynamic> a) {
    final acao = casaAcertoAcao(a);
    final status = a['status']?.toString();
    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(casaTexto(a['profissional_nome']),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text(casaEuroAdmin(a['net_payout_cents']),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            Text(casaDirecaoPtBr(a['direction']?.toString()),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xs),
            CasaLinha('Trabalhos', casaInt(a['total_jobs'])),
            CasaLinha('Total bruto', casaEuroAdmin(a['total_bruto_cents'])),
            CasaLinha('Comissão Bora', casaEuroAdmin(a['total_comissao_cents'])),
            CasaLinha('Recebido em mão', casaEuroAdmin(a['recebido_em_mao_cents'])),
            CasaLinha('Semana',
                '${casaDataHora(a['week_start_at'])} a ${casaDataHora(a['week_end_at'])}'),
            Row(children: [
              CasaEtiqueta(casaAcertoStatusPtBr(status),
                  cor: status == 'pending'
                      ? AppColors.warning
                      : status == 'disputed'
                          ? AppColors.error
                          : AppColors.success),
              const SizedBox(width: Spacing.sm),
              if (a['paid_at'] != null)
                Expanded(
                  child: Text(
                    '${casaDataHora(a['paid_at'])} · '
                    '${kCasaFormasAcerto[a['payment_method']] ?? casaTexto(a['payment_method'])}'
                    '${(a['payment_reference'] ?? '').toString().isEmpty ? '' : ' · ${a['payment_reference']}'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                )
              else
                const Spacer(),
              if (acao != null)
                FilledButton(
                  key: ValueKey('casa-acerto-marcar-${a['id']}'),
                  onPressed: _busy ? null : () => _marcar(a, acao),
                  child: Text(acao == 'paid' ? 'Marcar pago' : 'Marcar recebido'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Confirmação de dinheiro: nome e valor sempre à vista, forma de pagamento
/// e referência.
class _MarcarAcertoDialog extends StatefulWidget {
  const _MarcarAcertoDialog({required this.acerto, required this.status});
  final Map<String, dynamic> acerto;
  final String status;

  @override
  State<_MarcarAcertoDialog> createState() => _MarcarAcertoDialogState();
}

class _MarcarAcertoDialogState extends State<_MarcarAcertoDialog> {
  String _metodo = 'transferencia';
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pago = widget.status == 'paid';
    return AlertDialog(
      title: Text(pago ? 'Marcar como PAGO?' : 'Marcar como RECEBIDO?'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(casaTexto(widget.acerto['profissional_nome']),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(casaEuroAdmin(widget.acerto['net_payout_cents']),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: AppColors.primary)),
            Text(pago
                ? 'A Bora pagou este valor ao profissional.'
                : 'O profissional entregou este valor à Bora.'),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _metodo,
              decoration: const InputDecoration(labelText: 'Como'),
              items: [
                for (final e in kCasaFormasAcerto.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _metodo = v ?? _metodo),
            ),
            TextField(
              controller: _ref,
              decoration: const InputDecoration(
                  labelText: 'Referência (opcional)',
                  helperText: 'Ex.: n.º da transferência'),
            ),
            const SizedBox(height: Spacing.sm),
            const Text(
                'Depois de marcado, o acerto fica congelado (não muda mais).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, (metodo: _metodo, referencia: _ref.text.trim())),
          child: Text(pago ? 'Marcar pago' : 'Marcar recebido'),
        ),
      ],
    );
  }
}
