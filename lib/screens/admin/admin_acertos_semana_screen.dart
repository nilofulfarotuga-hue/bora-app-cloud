import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin "Acertos da semana" (PT-BR, só o Danilo).
///
/// É o ecrã ÚNICO do fecho semanal: quem a Bora paga, quem deve à Bora, e o
/// saldo. Daqui paga-se, marca-se pago/recebido, desfaz-se, reenvia-se o
/// recibo, exporta-se para a contabilista e configura-se a cobrança.
///
/// 2026-09-07 — o que mudou e porquê:
///  · Passou a abrir NA SEMANA DO AVISO (`semanaInicial`). O push traz
///    `ref = weekly_closeout_<data>`; antes abria sempre na última e, com duas
///    semanas por tratar, mostrava a errada.
///  · Passou a ver a LAVAGEM AUTO, que ficava de fora do fecho.
///  · "Pago" e "recebido" deixaram de ser a mesma coisa — são opostos, e
///    trocá-los faz o histórico mentir sobre quem devia a quem.
///  · Três totais em cima: o Danilo quer saber quanto sai e quanto entra sem
///    somar linhas de cabeça.
class AdminAcertosSemanaScreen extends StatefulWidget {
  const AdminAcertosSemanaScreen({super.key, this.semanaInicial});

  /// Semana a abrir (AAAA-MM-DD). Vem do aviso; nulo = a mais recente.
  final String? semanaInicial;

  @override
  State<AdminAcertosSemanaScreen> createState() =>
      _AdminAcertosSemanaScreenState();
}

class _AdminAcertosSemanaScreenState extends State<AdminAcertosSemanaScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  List<String> _weeks = const [];
  String? _week;
  String? _weekEnd;
  Map<String, dynamic> _totais = const {};
  String _boraMbway = '';
  bool _emailsEnabled = false;
  bool _busy = false;
  final Set<String> _abertos = {};

  final _client = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _week = widget.semanaInicial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client
          .rpc('admin_weekly_closeout_list', params: {'p_week_start': _week});
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = ((m['items'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _weeks = ((m['weeks'] as List?) ?? []).map((e) => e.toString()).toList();
        _week = (m['week_start'] as String?) ?? _week;
        _weekEnd = m['week_end'] as String?;
        _totais = ((m['totais'] as Map?) ?? {}).cast<String, dynamic>();
        _boraMbway = (m['bora_mbway'] as String?) ?? '';
        _emailsEnabled = m['emails_enabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _eur(num cents) =>
      '€${(cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  String _chaveDe(Map<String, dynamic> r) => '${r['type']}:${r['subject_id']}';

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  // ------------------------------------------------------------------ ações

  /// Copia o MB Way e o valor, e tenta abrir o MB Way. Não existe deep link
  /// universal do MB Way — por isso o que conta mesmo é o "copiado", e a
  /// abertura da app é só uma tentativa que nunca trava o resto.
  Future<void> _pagar(Map<String, dynamic> r) async {
    final mbway = (r['mbway'] as String?) ?? '';
    final valor = _eur((r['net_cents'] as num?) ?? 0);
    if (mbway.isEmpty) {
      _aviso('${r['name']} não tem MB Way registado.', erro: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: mbway));
    _aviso('MB Way $mbway copiado · $valor. Abre o MB Way e cola.');
    try {
      final uri = Uri.parse('mbway://');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Sem app MB Way instalada: fica o valor copiado, que é o que resolve.
    }
  }

  /// Um toque, sem diálogo de confirmação: o Danilo marca dezenas destes e
  /// cada confirmação é um toque a mais. O engano desfaz-se na própria linha.
  Future<void> _marcar(Map<String, dynamic> r) async {
    if (_busy) return;
    setState(() => _busy = true);
    final owes = r['direction'] == 'owes_bora';
    try {
      await _client.rpc('admin_set_settlement_state', params: {
        'p_subject_type': r['type'],
        'p_subject_id': r['subject_id'],
        'p_week_start': _week,
        'p_status': owes ? 'received' : 'paid',
      });
      _aviso(owes
          ? '${r['name']}: recebido. O comprovativo vai a caminho.'
          : '${r['name']}: pago. O comprovativo vai a caminho.');
      await _load();
    } catch (e) {
      _aviso('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _desfazer(Map<String, dynamic> r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client.rpc('admin_unmark_settlement', params: {
        'p_subject_type': r['type'],
        'p_subject_id': r['subject_id'],
        'p_week_start': _week,
      });
      _aviso('${r['name']}: voltou a pendente.');
      await _load();
    } catch (e) {
      _aviso('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client
          .rpc('admin_resend_weekly_digest', params: {'p_week_start': _week});
      _aviso('Recibos reenviados para a semana $_week.');
    } catch (e) {
      _aviso('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportar() async {
    try {
      await AdminExportService.instance.exportCsv(
        filename: 'acertos-semana-$_week.csv',
        headers: const [
          'Tipo',
          'Nome',
          'Email',
          'MB Way',
          'Valor (EUR)',
          'Sentido',
          'Estado',
          'Pago em',
          'Referência',
        ],
        rows: _items
            .map((r) => [
                  _tipoLabel(r['type'] as String?),
                  r['name'] ?? '',
                  r['email'] ?? '',
                  r['mbway'] ?? '',
                  (((r['net_cents'] as num?) ?? 0).abs() / 100)
                      .toStringAsFixed(2),
                  switch (r['direction']) {
                    'bora_pays' => 'a Bora paga',
                    'owes_bora' => 'deve à Bora',
                    _ => 'sem movimento',
                  },
                  _estadoLabel(r),
                  (r['paid_at'] as String?)?.substring(0, 16) ?? '',
                  r['payment_reference'] ?? '',
                ])
            .toList(),
        subject: 'Acertos da semana $_week',
      );
    } catch (e) {
      _aviso('Erro a exportar: $e', erro: true);
    }
  }

  Future<void> _editMbway() async {
    final ctrl = TextEditingController(text: _boraMbway);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MB Way da Bora (para cobranças)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número MB Way',
            hintText: '931992662',
            helperText: 'Vai escrito em todos os recibos de quem deve.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null) return;
    await _guardarDefinicao({'p_bora_mbway': v});
  }

  Future<void> _guardarDefinicao(Map<String, dynamic> params) async {
    try {
      await _client.rpc('admin_update_weekly_closeout_settings', params: params);
      await _load();
    } catch (e) {
      _aviso('Erro: $e', erro: true);
    }
  }

  Future<void> _abrirConfiguracoes() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfiguracoesDoFecho(
        onGuardar: _guardarDefinicao,
        emailsLigados: _emailsEnabled,
      ),
    );
    await _load();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final aPagar = _items.where((r) => r['direction'] == 'bora_pays').toList();
    final aReceber = _items.where((r) => r['direction'] == 'owes_bora').toList();
    final semMovimento = _items.where((r) => r['direction'] == 'zero').toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Acertos da semana',
        actions: [
          IconButton(
            tooltip: 'Exportar para a contabilista (CSV)',
            onPressed: _items.isEmpty ? null : _exportar,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Configurar',
            onPressed: _abrirConfiguracoes,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _erroCard()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _cabecalho(),
                      const SizedBox(height: 14),
                      if (aPagar.isNotEmpty) ...[
                        _secTitle('A PAGAR — a Bora paga', AppColors.warning,
                            aPagar.length),
                        ...aPagar.map(_itemCard),
                        const SizedBox(height: 10),
                      ],
                      if (aReceber.isNotEmpty) ...[
                        _secTitle('A RECEBER — devem à Bora', AppColors.success,
                            aReceber.length),
                        ...aReceber.map(_itemCard),
                        const SizedBox(height: 10),
                      ],
                      if (semMovimento.isNotEmpty)
                        _semMovimentoCard(semMovimento.length),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                              child: Text('Sem acertos nesta semana.')),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _erroCard() => Center(
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
      );

  Widget _cabecalho() {
    final pagar = (_totais['pagar_cents'] as num?) ?? 0;
    final receber = (_totais['receber_cents'] as num?) ?? 0;
    final saldo = (_totais['saldo_cents'] as num?) ?? 0;
    final porTratar = (_totais['n_por_tratar'] as num?) ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.calendar_month, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _weekEnd == null
                    ? 'Semana de ${_week ?? '—'}'
                    : 'Semana ${_dm(_week)} a ${_dm(_weekEnd)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_weeks.isNotEmpty)
              DropdownButton<String>(
                value: _weeks.contains(_week) ? _week : null,
                hint: Text(_week ?? '—'),
                underline: const SizedBox.shrink(),
                items: _weeks
                    .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _week = v);
                  _load();
                },
              ),
          ]),
          const Divider(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _kpi('Bora paga', _eur(pagar), AppColors.warning),
            _kpi('Bora recebe', _eur(receber), AppColors.success),
            _kpi(
              saldo >= 0 ? 'Saldo a favor' : 'Saldo contra',
              _eur(saldo),
              saldo >= 0 ? AppColors.success : AppColors.warning,
            ),
          ]),
          if (porTratar > 0) ...[
            const SizedBox(height: 10),
            Text('$porTratar por tratar nesta semana.',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: _editMbway,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _boraMbway.isEmpty
                            ? 'MB Way da Bora: definir (é preciso para cobrar)'
                            : 'MB Way da Bora: $_boraMbway',
                        style: TextStyle(
                          fontSize: 12,
                          color: _boraMbway.isEmpty
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 14),
                  ]),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _resend,
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('Reenviar recibos'),
            ),
          ]),
        ]),
      ),
    );
  }

  String _dm(String? iso) {
    if (iso == null || iso.length < 10) return iso ?? '—';
    return '${iso.substring(8, 10)}/${iso.substring(5, 7)}';
  }

  Widget _kpi(String label, String v, Color c) => Column(children: [
        Text(v,
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ]);

  Widget _secTitle(String t, Color c, int n) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text('$t  ($n)',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: c, fontSize: 13)),
      );

  Widget _semMovimentoCard(int n) => Card(
        color: AppColors.surface2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text('$n sem movimento nesta semana — nada a fazer.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
      );

  Widget _itemCard(Map<String, dynamic> r) {
    final owes = r['direction'] == 'owes_bora';
    final net = (r['net_cents'] as num?) ?? 0;
    final estado = (r['paid_status'] as String?) ?? 'pending';
    final tratado = estado == 'paid' || estado == 'received';
    final mbway = (r['mbway'] as String?) ?? '';
    final cor = owes ? AppColors.success : AppColors.warning;
    final chave = _chaveDe(r);
    final aberto = _abertos.contains(chave);
    final breakdown = (r['breakdown'] as List?) ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${r['name'] ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Text(_eur(net),
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: cor, fontSize: 17)),
          ]),
          Text(owes ? 'deve à Bora' : 'a Bora paga',
              style: TextStyle(fontSize: 11, color: cor)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(_tipoLabel(r['type'] as String?)),
            if (mbway.isNotEmpty) _chip('MB Way $mbway'),
            _statusChip(_estadoLabel(r),
                tratado ? AppColors.success : AppColors.textSecondary),
            _statusChip(_emailLabel(r['email_status'] as String?),
                r['email_status'] == 'sent'
                    ? AppColors.textSecondary
                    : AppColors.error),
            if (r['receipt_status'] != null)
              _statusChip(_reciboLabel(r['receipt_status'] as String?),
                  r['receipt_status'] == 'sent'
                      ? AppColors.textSecondary
                      : AppColors.error),
          ]),
          if ((r['email_error'] as String?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Email: ${r['email_error']}',
                  style: const TextStyle(fontSize: 11, color: AppColors.error)),
            ),
          if (aberto && breakdown.isNotEmpty) ...[
            const Divider(height: 18),
            ...breakdown.map((b) {
              final m = (b as Map).cast<String, dynamic>();
              final v = (m['value_cents'] as num?) ?? 0;
              final qty = m['qty'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      qty == null
                          ? '${m['label']}'
                          : '${m['label']}  ×$qty',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text('${v < 0 ? '−' : ''}${_eur(v)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: v < 0
                              ? AppColors.warning
                              : AppColors.textPrimary)),
                ]),
              );
            }),
            if ((r['payment_reference'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Referência: ${r['payment_reference']}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ),
          ],
          Row(children: [
            TextButton.icon(
              onPressed: breakdown.isEmpty
                  ? null
                  : () => setState(() =>
                      aberto ? _abertos.remove(chave) : _abertos.add(chave)),
              icon: Icon(aberto ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(aberto ? 'Fechar' : 'Detalhe'),
            ),
            const Spacer(),
            if (!tratado && !owes)
              TextButton(
                onPressed: _busy ? null : () => _pagar(r),
                child: const Text('Pagar'),
              ),
            if (!tratado)
              FilledButton(
                onPressed: _busy ? null : () => _marcar(r),
                child: Text(owes ? 'Marcar recebido' : 'Marcar pago'),
              ),
            if (tratado)
              TextButton(
                onPressed: _busy ? null : () => _desfazer(r),
                child: const Text('Desfazer'),
              ),
          ]),
        ]),
      ),
    );
  }

  String _tipoLabel(String? t) => switch (t) {
        'driver' => 'Estafeta',
        'cleaner' => 'Limpeza',
        'provider' => 'Serviços',
        'partner' => 'Parceiro',
        'washer' => 'Lavagem',
        _ => t ?? '',
      };

  String _estadoLabel(Map<String, dynamic> r) {
    final estado = (r['paid_status'] as String?) ?? 'pending';
    final quando = (r['paid_at'] as String?);
    final dm = quando != null && quando.length >= 10
        ? ' ${quando.substring(8, 10)}/${quando.substring(5, 7)}'
        : '';
    return switch (estado) {
      'paid' => 'PAGO$dm',
      'received' => 'RECEBIDO$dm',
      'disputed' => 'EM DISPUTA',
      _ => 'PENDENTE',
    };
  }

  String _emailLabel(String? s) => switch (s) {
        'sent' => 'recibo enviado',
        'aguarda_dominio' => 'recibo em espera',
        'skipped' => 'sem email',
        'failed' => 'recibo falhou',
        _ => 'recibo pendente',
      };

  String _reciboLabel(String? s) => switch (s) {
        'sent' => 'comprovativo enviado',
        'skipped' => 'comprovativo sem email',
        'failed' => 'comprovativo falhou',
        _ => 'comprovativo a caminho',
      };

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      );

  Widget _statusChip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 10, color: c, fontWeight: FontWeight.w700)),
      );
}

/// Definições do fecho: o que se liga, quando se lembra e a partir de quanto
/// se bloqueia. Tudo vive em `platform_settings`, nunca cravado no código.
class _ConfiguracoesDoFecho extends StatefulWidget {
  const _ConfiguracoesDoFecho({
    required this.onGuardar,
    required this.emailsLigados,
  });

  final Future<void> Function(Map<String, dynamic>) onGuardar;
  final bool emailsLigados;

  @override
  State<_ConfiguracoesDoFecho> createState() => _ConfiguracoesDoFechoState();
}

class _ConfiguracoesDoFechoState extends State<_ConfiguracoesDoFecho> {
  late bool _emails = widget.emailsLigados;
  bool _lembretes = true;
  bool _transportarDivida = false;
  int _hora = 10;
  final Set<int> _dias = {3, 5};
  final _tectoCtrl = TextEditingController(text: '0');
  bool _carregado = false;

  final _client = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _tectoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final res = await _client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', [
        'settlement_reminders_enabled',
        'settlement_reminder_weekdays',
        'settlement_reminder_hour',
        'driver_cash_debt_block_cents',
        'settlement_carry_over_enabled',
      ]);
      final m = {for (final r in res) r['key'] as String: r['value']};
      if (!mounted) return;
      setState(() {
        _lembretes = m['settlement_reminders_enabled'] == true;
        _transportarDivida = m['settlement_carry_over_enabled'] == true;
        _hora = int.tryParse('${m['settlement_reminder_hour']}') ?? 10;
        final dias = m['settlement_reminder_weekdays'];
        if (dias is List && dias.isNotEmpty) {
          _dias
            ..clear()
            ..addAll(dias.map((e) => int.tryParse('$e') ?? 0));
        }
        _tectoCtrl.text = '${m['driver_cash_debt_block_cents'] ?? 0}';
        _carregado = true;
      });
    } catch (_) {
      if (mounted) setState(() => _carregado = true);
    }
  }

  static const _nomesDias = {
    1: 'seg',
    2: 'ter',
    3: 'qua',
    4: 'qui',
    5: 'sex',
    6: 'sáb',
    7: 'dom',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: !_carregado
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    const Text('Configurar o fecho',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _emails,
                      onChanged: (v) => setState(() => _emails = v),
                      title: const Text('Enviar recibos por email'),
                      subtitle: const Text(
                          'Desligado, só o Danilo recebe; os outros ficam em espera.'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _lembretes,
                      onChanged: (v) => setState(() => _lembretes = v),
                      title: const Text('Lembrar quem deve, sozinho'),
                      subtitle: const Text(
                          'Email e aviso a quem não acertou, e a lista para ti.'),
                    ),
                    const SizedBox(height: 6),
                    const Text('Dias do lembrete',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Wrap(
                      spacing: 6,
                      children: _nomesDias.entries
                          .map((e) => FilterChip(
                                label: Text(e.value),
                                selected: _dias.contains(e.key),
                                onSelected: (s) => setState(() =>
                                    s ? _dias.add(e.key) : _dias.remove(e.key)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Text('Hora: '),
                      DropdownButton<int>(
                        value: _hora,
                        items: List.generate(24, (i) => i)
                            .map((h) => DropdownMenuItem(
                                value: h,
                                child: Text('${h.toString().padLeft(2, '0')}h')))
                            .toList(),
                        onChanged: (v) => setState(() => _hora = v ?? 10),
                      ),
                    ]),
                    const Divider(height: 24),
                    TextField(
                      controller: _tectoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Teto de dívida do estafeta (em cêntimos)',
                        helperText:
                            '0 = desligado. Acima deste valor o estafeta deixa de '
                            'receber pedidos até acertar. 5000 = 50 euros.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _transportarDivida,
                      onChanged: (v) => setState(() => _transportarDivida = v),
                      title: const Text('Transportar dívida para a semana seguinte'),
                      subtitle: const Text(
                          'MEXE EM VALORES. Só ligar depois de conferir uma semana à mão.'),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar')),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          await widget.onGuardar({
                            'p_emails_enabled': _emails,
                            'p_reminders_enabled': _lembretes,
                            'p_reminder_weekdays': _dias.toList()..sort(),
                            'p_reminder_hour': _hora,
                            'p_debt_block_cents':
                                int.tryParse(_tectoCtrl.text.trim()) ?? 0,
                            'p_carry_over_enabled': _transportarDivida,
                          });
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Guardar'),
                      ),
                    ]),
                  ]),
              ),
      ),
    );
  }
}
