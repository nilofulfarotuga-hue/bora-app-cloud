// Missão hermes-diretor-2026-11-20 (B10) — AUTORIZAÇÕES do Hermes no painel admin (PT-BR).
// O Hermes (robô diretor) só mexe em valores ou apaga com o "autorizo" do Danilo. Cada pedido
// chega aqui: o que vai fazer, porquê, quanto, e quanto tempo falta. Dois botões grandes:
// Autorizo (o único laranja do ecrã) e Recusar. A decisão vai SÓ pela RPC
// admin_hermes_autorizacao_decidir (a tabela não aceita escrita direta).
// Rotas: /admin/autorizacoes e /admin/autorizacoes/<id> (abre com esse pedido em destaque).
// Atualiza sozinho de 30 em 30 s; a contagem "expira em X min" desce a cada 10 s.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/hermes_diretor_model.dart';
import '../../stores/hermes_autorizacoes_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import '_hermes_widgets.dart';

class AdminAutorizacoesScreen extends StatefulWidget {
  const AdminAutorizacoesScreen({
    super.key,
    this.destacarId,
    this.store,
    this.relogio = true,
    this.agora,
  });

  /// O pedido que o link abriu (/admin/autorizacoes/<id>): fica com moldura verde.
  final int? destacarId;

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final AutorizacoesStore? store;

  /// `false` nos testes: sem temporizadores, o ecrã assenta.
  final bool relogio;

  /// Só para testes: a hora "de agora".
  final DateTime Function()? agora;

  @override
  State<AdminAutorizacoesScreen> createState() => _AdminAutorizacoesScreenState();
}

class _AdminAutorizacoesScreenState extends State<AdminAutorizacoesScreen> {
  late final AutorizacoesStore _store = widget.store ?? AutorizacoesStore();
  Timer? _relogio;
  int _ticks = 0;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _store.carregar();
    if (widget.relogio) {
      _relogio = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        _ticks++;
        if (_ticks % 3 == 0) {
          _store.carregar(silencioso: true); // de 30 em 30 s
        } else {
          setState(() {}); // só a contagem a descer
        }
      });
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  Future<void> _autorizar(AutorizacaoHermes a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorizar?'),
        content: Text('Autorizar: ${a.acao} — ${euros(a.valorEur)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sim, autorizar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _decidir(a, autorizar: true);
  }

  Future<void> _decidir(AutorizacaoHermes a, {required bool autorizar}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await _store.decidir(a.id, autorizar: autorizar);
      if (r.ok) {
        messenger.showSnackBar(SnackBar(
            content: Text(autorizar ? 'Autorizado. O Hermes já pode seguir.' : 'Recusado. O Hermes não vai fazer isto.')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Não foi possível decidir: ${_erroDaRpc(r)}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível decidir: ${humanizeAdminRpcError(e)}')));
    }
  }

  String _erroDaRpc(ResultadoDecisao r) {
    final e = r.erro ?? '';
    if (e.isEmpty) return 'o servidor não aceitou (estado: ${r.estado ?? '—'}).';
    return switch (e) {
      'expirada' => 'o pedido já expirou. O Hermes tem de pedir de novo.',
      'ja_decidida' => 'este pedido já foi decidido.',
      _ => e,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Autorizações do Hermes',
        actions: [
          IconButton(onPressed: () => _store.carregar(), icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (_store.carregando && _store.lista.isEmpty && !_store.naoLigado) {
            return const Center(child: CircularProgressIndicator());
          }
          final agora = _agora();
          final pendentes = _store.pendentes(agora);
          final historico = _store.historico(agora);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'O Hermes só mexe em valores ou apaga dados depois do seu "autorizo". '
                'Cada autorização serve para uma só operação, uma só vez, e dura 30 minutos.',
                style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
              ),
              const SizedBox(height: 12),
              if (_store.naoLigado) const FaixaNaoLigado(),
              if (_store.erro != null) ErroLeitura(humanizeAdminRpcError(_store.erro!)),
              if (!_store.naoLigado && _store.erro == null) ...[
                _titulo('À espera de você (${pendentes.length})'),
                if (pendentes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nenhum pedido à espera. Quando o Hermes precisar, aparece aqui.',
                        style: TextStyle(color: AppColors.textSubtle)),
                  ),
                for (var i = 0; i < pendentes.length; i++) _cartaoPendente(pendentes[i], agora, primeiro: i == 0),
                const SizedBox(height: 16),
                _titulo('Histórico (${historico.length})'),
                if (historico.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Ainda não há pedidos decididos.', style: TextStyle(color: AppColors.textSubtle)),
                  ),
                for (final a in historico) _linhaHistorico(a, agora),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );

  Widget _cartaoPendente(AutorizacaoHermes a, DateTime agora, {required bool primeiro}) {
    final destaque = widget.destacarId == a.id;
    final min = a.minutosAteExpirar(agora);
    final ocupado = _store.aDecidir.contains(a.id);
    String operacaoTexto;
    try {
      operacaoTexto = a.operacao == null ? '—' : const JsonEncoder.withIndent('  ').convert(a.operacao);
    } catch (_) {
      operacaoTexto = '${a.operacao}';
    }
    return Card(
      key: ValueKey('autorizacao-${a.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: destaque ? AppColors.primary : AppColors.divider, width: destaque ? 3 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Pedido número ${a.id}', style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            const SizedBox(width: 8),
            if (a.teste) const EtiquetaHermes('TESTE', cor: AppColors.info),
            const Spacer(),
            Text(min > 0 ? 'expira em $min min' : 'expirou',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: min > 0 && min <= 5 ? AppColors.error : AppColors.textSecondary)),
          ]),
          const SizedBox(height: 8),
          const Text('O Hermes vai fazer:', style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
          Text(a.acao, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (a.porque.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Porquê:', style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            Text(a.porque, style: const TextStyle(fontSize: 14)),
          ],
          const SizedBox(height: 8),
          Text('Valor: ${euros(a.valorEur)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Detalhe técnico (a chamada exata que o Hermes vai fazer)',
                  style: TextStyle(fontSize: 13, color: AppColors.textSubtle)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(operacaoTexto, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  // O único laranja do ecrã: só o primeiro pedido da fila; os outros ficam verdes.
                  style: FilledButton.styleFrom(
                    backgroundColor: primeiro ? AppColors.accent : AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: ocupado || min <= 0 ? null : () => _autorizar(a),
                  child: const Text('Autorizo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: ocupado ? null : () => _decidir(a, autorizar: false),
                  child: const Text('Recusar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _linhaHistorico(AutorizacaoHermes a, DateTime agora) {
    final estado = a.estadoNaTela(agora);
    final cor = switch (estado) {
      'autorizada' || 'usada' => AppColors.primary,
      'recusada' => AppColors.error,
      _ => AppColors.textSubtle,
    };
    final destaque = widget.destacarId == a.id;
    final via = AutorizacaoHermes.rotuloVia(a.via);
    final quem = (a.decididaPor ?? '').isEmpty ? '' : 'por ${a.decididaPor}';
    final decisao = [
      if (a.decididaEm != null) dataHoraLisboa(a.decididaEm!.toIso8601String()),
      if (quem.isNotEmpty) quem,
      if (via.isNotEmpty) via,
    ].join(' · ');
    return Card(
      key: ValueKey('autorizacao-${a.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: destaque ? AppColors.primary : AppColors.divider, width: destaque ? 3 : 1),
      ),
      child: ListTile(
        isThreeLine: true,
        title: Row(children: [
          Expanded(child: Text(a.acao, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (a.teste) ...[const EtiquetaHermes('TESTE', cor: AppColors.info), const SizedBox(width: 6)],
          EtiquetaHermes(AutorizacaoHermes.rotuloEstado(estado), cor: cor),
        ]),
        subtitle: Text(
          'Pedido ${a.id} · ${euros(a.valorEur)} · pedido ${dataHoraLisboa(a.criadaEm?.toIso8601String())}'
          '${decisao.isEmpty ? '' : '\n$decisao'}'
          '${(a.resultado ?? '').isEmpty ? '' : '\nResultado: ${a.resultado}'}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
