// BORA ASSISTENTE (07/10/2026) — ecrã de conversa do assistente de compras.
//
// O cliente escreve, dita ou fotografa a lista; a Edge Function
// `client-assistant` responde com texto curto + cartões (propostas por loja,
// divisão em 2 lojas, favores, lista lida da foto, chips de acção).
// A conversa activa fica em SharedPreferences e o histórico vem de
// `assistant_chat_messages` (a coluna `structured` redesenha os cartões).
//
// Verde #16A34A na barra; o único laranja é o "Encher o carrinho".

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../config/app_colors.dart';
import '../../../l10n/tr.dart';
import '../../../services/assistant_service.dart';
import '../../../stores/cart_store.dart';
import '../../../utils/home_destino.dart';
import '../../../utils/safe_image_picker.dart';
import '../../../widgets/bora_support_sheet.dart';
import '../../errand_form_screen.dart';
import '../../orders_screen.dart';
import '../../wallet_history_screen.dart';
import '../tvde/tvde_entrada_screen.dart';
import 'assistant_cards.dart';
import 'assistant_encher_carrinho.dart';

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    super.key,
    this.mensagemInicial,
    this.propostaInicial,
  });

  /// Enviada logo ao abrir (ex. vinda de uma faixa da home).
  final String? mensagemInicial;

  /// `/assistente?proposta=<uuid>` (web): abre e enche logo o carrinho.
  final String? propostaInicial;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _Msg {
  _Msg.utilizador(this.texto, {this.imagem, this.imageUrl})
      : deUtilizador = true,
        reply = null;
  _Msg.assistente(this.reply)
      : deUtilizador = false,
        texto = reply?.texto ?? '',
        imagem = null,
        imageUrl = null;

  final bool deUtilizador;
  final String texto;
  final Uint8List? imagem;
  final String? imageUrl;
  final AssistantReply? reply;
}

/// Reduz a foto para 1280 px no lado maior, JPEG q80 (corre em isolate).
Uint8List _reencodar(Uint8List bytes) {
  final dec = img.decodeImage(bytes);
  if (dec == null) return bytes;
  final maior = dec.width > dec.height ? dec.width : dec.height;
  final out = maior > 1280
      ? img.copyResize(
          dec,
          width: dec.width >= dec.height ? 1280 : null,
          height: dec.height > dec.width ? 1280 : null,
          interpolation: img.Interpolation.average,
        )
      : dec;
  return Uint8List.fromList(img.encodeJpg(out, quality: 80));
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final List<_Msg> _msgs = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _foco = FocusNode();

  String? _conversationId;
  bool _carregando = true;
  bool _aPensar = false;
  String? _banner;
  int? _restantesHoje;
  int _poupancaCents = 0;
  String? _aEncherId;

  // Voz
  stt.SpeechToText? _stt;
  bool _sttDisponivel = true;
  bool _aOuvir = false;
  String _textoAntesDoDitado = '';

  @override
  void initState() {
    super.initState();
    unawaited(AssistantFlags.carregar());
    unawaited(_arranque());
  }

  @override
  void dispose() {
    _stt?.stop();
    _input.dispose();
    _scroll.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _arranque() async {
    final id = await AssistantService.conversaGuardada();
    if (id != null) {
      try {
        final hist = await AssistantService.historico(id);
        if (!mounted) return;
        _conversationId = id;
        for (final h in hist) {
          if (h.role == 'user') {
            _msgs.add(_Msg.utilizador(h.content, imageUrl: h.imageUrl));
          } else if (h.reply != null) {
            _msgs.add(_Msg.assistente(h.reply));
            final r = h.reply!;
            if (r.poupancaAcumuladaCents > 0) {
              _poupancaCents = r.poupancaAcumuladaCents;
            }
          }
        }
      } catch (e) {
        debugPrint('[Assistente] histórico: $e');
      }
    }
    if (!mounted) return;
    setState(() => _carregando = false);
    _irParaOFim();

    final m = widget.mensagemInicial?.trim();
    if (m != null && m.isNotEmpty) {
      await _enviar(m);
    }
    final p = widget.propostaInicial;
    if (p != null && p.isNotEmpty) {
      await _abrirPropostaPorId(p);
    }
  }

  Future<void> _abrirPropostaPorId(String id) async {
    try {
      final prop = await AssistantService.proposta(id);
      if (!mounted) return;
      if (prop == null) {
        _snack('Esta proposta já não está disponível.'.tr);
        return;
      }
      await _encher(prop);
    } catch (e) {
      debugPrint('[Assistente] proposta $id: $e');
      if (mounted) _snack('Esta proposta já não está disponível.'.tr);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _irParaOFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ── Enviar ────────────────────────────────────────────────────────────

  Future<void> _enviar(String texto, {Uint8List? imagem}) async {
    final t = texto.trim();
    if ((t.isEmpty && imagem == null) || _aPensar) return;
    if (_aOuvir) await _pararVoz();
    if (!mounted) return;

    setState(() {
      _msgs.add(_Msg.utilizador(t, imagem: imagem));
      _aPensar = true;
      _banner = null;
      _input.clear();
    });
    _irParaOFim();

    final cart = context.read<CartStore>();
    final entrega = cart.deliveryLocation;
    try {
      final reply = await AssistantService.enviar(
        conversationId: _conversationId,
        message: t.isEmpty ? null : t,
        imageBase64: imagem == null ? null : base64Encode(imagem),
        imageMime: imagem == null ? null : 'image/jpeg',
        dropoffLat: entrega?.latitude,
        dropoffLng: entrega?.longitude,
        apartmentDelivery: cart.apartmentDelivery,
      );
      if (!mounted) return;
      final novoId = reply.conversationId;
      if (novoId != null && novoId != _conversationId) {
        _conversationId = novoId;
        unawaited(AssistantService.guardarConversa(novoId));
      }
      setState(() {
        _msgs.add(_Msg.assistente(reply));
        _aPensar = false;
        _restantesHoje = reply.messagesRemainingToday ?? _restantesHoje;
        if (reply.poupancaAcumuladaCents > 0) {
          _poupancaCents = reply.poupancaAcumuladaCents;
        }
        if (reply.handoff) {
          _banner = reply.ticketId == null
              ? 'Passei a conversa ao suporte humano.'.tr
              : 'Passei a conversa ao suporte humano (ticket #{0}).'
                  .trArgs([reply.ticketId!.substring(0, 8)]);
        }
      });
    } on AssistantException catch (e) {
      if (!mounted) return;
      setState(() {
        _aPensar = false;
        _banner = _textoDoErro(e);
      });
    }
    _irParaOFim();
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

  // ── Foto ──────────────────────────────────────────────────────────────

  Future<void> _escolherFoto() async {
    if (_aPensar) return;
    ImageSource? fonte;
    if (kIsWeb) {
      fonte = ImageSource.gallery;
    } else {
      fonte = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('Tirar foto da lista'.tr),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('Escolher da galeria'.tr),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (fonte == null || !mounted) return;
    try {
      final x = await SafeImagePicker.pickImage(
        source: fonte,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (x == null || !mounted) return;
      var bytes = await x.readAsBytes();
      // O seletor já reduz na maioria dos aparelhos; isto garante o tecto.
      if (bytes.length > 1200 * 1024) {
        bytes = await compute(_reencodar, bytes);
      }
      if (!mounted) return;
      await _enviar(_input.text, imagem: bytes);
    } catch (e) {
      debugPrint('[Assistente] foto: $e');
      if (mounted) _snack('Não consegui ler a foto.'.tr);
    }
  }

  // ── Voz ───────────────────────────────────────────────────────────────

  Future<void> _alternarVoz() async {
    if (_aOuvir) {
      await _pararVoz();
      return;
    }
    final s = _stt ??= stt.SpeechToText();
    bool ok = s.isAvailable;
    if (!ok) {
      try {
        ok = await s.initialize(
          onError: (e) {
            debugPrint('[Assistente] voz erro: ${e.errorMsg}');
            if (mounted && e.permanent) setState(() => _aOuvir = false);
          },
          onStatus: (st) {
            if (!mounted) return;
            if (st == 'done' || st == 'notListening') {
              setState(() => _aOuvir = false);
            }
          },
        );
      } catch (e) {
        debugPrint('[Assistente] voz init: $e');
        ok = false;
      }
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _sttDisponivel = false);
      _snack('Ditado por voz não disponível neste aparelho.'.tr);
      return;
    }
    _textoAntesDoDitado = _input.text.trim();
    setState(() => _aOuvir = true);
    try {
      await s.listen(
        onResult: (r) {
          if (!mounted) return;
          final dito = r.recognizedWords.trim();
          final novo = _textoAntesDoDitado.isEmpty
              ? dito
              : '$_textoAntesDoDitado $dito';
          _input.value = TextEditingValue(
            text: novo,
            selection: TextSelection.collapsed(offset: novo.length),
          );
          if (r.finalResult) setState(() => _aOuvir = false);
        },
        // ignore: deprecated_member_use
        localeId: 'pt_PT',
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('[Assistente] voz listen: $e');
      if (mounted) setState(() => _aOuvir = false);
    }
  }

  Future<void> _pararVoz() async {
    try {
      await _stt?.stop();
    } catch (_) {}
    if (mounted) setState(() => _aOuvir = false);
  }

  // ── Cartões ───────────────────────────────────────────────────────────

  Future<void> _encher(AssistantProposal p) async {
    if (_aEncherId != null) return;
    setState(() => _aEncherId = p.proposalId);
    try {
      await encherCarrinhoDaProposta(context, p);
    } finally {
      if (mounted) setState(() => _aEncherId = null);
    }
  }

  void _pedirFavor(List<AssistantFavor> favores) {
    final desc = favores
        .map((f) => f.quantity > 1 ? '${f.quantity}× ${f.query}' : f.query)
        .join(', ');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ErrandFormScreen(
          prefill: ErrandPrefill(
            description: 'Comprar: {0}'.trArgs([desc]),
            location: '',
            hasPurchase: true,
          ),
        ),
      ),
    );
  }

  Future<void> _acao(AssistantAcao a) async {
    final d = a.destino?.trim() ?? '';
    switch (a.tipo) {
      case 'abrir_pedido':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OrdersScreen()));
      case 'abrir_carteira':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WalletHistoryScreen()));
      case 'abrir_favores':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ErrandFormScreen(
              prefill: d.isEmpty
                  ? null
                  : ErrandPrefill(description: d, location: '', hasPurchase: true),
            ),
          ),
        );
      case 'abrir_tvde':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TvdeEntradaScreen()));
      case 'suporte_humano':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const BoraSupportSheet(showAgentCard: false),
        );
      case 'confirmar_lista':
        if (d.isNotEmpty) await _enviar(d);
      case 'abrir_loja':
        if (d.isNotEmpty) await abrirLojaPorId(context, d);
      default:
        if (d.isNotEmpty) await _enviar(d);
    }
  }

  Future<void> _novaConversa() async {
    if (_msgs.isEmpty && _conversationId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nova conversa'.tr),
        content: Text(
            'A conversa actual fica guardada no teu histórico. Começar de novo?'
                .tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Começar de novo'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AssistantService.guardarConversa(null);
    if (!mounted) return;
    setState(() {
      _conversationId = null;
      _msgs.clear();
      _banner = null;
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Text('Bora Assistente'.tr,
                style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Nova conversa'.tr,
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _novaConversa,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Container(
            width: double.infinity,
            color: AppColors.primaryWash,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _textoEstado(),
              style: const TextStyle(fontSize: 11, color: AppColors.primaryDark),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_banner != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF7ED),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.accentDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_banner!,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          Expanded(child: _corpo()),
          _Composer(
            controller: _input,
            foco: _foco,
            aPensar: _aPensar,
            aOuvir: _aOuvir,
            mostrarVoz: _sttDisponivel,
            onEnviar: () => _enviar(_input.text),
            onFoto: _escolherFoto,
            onVoz: _alternarVoz,
          ),
        ],
      ),
    );
  }

  String _textoEstado() {
    final partes = <String>[];
    if (_poupancaCents > 0) {
      partes.add('Já poupaste {0}'
          .trArgs(['€${(_poupancaCents / 100).toStringAsFixed(2)}']));
    }
    if (_restantesHoje != null) {
      partes.add('Restam {0} mensagens hoje'.trArgs([_restantesHoje]));
    }
    if (partes.isEmpty) {
      return 'Compara preços nas lojas da Guarda e enche o carrinho por ti.'.tr;
    }
    return partes.join(' · ');
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_msgs.isEmpty && !_aPensar) {
      return AssistantEmptyState(onSugestao: _enviar);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: _msgs.length + (_aPensar ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _msgs.length) return const _APensar();
        final m = _msgs[i];
        if (m.deUtilizador) return _BalaoUtilizador(msg: m);
        return _BalaoAssistente(
          reply: m.reply!,
          aEncherId: _aEncherId,
          onEncher: _encher,
          onFavor: _pedirFavor,
          onAcao: _acao,
          onConfirmarLista: _enviar,
        );
      },
    );
  }
}

class _BalaoUtilizador extends StatelessWidget {
  const _BalaoUtilizador({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final imagem = msg.imagem;
    final url = msg.imageUrl;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imagem != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(imagem, width: 180, fit: BoxFit.cover),
              )
            else if (url != null && url.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  width: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white70),
                ),
              ),
            if (msg.texto.isNotEmpty) ...[
              if (imagem != null || (url != null && url.isNotEmpty))
                const SizedBox(height: 6),
              Text(msg.texto,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalaoAssistente extends StatelessWidget {
  const _BalaoAssistente({
    required this.reply,
    required this.aEncherId,
    required this.onEncher,
    required this.onFavor,
    required this.onAcao,
    required this.onConfirmarLista,
  });

  final AssistantReply reply;
  final String? aEncherId;
  final void Function(AssistantProposal) onEncher;
  final void Function(List<AssistantFavor>) onFavor;
  final void Function(AssistantAcao) onAcao;
  final void Function(String) onConfirmarLista;

  @override
  Widget build(BuildContext context) {
    final r = reply;
    final lista = r.listaExtraida;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.texto.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(r.texto,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textPrimary, height: 1.35)),
            ),
          if (lista != null && lista.isNotEmpty)
            AssistantListaExtraidaCard(
                itens: lista, onConfirmar: onConfirmarLista),
          for (final p in r.propostas)
            AssistantProposalCard(
              proposta: p,
              aEncher: aEncherId == p.proposalId,
              onEncher: () => onEncher(p),
            ),
          if (r.divisao != null)
            AssistantDivisaoCard(
              divisao: r.divisao!,
              aEncherId: aEncherId,
              onEncher: onEncher,
            ),
          if (r.favores.isNotEmpty)
            AssistantFavoresCard(
              favores: r.favores,
              preco: r.favorPreco,
              onPedir: () => onFavor(r.favores),
            ),
          AssistantAcoesChips(acoes: r.acoes, onTap: onAcao),
        ],
      ),
    );
  }
}

class _APensar extends StatelessWidget {
  const _APensar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Text('a pensar…'.tr,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.foco,
    required this.aPensar,
    required this.aOuvir,
    required this.mostrarVoz,
    required this.onEnviar,
    required this.onFoto,
    required this.onVoz,
  });

  final TextEditingController controller;
  final FocusNode foco;
  final bool aPensar;
  final bool aOuvir;
  final bool mostrarVoz;
  final VoidCallback onEnviar;
  final VoidCallback onFoto;
  final VoidCallback onVoz;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Enviar foto da lista'.tr,
                onPressed: aPensar ? null : onFoto,
                icon: const Icon(Icons.photo_camera_outlined),
                color: AppColors.primaryDark,
              ),
              if (mostrarVoz)
                IconButton(
                  tooltip: aOuvir ? 'Parar'.tr : 'Ditar por voz'.tr,
                  onPressed: aPensar ? null : onVoz,
                  icon: Icon(aOuvir ? Icons.mic : Icons.mic_none),
                  color: aOuvir ? AppColors.error : AppColors.primaryDark,
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: foco,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onEnviar(),
                  decoration: InputDecoration(
                    hintText: aOuvir
                        ? 'A ouvir…'.tr
                        : 'Escreve a tua lista…'.tr,
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'Enviar'.tr,
                onPressed: aPensar ? null : onEnviar,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
