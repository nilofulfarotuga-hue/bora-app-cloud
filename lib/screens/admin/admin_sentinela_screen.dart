// Missão hermes-diretor-2026-11-20 (B10) — SENTINELA no painel admin (PT-BR).
// A sentinela é o vigia do Hermes: repara em pedido parado, pagamento estranho, erro repetido,
// robô em apuros e carrinho abandonado, e abre uma tarefa para o Hermes tratar. Este ecrã mostra
// os eventos por gravidade (urgente / normal / informação), a hora (Lisboa), o título e "o que o
// Hermes fez" (estado e resultado da tarefa ligada). "Marcar como visto" grava tratado_em e
// tratado_por='admin'. Lê `sentinela_eventos` e `despacho` (SELECT).

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/hermes_diretor_model.dart';
import '../../stores/sentinela_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import '_hermes_widgets.dart';

class AdminSentinelaScreen extends StatefulWidget {
  const AdminSentinelaScreen({super.key, this.store});

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final SentinelaStore? store;

  @override
  State<AdminSentinelaScreen> createState() => _AdminSentinelaScreenState();
}

class _AdminSentinelaScreenState extends State<AdminSentinelaScreen> {
  late final SentinelaStore _store = widget.store ?? SentinelaStore();

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

  Color _cor(String g) => switch (g) {
        'urgente' => AppColors.error,
        'normal' => AppColors.warning,
        _ => AppColors.info,
      };

  Future<void> _visto(EventoSentinela e) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store.marcarVisto(e.id);
      messenger.showSnackBar(const SnackBar(content: Text('Marcado como visto.')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível marcar: ${humanizeAdminRpcError(err)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Sentinela (o vigia do Hermes)',
        actions: [
          IconButton(onPressed: () => _store.carregar(), icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (_store.carregando && _store.eventos.isEmpty && !_store.naoLigado) {
            return const Center(child: CircularProgressIndicator());
          }
          final visiveis = _store.visiveis;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'O vigia olha para a app de minuto a minuto. Quando vê algo errado, avisa aqui e o Hermes '
                'abre uma tarefa para tratar. "Marcar como visto" só tira o aviso da lista de pendentes.',
                style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
              ),
              const SizedBox(height: 12),
              if (_store.naoLigado) const FaixaNaoLigado(),
              if (_store.erro != null) ErroLeitura(humanizeAdminRpcError(_store.erro!)),
              if (!_store.naoLigado && _store.erro == null) ...[
                _filtros(),
                const SizedBox(height: 8),
                if (visiveis.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Nenhum evento por aqui. Está tudo calmo.',
                          style: TextStyle(color: AppColors.textSubtle)),
                    ),
                  ),
                for (final g in const ['urgente', 'normal', 'info']) ..._grupo(g, visiveis),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _filtros() {
    Widget chip(String? g, String rotulo) => ChoiceChip(
          label: Text(rotulo),
          selected: _store.filtroGravidade == g,
          onSelected: (_) => _store.filtrar(g),
        );
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      chip(null, 'Todos'),
      chip('urgente', 'Urgente (${_store.porVer('urgente')})'),
      chip('normal', 'Normal (${_store.porVer('normal')})'),
      chip('info', 'Informação (${_store.porVer('info')})'),
      FilterChip(
        label: const Text('Só os por ver'),
        selected: _store.soPorVer,
        onSelected: _store.mudarSoPorVer,
      ),
    ]);
  }

  List<Widget> _grupo(String g, List<EventoSentinela> todos) {
    final lista = todos.where((e) => e.gravidade == g).toList();
    if (lista.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(EventoSentinela.rotuloGravidade(g).toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _cor(g))),
      ),
      for (final e in lista) _cartao(e),
    ];
  }

  Widget _cartao(EventoSentinela e) {
    final cor = _cor(e.gravidade);
    final tarefa = _store.tarefaDe(e);
    final ocupado = _store.aMarcar.contains(e.id);
    final String fez;
    if (e.despachoId == null) {
      fez = 'Ainda sem tarefa: o Hermes não abriu nada para este aviso.';
    } else if (tarefa == null) {
      fez = 'Tarefa número ${e.despachoId} (não deu para ler o estado).';
    } else {
      final res = (tarefa.resultado ?? '').trim();
      fez = 'Tarefa número ${tarefa.id}: ${tarefa.estado ?? '—'}${res.isEmpty ? '' : ' — $res'}';
    }
    return Card(
      key: ValueKey('sentinela-${e.id}'),
      color: e.tratado ? AppColors.surface2 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EtiquetaHermes(EventoSentinela.rotuloGravidade(e.gravidade), cor: cor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(EventoSentinela.rotuloTipo(e.tipo),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            ),
            Text(dataHoraLisboa(e.criadoEm?.toIso8601String()),
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
          ]),
          const SizedBox(height: 6),
          Text(e.titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('O que o Hermes fez: $fez', style: const TextStyle(fontSize: 13)),
          if ((e.resultado ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Resultado: ${e.resultado}', style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 8),
          if (e.tratado)
            Text(
              'Visto ${dataHoraLisboa(e.tratadoEm?.toIso8601String())}${(e.tratadoPor ?? '').isEmpty ? '' : ' por ${e.tratadoPor}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: ocupado ? null : () => _visto(e),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Marcar como visto'),
              ),
            ),
        ]),
      ),
    );
  }
}
