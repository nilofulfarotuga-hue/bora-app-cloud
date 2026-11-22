// Missão hermes-diretor-2026-11-20 (B10) — aba "Agentes" de /admin/motores e o cartão da previsão
// do crédito do Claude (PT-BR).
// Cada agente da tabela agentes_estado aparece com o estado em palavras simples (ligado ao relógio,
// a pedido, arquivado), a % de tarefas auditadas nas últimas 24 h e três botões, cada um com
// confirmação. Nada se apaga: "arquivar" só pára o agente.
// O gasto do mês mostrado é o do Hermes inteiro: o livro de gastos (ia_gastos) não diz qual
// agente fez cada chamada, por isso não se reparte por agente.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/hermes_diretor_model.dart';
import '../../stores/agentes_hermes_store.dart';
import '../../utils/hora_lisboa.dart';
import '_admin_rpc_errors.dart';
import '_hermes_widgets.dart';

class AdminAgentesTab extends StatefulWidget {
  const AdminAgentesTab({super.key, this.store});

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final AgentesHermesStore? store;

  @override
  State<AdminAgentesTab> createState() => _AdminAgentesTabState();
}

class _AdminAgentesTabState extends State<AdminAgentesTab> {
  late final AgentesHermesStore _store = widget.store ?? AgentesHermesStore();

  @override
  void initState() {
    super.initState();
    _store.carregar();
  }

  @override
  void dispose() {
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  Color _cor(EstadoAgente e) => switch (e) {
        EstadoAgente.relogio => AppColors.primary,
        EstadoAgente.aPedido => AppColors.info,
        EstadoAgente.arquivado => AppColors.textSubtle,
      };

  Future<void> _mudar(AgenteEstado a, EstadoAgente novo) async {
    final pergunta = switch (novo) {
      EstadoAgente.relogio => 'Ligar "${a.agente}" ao relógio? Ele passa a correr sozinho nos horários dele.',
      EstadoAgente.aPedido => 'Pôr "${a.agente}" a pedido? Só corre quando alguém lhe pedir uma tarefa.',
      EstadoAgente.arquivado => 'Arquivar "${a.agente}"? Ele pára de correr. Nada é apagado e dá para voltar atrás.',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AgenteEstado.rotuloEstado(novo)),
        content: Text(pergunta),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store.mudarEstado(a, novo);
      messenger.showSnackBar(SnackBar(content: Text('${a.agente}: ${AgenteEstado.rotuloEstado(novo).toLowerCase()}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível mudar: ${_msg(e)}')));
    }
  }

  String _msg(Object e) => e is StateError ? e.message : humanizeAdminRpcError(e);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (_store.carregando && _store.agentes.isEmpty && !_store.naoLigado) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Os agentes são os ajudantes do Hermes. "Ligado ao relógio" corre sozinho nos horários; '
              '"a pedido" só corre quando o Hermes ou você mandar; "arquivado" fica parado (nada se apaga).',
              style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
            ),
            const SizedBox(height: 12),
            if (_store.naoLigado) const FaixaNaoLigado(detalhe: 'Falta a tabela dos agentes (agentes_estado).'),
            if (_store.erro != null) ErroLeitura(humanizeAdminRpcError(_store.erro!)),
            if (!_store.naoLigado && _store.erro == null) ...[
              _resumo(),
              const SizedBox(height: 8),
              if (_store.arquivarEmFalta)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: FaixaNaoLigado(detalhe: 'Arquivar ainda não está ligado: faltam as colunas novas dos agentes.'),
                ),
              if (_store.agentes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhum agente registado.', style: TextStyle(color: AppColors.textSubtle)),
                ),
              for (final a in _store.agentes) _cartao(a),
            ],
          ],
        );
      },
    );
  }

  String _textoAuditoria(AuditoriaAgente? t) {
    if (t == null || t.precisavam == 0) return 'sem tarefas para auditar';
    final p = t.percentagem ?? (t.auditadasOk * 100 / t.precisavam);
    return '${p.toStringAsFixed(0)} % (${t.auditadasOk} de ${t.precisavam})';
  }

  Widget _kv(String k, String v) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );

  Widget _resumo() {
    final porEstado = {
      for (final e in EstadoAgente.values) e: _store.agentes.where((a) => a.estado == e).length,
    };
    final gasto = _store.gastoHermesMesUsd;
    return Card(
      key: const ValueKey('agentes-resumo'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 18, runSpacing: 8, children: [
            _kv('Ao relógio', '${porEstado[EstadoAgente.relogio]}'),
            _kv('A pedido', '${porEstado[EstadoAgente.aPedido]}'),
            _kv('Arquivados', '${porEstado[EstadoAgente.arquivado]}'),
            _kv('Tarefas auditadas (24 h)', _store.auditoriaLigada ? _textoAuditoria(_store.auditoriaTotal) : 'ainda não ligado'),
            _kv('Gasto do mês do Hermes (todos os agentes juntos)', gasto == null ? '—' : dolares(gasto)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'O livro de gastos não diz qual agente fez cada chamada, por isso o gasto é o total do Hermes.',
            style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
          ),
        ]),
      ),
    );
  }

  Widget _cartao(AgenteEstado a) {
    final estado = a.estado;
    final cor = _cor(estado);
    final ocupado = _store.aGravar.contains(a.agente);
    final aud = _store.auditoriaPorAgente[a.agente];
    return Card(
      key: ValueKey('agente-${a.agente}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(a.agente, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (a.desligado) ...[const EtiquetaHermes('desligado', cor: AppColors.textSubtle), const SizedBox(width: 6)],
            EtiquetaHermes(AgenteEstado.rotuloEstado(estado), cor: cor),
          ]),
          if (a.papel.isNotEmpty || a.departamento.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [if (a.papel.isNotEmpty) a.papel, if (a.departamento.isNotEmpty) '(${a.departamento})'].join(' '),
              style: const TextStyle(fontSize: 13),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 18, runSpacing: 4, children: [
            _kv('Auditadas (24 h)', _store.auditoriaLigada ? _textoAuditoria(aud) : 'ainda não ligado'),
            _kv('Última corrida', a.ultimaCorrida == null ? '—' : dataHoraLisboa(a.ultimaCorrida!.toIso8601String())),
            if (a.cadenciaMin != null) _kv('Cadência', 'a cada ${a.cadenciaMin} min'),
            if (a.tetoDiaEur != null) _kv('Teto por dia', euros(a.tetoDiaEur)),
          ]),
          if ((a.substituto ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Quem faz o trabalho dele agora: ${a.substituto}', style: const TextStyle(fontSize: 12)),
            ),
          if ((a.erro ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Último erro: ${a.erro}', style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton(
              onPressed: ocupado || estado == EstadoAgente.relogio ? null : () => _mudar(a, EstadoAgente.relogio),
              child: const Text('Ligar ao relógio'),
            ),
            OutlinedButton(
              onPressed: ocupado || (estado == EstadoAgente.aPedido && !a.desligado) ? null : () => _mudar(a, EstadoAgente.aPedido),
              child: const Text('Pôr a pedido'),
            ),
            OutlinedButton(
              onPressed: ocupado || estado == EstadoAgente.arquivado || _store.arquivarEmFalta
                  ? null
                  : () => _mudar(a, EstadoAgente.arquivado),
              child: const Text('Arquivar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Cartão "Previsão do mês" do crédito do Claude: gasto até hoje, previsão até ao fim do mês,
/// quanto falta e quem gasta mais. Lê a RPC admin_credito_claude_previsao().
class CartaoPrevisaoClaude extends StatefulWidget {
  const CartaoPrevisaoClaude({super.key, this.store});

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final PrevisaoClaudeStore? store;

  @override
  State<CartaoPrevisaoClaude> createState() => _CartaoPrevisaoClaudeState();
}

class _CartaoPrevisaoClaudeState extends State<CartaoPrevisaoClaude> {
  late final PrevisaoClaudeStore _store = widget.store ?? PrevisaoClaudeStore();

  @override
  void initState() {
    super.initState();
    _store.carregar();
  }

  @override
  void dispose() {
    if (widget.store == null) _store.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final p = _store.previsao;
        final Widget corpo;
        if (_store.naoLigado) {
          corpo = const FaixaNaoLigado(detalhe: 'Falta a função da previsão (admin_credito_claude_previsao).');
        } else if (_store.erro != null) {
          corpo = ErroLeitura(humanizeAdminRpcError(_store.erro!));
        } else if (p == null) {
          corpo = const Text('Carregando…', style: TextStyle(color: AppColors.textSubtle));
        } else {
          final pct = p.percentagem == null ? '—' : '${p.percentagem!.toStringAsFixed(0)} %';
          corpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 18, runSpacing: 8, children: [
              _kv('Gasto do mês até hoje (dia ${p.diaDoMes} de ${p.diasNoMes})', dolares(p.gastoUsd)),
              _kv('Previsão até ao fim do mês', dolares(p.previsaoUsd)),
              _kv('Crédito do mês', dolares(p.creditoUsd)),
              _kv('Quanto falta (crédito − previsão)', dolares(p.faltaUsd)),
              _kv('Do crédito já gasto', pct),
            ]),
            if (PrevisaoClaude.rotuloEstado(p.estado).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(PrevisaoClaude.rotuloEstado(p.estado), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 10),
            const Text('Quem gasta mais (este mês)', style: TextStyle(fontWeight: FontWeight.w600)),
            if (p.top.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Nenhuma chamada ao Claude este mês.', style: TextStyle(fontSize: 13, color: AppColors.textSubtle)),
              ),
            ...p.top.map((t) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${t.robo}${t.perfil.isEmpty ? '' : ' (${t.perfil})'}: ${dolares(t.usd)} · ${t.chamadas} chamadas',
                    style: const TextStyle(fontSize: 13),
                  ),
                )),
          ]);
        }
        return Card(
          key: const ValueKey('previsao-claude'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.trending_up, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Previsão do mês (crédito do Claude)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ]),
              const SizedBox(height: 8),
              corpo,
            ]),
          ),
        );
      },
    );
  }
}
