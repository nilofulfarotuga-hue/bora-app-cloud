// O AMIGO — o ecrã do rosto (missão m11-amigo-rosto, 09/11/2026).
//
// Ordem do Danilo (09/11, 05:11): "Não é o chat não. Ele vai ser um rosto...
// a pessoa clica e começa tipo igual no filme." Adendo 1 (05:23): "vai ser
// um amigo mesmo do cliente, sempre com uma deixinha".
//
// O rosto em grande no centro acorda, sorri e diz a saudação (a do
// client-assistant: pelo nome e com o habitual). O que ele diz aparece em
// legenda grande por baixo, com a palavra a ser dita a laranja. Em baixo: o
// microfone GRANDE ("Fala comigo"), "Escrever" e "Ver conversa" (o chat
// escrito de sempre, com a mesma conversa).
//
// A cara reage ao estado: a ouvir → atento; à espera do servidor → pensativo;
// a responder → a falar com a boca sincronizada; produto/pedido → alegre;
// nada encontrado → triste; erro → confuso. O campo `emocao` do servidor
// manda quando vem. No fim, a deixa do sistema (promoção, parceiro novo,
// tokens, check-in) é dita em voz com a cara alegre e fica como cartão.
//
// O cérebro, a memória, os cartões e o "pôr no carrinho" são os de sempre.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/amigo_voz.dart';
import '../../../services/assistant_service.dart';
import '../../../stores/cart_store.dart';
import '../../../widgets/amigo/amigo_rosto.dart';
import 'assistant_acoes.dart';
import 'assistant_cards.dart';
import 'assistant_chat_screen.dart';

/// Em que está o Amigo.
enum AmigoFase { acordar, aFalar, aOuvir, aPensar, parado }

/// A cara que uma resposta pede, pelo conteúdo (puro, testado). Null = sem
/// pista (fica a cara de falar).
AmigoEmocao? amigoEmocaoDaResposta(AssistantReply r) {
  if (r.handoff) return AmigoEmocao.confuso;
  if (r.propostas.isNotEmpty || r.divisao != null || r.comparacao != null) {
    return AmigoEmocao.alegre;
  }
  final t = r.texto.toLowerCase();
  if (RegExp(r'não (percebi|entendi)').hasMatch(t)) return AmigoEmocao.confuso;
  if (RegExp(r'não (encontrei|há|consegui|temos|tenho)|fechad|esgotad|indispon')
      .hasMatch(t)) {
    return AmigoEmocao.triste;
  }
  return null;
}

/// A cara do Amigo para o estado do ecrã (puro, testado).
AmigoEmocao amigoEmocaoParaEstado({
  required AmigoFase fase,
  AssistantReply? resposta,
  bool erro = false,
  bool aDizerDeixa = false,
}) {
  if (erro) return AmigoEmocao.confuso;
  switch (fase) {
    case AmigoFase.aOuvir:
      return AmigoEmocao.aOuvir;
    case AmigoFase.aPensar:
      return AmigoEmocao.pensativo;
    case AmigoFase.acordar:
      return AmigoEmocao.alegre;
    case AmigoFase.aFalar:
    case AmigoFase.parado:
      break;
  }
  if (aDizerDeixa) return AmigoEmocao.alegre;
  final r = resposta;
  if (r == null) return fase == AmigoFase.aFalar ? AmigoEmocao.aFalar : AmigoEmocao.neutro;
  return amigoEmocaoDe(r.emocao) ??
      amigoEmocaoDaResposta(r) ??
      (fase == AmigoFase.aFalar ? AmigoEmocao.aFalar : AmigoEmocao.neutro);
}

/// O que o ecrã precisa do servidor (trocável nos testes).
class AmigoCerebro {
  const AmigoCerebro();

  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) =>
      AssistantService.abrir(dropoffLat: lat, dropoffLng: lng, apartmentDelivery: apartamento);

  Future<AssistantReply> enviar({
    required String? conversationId,
    required String mensagem,
    double? lat,
    double? lng,
    bool apartamento = false,
  }) =>
      AssistantService.enviar(
        conversationId: conversationId,
        message: mensagem,
        dropoffLat: lat,
        dropoffLng: lng,
        apartmentDelivery: apartamento,
      );

  /// A conversa guardada, se teve mensagens nas últimas 6 h (senão, nova).
  Future<(String?, List<AssistantReply>)> conversaRecente() async {
    final id = await AssistantService.conversaGuardada();
    if (id == null) return (null, const <AssistantReply>[]);
    try {
      final hist = await AssistantService.historico(id);
      final ultima = hist.isEmpty ? null : hist.last.createdAt;
      if (ultima == null || DateTime.now().difference(ultima) > kAmigoConversaNova) {
        return (null, const <AssistantReply>[]);
      }
      return (id, [for (final h in hist) if (h.reply != null) h.reply!]);
    } catch (_) {
      return (null, const <AssistantReply>[]);
    }
  }

  Future<void> guardarConversa(String? id) => AssistantService.guardarConversa(id);

  Future<void> evento(String tipo, {int? duracaoS}) =>
      AssistantService.eventoAmigo(tipo, duracaoS: duracaoS);
}

/// O microfone (trocável nos testes).
class AmigoOuvido {
  stt.SpeechToText? _stt;

  Future<bool> iniciar({required void Function() aoParar}) async {
    final s = _stt ??= stt.SpeechToText();
    if (s.isAvailable) return true;
    try {
      return await s.initialize(
        onError: (e) {
          if (e.permanent) aoParar();
        },
        onStatus: (st) {
          if (st == 'done' || st == 'notListening') aoParar();
        },
      );
    } catch (e) {
      debugPrint('[Amigo] microfone: $e');
      return false;
    }
  }

  Future<void> ouvir(void Function(String texto, bool fim) aoOuvir) async {
    await _stt?.listen(
      onResult: (r) => aoOuvir(r.recognizedWords.trim(), r.finalResult),
      // ignore: deprecated_member_use
      localeId: 'pt_PT',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      ),
    );
  }

  Future<void> parar() async {
    try {
      await _stt?.stop();
    } catch (_) {}
  }
}

class AmigoScreen extends StatefulWidget {
  const AmigoScreen({
    super.key,
    this.cerebro = const AmigoCerebro(),
    this.voz,
    this.ouvido,
    this.aoVerConversa,
    this.mensagemInicial,
  });

  final AmigoCerebro cerebro;

  /// Enviada logo depois da saudação (ex.: "Pede ao Amigo" de uma pesquisa
  /// sem resultado numa loja — adendo 2, 09/11/2026).
  final String? mensagemInicial;

  /// Voz do Amigo (por defeito, a do sistema com as definições do painel).
  final AmigoVoz? voz;
  final AmigoOuvido? ouvido;

  /// Abre a conversa escrita (por defeito, o ecrã de chat de sempre).
  final VoidCallback? aoVerConversa;

  @override
  State<AmigoScreen> createState() => _AmigoScreenState();
}

class _AmigoScreenState extends State<AmigoScreen>
    with AssistantAcoesMixin<AmigoScreen> {
  late final AmigoVoz _voz;
  late final AmigoOuvido _ouvido;
  final _input = TextEditingController();
  final _foco = FocusNode();
  final DateTime _abertoEm = DateTime.now();

  AmigoFase _fase = AmigoFase.acordar;
  AssistantReply? _resposta;
  final List<AssistantReply> _respostas = [];
  String? _conversationId;
  bool _erro = false;
  bool _aDizerDeixa = false;
  bool _aEscrever = false;
  bool _microfoneOk = true;
  String _ouvidoTexto = '';
  String _pergunta = '';
  bool _enviouOuvido = false;

  /// Cada ação nova (falar, ouvir, sair) muda o turno: o que ainda estava a
  /// acontecer do turno anterior deixa de mexer no ecrã.
  int _turno = 0;

  @override
  void initState() {
    super.initState();
    _voz = widget.voz ??
        AmigoVoz(
          velocidade: AssistantFlags.vozVelocidade.value,
          somPorDefeito: AssistantFlags.vozPorDefeito.value,
        );
    _ouvido = widget.ouvido ?? AmigoOuvido();
    unawaited(widget.cerebro.evento('abrir'));
    unawaited(_arranque());
  }

  @override
  void dispose() {
    _turno++;
    unawaited(_ouvido.parar());
    final duracao = DateTime.now().difference(_abertoEm).inSeconds;
    unawaited(widget.cerebro.evento('fim', duracaoS: duracao));
    _voz.dispose();
    _input.dispose();
    _foco.dispose();
    super.dispose();
  }

  CartStore? get _carrinho {
    try {
      return context.read<CartStore>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _arranque() async {
    final turno = _turno;
    unawaited(AssistantFlags.carregar());
    final preparar = _voz.preparar();
    final conversa = widget.cerebro.conversaRecente();
    final cart = _carrinho;
    final saudacao = widget.cerebro.abrir(
      lat: cart?.deliveryLocation?.latitude,
      lng: cart?.deliveryLocation?.longitude,
      apartamento: cart?.apartmentDelivery ?? false,
    );
    final (id, antigas) = await conversa;
    _conversationId = id;
    _respostas.addAll(antigas);
    AssistantReply? r;
    try {
      r = await saudacao;
    } catch (_) {
      r = null;
    }
    await preparar;
    // deixa a animação de acordar acabar antes de falar
    final passou = DateTime.now().difference(_abertoEm).inMilliseconds;
    if (passou < 700) await Future<void>.delayed(Duration(milliseconds: 700 - passou));
    if (!mounted || turno != _turno) return;
    final boasVindas = AssistantFlags.boasVindasAmigo.value;
    r ??= AssistantReply.texto(
      boasVindas.isEmpty ? 'Olá! Sou o Amigo. Fala comigo: estou aqui para o que precisares.'.tr : boasVindas,
    );
    if (r.conversationId != null) {
      _conversationId = r.conversationId;
      unawaited(widget.cerebro.guardarConversa(_conversationId));
    }
    _respostas.add(r);
    await _dizer(r, emocao: AmigoEmocao.alegre);
    final m = widget.mensagemInicial?.trim() ?? '';
    if (mounted && m.isNotEmpty) await _enviar(m);
  }

  /// Diz a resposta (e a deixa no fim, com a cara alegre).
  Future<void> _dizer(AssistantReply r, {AmigoEmocao? emocao}) async {
    final turno = ++_turno;
    setState(() {
      _resposta = emocao == null ? r : r.comEmocao(amigoEmocaoNome(emocao));
      _fase = AmigoFase.aFalar;
      _aDizerDeixa = false;
    });
    await _voz.falar(r.texto);
    if (!mounted || turno != _turno) return;
    final d = r.deixa;
    if (d != null && d.texto.trim().isNotEmpty) {
      setState(() => _aDizerDeixa = true);
      await _voz.falar(d.texto);
      if (!mounted || turno != _turno) return;
    }
    // Depois da deixa a cara fica alegre (foi a última coisa que disse).
    setState(() => _fase = AmigoFase.parado);
  }

  Future<void> _enviar(String texto, {bool porVoz = false}) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    final turno = ++_turno;
    await _voz.parar();
    unawaited(widget.cerebro.evento(porVoz ? 'voz' : 'escrita'));
    setState(() {
      _fase = AmigoFase.aPensar;
      _erro = false;
      _aDizerDeixa = false;
      _pergunta = t;
      _resposta = null;
      _aEscrever = false;
      _input.clear();
    });
    final cart = _carrinho;
    AssistantReply r;
    var erro = false;
    try {
      r = await widget.cerebro.enviar(
        conversationId: _conversationId,
        mensagem: t,
        lat: cart?.deliveryLocation?.latitude,
        lng: cart?.deliveryLocation?.longitude,
        apartamento: cart?.apartmentDelivery ?? false,
      );
    } on AssistantException catch (e) {
      erro = true;
      r = AssistantReply.texto(_textoDoErro(e));
    } catch (_) {
      erro = true;
      r = AssistantReply.texto('Não consegui responder agora. Tenta outra vez.'.tr);
    }
    if (!mounted || turno != _turno) return;
    final novoId = r.conversationId;
    if (novoId != null && novoId != _conversationId) {
      _conversationId = novoId;
      unawaited(widget.cerebro.guardarConversa(novoId));
    }
    _respostas.add(r);
    _erro = erro;
    await _dizer(r);
  }

  String _textoDoErro(AssistantException e) {
    if (e.texto.isNotEmpty) return e.texto;
    switch (e.codigo) {
      case 'quota':
        return 'Chegaste ao limite de mensagens de hoje. Amanhã há mais.'.tr;
      case 'disabled':
        return 'O assistente está desligado de momento.'.tr;
      case 'auth':
        return 'Inicia sessão para falar com o assistente.'.tr;
      case 'rede':
        return 'Sem ligação. Verifica a internet e tenta outra vez.'.tr;
    }
    return 'Não consegui responder agora. Tenta outra vez.'.tr;
  }

  // ── Microfone ─────────────────────────────────────────────────────────

  Future<void> _microfone() async {
    if (_fase == AmigoFase.aOuvir) {
      await _ouvido.parar();
      _fimDeOuvir();
      return;
    }
    if (_fase == AmigoFase.aPensar) return;
    _turno++;
    await _voz.parar();
    final ok = await _ouvido.iniciar(aoParar: _fimDeOuvir);
    if (!mounted) return;
    if (!ok) {
      setState(() => _microfoneOk = false);
      snack('Ditado por voz não disponível neste aparelho.'.tr);
      return;
    }
    setState(() {
      _fase = AmigoFase.aOuvir;
      _erro = false;
      _aDizerDeixa = false;
      _ouvidoTexto = '';
      _enviouOuvido = false;
      _aEscrever = false;
    });
    try {
      await _ouvido.ouvir((texto, fim) {
        if (!mounted || _fase != AmigoFase.aOuvir) return;
        setState(() => _ouvidoTexto = texto);
        if (fim) _fimDeOuvir();
      });
    } catch (e) {
      debugPrint('[Amigo] ouvir: $e');
      _fimDeOuvir();
    }
  }

  void _fimDeOuvir() {
    if (!mounted || _fase != AmigoFase.aOuvir || _enviouOuvido) return;
    _enviouOuvido = true;
    final t = _ouvidoTexto.trim();
    if (t.isEmpty) {
      setState(() => _fase = AmigoFase.parado);
      return;
    }
    unawaited(_enviar(t, porVoz: true));
  }

  // ── Escrever / ver conversa ───────────────────────────────────────────

  void _abrirEscrita() {
    _turno++;
    unawaited(_voz.parar());
    setState(() {
      _aEscrever = true;
      if (_fase == AmigoFase.aFalar) _fase = AmigoFase.parado;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  Future<void> _verConversa() async {
    _turno++;
    await _voz.parar();
    if (_conversationId != null) {
      await widget.cerebro.guardarConversa(_conversationId);
    }
    if (!mounted) return;
    setState(() {
      if (_fase == AmigoFase.aFalar) _fase = AmigoFase.parado;
    });
    final f = widget.aoVerConversa;
    if (f != null) {
      f();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AssistantChatScreen()),
    );
  }

  // ── Ações dos cartões (assistant_acoes.dart) ──────────────────────────

  @override
  Iterable<AssistantReply> get respostasMostradas => _respostas;

  @override
  Future<void> enviarAoAssistente(String texto) => _enviar(texto);

  // ── UI ────────────────────────────────────────────────────────────────

  AmigoEmocao get _emocao => amigoEmocaoParaEstado(
        fase: _fase,
        resposta: _resposta,
        erro: _erro,
        aDizerDeixa: _aDizerDeixa,
      );

  @override
  Widget build(BuildContext context) {
    final r = _resposta;
    final temCartoes = r != null && (r.temCartoes || r.deixa != null);
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.primaryDark,
        title: Text('Amigo'.tr,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark)),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _voz.somLigado,
            builder: (_, som, __) => IconButton(
              key: const Key('amigo-som'),
              tooltip: som ? 'Desligar o som'.tr : 'Ligar o som'.tr,
              icon: Icon(som ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              onPressed: _voz.alternarSom,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, c) {
          final variante = amigoVarianteDe(AssistantFlags.rostoVariante.value);
          final propAlt = AmigoRosto.alturaPara(1, variante);
          final maxAlt = c.maxHeight * (temCartoes || _aEscrever ? 0.30 : 0.44);
          final larg = (c.maxWidth * 0.66).clamp(56.0, 300.0);
          final tamanho = (larg * propAlt > maxAlt ? maxAlt / propAlt : larg)
              .clamp(48.0, 300.0)
              .toDouble();
          return Column(
            children: [
              const SizedBox(height: 4),
              // Sem animar o tamanho: com o teclado a abrir, um rosto a encolher
              // passava do espaço durante a transição (provado no teste 320x568).
              AmigoRosto(
                key: const Key('amigo-rosto-grande'),
                tamanho: tamanho,
                emocao: _emocao,
                variante: variante,
                boca: _voz.bocaAgora,
                acordar: true,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Legenda(
                        voz: _voz,
                        fase: _fase,
                        ouvido: _ouvidoTexto,
                        pergunta: _pergunta,
                        // a dizer a deixa: a legenda guarda a resposta e o
                        // cartão da deixa fica realçado
                        textoFixo: _aDizerDeixa ? r?.texto : null,
                      ),
                      if (r?.deixa != null && _fase != AmigoFase.aPensar && _fase != AmigoFase.aOuvir)
                        _CartaoDeixa(
                          deixa: r!.deixa!,
                          destacada: _aDizerDeixa,
                          onTap: () => tocarDeixa(r.deixa!),
                        ),
                      if (r != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: AssistantCartoesDaResposta(
                            mostrarDeixa: false,
                            reply: r,
                            aEncherId: aEncherId,
                            onEncher: encher,
                            onFavor: pedirFavor,
                            onAcao: acao,
                            onConfirmarLista: _enviar,
                            onDeixa: tocarDeixa,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _aEscrever
                  ? _CaixaEscrever(
                      controller: _input,
                      foco: _foco,
                      onEnviar: () => _enviar(_input.text),
                      onFechar: () => setState(() => _aEscrever = false),
                    )
                  : _Comandos(
                      fase: _fase,
                      microfoneOk: _microfoneOk,
                      onMicrofone: _microfone,
                      onEscrever: _abrirEscrita,
                      onVerConversa: _verConversa,
                    ),
            ],
          );
        }),
      ),
    );
  }
}

extension on AssistantReply {
  /// A mesma resposta com outra cara (a saudação vem sempre alegre).
  AssistantReply comEmocao(String emocao) => AssistantReply(
        conversationId: conversationId,
        texto: texto,
        propostas: propostas,
        divisao: divisao,
        favores: favores,
        favorPreco: favorPreco,
        listaExtraida: listaExtraida,
        acoes: acoes,
        handoff: handoff,
        ticketId: ticketId,
        messagesRemainingToday: messagesRemainingToday,
        poupancaAcumuladaCents: poupancaAcumuladaCents,
        comparacao: comparacao,
        deixa: deixa,
        saudacao: saudacao,
        emocao: emocao,
      );
}

/// A legenda grande por baixo do rosto: o que o Amigo diz, com a palavra a
/// ser dita a laranja (como no protótipo); a ouvir mostra o que o cliente
/// disse; a pensar mostra a pergunta.
class _Legenda extends StatelessWidget {
  const _Legenda({
    required this.voz,
    required this.fase,
    required this.ouvido,
    required this.pergunta,
    this.textoFixo,
  });

  final String? textoFixo;
  final AmigoVoz voz;
  final AmigoFase fase;
  final String ouvido;
  final String pergunta;

  static const _estilo = TextStyle(
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    Widget corpo;
    if (fase == AmigoFase.aOuvir) {
      corpo = Text(
        ouvido.isEmpty ? 'Estou a ouvir…'.tr : ouvido,
        key: const Key('amigo-legenda-ouvir'),
        style: _estilo.copyWith(
            color: ouvido.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
      );
    } else if (fase == AmigoFase.aPensar) {
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pergunta.isNotEmpty)
            Text('Tu: {0}'.trArgs([pergunta]),
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Hum… deixa-me ver.'.tr, style: _estilo),
        ],
      );
    } else if (textoFixo != null) {
      corpo = Text(textoFixo!, key: const Key('amigo-legenda'), style: _estilo);
    } else {
      corpo = ValueListenableBuilder<String>(
        valueListenable: voz.legenda,
        builder: (_, texto, __) => ValueListenableBuilder<int>(
          valueListenable: voz.palavraAtual,
          builder: (_, atual, __) => Text.rich(
            _karaoke(texto, atual),
            key: const Key('amigo-legenda'),
            style: _estilo,
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryLight),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: corpo,
        ),
      ),
    );
  }

  static TextSpan _karaoke(String texto, int atual) {
    final partes = <InlineSpan>[];
    var fim = 0;
    var i = 0;
    for (final m in RegExp(r'\S+').allMatches(texto)) {
      if (m.start > fim) partes.add(TextSpan(text: texto.substring(fim, m.start)));
      partes.add(TextSpan(
        text: m.group(0),
        style: i == atual
            ? const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)
            : null,
      ));
      fim = m.end;
      i++;
    }
    if (fim < texto.length) partes.add(TextSpan(text: texto.substring(fim)));
    return TextSpan(children: partes);
  }
}

/// A deixa do sistema (promoção, parceiro novo, tokens, check-in) num cartão
/// clicável por baixo da legenda. O toque conta no painel (clicada_em).
class _CartaoDeixa extends StatelessWidget {
  const _CartaoDeixa({required this.deixa, required this.destacada, required this.onTap});

  final AssistantDeixa deixa;
  final bool destacada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: destacada ? AppColors.primaryWash : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: destacada ? AppColors.primary : AppColors.primaryLight,
            width: destacada ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: const Key('amigo-deixa-cartao'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryWash,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(AmigoDeixaLinha.icone(deixa.tipo),
                      color: AppColors.primaryDark, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    deixa.texto,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Comandos extends StatelessWidget {
  const _Comandos({
    required this.fase,
    required this.microfoneOk,
    required this.onMicrofone,
    required this.onEscrever,
    required this.onVerConversa,
  });

  final AmigoFase fase;
  final bool microfoneOk;
  final VoidCallback onMicrofone;
  final VoidCallback onEscrever;
  final VoidCallback onVerConversa;

  @override
  Widget build(BuildContext context) {
    final aOuvir = fase == AmigoFase.aOuvir;
    final aPensar = fase == AmigoFase.aPensar;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _BotaoPequeno(
              chave: const Key('amigo-escrever'),
              icone: Icons.keyboard_alt_outlined,
              texto: 'Escrever'.tr,
              onTap: aPensar ? null : onEscrever,
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: aOuvir ? 'Parar de ouvir e enviar'.tr : 'Fala comigo'.tr,
                  child: Material(
                    key: const Key('amigo-microfone'),
                    color: !microfoneOk || aPensar
                        ? AppColors.primaryLight
                        : (aOuvir ? AppColors.primaryDark : AppColors.primary),
                    shape: CircleBorder(
                      side: BorderSide(
                        color: aOuvir ? AppColors.primaryLight : Colors.white,
                        width: 4,
                      ),
                    ),
                    elevation: 0,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: !microfoneOk || aPensar ? null : onMicrofone,
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: Icon(
                          aOuvir ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  aOuvir ? 'A ouvir… toca para enviar'.tr : 'Fala comigo'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _BotaoPequeno(
              chave: const Key('amigo-ver-conversa'),
              icone: Icons.chat_bubble_outline_rounded,
              texto: 'Ver conversa'.tr,
              onTap: onVerConversa,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoPequeno extends StatelessWidget {
  const _BotaoPequeno({
    required this.chave,
    required this.icone,
    required this.texto,
    required this.onTap,
  });

  final Key chave;
  final IconData icone;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: chave,
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: AppColors.primaryDark, size: 26),
            const SizedBox(height: 4),
            // encolhe em vez de cortar ("Ver conve…" no ecrã de 320)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                texto,
                maxLines: 1,
                style: const TextStyle(fontSize: 12, color: AppColors.primaryDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaixaEscrever extends StatelessWidget {
  const _CaixaEscrever({
    required this.controller,
    required this.foco,
    required this.onEnviar,
    required this.onFechar,
  });

  final TextEditingController controller;
  final FocusNode foco;
  final VoidCallback onEnviar;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fechar'.tr,
            icon: const Icon(Icons.close_rounded),
            onPressed: onFechar,
          ),
          Expanded(
            child: TextField(
              key: const Key('amigo-caixa-texto'),
              controller: controller,
              focusNode: foco,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onEnviar(),
              decoration: InputDecoration(
                hintText: 'Escreve ao Amigo…'.tr,
                isDense: true,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('amigo-enviar'),
            tooltip: 'Enviar'.tr,
            color: AppColors.primary,
            icon: const Icon(Icons.send_rounded),
            onPressed: onEnviar,
          ),
        ],
      ),
    );
  }
}
