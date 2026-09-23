// Missão jev-decisor-2026-09-23 — DECISÕES (painel admin, PT-BR).
//
// O Decisor (Edge Function `decidir`: Jev da TypeSafe com Gemini de reserva) responde a
// perguntas pequenas e tipadas — escolher (choice), dar nota (score), sim/não (noul) — e
// grava cada resposta em `decisoes`. Este ecrã mostra:
//  • o cartão "Quanto custou hoje" (tokens × preço, por motor) e se o Jev já tem chave;
//  • um interruptor por regra: desligado / sombra (decide e só registra) / ativo;
//  • a lista das últimas decisões com filtros por tipo, motor e regra, a confiança, e o
//    que aconteceu de verdade (acertou / errou) quando já se sabe.
// Lê `admin_decisor_resumo()` e a tabela `decisoes` (RLS: só admin). Muda o modo por
// `admin_decisor_set_modo` (auditado em admin_audit_log).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/decisao_model.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Lê o resumo + as últimas decisões. Nulo = Supabase (os testes injetam um falso).
typedef CarregarDecisoes = Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> Function();

/// Chama um RPC de ação. Nulo = Supabase.
typedef ChamarRpcDecisor = Future<dynamic> Function(String fn, Map<String, dynamic> params);

class AdminDecisoesScreen extends StatefulWidget {
  const AdminDecisoesScreen({super.key, this.carregar, this.chamarRpc});

  final CarregarDecisoes? carregar;
  final ChamarRpcDecisor? chamarRpc;

  @override
  State<AdminDecisoesScreen> createState() => _AdminDecisoesScreenState();
}

class _AdminDecisoesScreenState extends State<AdminDecisoesScreen> {
  Map<String, dynamic> _resumo = {};
  List<Decisao> _decisoes = [];
  bool _carregando = true;
  String? _erro;
  String? _filtroTipo;
  String? _filtroMotor;
  String? _filtroRegra;

  /// Regra cujo modo está a ser gravado agora (trava só aquele interruptor — PADRÃO 3.13).
  String? _gravandoRegra;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _lerSupabase() async {
    final sb = Supabase.instance.client;
    final resumo = await sb.rpc('admin_decisor_resumo');
    final linhas = await sb
        .from('decisoes')
        .select('id, quando, tipo, pergunta, estado_resumo, resposta, confianca, probabilidades, motor, modelo, '
            'latencia_ms, tokens_entrada, custo_usd, usado_por, contexto_id, modo, acao_tomada, erro, resultado_real')
        .order('quando', ascending: false)
        .limit(200);
    return (
      Map<String, dynamic>.from((resumo as Map?) ?? {}),
      List<Map<String, dynamic>>.from(linhas),
    );
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final (resumo, linhas) = await (widget.carregar ?? _lerSupabase)();
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _decisoes = linhas.map(Decisao.fromMap).toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Future<void> _mudarModo(String regra, String modo) async {
    setState(() => _gravandoRegra = regra);
    try {
      final chamar = widget.chamarRpc ??
          (String fn, Map<String, dynamic> p) => Supabase.instance.client.rpc(fn, params: p);
      await chamar('admin_decisor_set_modo', {'p_regra': regra, 'p_modo': modo});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${rotuloRegraDecisor(regra)}: agora em "$modo".'),
        ));
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível mudar: $e')));
      }
    } finally {
      if (mounted) setState(() => _gravandoRegra = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Decisões (Jev / Gemini)',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _cartaoCusto(),
                      const SizedBox(height: 8),
                      _cartaoRegras(),
                      const SizedBox(height: 8),
                      _filtros(),
                      const SizedBox(height: 4),
                      ..._listaFiltrada(),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoCusto() {
    final hoje = Map<String, dynamic>.from((_resumo['hoje'] as Map?) ?? {});
    final temChave = _resumo['tem_chave_jev'] == true;
    final custo = custoHojeUsd(hoje);
    final porMotor = hoje.entries.map((e) {
      final v = Map<String, dynamic>.from(e.value as Map);
      return '${e.key}: ${v['chamadas']} chamadas · ${v['tokens_entrada']} tokens · '
          'US\$ ${(v['custo_usd'] as num? ?? 0).toStringAsFixed(6)} · mediana ${v['latencia_mediana_ms'] ?? '—'} ms';
    }).join('\n');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quanto custou hoje', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Wrap(spacing: 18, runSpacing: 6, children: [
              _kv('Custo (US\$)', custo.toStringAsFixed(6)),
              _kv('Decisões', '${somaHoje(hoje, 'chamadas')}'),
              _kv('Tokens de entrada', '${somaHoje(hoje, 'tokens_entrada')}'),
              _kv('Jev (TypeSafe)', temChave ? 'com chave' : 'SEM chave — usando Gemini'),
            ]),
            if (porMotor.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(porMotor, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 6),
            Text(
              'Preço do Jev: US\$ ${_resumo['preco_jev_usd_mtok'] ?? '0.042'} por milhão de tokens de entrada (saída grátis).',
              style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
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

  Widget _cartaoRegras() {
    final modos = Map<String, dynamic>.from((_resumo['modos'] as Map?) ?? {});
    final acerto = Map<String, dynamic>.from((_resumo['acerto'] as Map?) ?? {});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Regras (sombra = decide e só registra, não manda)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            for (final regra in kRegrasDecisor) _linhaRegra(regra, (modos[regra] ?? 'desligado').toString(), acerto),
          ],
        ),
      ),
    );
  }

  Widget _linhaRegra(String regra, String modo, Map<String, dynamic> acerto) {
    final pontos = acerto.entries.where((e) => e.key.startsWith('$regra:')).map((e) {
      final v = Map<String, dynamic>.from(e.value as Map);
      return '${e.key.split(':').last}: acertou ${v['acertou']} de ${v['com_resultado']}';
    }).join(' · ');
    final opcoes = ['desligado', 'sombra', if (regraAceitaAtivo(regra)) 'ativo'];
    final gravando = _gravandoRegra == regra;
    return Padding(
      key: ValueKey('regra_$regra'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotuloRegraDecisor(regra), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (pontos.isNotEmpty)
            Text(pontos, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (!regraAceitaAtivo(regra))
            Text(
              regra == 'despacho'
                  ? 'Modo ativo não existe: mexer no despacho é zona protegida (só proposta).'
                  : 'Modo ativo ainda sem ação definida — por agora só sombra.',
              style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final o in opcoes)
                ChoiceChip(
                  key: ValueKey('modo_${regra}_$o'),
                  label: Text(o),
                  selected: modo == o,
                  selectedColor: AppColors.primaryLight,
                  onSelected: gravando || modo == o ? null : (_) => _mudarModo(regra, o),
                ),
              if (gravando) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    Widget grupo(String titulo, List<String?> valores, String? atual, ValueChanged<String?> escolher,
        String Function(String?) rotulo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            for (final v in valores)
              ChoiceChip(
                label: Text(rotulo(v)),
                selected: atual == v,
                onSelected: (_) => setState(() => escolher(v)),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        grupo('Tipo:', [null, 'choice', 'score', 'noul'], _filtroTipo, (v) => _filtroTipo = v,
            (v) => v == null ? 'todos' : {'choice': 'escolha', 'score': 'nota', 'noul': 'sim/não'}[v]!),
        grupo('Motor:', [null, 'jev', 'gemini', 'nenhum'], _filtroMotor, (v) => _filtroMotor = v,
            (v) => v ?? 'todos'),
        grupo('Regra:', [null, ...kRegrasDecisor], _filtroRegra, (v) => _filtroRegra = v,
            (v) => v == null ? 'todas' : rotuloRegraDecisor(v)),
      ],
    );
  }

  List<Widget> _listaFiltrada() {
    final lista = filtrarDecisoes(_decisoes, tipo: _filtroTipo, motor: _filtroMotor, usadoPor: _filtroRegra);
    if (lista.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nenhuma decisão com estes filtros.')),
        ),
      ];
    }
    return lista.map(_linhaDecisao).toList();
  }

  Widget _linhaDecisao(Decisao d) {
    final acertou = d.acertou;
    final cor = d.motor == 'nenhum'
        ? AppColors.error
        : (acertou == null ? AppColors.textSubtle : (acertou ? AppColors.success : AppColors.warning));
    final quando = '${d.quando.day.toString().padLeft(2, '0')}/${d.quando.month.toString().padLeft(2, '0')} '
        '${d.quando.hour.toString().padLeft(2, '0')}:${d.quando.minute.toString().padLeft(2, '0')}';
    final conf = d.confianca == null ? '—' : '${(d.confianca! * 100).round()}%';
    final real = d.resultadoReal == null
        ? 'resultado real: ainda não se sabe'
        : 'resultado real: ${d.resultadoReal} (${acertou == true ? 'acertou' : acertou == false ? 'errou' : '—'})';
    return Card(
      child: ExpansionTile(
        leading: Icon(
          d.motor == 'nenhum' ? Icons.error_outline : Icons.bolt,
          color: cor,
        ),
        title: Text('${rotuloRegraDecisor(d.usadoPor)} · ${d.respostaLegivel}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$quando · ${d.motor}${d.modelo != null ? ' (${d.modelo})' : ''} · confiança $conf · '
          '${d.latenciaMs ?? 0} ms · ${d.modo}\n$real',
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('Pergunta: ${d.pergunta}', style: const TextStyle(fontSize: 12)),
          if (d.probabilidades.isNotEmpty)
            Text(
              'Probabilidades: ${d.probabilidades.entries.map((e) => '${e.key} ${(e.value * 100).toStringAsFixed(1)}%').join(' · ')}',
              style: const TextStyle(fontSize: 12),
            ),
          if (d.contextoId != null) SelectableText('Referência: ${d.contextoId}', style: const TextStyle(fontSize: 12)),
          if (d.acaoTomada != null) Text('Ação tomada: ${d.acaoTomada}', style: const TextStyle(fontSize: 12)),
          if (d.estadoResumo != null)
            SelectableText('Estado enviado: ${d.estadoResumo}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (d.erro != null)
            SelectableText('Erro: ${d.erro}', style: const TextStyle(fontSize: 11, color: AppColors.error)),
        ],
      ),
    );
  }
}
