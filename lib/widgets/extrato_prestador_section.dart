// Contas claras (20/09/2026) — o extrato do estafeta e do motorista.
//
// Regra dura: o Flutter NÃO faz contas de dinheiro. Tudo o que está aqui vem de
// UMA RPC do servidor (`extrato_prestador`). Um valor que o servidor não souber
// aparece como "—" com a razão, nunca como zero.
//
// Ordem copiada da clareza do Uber/Glovo (docs/REFERENCIA-EXTRATOS.md):
//   1. o que a Bora te deve / o que deves à Bora — cada um com as linhas;
//   2. um trabalho por linha (dia a dia); um toque abre as parcelas;
//   3. dinheiro em mão: o que recebeste do cliente e o que é da Bora;
//   4. o último acerto semanal: quanto, quando, pago?, comprovativo;
//   5. talões (reembolsos) com o nome do caminho por onde foram pagos.
//
// Substitui o antigo WeeklySettlementCard (dois números da mesma semana lado a
// lado liam-se como contradição — PADRAO_BORA §2.5).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

class ExtratoPrestadorSection extends StatefulWidget {
  const ExtratoPrestadorSection({super.key, this.userId, this.admin = false});

  /// Admin: ver o extrato de outra pessoa (a RPC só aceita p_user_id de admin).
  final String? userId;

  /// Admin: esconde o botão de alterar o MB Way (é da pessoa, não do painel).
  final bool admin;

  @override
  State<ExtratoPrestadorSection> createState() =>
      _ExtratoPrestadorSectionState();
}

class _ExtratoPrestadorSectionState extends State<ExtratoPrestadorSection> {
  Map<String, dynamic>? _x;
  bool _loading = true;
  String? _error;
  String? _mbwayPhone;
  int _semanas = 4;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.rpc('extrato_prestador', params: {
        'p_semanas': _semanas,
        if (widget.userId != null) 'p_user_id': widget.userId,
      });
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        throw Exception(map['error'] ?? 'extrato indisponível');
      }
      String? mbway;
      try {
        final uid = widget.userId ?? supabase.auth.currentUser?.id;
        if (uid != null) {
          final d = await supabase
              .from('drivers')
              .select('mbway_phone')
              .eq('user_id', uid)
              .maybeSingle();
          mbway = d?['mbway_phone'] as String?;
        }
      } catch (_) {/* o número é opcional */}
      if (!mounted) return;
      setState(() {
        _x = map;
        _mbwayPhone = mbway;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ─── formatação (só apresentação; sem aritmética de dinheiro) ────────────

  /// "12,34 €" a partir de cêntimos inteiros vindos do servidor; null → "—".
  static String eur(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt();
    final sinal = n < 0 ? '-' : '';
    final abs = n.abs();
    final e = abs ~/ 100;
    final c = (abs % 100).toString().padLeft(2, '0');
    return '$sinal$e,$c €';
  }

  static String _pagamento(String? p) {
    switch (p) {
      case 'cash':
        return 'dinheiro';
      case 'mbway':
        return 'MB Way';
      case 'card':
        return 'cartão';
      case null:
        return '';
      default:
        return p;
    }
  }

  static String _diaBonito(String iso) {
    // iso = YYYY-MM-DD (hora de Lisboa, já vinda do servidor)
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}';
  }

  Future<void> _editMbway() async {
    final ctrl = TextEditingController(text: _mbwayPhone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MB Way para receber os acertos'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número MB Way',
            hintText: '+351 912 345 678',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await Supabase.instance.client
          .rpc('update_driver_mbway_phone', params: {'p_phone': result});
      if (!mounted) return;
      setState(() => _mbwayPhone = result.isEmpty ? null : result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MB Way actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Não foi possível carregar o extrato.'),
              const SizedBox(height: 6),
              Text(_error!,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    final x = _x!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo('Contas com a Bora'),
        _contasCard(x),
        const SizedBox(height: 16),
        _titulo('Trabalhos, um a um'),
        _trabalhosList(x),
        const SizedBox(height: 16),
        if (((x['dinheiro_em_mao'] as Map?)?['linhas'] as List?)?.isNotEmpty ??
            false) ...[
          _titulo('Dinheiro em mão'),
          _dinheiroEmMaoCard(Map<String, dynamic>.from(x['dinheiro_em_mao'] as Map)),
          const SizedBox(height: 16),
        ],
        _titulo('Acerto semanal'),
        _acertosCard(x),
        const SizedBox(height: 16),
        if ((x['taloes'] as List?)?.isNotEmpty ?? false) ...[
          _titulo('Talões (reembolsos)'),
          _taloesCard(x['taloes'] as List),
          const SizedBox(height: 16),
        ],
        _periodoSelector(),
      ],
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700)),
      );

  // 1) A Bora deve-te / deves à Bora — cada um com as linhas que o compõem
  Widget _contasCard(Map<String, dynamic> x) {
    final deveLhe = Map<String, dynamic>.from(x['deve_lhe_a_bora'] as Map? ?? {});
    final deve = Map<String, dynamic>.from(x['deve_a_bora'] as Map? ?? {});
    final saldo = x['saldo_cents'];
    final positivo = saldo != null && (saldo as num) >= 0;
    return Card(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bloco('A Bora deve-te', deveLhe, AppColors.success),
            const Divider(height: 22),
            _bloco('Deves à Bora', deve, AppColors.error),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    positivo ? 'No fim, a Bora deve-te' : 'No fim, deves à Bora',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  eur(saldo == null ? null : (saldo as num).abs()),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: positivo ? AppColors.success : AppColors.error),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Os acertos fecham à segunda-feira. Desde 20/09 as corridas TVDE entram '
              'no acerto; as de semanas anteriores ficam aqui, à parte, até serem pagas.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_android, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'MB Way para receber: ${_mbwayPhone ?? '— (por definir)'}',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                if (!widget.admin)
                  TextButton(onPressed: _editMbway, child: const Text('Alterar')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bloco(String titulo, Map<String, dynamic> b, Color cor) {
    final linhas = (b['linhas'] as List? ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(eur(b['total_cents']),
                style: TextStyle(fontWeight: FontWeight.w800, color: cor)),
          ],
        ),
        if (linhas.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Nada por acertar.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        for (final l in linhas)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8),
            child: Row(
              children: [
                Expanded(
                    child: Text('• ${(l as Map)['nome']}',
                        style: const TextStyle(fontSize: 13))),
                Text(eur(l['valor_cents']),
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }

  // 2) trabalhos, um por linha, agrupados por dia; toque abre as parcelas
  Widget _trabalhosList(Map<String, dynamic> x) {
    final trabalhos = (x['trabalhos'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (trabalhos.isEmpty) {
      return Card(
        color: AppColors.card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Sem trabalhos neste período.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final widgets = <Widget>[];
    String? diaAtual;
    for (final t in trabalhos) {
      final dia = t['dia'] as String? ?? '';
      if (dia != diaAtual) {
        diaAtual = dia;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Text(_diaBonito(dia),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ));
      }
      final isCorrida = t['tipo'] == 'corrida';
      final isComp = t['tipo'] == 'compensacao';
      widgets.add(ListTile(
        dense: true,
        onTap: () => _abrirDetalhe(t),
        leading: Icon(
          isCorrida
              ? Icons.directions_car
              : (isComp ? Icons.replay : Icons.delivery_dining),
          color: AppColors.primary,
        ),
        title: Text(t['descricao'] as String? ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            (t['quando_txt'] as String? ?? '').split(' ').last,
            if ((t['pagamento'] as String?) != null) _pagamento(t['pagamento'] as String?),
            if (t['recebeu_em_mao_cents'] != null &&
                (t['recebeu_em_mao_cents'] as num) > 0)
              'recebeste ${eur(t['recebeu_em_mao_cents'])} em mão',
          ].where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(eur(t['ganhou_cents']),
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.success)),
            if (((t['tokens'] as num?) ?? 0) > 0)
              Text('+${t['tokens']} tokens',
                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ));
    }
    return Card(
      color: AppColors.card,
      child: Column(children: widgets),
    );
  }

  void _abrirDetalhe(Map<String, dynamic> t) {
    final parcelas = (t['parcelas'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cash = ((t['recebeu_em_mao_cents'] as num?) ?? 0) > 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['descricao'] as String? ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '${t['quando_txt'] ?? ''}'
                '${(t['pagamento'] as String?) != null ? ' · ${_pagamento(t['pagamento'] as String?)}' : ''}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if ((t['de'] as String? ?? '').isNotEmpty ||
                  (t['para'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('De: ${t['de'] ?? '—'}', style: const TextStyle(fontSize: 12)),
                Text('Para: ${t['para'] ?? '—'}', style: const TextStyle(fontSize: 12)),
              ],
              const Divider(height: 20),
              const Text('O que ganhaste', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final p in parcelas)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(p['nome'] as String? ?? '')),
                      Text(p['tokens'] != null && p['valor_cents'] == null
                          ? '${p['tokens']} tokens'
                          : eur(p['valor_cents'])),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('Ganhaste',
                            style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(eur(t['ganhou_cents']),
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ),
              ),
              const Divider(height: 20),
              _linha('O cliente pagou', eur(t['cliente_pagou_cents'])),
              _linha('Parte da Bora', eur(t['parte_bora_cents'])),
              if (cash) ...[
                const SizedBox(height: 6),
                const Text('Dinheiro em mão', style: TextStyle(fontWeight: FontWeight.w700)),
                _linha('Recebeste do cliente', eur(t['recebeu_em_mao_cents'])),
                if (((t['pagou_na_loja_cents'] as num?) ?? 0) > 0)
                  _linha('Pagaste na loja (talão)', eur(t['pagou_na_loja_cents'])),
                _linha('Fica para ti', eur(t['ganhou_cents'])),
                _linha('Fica para a Bora (entregas no acerto)',
                    eur(t['fica_para_a_bora_cents'])),
              ],
              if ((t['nota'] as String?) != null) ...[
                const SizedBox(height: 10),
                Text(t['nota'] as String,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linha(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
          Text(v, style: const TextStyle(fontSize: 13)),
        ]),
      );

  // 3) dinheiro em mão
  Widget _dinheiroEmMaoCard(Map<String, dynamic> d) {
    final linhas = (d['linhas'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Card(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _linha('Recebeste dos clientes', eur(d['total_recebido_cents'])),
            _linha('Pagaste nas lojas (talões)', eur(d['total_pagou_na_loja_cents'])),
            _linha('Fica para ti', eur(d['total_fica_para_ela_cents'])),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Expanded(
                    child: Text('É da Bora (abate no acerto)',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Text(eur(d['total_fica_para_a_bora_cents']),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.error)),
              ]),
            ),
            const Divider(height: 18),
            for (final l in linhas)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${(l['quando_txt'] as String? ?? '')} · ${l['descricao'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Text('${eur(l['recebeu_do_cliente_cents'])} → Bora ${eur(l['fica_para_a_bora_cents'])}',
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  // 4) acertos semanais: o último em destaque, os anteriores em lista
  Widget _acertosCard(Map<String, dynamic> x) {
    final acertos = (x['acertos'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final semana = x['semana_em_curso'];
    final semanaMap = semana is Map ? Map<String, dynamic>.from(semana) : null;
    return Card(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (semanaMap != null && semanaMap['erro'] == null) ...[
              const Text('Esta semana (previsão, fecha na segunda-feira)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              _linha('Entregas', '${semanaMap['total_deliveries'] ?? '—'}'),
              // Desde 20/09/2026 as corridas TVDE entram no acerto semanal.
              if (semanaMap['tvde_rides_count'] != null)
                _linha('Corridas TVDE', '${semanaMap['tvde_rides_count']}'),
              _linha('Ganhos (entregas + corridas)',
                  _eurFromEuros(semanaMap['total_earnings'])),
              if (semanaMap['tvde_earnings'] != null)
                _linha('  dos quais em corridas',
                    _eurFromEuros(semanaMap['tvde_earnings'])),
              _linha('Dinheiro recebido em mão',
                  _eurFromEuros(semanaMap['total_cash_received'])),
              if (semanaMap['tvde_cash_received'] != null)
                _linha('  do qual em corridas',
                    _eurFromEuros(semanaMap['tvde_cash_received'])),
              _linha('Talões que adiantaste',
                  _eurFromEuros(semanaMap['total_reimbursements'])),
              _linha('Tokens convertidos',
                  _eurFromEuros(semanaMap['tokens_converted_value'])),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          semanaMap['direction'] == 'driver_pays_bora'
                              ? 'Vais entregar à Bora'
                              : 'A Bora vai pagar-te',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(_eurFromEuros(semanaMap['net_balance'], abs: true),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: semanaMap['direction'] == 'driver_pays_bora'
                              ? AppColors.error
                              : AppColors.success)),
                ]),
              ),
              const Divider(height: 18),
            ] else if (semanaMap != null) ...[
              Text('Esta semana: — (${semanaMap['erro']})',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Divider(height: 18),
            ],
            if (acertos.isEmpty)
              Text('Ainda não há acertos fechados.',
                  style: TextStyle(color: AppColors.textSecondary))
            else ...[
              _acertoLinha(acertos.first, destaque: true),
              for (final a in acertos.skip(1)) _acertoLinha(a),
            ],
          ],
        ),
      ),
    );
  }

  /// O servidor devolve o acerto (fórmula oficial) em euros — só se formata.
  static String _eurFromEuros(dynamic v, {bool abs = false}) {
    if (v == null) return '—';
    var d = (v as num).toDouble();
    if (abs) d = d.abs();
    return '${d.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Widget _acertoLinha(Map<String, dynamic> a, {bool destaque = false}) {
    final pago = a['estado'] == 'paid' || a['estado'] == 'received';
    final sentido = a['sentido'] as String?;
    final comp = a['comprovativo'];
    final compTxt = comp is Map && comp['estado'] == 'sent'
        ? 'comprovativo enviado para ${comp['para'] ?? 'o teu email'}'
        : (pago ? 'sem comprovativo por email' : null);
    return Padding(
      padding: EdgeInsets.only(top: destaque ? 0 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Semana ${a['semana'] ?? ''}',
                    style: TextStyle(
                        fontWeight: destaque ? FontWeight.w800 : FontWeight.w600))),
            Text(eur(a['liquido_cents'] == null ? null : (a['liquido_cents'] as num).abs()),
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: destaque ? 18 : 14,
                    color: sentido == 'driver_pays_bora'
                        ? AppColors.error
                        : AppColors.success)),
          ]),
          Text(
            [
              sentido == 'driver_pays_bora' ? 'tu entregas à Bora' : 'a Bora paga-te',
              pago
                  ? 'pago a ${a['pago_em_txt'] ?? '—'}${a['metodo'] != null ? ' por ${_pagamento(a['metodo'] as String?)}' : ''}'
                  : 'por pagar',
              if ((a['referencia'] as String?)?.isNotEmpty ?? false)
                'ref. ${a['referencia']}',
              if (compTxt != null) compTxt,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (destaque)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${a['entregas'] ?? 0} entregas · ganhos ${eur(a['ganhos_cents'])} · '
                'em mão ${eur(a['cash_recebido_cents'])} · tokens ${eur(a['tokens_cents'])}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  // 5) talões
  Widget _taloesCard(List taloes) {
    return Card(
      color: AppColors.card,
      child: Column(
        children: [
          for (final r in taloes)
            ListTile(
              dense: true,
              leading: Icon(
                (r as Map)['estado'] == 'pending_admin'
                    ? Icons.hourglass_top
                    : Icons.receipt_long,
                color: r['estado'] == 'pending_admin'
                    ? AppColors.warning
                    : AppColors.primary,
              ),
              title: Text(r['texto'] as String? ?? ''),
              subtitle: Text('pedido ${(r['pedido'] as String? ?? '').substring(0, 8)}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Text(eur(r['valor_cents']),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _periodoSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final n in const [4, 8, 12])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('$n semanas'),
              selected: _semanas == n,
              onSelected: (_) {
                setState(() => _semanas = n);
                _load();
              },
            ),
          ),
      ],
    );
  }
}
