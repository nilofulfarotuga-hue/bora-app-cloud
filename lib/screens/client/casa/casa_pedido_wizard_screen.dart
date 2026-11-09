import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../models/falha_de_acao.dart';
import '../../../services/auto_address.dart';
import '../../../stores/casa_store.dart';
import '../../../stores/session_store.dart';
import '../../../utils/hora_lisboa.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/auto_address_hint.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/checkout_legal_notice.dart';
import 'casa_meus_pedidos_screen.dart';
import 'casa_pagamento_flow.dart';
import 'casa_pedido_screen.dart';
import 'casa_regras.dart';
import 'casa_widgets.dart';

/// CASA — assistente do pedido (31/10/2026). Três passos:
///   1. O trabalho: perguntas do serviço, quantidade/horas, texto livre, fotos
///   2. Quando e onde: dia e hora (Lisboa), morada preenchida sozinha
///   3. Confirmar: pagamento (preço fixo/hora) ou pedido de orçamento grátis
///
/// O total que aqui aparece é só para mostrar: o servidor recalcula sempre
/// (casa_criar_pedido). Ao confirmar: cria o pedido, sobe as fotos, abre o
/// acompanhamento.
///
/// Regra 1.26: nenhum passo fica preso à espera de uma permissão — a câmara
/// tem tecto de tempo e frase clara quando é recusada, e a localização é um
/// presente (AutoAddress nunca lança nem bloqueia).
class CasaPedidoWizardScreen extends StatefulWidget {
  const CasaPedidoWizardScreen({super.key, required this.servico, this.agora});

  final CasaServico servico;

  /// Relógio do ecrã — só os testes o trocam.
  @visibleForTesting
  final DateTime Function()? agora;

  @override
  State<CasaPedidoWizardScreen> createState() => _CasaPedidoWizardScreenState();
}

class _FotoEscolhida {
  const _FotoEscolhida(this.bytes, this.extensao);
  final Uint8List bytes;
  final String extensao;
}

class _CasaPedidoWizardScreenState extends State<CasaPedidoWizardScreen> {
  int _passo = 0;

  // Passo 1 — o trabalho
  late double _quantidade = widget.servico.minQuantidade;
  final Map<String, String> _escolhas = {};
  final Map<String, TextEditingController> _textos = {};
  final _descricaoCtrl = TextEditingController();
  final List<_FotoEscolhida> _fotos = [];
  bool _aEscolherFoto = false;

  // Passo 2 — quando e onde
  /// INSTANTE (UTC) em que o relógio de Lisboa marca a hora escolhida
  /// (regra 1.27 do PADRAO_BORA, igual à limpeza).
  DateTime? _quando;
  final _ruaCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  bool _aLocalizar = false;

  // Passo 3 — pagamento
  String? _metodo;

  /// Trava de re-entrada LOCAL do botão de avançar (PADRAO_BORA 3.13): fecha
  /// antes do primeiro await e só abre quando o fluxo inteiro acaba.
  bool _avancando = false;

  /// Uma chave de idempotência por assistente: repetir o "confirmar" (dois
  /// toques, rede que cai a meio) manda SEMPRE a mesma, e o servidor devolve
  /// o pedido que já criou em vez de criar outro.
  final String _chave = const Uuid().v4();

  final _scroll = ScrollController();
  final Map<CasaCampo, GlobalKey> _ancoras = {
    for (final c in CasaCampo.values) c: GlobalKey(),
  };
  final Map<String, GlobalKey> _ancorasPerguntas = {};

  CasaServico get _servico => widget.servico;
  bool get _orcamento => _servico.pedeOrcamento;

  @override
  void initState() {
    super.initState();
    for (final p in _servico.perguntas) {
      _ancorasPerguntas[p.id] = GlobalKey();
      if (!p.escolha) _textos[p.id] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ajustarMetodo();
      _preencherMoradaSozinho();
    });
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    _descricaoCtrl.dispose();
    _ruaCtrl.dispose();
    _cidadeCtrl.dispose();
    _postalCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  CasaConfig get _config => context.read<CasaStore>().config;

  int get _totalCents => casaTotalEstimadoCents(_servico, _quantidade) ?? 0;

  /// Mantém um método válido: se a quantidade passar o limite do dinheiro e
  /// o dinheiro estava escolhido, troca para o primeiro que sobrar (ou nenhum).
  void _ajustarMetodo() {
    if (_orcamento) return;
    final metodos =
        casaMetodosPagamento(totalCents: _totalCents, config: _config);
    final valido = metodos.any((m) => m.codigo == _metodo && m.disponivel);
    if (!valido) {
      setState(() {
        _metodo =
            casaMetodoPorDefeito(totalCents: _totalCents, config: _config);
      });
    }
  }

  // ── morada automática (o mesmo serviço do Favor e da Lavagem) ────────────

  /// Preenche a morada sem o cliente tocar em nada: morada guardada → casa →
  /// GPS. REGRA DE 24/08: nunca trava — falhar deixa os campos vazios.
  Future<void> _preencherMoradaSozinho() async {
    if (!mounted || _ruaCtrl.text.trim().isNotEmpty) return;
    setState(() => _aLocalizar = true);
    SessionStore? sessao;
    try {
      sessao = context.read<SessionStore>();
    } catch (_) {
      sessao = null; // sem SessionStore na árvore (testes): segue sem casa
    }
    final s = await AutoAddress.descobrir(
      homeStreet: sessao?.homeStreet,
      homeCity: sessao?.homeCity,
      homeLocation: sessao?.homeLocation,
    );
    if (!mounted) return;
    setState(() {
      _aLocalizar = false;
      // Se o cliente já começou a escrever, ganha ele.
      if (s != null && _ruaCtrl.text.trim().isEmpty) {
        final m = casaPartirMorada(s.morada);
        _ruaCtrl.text = m.rua.isEmpty ? s.morada : m.rua;
        if (_cidadeCtrl.text.trim().isEmpty) _cidadeCtrl.text = m.cidade;
        if (_postalCtrl.text.trim().isEmpty) {
          _postalCtrl.text = m.codigoPostal;
        }
        _lat = s.coords?.latitude;
        _lng = s.coords?.longitude;
      }
    });
  }

  void _aoEscolherMorada(String morada, ll.LatLng? coords) {
    setState(() {
      _lat = coords?.latitude;
      _lng = coords?.longitude;
      final m = casaPartirMorada(morada);
      if (m.cidade.isNotEmpty && _cidadeCtrl.text.trim().isEmpty) {
        _cidadeCtrl.text = m.cidade;
      }
      if (m.codigoPostal.isNotEmpty && _postalCtrl.text.trim().isEmpty) {
        _postalCtrl.text = m.codigoPostal;
      }
    });
  }

  /// A rua que vai ao servidor: se o campo ficou com a linha inteira do Google
  /// (traz código postal), fica só a parte da rua.
  String get _ruaFinal {
    final texto = _ruaCtrl.text.trim();
    final m = casaPartirMorada(texto);
    return (m.codigoPostal.isNotEmpty && m.rua.isNotEmpty) ? m.rua : texto;
  }

  // ── fotos ────────────────────────────────────────────────────────────────

  Future<void> _adicionarFoto() async {
    if (_aEscolherFoto) return;
    final max = _config.maxFotos;
    if (_fotos.length >= max) {
      _snack('Já tens {0} fotos — é o máximo.'.trArgs([max]));
      return;
    }
    setState(() => _aEscolherFoto = true);
    try {
      final f = await casaEscolherFoto(context);
      if (f != null && mounted) {
        setState(() => _fotos.add(_FotoEscolhida(f.bytes, f.extensao)));
      }
    } finally {
      if (mounted) setState(() => _aEscolherFoto = false);
    }
  }

  // ── navegação entre passos ───────────────────────────────────────────────

  List<String> get _titulos =>
      ['O trabalho'.tr, 'Quando e onde'.tr, 'Confirmar'.tr];

  Map<String, String> get _respostasTexto => {
        ..._escolhas,
        for (final e in _textos.entries) e.key: e.value.text.trim(),
      };

  CasaFalta? _faltaNoPasso(int passo) {
    switch (passo) {
      case 0:
        return casaFaltaNoServico(
          servico: _servico,
          respostas: _respostasTexto,
          quantidade: _quantidade,
          descricao: _descricaoCtrl.text,
        );
      case 1:
        return casaFaltaNoQuandoOnde(
          quando: _quando,
          agora: _agora(),
          minLeadHours: _config.minLeadHours,
          rua: _ruaCtrl.text,
          cidade: _cidadeCtrl.text,
        );
      default:
        return casaFaltaNoPagamento(
          servico: _servico,
          metodo: _metodo,
          totalCents: _totalCents,
          config: _config,
        );
    }
  }

  Future<void> _avancar() async {
    if (_avancando) return;
    setState(() => _avancando = true);
    try {
      await _avancarPasso();
    } finally {
      if (mounted) setState(() => _avancando = false);
    }
  }

  Future<void> _avancarPasso() async {
    // Um botão que parece funcionar e não faz nada é pior do que um erro:
    // rola-se até ao campo que falta e diz-se qual é.
    final falta = _faltaNoPasso(_passo);
    if (falta != null) {
      await _mostrarFalta(falta);
      return;
    }
    if (_passo < 2) {
      setState(() => _passo += 1);
      _irAoTopo();
      return;
    }
    await _confirmar();
  }

  Future<void> _mostrarFalta(CasaFalta falta) async {
    final chave = falta.campo == CasaCampo.pergunta
        ? _ancorasPerguntas[falta.perguntaId]
        : _ancoras[falta.campo];
    final ctx = chave?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
    }
    _snack(falta.mensagem);
  }

  void _irAoTopo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _voltar() {
    if (_passo == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _passo -= 1);
      _irAoTopo();
    }
  }

  // ── confirmar ────────────────────────────────────────────────────────────

  Map<String, dynamic> get _respostasFinais => {
        for (final e in _respostasTexto.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      };

  Future<void> _confirmar() async {
    final store = context.read<CasaStore>();
    final quando = _quando;
    if (quando == null) return;
    try {
      var pedido = await store.criarPedido(
        servico: _servico,
        quantidade: _orcamento ? 1 : _quantidade,
        descricao: _descricaoCtrl.text.trim(),
        respostas: _respostasFinais,
        rua: _ruaFinal,
        cidade: _cidadeCtrl.text.trim(),
        codigoPostal: _postalCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        scheduledAt: quando,
        // No orçamento o servidor ignora (escolhe-se ao aceitar).
        metodoPagamento: _orcamento ? 'cash' : (_metodo ?? 'cash'),
        chave: _chave,
      );
      if (!mounted) return;

      // Fotos depois do pedido (precisam do id). Uma que falhe não estraga o
      // pedido: diz-se e pode juntar-se no ecrã do pedido.
      var falhadas = 0;
      for (final f in _fotos) {
        try {
          await store.adicionarFoto(pedido.id, f.bytes, extensao: f.extensao);
        } catch (e) {
          debugPrint('Casa: foto falhou => $e');
          falhadas += 1;
        }
      }
      if (_fotos.isNotEmpty) {
        pedido = await store.pedido(pedido.id) ?? pedido;
      }
      if (!mounted) return;
      // Cartão/MB Way (m11): cobra já. Se não fechar, o pedido fica "À espera do pagamento" e o
      // ecrã do pedido tem "Pagar agora"; só vai aos profissionais depois de pago.
      if (casaPorPagarNaApp(pedido)) {
        final pago = await CasaPagamentoFlow.pagar(context, store, pedido);
        if (pago) pedido = await store.pedido(pedido.id) ?? pedido;
        if (!mounted) return;
      }
      if (falhadas > 0) {
        _snack(
            'Não consegui enviar {0} foto(s). Podes juntá-las no ecrã do pedido.'.trArgs([falhadas]));
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CasaPedidoScreen(pedido: pedido, acabadoDeCriar: true),
        ),
      );
    } on JaFicouCriado catch (e) {
      // Não é falha: o pedido ficou feito, só a resposta se perdeu.
      if (!mounted) return;
      _snack(e.mensagem);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CasaMeusPedidosScreen()),
      );
    } catch (e) {
      _snack(casaMensagemDeErro(e, maxCashCents: store.config.maxCashCents));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = context.watch<CasaStore>().config;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: _servico.nome),
      body: Column(
        children: [
          _Progresso(passo: _passo, total: _titulos.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.sm, Spacing.lg, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '{0} de {1} · {2}'.trArgs(
                    [_passo + 1, _titulos.length, _titulos[_passo]]),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(Spacing.lg),
              child: switch (_passo) {
                0 => _passoTrabalho(config),
                1 => _passoQuandoOnde(config),
                _ => _passoConfirmar(config),
              },
            ),
          ),
          _barraDeBaixo(),
        ],
      ),
    );
  }

  Widget _barraDeBaixo() {
    final ultimo = _passo == 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
        child: ultimo
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // DL 24/2014: no preço fixo/hora o aviso de livre resolução
                  // vai mesmo acima do botão que fecha a encomenda. O pedido
                  // de orçamento não obriga a pagar nada.
                  if (!_orcamento) ...[
                    const CheckoutLegalNotice(kind: CheckoutLegalKind.servico),
                    const SizedBox(height: Spacing.sm),
                  ],
                  BoraPrimaryButton(
                    label: _orcamento
                        ? 'Pedir orçamentos grátis'.tr
                        : 'Encomenda com obrigação de pagar'.tr,
                    loading: _avancando,
                    onPressed: _avancar,
                  ),
                  TextButton(
                    onPressed: _voltar,
                    child: Text(
                      'Voltar'.tr,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  // A saída está SEMPRE viva (não depende de nenhum "busy").
                  TextButton(
                    onPressed: _voltar,
                    child: Text(
                      _passo == 0 ? 'Cancelar'.tr : 'Voltar'.tr,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: BoraPrimaryButton(
                      label: 'Continuar'.tr,
                      icon: Icons.arrow_forward,
                      loading: _avancando,
                      onPressed: _avancar,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Passo 1: o trabalho ──────────────────────────────────────────────────

  Widget _passoTrabalho(CasaConfig config) {
    final s = _servico;
    final passo = casaPassoQuantidade(s);
    final total = casaTotalEstimadoCents(s, _quantidade);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CasaCartao(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nome e descrição vêm do catálogo: sem .tr.
              Text(
                s.nome,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              if (s.descricao.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(s.descricao,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: Spacing.sm),
              Text(
                casaTextoPreco(s, quoteMaxPros: config.quoteMaxPros),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (casaServicoPedeMaterial(s)) ...[
          const SizedBox(height: Spacing.md),
          const CasaAvisoMaterial(key: Key('casa_aviso_material')),
        ],
        const SizedBox(height: Spacing.lg),
        for (final p in s.perguntas) ...[
          KeyedSubtree(
            key: _ancorasPerguntas[p.id],
            child: _pergunta(p),
          ),
          const SizedBox(height: Spacing.lg),
        ],
        if (!_orcamento && s.maxQuantidade > s.minQuantidade) ...[
          KeyedSubtree(
            key: _ancoras[CasaCampo.quantidade],
            child: CasaTituloSecao(casaRotuloQuantidade(s)),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Menos'.tr,
                onPressed: _quantidade - passo >= s.minQuantidade
                    ? () {
                        setState(() => _quantidade -= passo);
                        _ajustarMetodo();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                casaQuantidadeTexto(s, _quantidade),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                tooltip: 'Mais'.tr,
                onPressed: _quantidade + passo <= s.maxQuantidade
                    ? () {
                        setState(() => _quantidade += passo);
                        _ajustarMetodo();
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
        ],
        KeyedSubtree(
          key: _ancoras[CasaCampo.descricao],
          child: CasaTituloSecao(_orcamento
              ? 'Descreve o trabalho'.tr
              : 'Mais alguma coisa? (opcional)'.tr),
        ),
        TextField(
          controller: _descricaoCtrl,
          maxLines: 4,
          minLines: 2,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText:
                'Ex.: o móvel está na sala, 2.º andar sem elevador, há estacionamento à porta…'.tr,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CasaTituloSecao(
            'Fotos ({0} de {1})'.trArgs([_fotos.length, config.maxFotos])),
        if (_orcamento)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(
              'Com fotos os profissionais dão um preço mais certo.'.tr,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (var i = 0; i < _fotos.length; i++)
              _MiniaturaLocal(
                bytes: _fotos[i].bytes,
                onTirar: () => setState(() {
                  _fotos.removeAt(i);
                }),
              ),
            if (_fotos.length < config.maxFotos)
              InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: _aEscolherFoto ? null : _adicionarFoto,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: Center(
                    child: _aEscolherFoto
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_a_photo_outlined,
                                  color: AppColors.primary),
                              const SizedBox(height: 4),
                              Text(
                                'Adicionar'.tr,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
          ],
        ),
        if (total != null) ...[
          const SizedBox(height: Spacing.xl),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: AppColors.primaryWash,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  casaEuro(total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Valor indicativo — o valor final é calculado pelo Bora quando confirmas.'.tr,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _pergunta(CasaPergunta p) {
    // O texto da pergunta e as opções vêm do catálogo (servidor): sem .tr.
    if (p.escolha) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CasaTituloSecao(p.texto),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final o in p.opcoes)
                ChoiceChip(
                  label: Text(o),
                  selected: _escolhas[p.id] == o,
                  onSelected: (_) => setState(() => _escolhas[p.id] = o),
                  selectedColor: AppColors.primaryWash,
                  labelStyle: TextStyle(
                    color: _escolhas[p.id] == o
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: _escolhas[p.id] == o
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CasaTituloSecao(p.texto),
        TextField(
          controller: _textos[p.id],
          maxLines: 2,
          minLines: 1,
          maxLength: 300,
        ),
      ],
    );
  }

  // ── Passo 2: quando e onde ───────────────────────────────────────────────

  Future<void> _escolherDataHora() async {
    // Os seletores trabalham com o relógio de Lisboa; guarda-se o instante.
    final lead = _config.minLeadHours;
    final maisCedo = _agora().add(Duration(hours: lead));
    final inicial = _quando ?? maisCedo.add(const Duration(hours: 1));
    final primeiro = paredeLisboa(maisCedo);
    final diaInicial =
        paredeLisboa(inicial.isBefore(maisCedo) ? maisCedo : inicial);
    final horaInicial = paredeLisboa(inicial);
    final ultimo = paredeLisboa(_agora().add(const Duration(days: 60)));
    final data = await showDatePicker(
      context: context,
      initialDate: DateTime(diaInicial.year, diaInicial.month, diaInicial.day),
      firstDate: DateTime(primeiro.year, primeiro.month, primeiro.day),
      lastDate: DateTime(ultimo.year, ultimo.month, ultimo.day),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: horaInicial.hour, minute: horaInicial.minute),
    );
    if (hora == null || !mounted) return;
    setState(() {
      // DateTime.utc só para levar os campos: o fuso do telemóvel não entra.
      _quando = instanteDeLisboa(DateTime.utc(
          data.year, data.month, data.day, hora.hour, hora.minute));
    });
  }

  Widget _passoQuandoOnde(CasaConfig config) {
    final quando = _quando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: _ancoras[CasaCampo.data],
          child: CasaTituloSecao('Dia e hora'.tr),
        ),
        CasaCartao(
          onTap: _escolherDataHora,
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              const Icon(Icons.event, color: AppColors.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  quando == null
                      ? 'Escolher dia e hora'.tr
                      : casaQuandoTexto(quando),
                  style: TextStyle(
                    color: quando == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSubtle),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            'Antecedência mínima: {0} h.'.trArgs([config.minLeadHours]),
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        KeyedSubtree(
          key: _ancoras[CasaCampo.rua],
          child: CasaTituloSecao('Morada'.tr),
        ),
        AddressAutocompleteField(
          controller: _ruaCtrl,
          labelText: 'Rua e número'.tr,
          prefixIcon: const Icon(Icons.place_outlined),
          onSelected: _aoEscolherMorada,
          // Escrever à mão limpa as coordenadas antigas, mas nunca bloqueia.
          onChanged: (_) {
            if (_lat != null || _lng != null) {
              setState(() {
                _lat = null;
                _lng = null;
              });
            }
          },
        ),
        AutoAddressHint(visible: _aLocalizar),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: KeyedSubtree(
                key: _ancoras[CasaCampo.cidade],
                child: TextField(
                  controller: _cidadeCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Localidade'.tr),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _postalCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Código postal'.tr),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'O profissional só vê a rua e o número depois de aceitar o trabalho.'.tr,
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
        ),
      ],
    );
  }

  // ── Passo 3: confirmar ───────────────────────────────────────────────────

  Widget _passoConfirmar(CasaConfig config) {
    final s = _servico;
    final quando = _quando;
    final respostas = _respostasFinais;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CasaTituloSecao('Resumo'.tr),
        CasaCartao(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CasaLinhaResumo('Serviço'.tr, s.nome),
              if (!_orcamento && s.maxQuantidade > s.minQuantidade)
                CasaLinhaResumo(casaRotuloQuantidade(s),
                    casaQuantidadeTexto(s, _quantidade)),
              if (quando != null)
                CasaLinhaResumo('Quando'.tr, casaQuandoTexto(quando)),
              CasaLinhaResumo(
                'Onde'.tr,
                [_ruaFinal, _cidadeCtrl.text.trim()]
                    .where((t) => t.isNotEmpty)
                    .join(', '),
              ),
              for (final p in s.perguntas)
                if (p.id != kCasaPerguntaMaterial &&
                    (respostas[p.id] ?? '').toString().isNotEmpty)
                  CasaLinhaResumo(p.texto, respostas[p.id].toString()),
              if (casaServicoPedeMaterial(s))
                CasaLinhaResumo(
                  'Material'.tr,
                  '{0} — o profissional leva só as ferramentas'.trArgs(
                      [(respostas[kCasaPerguntaMaterial] ?? '').toString()]),
                  key: const Key('casa_resumo_material'),
                ),
              if (_fotos.isNotEmpty)
                CasaLinhaResumo('Fotos'.tr, '${_fotos.length}'),
              if (!_orcamento) ...[
                const Divider(height: Spacing.lg),
                CasaLinhaResumo(
                  'Total (indicativo)'.tr,
                  casaEuro(_totalCents),
                  forte: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        if (_orcamento)
          CasaCartao(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'O pedido de orçamento é grátis e sem compromisso. Até {0} profissionais respondem com o preço, o prazo e o que inclui; tu comparas, escolhes e só aí decides como pagar.'.trArgs([config.quoteMaxPros]),
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          )
        else ...[
          KeyedSubtree(
            key: _ancoras[CasaCampo.pagamento],
            child: CasaTituloSecao('Pagamento'.tr),
          ),
          CasaEscolhaPagamento(
            totalCents: _totalCents,
            config: config,
            metodo: _metodo,
            onEscolher: (m) => setState(() => _metodo = m),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Cancelamento: grátis até {0} h antes · 50% entre {0} h e {1} h · 100% a menos de {1} h.'.trArgs([config.cancelFreeHours, config.cancelHalfHours]),
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

// ─── widgets internos ────────────────────────────────────────────────────────

class _Progresso extends StatelessWidget {
  const _Progresso({required this.passo, required this.total});

  final int passo;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= passo ? AppColors.primary : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: Spacing.xs),
          ],
        ],
      ),
    );
  }
}

class _MiniaturaLocal extends StatelessWidget {
  const _MiniaturaLocal({required this.bytes, required this.onTirar});

  final Uint8List bytes;
  final VoidCallback onTirar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTirar,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Semantics(
                    label: 'Remover foto'.tr,
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
