// Missão hermes-diretor-2026-11-20 (B10) — LIÇÕES DOS ROBÔS no painel admin (PT-BR).
// Por robô (suporte, Amigo, WhatsApp, Hermes): as lições (o que errou e a regra certa) com
// ligar/desligar e editar, o contador `vezes`, e por baixo os casos de teste do robô com o
// último resultado da regressão (passou/falhou e quando). Lê `licoes_robos`, `robos_casos_teste`
// e a RPC robos_regressao_resumo. As lições antes viviam num cartão de /admin/motores;
// agora esse cartão abre este ecrã (nada duplicado).

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/credito_claude_model.dart' show LicaoRobo;
import '../../models/hermes_diretor_model.dart';
import '../../stores/licoes_robos_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import '_hermes_widgets.dart';

class AdminLicoesRobosScreen extends StatefulWidget {
  const AdminLicoesRobosScreen({super.key, this.store});

  /// Só para testes; em produção fica nulo e usa o Supabase.
  final LicoesRobosStore? store;

  @override
  State<AdminLicoesRobosScreen> createState() => _AdminLicoesRobosScreenState();
}

class _AdminLicoesRobosScreenState extends State<AdminLicoesRobosScreen> {
  late final LicoesRobosStore _store = widget.store ?? LicoesRobosStore();

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

  Future<void> _tentar(Future<void> Function() acao, String ok) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await acao();
      messenger.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: ${humanizeAdminRpcError(e)}')));
    }
  }

  static String _nomeRobo(String r) => switch (r) {
        'suporte' => 'Suporte',
        'amigo' => 'Amigo Bora',
        'whatsapp' => 'WhatsApp das lojas',
        'hermes' => 'Hermes',
        _ => r,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Lições dos robôs',
        actions: [
          IconButton(onPressed: () => _store.carregar(), icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (_store.carregando && _store.licoes.isEmpty && _store.casos.isEmpty && !_store.naoLigado) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Cada vez que um robô erra, fica uma lição com a regra certa, e todos os robôs leem as lições ligadas. '
                'Os casos de teste (regressão) repetem perguntas reais para ver se o robô ainda acerta.',
                style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
              ),
              const SizedBox(height: 12),
              if (_store.naoLigado) const FaixaNaoLigado(),
              if (_store.erro != null) ErroLeitura(humanizeAdminRpcError(_store.erro!)),
              if (!_store.naoLigado)
                for (final robo in _store.robos) _cartaoRobo(robo),
            ],
          );
        },
      ),
    );
  }

  Widget _cartaoRobo(String robo) {
    final licoes = _store.licoesDe(robo);
    final casos = _store.casosDe(robo);
    final ativas = licoes.where((l) => l.ativa).length;
    final r = _store.resumoDe(robo);
    final String teste;
    if (_store.casosNaoLigado) {
      teste = 'testes: ainda não ligado';
    } else if (r.casos == 0) {
      teste = 'sem casos de teste';
    } else {
      teste = 'testes: ${r.passaram} de ${r.casos} passaram';
    }
    final falhou = !_store.casosNaoLigado && r.falharam > 0;
    return Card(
      key: ValueKey('robo-$robo'),
      child: ExpansionTile(
        initiallyExpanded: licoes.isNotEmpty || casos.isNotEmpty,
        leading: Icon(Icons.smart_toy_outlined, color: falhou ? AppColors.error : AppColors.primary),
        title: Text(_nomeRobo(robo), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${licoes.length} lições ($ativas ligadas) · $teste',
            style: TextStyle(fontSize: 12, color: falhou ? AppColors.error : null)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (_store.licoesNaoLigado)
            const Padding(padding: EdgeInsets.all(12), child: FaixaNaoLigado(detalhe: 'Falta a tabela das lições (licoes_robos).'))
          else if (licoes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nenhuma lição para este robô.', style: TextStyle(color: AppColors.textSubtle)),
            ),
          ...licoes.map(_linhaLicao),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Casos de teste (regressão)', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (_store.casosNaoLigado)
            const Padding(padding: EdgeInsets.all(12), child: FaixaNaoLigado(detalhe: 'Faltam os casos de teste (robos_casos_teste).'))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(_textoResumo(r), style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            ),
            if (casos.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Nenhum caso de teste para este robô.', style: TextStyle(color: AppColors.textSubtle)),
              ),
            ...casos.map(_linhaCaso),
          ],
        ],
      ),
    );
  }

  String _textoResumo(ResumoRegressao r) {
    if (r.casos == 0) return 'Última regressão: ainda sem casos.';
    final quando = r.ultimaCorridaEm == null ? 'nunca corrida' : dataHoraLisboa(r.ultimaCorridaEm!.toIso8601String());
    return 'Última regressão ($quando): ${r.casos} casos, ${r.passaram} passaram, '
        '${r.falharam} falharam, ${r.nuncaCorridos} nunca corridos.';
  }

  Widget _linhaLicao(LicaoRobo l) {
    final ocupado = _store.aGravar.contains(l.id);
    return ListTile(
      key: ValueKey('licao-${l.id}'),
      isThreeLine: true,
      title: Text('${l.vezes}x · ${l.regra}',
          style: TextStyle(fontWeight: FontWeight.w600, color: l.ativa ? null : AppColors.textSubtle)),
      subtitle: Text(
        'Errou: ${l.errou}\n${l.origem}${l.origem.isEmpty ? '' : ' · '}'
        '${l.ativa ? 'criada ${dataHoraLisboa(l.criadaEm?.toIso8601String())}' : 'desligada ${dataHoraLisboa(l.arquivadaEm?.toIso8601String())}'}'
        '${l.editadaEm != null ? ' · editada ${dataHoraLisboa(l.editadaEm!.toIso8601String())}' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Editar a regra',
          icon: const Icon(Icons.edit_outlined),
          onPressed: ocupado ? null : () => _dialogoEditar(l),
        ),
        Switch(
          value: l.ativa,
          onChanged: ocupado
              ? null
              : (v) => _tentar(() => _store.definirLicaoAtiva(l, v),
                  v ? 'Lição ligada: os robôs voltam a ler.' : 'Lição desligada: os robôs deixam de ler.'),
        ),
      ]),
    );
  }

  Widget _linhaCaso(CasoTesteRobo c) {
    final ocupado = _store.aGravar.contains(-c.id);
    final Color cor;
    final String rotulo;
    switch (c.ultimoResultado) {
      case 'passou':
        cor = AppColors.primary;
        rotulo = 'Passou';
      case 'falhou':
        cor = AppColors.error;
        rotulo = 'Falhou';
      default:
        cor = AppColors.textSubtle;
        rotulo = 'Nunca corrido';
    }
    return ListTile(
      key: ValueKey('caso-${c.id}'),
      isThreeLine: true,
      title: Text(c.pergunta, style: TextStyle(fontSize: 14, color: c.ativo ? null : AppColors.textSubtle)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.deveConter.isNotEmpty)
          Text('Tem de conter: ${c.deveConter.join(', ')}', style: const TextStyle(fontSize: 12)),
        if (c.naoPodeConter.isNotEmpty)
          Text('Não pode conter: ${c.naoPodeConter.join(', ')}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Row(children: [
          EtiquetaHermes(rotulo, cor: cor),
          const SizedBox(width: 8),
          if (c.ultimaCorridaEm != null)
            Text(dataHoraLisboa(c.ultimaCorridaEm!.toIso8601String()),
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        ]),
        if (c.ultimoResultado == 'falhou' && (c.ultimaResposta ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Resposta: ${c.ultimaResposta}',
                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
      ]),
      trailing: Switch(
        value: c.ativo,
        onChanged: ocupado
            ? null
            : (v) => _tentar(() => _store.definirCasoAtivo(c, v),
                v ? 'Caso de teste ligado.' : 'Caso de teste desligado.'),
      ),
    );
  }

  Future<void> _dialogoEditar(LicaoRobo l) async {
    final errou = TextEditingController(text: l.errou);
    final regra = TextEditingController(text: l.regra);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar lição · ${_nomeRobo(l.robo)}'),
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
    if (ok != true || !mounted) return;
    if (e.isEmpty || r.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Os dois campos são obrigatórios.')));
      return;
    }
    await _tentar(() => _store.editarLicao(l, errou: e, regra: r), 'Lição salva.');
  }
}
