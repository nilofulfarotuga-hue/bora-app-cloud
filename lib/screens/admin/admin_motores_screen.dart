// Missão 02/09/2026 (noite) — MOTORES: o roteador "Motor Bora" no painel admin (PT-BR).
// Lê `motor_estado` (uma linha por fornecedor, escrita pelo roteador de 20 em 20 s: quota gasta hoje,
// latência mediana, castigado, último erro) e `motor_chamadas` (o log). O botão "Pausar" escreve
// `motor_estado.pausado` — o roteador lê a coluna no próximo ciclo e deixa de usar o fornecedor.
// Chaves NUNCA aparecem aqui (só "tem chave: sim/não").
//
// 31/10/2026 (missão motor-claude-2026-10-31, Bloco 5): no topo, o motor Claude primeiro —
// cartão "Crédito Claude" (resta, vence, próximo crédito, gasto de hoje/mês/por robô, parte do dia),
// interruptores por robô (claude_robos), exportar o livro de gastos (ia_gastos) e as lições dos
// robôs (licoes_robos). Model → Store → Screen: credito_claude_model.dart → CreditoClaudeStore.
// Enquanto a migração 20261031_motor_claude_porteiro.sql não for aplicada, mostra "ainda não ativado".

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/credito_claude_model.dart';
import '../../services/admin_export_service.dart';
import '../../stores/credito_claude_store.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../utils/hora_lisboa.dart';

class AdminMotoresScreen extends StatefulWidget {
  const AdminMotoresScreen({super.key});

  @override
  State<AdminMotoresScreen> createState() => _AdminMotoresScreenState();
}

class _AdminMotoresScreenState extends State<AdminMotoresScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _motores = [];
  List<Map<String, dynamic>> _chamadas = [];
  // 23/10/2026 (missão omniroute-23-10): o roteador OmniRoute da VPS. Uma linha só ('vps'),
  // escrita de 10 em 10 min por /opt/omniroute/or_estado.py. Sem chaves.
  Map<String, dynamic>? _omniroute;
  DateTime? _omnirouteEm;
  bool _loading = false;
  String? _erro;
  final _claude = CreditoClaudeStore();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _claude.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    _claude.carregar();
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final m = await _supabase
          .from('motor_estado')
          .select('fornecedor, dados, pausado, updated_at')
          .order('fornecedor');
      final c = await _supabase
          .from('motor_chamadas')
          .select('maquina, perfil, fornecedor, modelo, ok, latencia_ms, tokens, erro, created_at')
          .order('created_at', ascending: false)
          .limit(120);
      final o = await _supabase
          .from('omniroute_estado')
          .select('dados, updated_at')
          .eq('id', 'vps')
          .maybeSingle();
      setState(() {
        _motores = List<Map<String, dynamic>>.from(m);
        _chamadas = List<Map<String, dynamic>>.from(c);
        _omniroute = o == null ? null : Map<String, dynamic>.from((o['dados'] as Map?) ?? {});
        _omnirouteEm = o == null ? null : DateTime.tryParse('${o['updated_at']}');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pausar(Map<String, dynamic> m, bool pausar) async {
    try {
      await _supabase
          .from('motor_estado')
          .update({'pausado': pausar})
          .eq('fornecedor', m['fornecedor']);
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pausar
            ? '${m['fornecedor']} pausado — o roteador deixa de o usar no próximo ciclo (20 s).'
            : '${m['fornecedor']} retomado.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  String _quando(dynamic v) => dataHoraLisboa(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Motores (Claude primeiro, depois o grátis)',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _SeccaoClaude(store: _claude),
                    const SizedBox(height: 8),
                    _cartaoOmniroute(),
                    const SizedBox(height: 8),
                    _resumo(),
                    const SizedBox(height: 8),
                    ..._motores.map(_cartao),
                    const SizedBox(height: 16),
                    const Text('Últimas chamadas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 6),
                    ..._chamadas.take(60).map(_linhaChamada),
                  ],
                ),
    );
  }

  Widget _resumo() {
    final comChave = _motores.where((m) => (m['dados'] as Map?)?['chave'] == true).length;
    final castigados = _motores.where((m) => (m['dados'] as Map?)?['castigado_ate'] != null).length;
    final pausados = _motores.where((m) => m['pausado'] == true).length;
    final ok = _chamadas.where((c) => c['ok'] == true).length;
    final lat = _chamadas.where((c) => c['ok'] == true && c['latencia_ms'] != null).map((c) => (c['latencia_ms'] as num).toInt()).toList()..sort();
    final mediana = lat.isEmpty ? '—' : '${lat[lat.length ~/ 2]} ms';
    final p95 = lat.isEmpty ? '—' : '${lat[((lat.length * 0.95).ceil() - 1).clamp(0, lat.length - 1)]} ms';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _kv('Fornecedores com chave', '$comChave / ${_motores.length}'),
            _kv('Castigados agora', '$castigados'),
            _kv('Pausados por você', '$pausados'),
            _kv('Últimas chamadas OK', '$ok / ${_chamadas.length}'),
            _kv('Latência mediana', mediana),
            _kv('p95', p95),
          ],
        ),
      ),
    );
  }

  Widget _cartaoOmniroute() {
    final d = _omniroute;
    if (d == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.alt_route, color: AppColors.textSubtle),
          title: Text('OmniRoute', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Ainda sem estado. A VPS escreve de 10 em 10 minutos.'),
        ),
      );
    }
    final minutos = _omnirouteEm == null ? null : DateTime.now().toUtc().difference(_omnirouteEm!.toUtc()).inMinutes;
    final parado = minutos == null || minutos > 25;
    final consumo = Map<String, dynamic>.from((d['consumo_hoje'] as Map?) ?? {});
    final combos = List<Map<String, dynamic>>.from(((d['combos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final forn = List<Map<String, dynamic>>.from(((d['fornecedores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.alt_route, color: parado ? AppColors.error : AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('OmniRoute (roteador da VPS)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text(
                parado ? 'sem notícias há ${minutos ?? '?'} min' : 'atualizado há $minutos min',
                style: TextStyle(fontSize: 11, color: parado ? AppColors.error : AppColors.textSubtle),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 18, runSpacing: 6, children: [
              _kv('Fornecedores vivos', '${d['vivos'] ?? 0}'),
              _kv('Mortos', '${d['mortos'] ?? 0}'),
              _kv('Combo em uso', '${d['combo_em_uso'] ?? '—'}'),
              _kv('Pedidos hoje', '${consumo['pedidos'] ?? 0} (${consumo['ok'] ?? 0} ok)'),
              _kv('Recuos hoje', '${consumo['recuos'] ?? 0}'),
              _kv('Tokens hoje', '${consumo['tokens'] ?? 0}'),
            ]),
            const SizedBox(height: 10),
            const Text('Combos — quem está respondendo agora', style: TextStyle(fontWeight: FontWeight.w600)),
            ...combos.map((c) {
              final ativo = c['nivel_ativo'];
              final usam = (c['agentes'] as List?)?.join(', ') ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${c['nome']} (${c['niveis']} níveis): ${ativo ?? 'NENHUM nível vivo'}'
                  '${ativo != null && ativo != c['primeiro_nivel'] ? ' — o 1.º nível (${c['primeiro_nivel']}) está fora' : ''}'
                  '${usam.isNotEmpty ? '\n   usado por: $usam' : ''}',
                  style: TextStyle(fontSize: 13, color: ativo == null ? AppColors.error : null),
                ),
              );
            }),
            const SizedBox(height: 10),
            const Text('Fornecedores', style: TextStyle(fontWeight: FontWeight.w600)),
            ...forn.map((f) {
              final vivo = f['vivo'] == true;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(vivo ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 16, color: vivo ? AppColors.primary : AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${f['nome']} · ${vivo ? 'vivo' : 'morto'} · hoje ${f['pedidos_hoje'] ?? 0} pedidos '
                      '(${f['ok_hoje'] ?? 0} ok, ${f['falhas_hoje'] ?? 0} falhas)'
                      '${!vivo && f['erro'] != null ? '\n${f['erro']}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );

  Widget _cartao(Map<String, dynamic> m) {
    final d = Map<String, dynamic>.from((m['dados'] as Map?) ?? {});
    final hoje = Map<String, dynamic>.from((d['hoje'] as Map?) ?? {});
    final temChave = d['chave'] == true;
    final pausado = m['pausado'] == true;
    final castigado = d['castigado_ate'] != null;
    final cor = pausado
        ? AppColors.textSubtle
        : (!temChave ? AppColors.textSubtle : (castigado ? AppColors.accent : AppColors.primary));
    final estado = pausado
        ? 'PAUSADO por você'
        : (!temChave ? 'sem chave' : (castigado ? 'castigado até ${_quando(d['castigado_ate'])}' : 'disponível'));
    final lat = d['latencia_mediana_ms'];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cor.withValues(alpha: 0.15),
          child: Icon(pausado ? Icons.pause : (castigado ? Icons.hourglass_bottom : Icons.bolt), color: cor, size: 20),
        ),
        title: Text('${m['fornecedor']} · $estado', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'hoje: ${hoje['pedidos'] ?? 0} pedidos (${hoje['ok'] ?? 0} ok, ${hoje['falhas'] ?? 0} falhas) · ${hoje['tokens'] ?? 0} tokens'
          ' · último minuto: ${d['ultimo_minuto'] ?? 0} · latência: ${lat == null ? '—' : '$lat ms'}'
          '${d['castigo_motivo'] != null ? '\ncastigo: ${d['castigo_motivo']}' : ''}'
          '${d['ultimo_erro'] != null ? '\núltimo erro: ${d['ultimo_erro']}' : ''}'
          '${d['nota'] != null ? '\n${d['nota']}' : ''}',
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: () => _pausar(m, !pausado),
          child: Text(pausado ? 'Retomar' : 'Pausar'),
        ),
      ),
    );
  }

  Widget _linhaChamada(Map<String, dynamic> c) {
    final ok = c['ok'] == true;
    return ListTile(
      dense: true,
      leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: ok ? AppColors.primary : AppColors.error),
      title: Text('${c['fornecedor']}:${c['modelo']} · ${c['perfil'] ?? '—'} · ${c['latencia_ms'] ?? 0} ms · ${c['maquina'] ?? ''}'),
      subtitle: Text('${_quando(c['created_at'])}${c['erro'] != null ? ' · ${c['erro']}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

// ══ Motor Claude (31/10/2026) ═══════════════════════════════════════════════

String _usd(double v) {
  final casas = (v != 0 && v.abs() < 1) ? 4 : 2;
  return 'US\$ ${v.toStringAsFixed(casas).replaceAll('.', ',')}';
}

String _dia(DateTime? d) {
  if (d == null) return '—';
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(d.day)}/${dd(d.month)}/${d.year}';
}

String _prioridade(int p) => switch (p) {
      1 => 'P1 (clientes: usa enquanto houver crédito)',
      2 => 'P2 (decisões: até a parte do dia)',
      _ => 'P$p (agentes e volume: até metade da parte do dia)',
    };

/// Cartão do crédito, interruptores por robô e lições dos robôs. Lê tudo do [CreditoClaudeStore].
class _SeccaoClaude extends StatelessWidget {
  const _SeccaoClaude({required this.store});

  final CreditoClaudeStore store;

  void _snack(BuildContext context, String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _tentar(BuildContext context, Future<void> Function() acao, String ok) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await acao();
      messenger.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final e = store.estado;
        if (e == null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome, color: AppColors.textSubtle),
              title: const Text('Crédito Claude', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(store.carregando
                  ? 'Carregando…'
                  : (store.erro != null ? 'Erro ao ler: ${store.erro}' : 'Sem dados.')),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (store.erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('A última leitura falhou (mostrando a anterior): ${store.erro}',
                    style: const TextStyle(fontSize: 12, color: AppColors.error)),
              ),
            _cartaoCredito(context, e),
            if (e.settingsAtivos) ...[
              const SizedBox(height: 8),
              _cartaoRobos(context, e),
            ],
            const SizedBox(height: 8),
            _cartaoLicoes(context),
          ],
        );
      },
    );
  }

  // ── a) Crédito ───────────────────────────────────────────────────────────

  Widget _cartaoCredito(BuildContext context, EstadoCreditoClaude e) {
    final cabecalho = Row(children: [
      Icon(Icons.auto_awesome, color: e.ativado ? AppColors.primary : AppColors.textSubtle),
      const SizedBox(width: 8),
      const Expanded(
        child: Text('Crédito Claude (saldo da API da Anthropic)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      if (store.gravando || store.carregando)
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      if (e.settingsAtivos)
        IconButton(
          tooltip: 'Atualizar o crédito lido na Console',
          icon: const Icon(Icons.edit_outlined),
          onPressed: store.gravando ? null : () => _dialogoCredito(context, e),
        ),
    ]);

    if (!e.ativado) {
      final falta = [
        if (!e.settingsAtivos) 'as chaves claude_* em platform_settings',
        if (!e.livroAtivo) 'o livro de gastos (tabela ia_gastos)',
      ].join(' e ');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cabecalho,
            const SizedBox(height: 6),
            const Text('Ainda não ativado', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Falta no servidor: $falta. A migração 20261031_motor_claude_porteiro está por aplicar. '
              'Quando for aplicada, este cartão passa a mostrar o crédito e o gasto sozinho.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSubtle),
            ),
          ]),
        ),
      );
    }

    final r = e.ritmo;
    final resta = r.restaUsd;
    final parte = r.parteDoDiaUsd;
    final primeiroLote = e.lotes.isEmpty ? null : e.lotes.first;

    final String aviso;
    final Color corAviso;
    if (!e.ligado) {
      aviso = 'Claude desligado no interruptor geral: todos os robôs estão usando só a rotação grátis.';
      corAviso = AppColors.textSubtle;
    } else if (resta <= 0) {
      aviso = 'Crédito acabado: todos os robôs foram para a rotação grátis até o próximo crédito.';
      corAviso = AppColors.error;
    } else if (e.gastoHojeUsd >= parte) {
      aviso = 'Parte do dia esgotada: só P1 (clientes) continua no Claude hoje; P2 e P3 foram para a rotação grátis.';
      corAviso = AppColors.accent;
    } else if (e.gastoHojeUsd >= parte * 0.5) {
      aviso = 'Passou de metade da parte do dia: P3 (agentes e volume) foi para a rotação grátis hoje.';
      corAviso = AppColors.accent;
    } else {
      aviso = 'Dentro do ritmo: todos os robôs ligados podem usar o Claude.';
      corAviso = AppColors.primary;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cabecalho,
          const SizedBox(height: 8),
          Wrap(spacing: 18, runSpacing: 8, children: [
            _kv('Resta (crédito lido − gasto desde a leitura)', _usd(resta)),
            _kv('Vence (o lote que expira primeiro)',
                primeiroLote == null ? '—' : '${_dia(primeiroLote.expira)} · ${_usd(primeiroLote.usd)}'),
            _kv('Próximo crédito (mensal do plano)',
                '${e.mensalUsd == null ? '—' : _usd(e.mensalUsd!)} em ${_dia(e.proximoCredito)} · faltam ${e.diasAteProximo} d'),
            _kv('Gasto de hoje (dia de Lisboa)', '${_usd(e.gastoHojeUsd)} · ${e.chamadasHoje} chamadas'),
            _kv('Gasto do mês', _usd(e.gastoMesUsd)),
            _kv('Parte do dia (quanto dá para gastar por dia até o próximo crédito)', _usd(parte)),
          ]),
          const SizedBox(height: 8),
          Text(aviso, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: corAviso)),
          const SizedBox(height: 6),
          Text(
            'Lido na Console em ${dataHoraLisboa(e.lidoEm?.toIso8601String())}: ${_usd(r.creditoLidoUsd)}. '
            'Gasto desde a leitura: ${_usd(r.gastoDesdeLeituraUsd)}. '
            'Parte do dia = (resta + gasto de hoje) ÷ dias até o próximo crédito.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
          ),
          if (e.lotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Lotes de crédito (validade de cada um)', style: TextStyle(fontWeight: FontWeight.w600)),
            ...e.lotes.map((l) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${_usd(l.usd)} · vence ${_dia(l.expira)}${l.origem.isEmpty ? '' : ' · ${l.origem}'}',
                      style: const TextStyle(fontSize: 13)),
                )),
          ],
          const SizedBox(height: 10),
          const Text('Gasto por robô (este mês)', style: TextStyle(fontWeight: FontWeight.w600)),
          if (e.gastoPorRobo.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Nenhuma chamada ao Claude este mês.', style: TextStyle(fontSize: 13, color: AppColors.textSubtle)),
            ),
          ...e.gastoPorRobo.map((g) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${g.robo}: mês ${_usd(g.mesUsd)} (${g.chamadasMes} chamadas) · hoje ${_usd(g.hojeUsd)} (${g.chamadasHoje})',
                  style: const TextStyle(fontSize: 13),
                ),
              )),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _exportar(context),
              icon: const Icon(Icons.download),
              label: const Text('Exportar livro de gastos (CSV)'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      );

  Future<void> _exportar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final linhas = await store.linhasDoLivro();
      if (linhas.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('O livro de gastos ainda está vazio.')));
        return;
      }
      await AdminExportService.instance.exportCsv(
        filename: 'livro_gastos_claude_${DateTime.now().millisecondsSinceEpoch}.csv',
        headers: CreditoClaudeStore.colunasLivro,
        rows: linhas,
      );
      messenger.showSnackBar(SnackBar(content: Text('CSV com ${linhas.length} chamadas baixado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não consegui exportar: $e')));
    }
  }

  Future<void> _dialogoCredito(BuildContext context, EstadoCreditoClaude e) async {
    final valor = TextEditingController(
        text: e.creditoLidoUsd == null ? '' : e.ritmo.restaUsd.toStringAsFixed(2).replaceAll('.', ','));
    var proximo = e.proximoCredito ?? DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Atualizar crédito Claude'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Leia o valor em console.anthropic.com > Billing (Créditos promocionais). '
              'A hora da leitura fica "agora" e o gasto passa a contar daqui.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Crédito que resta (US\$)'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('Próximo crédito: ${_dia(proximo)}')),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: proximo,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 400)),
                  );
                  if (d != null) setD(() => proximo = d);
                },
                child: const Text('Mudar'),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    // Sem dispose() aqui: a animação de saída do diálogo ainda desenha o campo.
    final usd = double.tryParse(valor.text.trim().replaceAll(',', '.'));
    if (ok != true || !context.mounted) return;
    if (usd == null || usd < 0) {
      _snack(context, 'Valor inválido.');
      return;
    }
    await _tentar(context, () => store.atualizarCredito(usd: usd, proximoCredito: proximo),
        'Crédito atualizado: ${_usd(usd)}, próximo em ${_dia(proximo)}.');
  }

  // ── b) Interruptores por robô ────────────────────────────────────────────

  Widget _cartaoRobos(BuildContext context, EstadoCreditoClaude e) {
    final bloqueado = store.gravando;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            value: e.ligado,
            onChanged: bloqueado
                ? null
                : (v) => _tentar(context, () => store.gravarLigado(v),
                    v ? 'Claude ligado para os robôs.' : 'Claude desligado: todos vão para a rotação grátis.'),
            title: const Text('Claude ligado (interruptor geral)', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Desligado = nenhum robô usa o Claude; todos usam só a rotação grátis.'),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Por robô: "usar Claude" e modelo (Haiku ou Sonnet; Opus nunca é automático)',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ...e.robos.map((r) => ListTile(
                enabled: e.ligado,
                title: Text(r.nome),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_prioridade(r.prioridade)} · ${r.chave}', style: const TextStyle(fontSize: 12)),
                  DropdownButton<String>(
                    isDense: true,
                    value: r.modeloEscolhivel,
                    hint: Text(r.modelo.isEmpty
                        ? 'escolher modelo'
                        : (r.modelo.contains('opus') ? '${r.modelo} (o porteiro usa Sonnet)' : r.modelo)),
                    items: [
                      for (final m in kModelosClaude.entries)
                        DropdownMenuItem(value: m.key, child: Text(m.value, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: bloqueado
                        ? null
                        : (m) {
                            if (m == null || m == r.modelo) return;
                            _tentar(context, () => store.gravarRobo(r.chave, modelo: m),
                                '${r.nome}: agora usa ${kModelosClaude[m]}.');
                          },
                  ),
                ]),
                trailing: Switch(
                  value: r.usar,
                  onChanged: bloqueado
                      ? null
                      : (v) => _tentar(context, () => store.gravarRobo(r.chave, usar: v),
                          v ? '${r.nome}: usa o Claude primeiro.' : '${r.nome}: só a rotação grátis.'),
                ),
              )),
        ]),
      ),
    );
  }

  // ── d) Lições dos robôs ──────────────────────────────────────────────────

  Widget _cartaoLicoes(BuildContext context) {
    final String resumo;
    if (!store.licoesAtivas) {
      resumo = 'Ainda não ativado (tabela licoes_robos por criar).';
    } else if (store.erroLicoes != null) {
      resumo = 'Erro ao ler: ${store.erroLicoes}';
    } else {
      resumo = '${store.licoes.length} ${store.verArquivadas ? 'arquivadas' : 'ativas'} · '
          'o que os robôs erraram e a regra certa (todos os robôs leem as ativas)';
    }
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.menu_book_outlined, color: AppColors.primary),
        title: const Text('Lições dos robôs', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(resumo, style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: !store.licoesAtivas
            ? const []
            : [
                SwitchListTile(
                  dense: true,
                  value: store.verArquivadas,
                  onChanged: (v) => store.mostrarArquivadas(v),
                  title: const Text('Ver arquivadas'),
                ),
                if (store.licoes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(store.verArquivadas ? 'Nenhuma lição arquivada.' : 'Nenhuma lição ativa.',
                        style: const TextStyle(color: AppColors.textSubtle)),
                  ),
                ...store.licoes.map((l) => _linhaLicao(context, l)),
              ],
      ),
    );
  }

  Widget _linhaLicao(BuildContext context, LicaoRobo l) {
    final data = l.ativa
        ? 'criada ${dataHoraLisboa(l.criadaEm?.toIso8601String())}'
            '${l.editadaEm != null ? ' · editada ${dataHoraLisboa(l.editadaEm!.toIso8601String())}' : ''}'
        : 'arquivada ${dataHoraLisboa(l.arquivadaEm?.toIso8601String())}${l.arquivadaPor != null ? ' por ${l.arquivadaPor}' : ''}';
    return ListTile(
      isThreeLine: true,
      title: Text('${l.robo} · ${l.vezes}x', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Errou: ${l.errou}\nRegra: ${l.regra}\n${l.origem} · $data'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (l.ativa)
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _dialogoLicao(context, l),
          ),
        IconButton(
          tooltip: l.ativa ? 'Arquivar (os robôs deixam de ler)' : 'Reativar',
          icon: Icon(l.ativa ? Icons.archive_outlined : Icons.unarchive_outlined),
          onPressed: () => _confirmarArquivo(context, l),
        ),
      ]),
    );
  }

  Future<void> _dialogoLicao(BuildContext context, LicaoRobo l) async {
    final errou = TextEditingController(text: l.errou);
    final regra = TextEditingController(text: l.regra);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar lição · ${l.robo}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: errou,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'O que o robô errou'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: regra,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'A regra certa'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    // Sem dispose() aqui: a animação de saída do diálogo ainda desenha os campos.
    final e = errou.text.trim();
    final r = regra.text.trim();
    if (ok != true || !context.mounted) return;
    if (e.isEmpty || r.isEmpty) {
      _snack(context, 'Os dois campos são obrigatórios.');
      return;
    }
    await _tentar(context, () => store.editarLicao(l, errou: e, regra: r), 'Lição salva.');
  }

  Future<void> _confirmarArquivo(BuildContext context, LicaoRobo l) async {
    final arquivar = l.ativa;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(arquivar ? 'Arquivar esta lição?' : 'Reativar esta lição?'),
        content: Text(arquivar
            ? 'Os robôs deixam de a ler. Fica guardada em "Ver arquivadas".'
            : 'Os robôs voltam a ler esta lição.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(arquivar ? 'Arquivar' : 'Reativar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _tentar(context, () => store.arquivarLicao(l, arquivar: arquivar),
        arquivar ? 'Lição arquivada.' : 'Lição reativada.');
  }
}
