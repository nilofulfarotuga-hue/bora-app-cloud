// Visualizador ÚNICO de fotos em ecrã inteiro (08/10/2026, pedido do Danilo).
//
// Caso real: na miniatura da receita que a cliente mandou num Favor, o Danilo
// (a fazer de estafeta) não conseguia ler os números. Ao tocar numa foto, ela
// abre no ecrã TODO: fundo preto, a imagem inteira sem cortes
// (BoxFit.contain), dois dedos até 5x, arrastar, dois toques para ampliar.
// Carrega SEMPRE o ficheiro original (sem miniatura nem `cacheWidth`).
// Fotos de baldes privados (order-photos, receipts, documentos) passam pelo
// `resolveSignedUrlIfPrivate` — URL assinada por 1 hora, que chega para ler.
//
// Usa-se em todas as fotos que se tocam nas 3 apps e no painel:
// `BoraFotoEcraInteiro.abrir(context, urlOrPath: ...)`. O
// `PrivateBucketImage` já abre isto sozinho ao tocar.
import 'package:flutter/material.dart';

import 'private_bucket_image.dart';

/// Uma foto a mostrar: endereço/caminho do Storage OU uma imagem já em
/// memória (ficheiro local acabado de tirar, bytes).
class BoraFoto {
  const BoraFoto.url(String this.urlOrPath) : imagem = null;
  const BoraFoto.imagem(ImageProvider this.imagem) : urlOrPath = null;

  final String? urlOrPath;
  final ImageProvider? imagem;
}

class BoraFotoEcraInteiro extends StatefulWidget {
  const BoraFotoEcraInteiro({
    super.key,
    required this.fotos,
    this.inicial = 0,
    this.titulo,
  });

  final List<BoraFoto> fotos;
  final int inicial;
  final String? titulo;

  /// Abre uma foto. Passa [urlOrPath] (URL ou `bucket/caminho`) ou [imagem].
  static Future<void> abrir(
    BuildContext context, {
    String? urlOrPath,
    ImageProvider? imagem,
    String? titulo,
  }) {
    final foto = imagem != null
        ? BoraFoto.imagem(imagem)
        : BoraFoto.url(urlOrPath ?? '');
    return abrirVarias(context, [foto], titulo: titulo);
  }

  /// Abre várias fotos para passar com o dedo (galerias).
  static Future<void> abrirVarias(
    BuildContext context,
    List<BoraFoto> fotos, {
    int inicial = 0,
    String? titulo,
  }) {
    if (fotos.isEmpty) return Future<void>.value();
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => BoraFotoEcraInteiro(
          fotos: fotos,
          inicial: inicial.clamp(0, fotos.length - 1),
          titulo: titulo,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<BoraFotoEcraInteiro> createState() => _BoraFotoEcraInteiroState();
}

class _BoraFotoEcraInteiroState extends State<BoraFotoEcraInteiro> {
  late final PageController _paginas =
      PageController(initialPage: widget.inicial);
  late int _atual = widget.inicial;
  bool _ampliada = false;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final varias = widget.fotos.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _paginas,
              // Com a foto ampliada o dedo arrasta a foto, não muda de página.
              physics: _ampliada || !varias
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.fotos.length,
              onPageChanged: (i) => setState(() {
                _atual = i;
                _ampliada = false;
              }),
              itemBuilder: (_, i) => _FotoAmpliavel(
                foto: widget.fotos[i],
                onAmpliada: (v) {
                  if (v != _ampliada) setState(() => _ampliada = v);
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const Key('bora_foto_fechar'),
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close, color: Colors.white),
                      iconSize: 28,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        if (widget.titulo != null) widget.titulo!,
                        if (varias) '${_atual + 1} / ${widget.fotos.length}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _ampliada
                      ? 'Dois toques para voltar ao tamanho normal'
                      : 'Dois dedos ou dois toques para ampliar',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FotoAmpliavel extends StatefulWidget {
  const _FotoAmpliavel({required this.foto, required this.onAmpliada});

  final BoraFoto foto;
  final ValueChanged<bool> onAmpliada;

  @override
  State<_FotoAmpliavel> createState() => _FotoAmpliavelState();
}

class _FotoAmpliavelState extends State<_FotoAmpliavel> {
  static const double _maxZoom = 5;
  static const double _zoomDoisToques = 2.5;

  final TransformationController _transf = TransformationController();
  Offset? _pontoToque;
  ImageProvider? _imagem;
  bool _aCarregar = true;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _transf.addListener(_aoMudarZoom);
    _resolver();
  }

  @override
  void dispose() {
    _transf.removeListener(_aoMudarZoom);
    _transf.dispose();
    super.dispose();
  }

  void _aoMudarZoom() {
    widget.onAmpliada(_transf.value.getMaxScaleOnAxis() > 1.01);
  }

  Future<void> _resolver() async {
    final dada = widget.foto.imagem;
    if (dada != null) {
      setState(() {
        _imagem = dada;
        _aCarregar = false;
      });
      return;
    }
    final bruto = (widget.foto.urlOrPath ?? '').trim();
    final url = bruto.isEmpty ? null : await resolveSignedUrlIfPrivate(bruto);
    if (!mounted) return;
    setState(() {
      _aCarregar = false;
      if (url == null || url.isEmpty) {
        _falhou = true;
      } else {
        // Original: sem cacheWidth/cacheHeight para não perder resolução.
        _imagem = NetworkImage(url);
      }
    });
  }

  void _doisToques() {
    final ampliada = _transf.value.getMaxScaleOnAxis() > 1.01;
    if (ampliada) {
      _transf.value = Matrix4.identity();
      return;
    }
    final p = _pontoToque ?? Offset.zero;
    const s = _zoomDoisToques;
    // Amplia à volta do ponto tocado (escala s + translação que o mantém
    // no mesmo sítio do ecrã). setEntry existe em todas as versões do
    // vector_math que o Flutter do CI (3.41) e o do PC (3.47) trazem.
    _transf.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -p.dx * (s - 1))
      ..setEntry(1, 3, -p.dy * (s - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_falhou || _imagem == null) {
      return const _ErroFoto();
    }
    return GestureDetector(
      onDoubleTapDown: (d) => _pontoToque = d.localPosition,
      onDoubleTap: _doisToques,
      child: InteractiveViewer(
        transformationController: _transf,
        minScale: 1,
        maxScale: _maxZoom,
        clipBehavior: Clip.none,
        child: SizedBox.expand(
          child: Image(
            image: _imagem!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            loadingBuilder: (ctx, child, progresso) {
              if (progresso == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (_, __, ___) => const _ErroFoto(),
          ),
        ),
      ),
    );
  }
}

class _ErroFoto extends StatelessWidget {
  const _ErroFoto();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56),
            SizedBox(height: 12),
            Text(
              'Não foi possível abrir a foto. Verifica a ligação e tenta de novo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
