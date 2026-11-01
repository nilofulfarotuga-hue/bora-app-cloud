import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../stores/casa_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/checkout_legal_notice.dart';
import 'casa_chat_screen.dart';
import 'casa_meus_pedidos_screen.dart';
import 'casa_regras.dart';
import 'casa_widgets.dart';

/// Abre o acompanhamento a partir só do id (toque num aviso `casa_status`,
/// `bookingId` = id do pedido). Lê o pedido no servidor; se não conseguir,
/// abre "Os meus pedidos" — nunca deixa o toque sem resposta.
Future<void> abrirCasaPedidoPorId(BuildContext context, String pedidoId) async {
  final store = context.read<CasaStore>();
  final pedido = await store.pedido(pedidoId);
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => pedido == null
          ? const CasaMeusPedidosScreen()
          : CasaPedidoScreen(pedido: pedido),
    ),
  );
}

/// CASA — acompanhamento do pedido do cliente (31/10/2026).
///
/// Linha do tempo dos estados, orçamentos recebidos (comparar e aceitar),
/// pedidos de valor extra (aceitar/recusar), chat e ligar SÓ com
/// `pode_contactar`, confirmar a conclusão com as fotos de antes e depois,
/// avaliar (só depois de confirmado e pago), pedir para refazer (garantia) e
/// cancelar com a simulação do custo primeiro.
///
/// Tudo o que muda o pedido é uma RPC; aqui só se reage. O tempo real vem do
/// [CasaStore.abrirPedido]; ao voltar ao primeiro plano relê-se o servidor.
class CasaPedidoScreen extends StatefulWidget {
  const CasaPedidoScreen({
    super.key,
    required this.pedido,
    this.acabadoDeCriar = false,
    this.agora,
  });

  final CasaPedido pedido;

  /// Aberto logo a seguir a criar: mostra a faixa "Pedido feito".
  final bool acabadoDeCriar;

  /// Relógio do ecrã — só os testes o trocam.
  @visibleForTesting
  final DateTime Function()? agora;

  @override
  State<CasaPedidoScreen> createState() => _CasaPedidoScreenState();
}

class _CasaPedidoScreenState extends State<CasaPedidoScreen>
    with WidgetsBindingObserver {
  // Guardado no initState: ler o Provider no dispose rebenta quando o ecrã
  // sai da árvore junto com ele (cicatriz do chat da limpeza, 07/10).
  late final CasaStore _store;

  /// Trava de re-entrada LOCAL (PADRAO_BORA 3.13): uma para todas as ações,
  /// porque todas mexem no MESMO pedido.
  bool _acaoEmCurso = false;
  bool _aJuntarFoto = false;

  @override
  void initState() {
    super.initState();
    _store = context.read<CasaStore>();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _store.abrirPedido(widget.pedido);
      _store.refreshTracked();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.fecharPedido(widget.pedido.id);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _store.refreshTracked();
  }

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  /// O pedido mais recente que o store tem (tempo real), senão o recebido.
  CasaPedido get _pedido {
    final a = _store.aberto;
    return (a != null && a.id == widget.pedido.id) ? a : widget.pedido;
  }

  Future<void> _comTrava(Future<void> Function() acao) async {
    if (_acaoEmCurso) return;
    setState(() => _acaoEmCurso = true);
    try {
      await acao();
    } catch (e) {
      _snack(casaMensagemDeErro(e, maxCashCents: _store.config.maxCashCents));
    } finally {
      if (mounted) setState(() => _acaoEmCurso = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── orçamentos ───────────────────────────────────────────────────────────

  Future<void> _aceitarOrcamento(CasaOrcamento o) async {
    final config = _store.config;
    var metodo =
        casaMetodoPorDefeito(totalCents: o.precoCents, config: config);
    // Regra 1.2: o botão nunca fica mudo — sem método possível, o toque diz
    // porquê (hoje: dinheiro acima do limite e cartão/MB Way por ligar).
    String? aviso;
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Aceitar o orçamento de {0}'.trArgs([casaEuro(o.precoCents)]),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Escolhe como vais pagar. Os outros orçamentos ficam recusados.'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.lg),
              CasaEscolhaPagamento(
                totalCents: o.precoCents,
                config: config,
                metodo: metodo,
                onEscolher: (m) => setSheet(() {
                  metodo = m;
                  aviso = null;
                }),
              ),
              const SizedBox(height: Spacing.md),
              const CheckoutLegalNotice(kind: CheckoutLegalKind.servico),
              const SizedBox(height: Spacing.sm),
              if (aviso != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    aviso!,
                    key: const Key('casa_aceitar_orcamento_aviso'),
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              BoraPrimaryButton(
                key: const Key('casa_aceitar_orcamento_confirmar'),
                label: 'Aceitar com obrigação de pagar'.tr,
                onPressed: () {
                  final m = metodo;
                  if (m == null) {
                    setSheet(() => aviso = casaExplicacaoDinheiro(config));
                    return;
                  }
                  Navigator.pop(ctx, m);
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Agora não'.tr,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    await _comTrava(() async {
      await _store.aceitarOrcamento(o.id, escolhido);
      _snack('Orçamento aceite. O profissional já foi avisado.'.tr);
    });
  }

  // ── extras ───────────────────────────────────────────────────────────────

  Future<void> _responderExtra(CasaExtra e, bool aceitar) async {
    if (aceitar) {
      final p = _pedido;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Aceitar mais {0}?'.trArgs([casaEuro(e.valorCents)])),
          content: Text(
            'O total passa a {0}. Motivo: {1}'.trArgs(
                [casaEuro(p.totalCents + e.valorCents), e.motivo]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Aceitar'.tr),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _comTrava(() async {
      await _store.responderExtra(e.id, aceitar);
      _snack(aceitar
          ? 'Valor extra aceite.'.tr
          : 'Valor extra recusado. O profissional já foi avisado.'.tr);
    });
  }

  // ── conclusão, avaliação, refazer ────────────────────────────────────────

  Future<void> _confirmarConclusao() async {
    CasaPedido? novo;
    await _comTrava(() async {
      novo = await _store.confirmarConclusao(_pedido.id);
      _snack('Obrigado! Trabalho confirmado.'.tr);
    });
    final p = novo;
    if (p != null && mounted && p.ratingCliente == null && casaPedidoPago(p)) {
      await _avaliar();
    }
  }

  Future<void> _avaliar() async {
    var estrelas = 5;
    final comentarioCtrl = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Como correu o trabalho?'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '{0} estrelas'.trArgs([i]),
                      onPressed: () => setDialog(() => estrelas = i),
                      icon: Icon(
                        i <= estrelas ? Icons.star : Icons.star_border,
                        color: AppColors.warning,
                        size: 30,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: comentarioCtrl,
                maxLines: 2,
                maxLength: 500,
                decoration:
                    InputDecoration(hintText: 'Comentário (opcional)'.tr),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Agora não'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enviar'.tr),
            ),
          ],
        ),
      ),
    );
    final comentario = comentarioCtrl.text.trim();
    if (enviar != true || !mounted) return;
    await _comTrava(() async {
      await _store.avaliar(_pedido.id, estrelas, comentario: comentario);
      _snack('Obrigado pela avaliação!'.tr);
    });
  }

  Future<void> _pedirRefazer() async {
    final motivoCtrl = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Pedir para refazer'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Diz o que ficou mal. O profissional volta sem custo dentro da garantia, e a equipa do Bora acompanha.'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: motivoCtrl,
                maxLines: 3,
                maxLength: 500,
                onChanged: (_) => setDialog(() {}),
                decoration:
                    InputDecoration(hintText: 'O que correu mal?'.tr),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr),
            ),
            TextButton(
              onPressed: motivoCtrl.text.trim().length < 5
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Enviar'.tr),
            ),
          ],
        ),
      ),
    );
    final motivo = motivoCtrl.text.trim();
    if (enviar != true || !mounted) return;
    await _comTrava(() async {
      await _store.pedirRefazer(_pedido.id, motivo);
      _snack('Pedido para refazer enviado.'.tr);
    });
  }

  // ── cancelar (simulação primeiro) ────────────────────────────────────────

  Future<void> _cancelar() async {
    if (_acaoEmCurso) return;
    setState(() => _acaoEmCurso = true);
    CasaSimulacaoCancelamento? sim;
    try {
      sim = await _store.simularCancelamento(_pedido.id);
    } catch (e) {
      _snack(casaMensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _acaoEmCurso = false);
    }
    if (sim == null || !mounted) return;
    final s = sim;
    final custo = s.gratis
        ? 'Podes cancelar sem pagar nada.'.tr
        : s.escalao == 'total'
            ? 'Como já está muito perto da hora, cancelar custa o valor total: {0}.'.trArgs([casaEuro(s.taxaCents)])
            : 'Como falta pouco tempo, cancelar custa {0}.'.trArgs([casaEuro(s.taxaCents)]);
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar o pedido?'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(custo),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: motivoCtrl,
              maxLines: 2,
              maxLength: 300,
              decoration: InputDecoration(hintText: 'Motivo (opcional)'.tr),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Manter o pedido'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar pedido'.tr,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    final motivo = motivoCtrl.text.trim();
    if (confirmar != true || !mounted) return;
    await _comTrava(() async {
      final taxa = await _store.cancelar(_pedido.id, motivo: motivo);
      _snack(taxa > 0
          ? 'Pedido cancelado. Taxa de cancelamento: {0}.'.trArgs([casaEuro(taxa)])
          : 'Pedido cancelado.'.tr);
    });
  }

  // ── fotos e contacto ─────────────────────────────────────────────────────

  Future<void> _juntarFoto() async {
    if (_aJuntarFoto) return;
    setState(() => _aJuntarFoto = true);
    try {
      final f = await casaEscolherFoto(context);
      if (f == null || !mounted) return;
      await _store.adicionarFoto(_pedido.id, f.bytes, extensao: f.extensao);
      await _store.refreshTracked();
      _snack('Foto enviada.'.tr);
    } catch (e) {
      _snack(casaMensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _aJuntarFoto = false);
    }
  }

  Future<void> _ligar(String telefone) async {
    final uri = Uri.parse('tel:$telefone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    _snack('Não consegui abrir o telefone. O número é {0}.'.trArgs([telefone]));
  }

  void _abrirChat(CasaPedido p) {
    final prof = p.profissional;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CasaChatScreen(
          pedidoId: p.id,
          titulo: (prof?.nome.isNotEmpty ?? false)
              ? prof!.nome
              : 'O teu profissional'.tr,
          telefone: prof?.phone,
        ),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CasaStore>();
    final p = _pedido;
    final acoes = CasaAcoesCliente.de(p,
        agora: _agora(), maxFotos: store.config.maxFotos);
    final fim =
        p.estado == CasaEstado.cancelado || p.estado == CasaEstado.expirado;
    final servico = store.servicoPorId(p.servicoId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: p.servicoNome.isEmpty ? 'O teu pedido'.tr : p.servicoNome,
      ),
      body: RefreshIndicator(
        onRefresh: store.refreshTracked,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          children: [
            if (widget.acabadoDeCriar && !fim) ...[
              _FaixaPedidoFeito(orcamento: p.modo == CasaModo.orcamento),
              const SizedBox(height: Spacing.lg),
            ],
            if (fim) _FaixaFim(pedido: p) else _LinhaDoTempo(pedido: p),
            const SizedBox(height: Spacing.lg),
            if (p.estado == CasaEstado.disputa) ...[
              _Aviso(
                icone: Icons.replay_outlined,
                texto:
                    'Pediste para refazer. O profissional e a equipa do Bora já foram avisados.'.tr,
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (acoes.responderExtras) ...[
              for (final e in p.extrasPorResponder) ...[
                _CartaoExtra(
                  extra: e,
                  ocupado: _acaoEmCurso,
                  onAceitar: () => _responderExtra(e, true),
                  onRecusar: () => _responderExtra(e, false),
                ),
                const SizedBox(height: Spacing.md),
              ],
            ],
            if (p.modo == CasaModo.orcamento &&
                (p.estado == CasaEstado.orcamentos ||
                    p.orcamentos.isNotEmpty)) ...[
              _SecaoOrcamentos(
                pedido: p,
                agora: _agora(),
                quoteMaxPros: store.config.quoteMaxPros,
                podeAceitar: acoes.aceitarOrcamentos,
                ocupado: _acaoEmCurso,
                onAceitar: _aceitarOrcamento,
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (p.profissional != null && !fim) ...[
              _CartaoProfissional(
                pedido: p,
                podeContactar: acoes.contactar,
                onChat: () => _abrirChat(p),
                onLigar: _ligar,
              ),
              const SizedBox(height: Spacing.lg),
            ],
            if (const {
              CasaEstado.concluido,
              CasaEstado.confirmado,
              CasaEstado.disputa,
            }.contains(p.estado)) ...[
              _CartaoTrabalhoFeito(pedido: p),
              const SizedBox(height: Spacing.lg),
            ],
            if (acoes.confirmarConclusao) ...[
              BoraPrimaryButton(
                label: 'Confirmar que está tudo bem'.tr,
                icon: Icons.check_circle,
                loading: _acaoEmCurso,
                onPressed: _confirmarConclusao,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Confirma depois de ver o trabalho. Se algo não estiver bem, pede para refazer.'.tr,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (acoes.avaliar) ...[
              BoraPrimaryButton(
                label: 'Avaliar o profissional'.tr,
                icon: Icons.star,
                loading: _acaoEmCurso,
                onPressed: _avaliar,
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (p.ratingCliente != null) ...[
              Text(
                'A tua avaliação: {0} de 5'.trArgs([p.ratingCliente]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Spacing.md),
            ],
            _CartaoDetalhes(pedido: p, servico: servico),
            const SizedBox(height: Spacing.lg),
            _CartaoFotosDoProblema(
              pedido: p,
              podeJuntar: acoes.adicionarFotos,
              aJuntar: _aJuntarFoto,
              onJuntar: _juntarFoto,
            ),
            if (acoes.refazer) ...[
              const SizedBox(height: Spacing.sm),
              TextButton.icon(
                onPressed: _acaoEmCurso ? null : _pedirRefazer,
                icon: const Icon(Icons.replay_outlined),
                label: Text(p.garantiaAte != null &&
                        p.estado == CasaEstado.confirmado
                    ? 'Algo correu mal? Pedir para refazer (garantia até {0})'.trArgs([casaQuandoTexto(p.garantiaAte!)])
                    : 'Algo correu mal? Pedir para refazer'.tr),
              ),
            ],
            if (acoes.cancelar) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _acaoEmCurso ? null : _cancelar,
                child: Text('Cancelar pedido'.tr,
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── widgets internos ────────────────────────────────────────────────────────

class _FaixaPedidoFeito extends StatelessWidget {
  const _FaixaPedidoFeito({required this.orcamento});

  final bool orcamento;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.task_alt, color: AppColors.primary, size: 28),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              orcamento
                  ? 'Pedido de orçamento enviado! Avisamos-te quando chegarem respostas.'.tr
                  : 'Pedido feito! Estamos a procurar um profissional para ti.'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return CasaCartao(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(texto,
                style: const TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _FaixaFim extends StatelessWidget {
  const _FaixaFim({required this.pedido});

  final CasaPedido pedido;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final expirado = p.estado == CasaEstado.expirado;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(expirado ? Icons.hourglass_top_outlined : Icons.cancel_outlined,
                  color: AppColors.textSecondary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  casaEstadoTr(p.estado),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            expirado
                ? 'Não encontrámos profissional disponível para esta hora. Experimenta marcar outra hora.'.tr
                : p.cancelFeeCents > 0
                    ? 'Taxa de cancelamento: {0}.'.trArgs([casaEuro(p.cancelFeeCents)])
                    : 'Sem custo de cancelamento.'.tr,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (!expirado && (p.cancelReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            // Motivo escrito por uma pessoa: fica como está (sem .tr).
            Text(
              p.cancelReason!.trim(),
              style: const TextStyle(
                  color: AppColors.textSubtle, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaDoTempo extends StatelessWidget {
  const _LinhaDoTempo({required this.pedido});

  final CasaPedido pedido;

  DateTime? _hora(CasaEstado e) => switch (e) {
        CasaEstado.procura || CasaEstado.orcamentos => pedido.createdAt,
        CasaEstado.aceite => pedido.acceptedAt,
        CasaEstado.aCaminho => pedido.onTheWayAt,
        CasaEstado.chegou => pedido.arrivedAt,
        CasaEstado.emCurso => pedido.startedAt,
        CasaEstado.concluido => pedido.doneAt,
        CasaEstado.confirmado => pedido.confirmedAt,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final passos = casaPassosDaLinha(pedido.modo);
    final atual = casaIndiceNaLinha(pedido.estado, passos);
    return CasaCartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            casaEstadoTr(pedido.estado),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          for (var i = 0; i < passos.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      i < atual
                          ? Icons.check_circle
                          : i == atual
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                      size: 20,
                      color:
                          i <= atual ? AppColors.primary : AppColors.textSubtle,
                    ),
                    if (i < passos.length - 1)
                      Container(
                        width: 2,
                        height: 20,
                        color: i < atual ? AppColors.primary : AppColors.divider,
                      ),
                  ],
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      casaRotuloPasso(passos[i]),
                      style: TextStyle(
                        color: i <= atual
                            ? AppColors.textPrimary
                            : AppColors.textSubtle,
                        fontWeight:
                            i == atual ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (i <= atual && _hora(passos[i]) != null)
                  Text(
                    casaQuandoTexto(_hora(passos[i])!),
                    style: const TextStyle(
                        color: AppColors.textSubtle, fontSize: 11),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CartaoExtra extends StatelessWidget {
  const _CartaoExtra({
    required this.extra,
    required this.ocupado,
    required this.onAceitar,
    required this.onRecusar,
  });

  final CasaExtra extra;
  final bool ocupado;
  final VoidCallback onAceitar;
  final VoidCallback onRecusar;

  @override
  Widget build(BuildContext context) {
    return CasaCartao(
      destacado: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'O profissional pede mais {0}'.trArgs([casaEuro(extra.valorCents)]),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          // Motivo escrito pelo profissional: sem .tr.
          Text(extra.motivo,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.xs),
          Text(
            'Só é cobrado se aceitares.'.tr,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: ocupado ? null : onRecusar,
                  child: Text('Recusar'.tr),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: BoraPrimaryButton(
                  label: 'Aceitar'.tr,
                  loading: ocupado,
                  onPressed: onAceitar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecaoOrcamentos extends StatelessWidget {
  const _SecaoOrcamentos({
    required this.pedido,
    required this.agora,
    required this.quoteMaxPros,
    required this.podeAceitar,
    required this.ocupado,
    required this.onAceitar,
  });

  final CasaPedido pedido;
  final DateTime agora;
  final int quoteMaxPros;
  final bool podeAceitar;
  final bool ocupado;
  final ValueChanged<CasaOrcamento> onAceitar;

  @override
  Widget build(BuildContext context) {
    final lista = [...pedido.orcamentos]..sort((a, b) {
        if (a.aberto != b.aberto) return a.aberto ? -1 : 1;
        return a.precoCents.compareTo(b.precoCents);
      });
    final abertos = lista.where((o) => o.aberto).toList();
    final maisBarato = abertos.length > 1 ? abertos.first.id : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CasaTituloSecao(
            'Orçamentos recebidos ({0})'.trArgs([pedido.orcamentos.length])),
        if (lista.isEmpty)
          _Aviso(
            icone: Icons.schedule_outlined,
            texto:
                'Ainda não chegou nenhum orçamento. Avisamos-te assim que chegar — até {0} profissionais podem responder.'.trArgs([quoteMaxPros]),
          ),
        for (final o in lista) ...[
          _CartaoOrcamento(
            orcamento: o,
            maisBarato: o.id == maisBarato,
            podeAceitar: podeAceitar && casaOrcamentoAceitavel(o, agora),
            ocupado: ocupado,
            onAceitar: () => onAceitar(o),
          ),
          const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

class _CartaoOrcamento extends StatelessWidget {
  const _CartaoOrcamento({
    required this.orcamento,
    required this.maisBarato,
    required this.podeAceitar,
    required this.ocupado,
    required this.onAceitar,
  });

  final CasaOrcamento orcamento;
  final bool maisBarato;
  final bool podeAceitar;
  final bool ocupado;
  final VoidCallback onAceitar;

  String _estadoTexto(String estado) => switch (estado) {
        'aceite' => 'Aceite'.tr,
        'recusado' => 'Recusado'.tr,
        'expirado' => 'Expirado'.tr,
        'retirado' => 'Retirado pelo profissional'.tr,
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final o = orcamento;
    final prof = o.profissional;
    final estado = _estadoTexto(o.estado);
    final expira = o.expiraEm;
    return Opacity(
      opacity: o.aberto || o.estado == 'aceite' ? 1 : 0.6,
      child: CasaCartao(
        destacado: o.estado == 'aceite',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prof != null) CasaResumoProfissional(pessoa: prof),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Text(
                  casaEuro(o.precoCents),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                if (maisBarato)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryWash,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      'Mais barato'.tr,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                if (estado.isNotEmpty)
                  Text(
                    estado,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // O que o profissional escreveu (inclui, materiais, prazo): é
            // texto dele, por isso vai sem .tr.
            if (o.inclui.trim().isNotEmpty)
              CasaLinhaResumo('Inclui'.tr, o.inclui.trim()),
            CasaLinhaResumo(
              'Materiais'.tr,
              o.materiaisIncluidos
                  ? (o.materiais.trim().isEmpty
                      ? 'Incluídos no preço'.tr
                      : 'Incluídos: {0}'.trArgs([o.materiais.trim()]))
                  : (o.materiais.trim().isEmpty
                      ? 'Não incluídos'.tr
                      : 'À parte: {0}'.trArgs([o.materiais.trim()])),
            ),
            if (o.prazo.trim().isNotEmpty)
              CasaLinhaResumo('Prazo'.tr, o.prazo.trim()),
            if ((o.duracaoMin ?? 0) > 0)
              CasaLinhaResumo('Duração'.tr, casaDuracaoTexto(o.duracaoMin!)),
            if (o.aberto && expira != null)
              CasaLinhaResumo('Válido até'.tr, casaQuandoTexto(expira)),
            if (podeAceitar) ...[
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Aceitar este orçamento'.tr,
                loading: ocupado,
                onPressed: onAceitar,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartaoProfissional extends StatelessWidget {
  const _CartaoProfissional({
    required this.pedido,
    required this.podeContactar,
    required this.onChat,
    required this.onLigar,
  });

  final CasaPedido pedido;
  final bool podeContactar;
  final VoidCallback onChat;
  final ValueChanged<String> onLigar;

  @override
  Widget build(BuildContext context) {
    final prof = pedido.profissional!;
    final telefone = prof.phone;
    return CasaCartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CasaTituloSecao('O teu profissional'.tr),
          CasaResumoProfissional(pessoa: prof),
          const SizedBox(height: Spacing.md),
          if (podeContactar)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text('Mensagens'.tr),
                  ),
                ),
                if (telefone != null && telefone.isNotEmpty) ...[
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onLigar(telefone),
                      icon: const Icon(Icons.call),
                      label: Text('Ligar'.tr),
                    ),
                  ),
                ],
              ],
            )
          else
            Text(
              'As mensagens e o telefone aparecem quando o trabalho estiver aceite e pago.'.tr,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _CartaoTrabalhoFeito extends StatelessWidget {
  const _CartaoTrabalhoFeito({required this.pedido});

  final CasaPedido pedido;

  @override
  Widget build(BuildContext context) {
    final antes = pedido.fotosDe('antes');
    final depois = pedido.fotosDe('depois');
    final extra = pedido.fotosDe('extra');
    return CasaCartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CasaTituloSecao('O trabalho feito'.tr),
          if (antes.isEmpty && depois.isEmpty && extra.isEmpty)
            Text(
              'O profissional não juntou fotos.'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          CasaFilaDeFotos(titulo: 'Antes'.tr, fotos: antes),
          CasaFilaDeFotos(titulo: 'Depois'.tr, fotos: depois),
          CasaFilaDeFotos(titulo: 'Outras'.tr, fotos: extra),
        ],
      ),
    );
  }
}

class _CartaoDetalhes extends StatelessWidget {
  const _CartaoDetalhes({required this.pedido, required this.servico});

  final CasaPedido pedido;
  final CasaServico? servico;

  String _metodo(String m) => switch (m) {
        'card' => 'Cartão'.tr,
        'mbway' => 'MB Way'.tr,
        _ => 'Dinheiro'.tr,
      };

  /// Texto da pergunta pelo id (catálogo); sem catálogo, o próprio id.
  String _pergunta(String id) {
    for (final p in servico?.perguntas ?? const <CasaPergunta>[]) {
      if (p.id == id) return p.texto;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final quando = p.scheduledAt;
    final orcamentoPorEscolher =
        p.modo == CasaModo.orcamento && p.estado == CasaEstado.orcamentos;
    final s = servico;
    return CasaCartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CasaTituloSecao('Detalhes'.tr),
          if (p.oficioNome.isNotEmpty) CasaLinhaResumo('Ofício'.tr, p.oficioNome),
          if (p.modo != CasaModo.orcamento && s != null && s.maxQuantidade > s.minQuantidade)
            CasaLinhaResumo(
                casaRotuloQuantidade(s), casaQuantidadeTexto(s, p.quantidade)),
          if (quando != null) CasaLinhaResumo('Quando'.tr, casaQuandoTexto(quando)),
          if (p.morada.isNotEmpty) CasaLinhaResumo('Onde'.tr, p.morada),
          for (final e in p.respostas.entries)
            if ('${e.value}'.trim().isNotEmpty)
              CasaLinhaResumo(_pergunta(e.key), '${e.value}'),
          if (p.descricao.trim().isNotEmpty)
            CasaLinhaResumo('O que escreveste'.tr, p.descricao.trim()),
          if (!orcamentoPorEscolher) ...[
            const Divider(height: Spacing.lg),
            CasaLinhaResumo('Pagamento'.tr, _metodo(p.paymentMethod)),
            if (p.precoCents > 0)
              CasaLinhaResumo('Preço'.tr, casaEuro(p.precoCents)),
            if (p.extrasCents > 0)
              CasaLinhaResumo('Extras aceites'.tr, '+ ${casaEuro(p.extrasCents)}'),
            if (p.totalCents > 0)
              CasaLinhaResumo('Total'.tr, casaEuro(p.totalCents), forte: true),
          ],
          if (p.garantiaAte != null)
            CasaLinhaResumo('Garantia até'.tr, casaQuandoTexto(p.garantiaAte!)),
        ],
      ),
    );
  }
}

class _CartaoFotosDoProblema extends StatelessWidget {
  const _CartaoFotosDoProblema({
    required this.pedido,
    required this.podeJuntar,
    required this.aJuntar,
    required this.onJuntar,
  });

  final CasaPedido pedido;
  final bool podeJuntar;
  final bool aJuntar;
  final VoidCallback onJuntar;

  @override
  Widget build(BuildContext context) {
    final fotos = pedido.fotosDe('problema');
    if (fotos.isEmpty && !podeJuntar) return const SizedBox.shrink();
    return CasaCartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CasaTituloSecao('As tuas fotos'.tr),
          if (fotos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                'Ainda sem fotos. Uma foto ajuda o profissional a vir preparado.'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final f in fotos)
                CasaFotoPrivada(storagePath: f.storagePath),
            ],
          ),
          if (podeJuntar) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: aJuntar ? null : onJuntar,
                icon: aJuntar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text('Juntar foto'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
