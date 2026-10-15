import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import '../services/place_autocomplete_service.dart';
import '../services/web_health_log.dart';

import '../l10n/tr.dart';

/// A [TextFormField] that shows Google Places autocomplete suggestions
/// as the user types in a floating overlay (not inline), so it is always
/// visible regardless of the parent scroll context.
///
/// When the user picks a suggestion the widget resolves the place to
/// coordinates and calls [onSelected].
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.onChanged,
    this.labelText = 'Morada',
    this.prefixIcon,
    this.validator,
    this.serviceOverride,
    this.confirmarAoSair = true,
    this.helperText,
  });

  final TextEditingController controller;

  /// Morada escrita conta sempre (missão tvde-pedir-nunca-trava, 14/10/2026).
  /// Quando o cliente escreve e sai do campo / carrega em "concluído" SEM
  /// tocar numa sugestão, o campo geocodifica o texto (com as variantes
  /// tolerantes) e, se encontrar, chama [onSelected] com as coordenadas e
  /// mostra por baixo a morada encontrada para confirmar. Se não encontrar,
  /// diz isso no próprio campo e NÃO chama [onSelected].
  ///
  /// Desligar só onde o [onSelected] faz mais do que guardar a morada (fecha
  /// uma folha, abre um diálogo, escreve na base) — aí a confirmação fica
  /// para o toque numa sugestão ou para [AddressAutocompleteFieldState.confirmarTextoEscrito].
  final bool confirmarAoSair;

  /// Texto de ajuda por baixo do campo, vindo do ecrã (ex.: "Liga a
  /// localização ou escreve a morada" quando o GPS falhou). A confirmação da
  /// morada encontrada tem prioridade sobre ele.
  final String? helperText;

  /// Test seam: injeta um [PlaceAutocompleteService] falso nos testes de
  /// widget (a renderização das sugestões não pode depender da rede). Em
  /// produção fica null e criamos o serviço real.
  final PlaceAutocompleteService? serviceOverride;

  /// Called when the user selects a suggestion.
  /// [address] is the human-readable string; [coords] is the resolved
  /// location (null when the API key is not configured or the call fails).
  final void Function(String address, ll.LatLng? coords) onSelected;

  /// Called when the user TYPES (not when a suggestion is selected
  /// programmatically). Use this to detect manual edits and reset any
  /// "address confirmed" state in the parent.
  final ValueChanged<String>? onChanged;

  final String labelText;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;

  @override
  State<AddressAutocompleteField> createState() =>
      AddressAutocompleteFieldState();
}

/// Estado público para o ecrã poder, com uma `GlobalKey`, confirmar o texto
/// escrito antes de pedir ([confirmarTextoEscrito]) e levar o foco ao campo
/// em falta ([pedirFoco]) — o botão diz o que falta e leva lá.
class AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  late final PlaceAutocompleteService _service;
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  Timer? _focusLossTimer;
  List<PlacePrediction> _predictions = const [];
  bool _resolving = false;
  bool _isSelecting = false;

  // Estado do serviço na última pesquisa + o texto pesquisado. O campo NUNCA
  // fica mudo: sem resultados ou sem serviço, o overlay mostra o que se passa
  // e oferece o modo manual ("Usar esta morada") — regra LOCALIZAÇÃO NUNCA
  // TRAVA (24/08; cliente TVDE perdida 2x a 31/08).
  PlaceServiceStatus _status = PlaceServiceStatus.ready;
  String _lastQueryText = '';

  // ── Programmatic-change guards ─────────────────────────────────────────
  // GUARD 1 (sync): true while _onSelect is setting controller.text in the
  // same call stack.  Blocks the synchronous onChanged callback.
  bool _isProgrammaticChange = false;

  // GUARD 2 (async): stores the text we just set programmatically.
  // On Android/iOS the platform IME echoes the new text back via the
  // platform channel AFTER the synchronous frame, so _isProgrammaticChange
  // is already false when the echo arrives.  Comparing against this value
  // lets us discard that echo without touching the parent's reset callback.
  String? _lastSelectedText;
  // ────────────────────────────────────────────────────────────────────────

  // ── Morada escrita à mão (missão tvde-pedir-nunca-trava, 14/10/2026) ────
  // Cicatriz: a cliente escrevia a morada e não tocava em nenhuma sugestão;
  // o ecrã ficava sem coordenadas e o botão de pedir cinzento, sem dizer
  // porquê. Agora o texto escrito confirma-se sozinho ao sair do campo.

  /// Há texto escrito pelo cliente que ainda não virou morada com
  /// coordenadas (nem por sugestão, nem pela confirmação automática).
  bool _textoPendente = false;

  /// Sobe a cada edição ou escolha: uma confirmação que acabe depois de o
  /// cliente ter escrito mais (ou escolhido uma sugestão) é descartada.
  int _seq = 0;
  Future<bool>? _confirmacaoEmCurso;
  String? _textoEmConfirmacao;

  /// Morada encontrada no mapa (para o cliente confirmar) ou o erro de não a
  /// ter encontrado — ambos dizem respeito a [_textoDoAviso] e somem quando o
  /// texto do campo muda.
  String? _moradaEncontrada;
  String? _erroMorada;
  String? _textoDoAviso;
  String _ultimoTexto = '';

  /// O cliente escreveu e ainda não ficou morada com coordenadas.
  bool get temTextoPorConfirmar =>
      _textoPendente && widget.controller.text.trim().isNotEmpty;

  /// Leva o foco (e o teclado) a este campo — é para aqui que o botão de
  /// pedir manda o cliente quando falta esta morada.
  void pedirFoco() {
    if (!mounted) return;
    _focusNode.requestFocus();
  }

  /// Geocodifica o texto escrito e, se encontrar, aceita-o como se fosse uma
  /// sugestão escolhida ([AddressAutocompleteField.onSelected] com
  /// coordenadas). Devolve `true` quando ficou morada com coordenadas.
  /// Chamar duas vezes seguidas com o mesmo texto devolve a mesma tentativa.
  Future<bool> confirmarTextoEscrito() {
    final texto = widget.controller.text.trim();
    if (texto.isEmpty) return Future<bool>.value(false);
    final emCurso = _confirmacaoEmCurso;
    if (emCurso != null && _textoEmConfirmacao == texto) return emCurso;
    final tentativa = _confirmar(texto);
    _confirmacaoEmCurso = tentativa;
    _textoEmConfirmacao = texto;
    tentativa.whenComplete(() {
      if (identical(_confirmacaoEmCurso, tentativa)) {
        _confirmacaoEmCurso = null;
        _textoEmConfirmacao = null;
      }
    });
    return tentativa;
  }

  Future<bool> _confirmar(String texto) async {
    final seq = _seq;
    _debounce?.cancel();
    if (mounted) {
      setState(() {
        _resolving = true;
        _erroMorada = null;
      });
    }

    MoradaGeocodificada? achada;
    try {
      // 1) Geocoding tolerante (texto todo → sem nº de porta → abreviaturas
      //    por extenso), com o melhor resultado na Guarda.
      achada = await _service.geocodeTolerante(texto);
      // 2) Comércio/POI que o Geocoding não conhece ("Continente", "Lavie"):
      //    fica a 1.ª sugestão, que já vem com a Guarda à frente.
      if (achada == null) {
        final sugestoes = await _service.fetchPredictionsTolerante(texto);
        // Quem escreveu "…, Guarda" não quer a mesma rua em Lisboa: só vale
        // uma sugestão da Guarda (prova web 15/10, "Av. Rainha D. Amélia").
        final pedeGuarda = textoPedeGuarda(texto);
        final validas = sugestoes.predictions.where((p) {
          final linha = '${p.description} ${p.secondaryText ?? ''}';
          return (!pedeGuarda || textoPedeGuarda(linha)) &&
              partilhaPalavra(texto, linha);
        });
        if (validas.isNotEmpty) {
          final p = validas.first;
          final c = await _service.resolvePlaceLocation(p.placeId) ??
              await _service.geocodeAddress(p.description);
          if (c != null) achada = MoradaGeocodificada(c, morada: p.description);
        }
      }
    } catch (e) {
      debugPrint('AddressAutocomplete: confirmação do texto falhou => $e');
    }
    _service.resetSession();

    if (!mounted) return false;
    if (seq != _seq) {
      // O cliente escreveu mais ou escolheu uma sugestão entretanto: manda o
      // que ele fez depois, esta tentativa já não conta.
      setState(() => _resolving = false);
      return false;
    }

    if (achada == null) {
      setState(() {
        _resolving = false;
        _moradaEncontrada = null;
        _erroMorada =
            'Não encontrei esta morada no mapa. Escolhe uma sugestão ou acrescenta a cidade (ex.: Guarda).'
                .tr;
        _textoDoAviso = texto;
      });
      WebHealthLog.log(
        motivo: 'geocode_manual_falhou',
        ecra: widget.labelText,
        detalhe: 'confirmação automática: ${texto.length} caracteres sem coordenadas',
      );
      return false;
    }

    // Aceite: o texto do cliente fica (tem o nº da porta, que o motorista
    // precisa); por baixo aparece a morada encontrada no mapa para confirmar.
    _removeOverlay();
    if (widget.controller.text != texto) {
      _lastSelectedText = texto;
      _isProgrammaticChange = true;
      widget.controller.text = texto;
      widget.controller.selection =
          TextSelection.fromPosition(TextPosition(offset: texto.length));
      _isProgrammaticChange = false;
    }
    setState(() {
      _resolving = false;
      _predictions = const [];
      _textoPendente = false;
      _erroMorada = null;
      _moradaEncontrada = achada!.morada ?? '';
      _textoDoAviso = texto;
    });
    debugPrint('AddressAutocomplete: TEXTO CONFIRMADO "$texto" => ${achada.coords}');
    widget.onSelected(texto, achada.coords);
    return true;
  }

  /// Qualquer mudança do texto (escrita ou vinda do ecrã, ex.: GPS) apaga o
  /// aviso da morada anterior. O texto vindo do ecrã não fica "por
  /// confirmar": o [_onChanged] volta a marcar só quando foi o cliente.
  void _onControllerChanged() {
    final texto = widget.controller.text;
    if (texto == _ultimoTexto) return;
    _ultimoTexto = texto;
    _textoPendente = false;
    if (_textoDoAviso != null && texto.trim() != _textoDoAviso) {
      _textoDoAviso = null;
      if (_moradaEncontrada != null || _erroMorada != null) {
        _moradaEncontrada = null;
        _erroMorada = null;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _service =
        widget.serviceOverride ?? createPlaceAutocompleteService(googleApiKey);
    _focusNode.addListener(_onFocusChanged);
    _ultimoTexto = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusLossTimer?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // Uber/Google-style: ao focar, sobe o campo para o topo do Scrollable
      // (se houver) para que a lista de sugestões — que abre PARA BAIXO —
      // tenha espaço acima do teclado. É no-op quando o campo não está dentro
      // de um Scrollable (ex.: alguns formulários), sem efeitos colaterais.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;
        final ctx = _fieldKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
      return;
    }
    _debounce?.cancel();
    _focusLossTimer?.cancel();
    _focusLossTimer = Timer(const Duration(milliseconds: 200), () {
      if (_isSelecting) return;
      _removeOverlay();
      if (_predictions.isNotEmpty && mounted) {
        setState(() => _predictions = const []);
      }
      // Saiu do campo com morada escrita e sem tocar em nenhuma sugestão:
      // a morada escrita conta (missão tvde-pedir-nunca-trava, 14/10).
      if (mounted && widget.confirmarAoSair && temTextoPorConfirmar) {
        confirmarTextoEscrito();
      }
    });
  }

  void _onSubmitted(String _) {
    if (widget.confirmarAoSair && temTextoPorConfirmar) {
      confirmarTextoEscrito();
    }
  }

  void _onChanged(String value) {
    // Guard 1: synchronous programmatic change still in progress.
    if (_isProgrammaticChange) {
      debugPrint(
          '[ACF._onChanged] BLOCKED guard1 (programmatic) value="$value"');
      return;
    }

    // Guard 2: async IME echo of the text we programmatically set.
    // The echo carries the exact text we assigned, so it is NOT a user edit.
    if (value == _lastSelectedText) {
      debugPrint('[ACF._onChanged] BLOCKED guard2 (IME echo) value="$value"');
      return;
    }

    // Genuine user keystroke — discard the selection memory so future
    // edits (even to the same string) propagate normally.
    debugPrint('[ACF._onChanged] PASS — genuine user input value="$value"');
    _lastSelectedText = null;
    _seq++;
    _textoPendente = value.trim().isNotEmpty;

    // Notify parent that the user is typing (NOT a programmatic selection).
    widget.onChanged?.call(value);

    _debounce?.cancel();
    final trimmed = value.trim();
    // Sugestões automáticas desde o 1.º caractere (estilo Uber): digitar "r"
    // já mostra ruas. O debounce curto evita chamadas a cada tecla.
    if (trimmed.isEmpty) {
      _service.resetSession();
      _updatePredictions(
          const PredictionsResult(PlaceServiceStatus.ready, []), '');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final query = widget.controller.text.trim();
      if (query.isEmpty || !mounted) return;
      // Tolerante: texto todo vazio → repete sem nº de porta / abreviaturas.
      final result = await _service.fetchPredictionsTolerante(query);
      if (!mounted) return;
      // Discard stale result if the user typed more while we were fetching.
      if (widget.controller.text.trim() != query) return;
      _updatePredictions(result, query);
    });
  }

  void _updatePredictions(PredictionsResult result, String query) {
    setState(() {
      _predictions = result.predictions;
      _status = result.status;
      _lastQueryText = query;
    });

    // Com sugestões, mostra-as. Sem sugestões, o overlay só desaparece quando
    // não há nada útil a dizer (texto curto com serviço vivo); nos restantes
    // casos mostra o estado + o modo manual — nunca um campo mudo.
    final mostrarOverlay = result.predictions.isNotEmpty ||
        _status == PlaceServiceStatus.loading ||
        _status == PlaceServiceStatus.unavailable ||
        (_status == PlaceServiceStatus.ready && query.length >= 4);

    if (!mostrarOverlay) {
      _removeOverlay();
    } else if (_overlayEntry == null) {
      _insertOverlay();
    } else {
      // Refresh the existing entry with the new content.
      _overlayEntry!.markNeedsBuild();
    }

    if (_status == PlaceServiceStatus.ready &&
        result.predictions.isEmpty &&
        query.length >= 8) {
      // Morada a sério sem um único resultado: fica registado para o painel.
      WebHealthLog.log(
        motivo: 'sem_resultados',
        ecra: widget.labelText,
        detalhe: 'consulta com ${query.length} caracteres',
      );
    }
  }

  void _insertOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlayContent(BuildContext context) {
    final RenderBox? box =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final double width = box?.size.width ?? 280.0;

    // Abre SEMPRE para baixo — o caminho de renderização comprovado (funciona
    // na limpeza e no resto). A tentativa anterior de abrir para CIMA em
    // campos a meio da página produzia uma CAIXA BRANCA VAZIA: o anchor
    // invertido (followerAnchor bottomLeft) com a ListView shrinkWrap dentro
    // das constraints soltas do Overlay não renderizava as sugestões. Em vez
    // disso, o campo sobe ao focar (ver _onFocusChanged), estilo Uber/Google,
    // deixando a lista abaixo do campo e acima do teclado.
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      child: SizedBox(
        width: width,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              children: _buildOverlayRows(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Linhas do overlay: sugestões quando existem; caso contrário o estado do
  /// serviço em PT-PT + o modo manual. O campo nunca fica mudo.
  List<Widget> _buildOverlayRows(BuildContext context) {
    if (_predictions.isNotEmpty) {
      final rows = <Widget>[];
      for (var i = 0; i < _predictions.length; i++) {
        if (i > 0) rows.add(const Divider(height: 1));
        final p = _predictions[i];
        rows.add(ListTile(
          dense: true,
          leading: Icon(
            p.isEstablishment
                ? Icons.storefront_outlined
                : Icons.location_on_outlined,
            size: 20,
          ),
          title: Text(
            p.primaryText ?? p.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: p.secondaryText == null
              ? null
              : Text(
                  p.secondaryText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _onSelect(p),
        ));
      }
      return rows;
    }

    switch (_status) {
      case PlaceServiceStatus.loading:
        return [
          ListTile(
            dense: true,
            leading: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('A procurar moradas…'.tr),
          ),
        ];
      case PlaceServiceStatus.ready:
        return [
          ListTile(
            dense: true,
            leading: const Icon(Icons.search_off_outlined, size: 20),
            title: Text('Não encontrei essa morada.'.tr),
            subtitle: Text('Escreve a rua e o número.'.tr),
          ),
          const Divider(height: 1),
          _buildManualRow(),
        ];
      case PlaceServiceStatus.unavailable:
        return [
          ListTile(
            dense: true,
            leading: const Icon(Icons.wifi_off_outlined, size: 20),
            title: Text('Sem sugestões automáticas neste momento.'.tr),
            subtitle: Text('Podes escrever a morada completa à mão.'.tr),
          ),
          const Divider(height: 1),
          _buildManualRow(),
        ];
    }
  }

  /// Modo manual — a rede de segurança: o texto escrito segue como morada,
  /// com geocodificação em segundo plano (servidor, se preciso). Nunca
  /// bloqueia o cliente por falta de sugestões.
  Widget _buildManualRow() {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.edit_location_alt_outlined, size: 20),
      title: Text(
        'Usar esta morada: "{0}"'.trArgs([_lastQueryText]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _onManualUse,
    );
  }

  Future<void> _onManualUse() async {
    final texto = widget.controller.text.trim();
    if (texto.isEmpty) return;

    _isSelecting = true;
    _focusLossTimer?.cancel();
    _debounce?.cancel();
    _removeOverlay();
    _seq++;
    _textoPendente = false;
    setState(() {
      _predictions = const [];
      _resolving = true;
      _erroMorada = null;
      _moradaEncontrada = null;
      _textoDoAviso = null;
    });
    _lastSelectedText = texto;

    ll.LatLng? coords;
    try {
      // Tolerante (14/10): sem nº de porta / abreviaturas por extenso.
      coords = (await _service.geocodeTolerante(texto))?.coords;
    } catch (e) {
      debugPrint('AddressAutocomplete: geocode manual falhou => $e');
    }
    debugPrint('AddressAutocomplete: MANUAL "$texto" => $coords');
    if (coords == null) {
      WebHealthLog.log(
        motivo: 'geocode_manual_falhou',
        ecra: widget.labelText,
        detalhe: 'morada com ${texto.length} caracteres seguiu sem coordenadas',
      );
    }

    _service.resetSession();
    if (!mounted) return;
    _isSelecting = false;
    setState(() => _resolving = false);
    widget.onSelected(texto, coords);
  }

  Future<void> _onSelect(PlacePrediction prediction) async {
    _isSelecting = true;
    _focusLossTimer?.cancel();
    _debounce?.cancel();
    _removeOverlay();
    _seq++;
    _textoPendente = false;
    setState(() {
      _predictions = const [];
      _resolving = true;
      _erroMorada = null;
      _moradaEncontrada = null;
      _textoDoAviso = null;
    });

    // Arm both guards BEFORE touching the controller so that neither the
    // synchronous callback nor the async IME echo calls widget.onChanged.
    _lastSelectedText = prediction.description;
    _isProgrammaticChange = true;
    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: prediction.description.length),
    );
    _isProgrammaticChange = false;
    // _lastSelectedText intentionally kept set — cleared only when the user
    // makes a genuine edit (see _onChanged guard 2).

    debugPrint(
        'AddressAutocomplete: SELECTED "${prediction.description}" placeId=${prediction.placeId}');

    ll.LatLng? coords;
    try {
      coords = await _service.resolvePlaceLocation(prediction.placeId);
    } catch (e) {
      debugPrint('AddressAutocomplete: resolvePlaceLocation threw => $e');
    }

    // Fallback: if Place Details failed, try Geocoding API.
    if (coords == null && prediction.description.isNotEmpty) {
      debugPrint(
          'AddressAutocomplete: Place Details returned null — trying Geocoding fallback');
      try {
        coords = await _service.geocodeAddress(prediction.description);
      } catch (e) {
        debugPrint('AddressAutocomplete: geocodeAddress threw => $e');
      }
    }

    debugPrint('AddressAutocomplete: COORDS => $coords');

    _service.resetSession();

    if (!mounted) return;
    _isSelecting = false;
    setState(() => _resolving = false);
    widget.onSelected(prediction.description, coords);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        onFieldSubmitted: _onSubmitted,
        textInputAction: TextInputAction.done,
        validator: widget.validator,
        // Parte 9 — dentro de bottom-sheets/scrollables, mantém o campo bem acima
        // do teclado deixando espaço para a lista de sugestões (abre para baixo,
        // ~260px) para nunca ficar atrás do teclado. Ver licao-autocomplete-teclado.
        scrollPadding: const EdgeInsets.only(bottom: 320),
        decoration: InputDecoration(
          labelText: widget.labelText.tr,
          // Morada escrita aceite → mostra onde ficou no mapa, para o cliente
          // confirmar. Senão, a ajuda que o ecrã mandou (ex.: GPS desligado).
          helperText: _moradaEncontrada != null
              ? (_moradaEncontrada!.isEmpty
                  ? 'Morada encontrada no mapa.'.tr
                  : 'No mapa: {0}'.trArgs([_moradaEncontrada!]))
              : widget.helperText,
          helperMaxLines: 2,
          errorText: _erroMorada,
          errorMaxLines: 3,
          prefixIcon:
              widget.prefixIcon ?? const Icon(Icons.location_on_outlined),
          suffixIcon: _resolving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
