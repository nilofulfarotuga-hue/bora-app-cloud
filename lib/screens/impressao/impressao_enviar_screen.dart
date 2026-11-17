// "Imprimir documentos" (missão a3-guarda-16-11, parte 2; Bloco 2.1 da caixa 111).
// O cliente tira uma foto, escolhe fotos da galeria ou um ficheiro PDF/JPG/PNG (17/11/2026: pedido
// do Danilo, "tira foto, puxa o PDF", igual à receita da farmácia); a app conta as páginas sozinha e mostra a
// primeira página; escolhe tamanho, cor, faces, papel, cópias, páginas e acabamento; vê o preço
// calculado pelo SERVIDOR antes de enviar; escolhe levantar na loja ou entrega e o pagamento.
// Grandes formatos (A2/A1/A0) = "Pedir orçamento" pelo WhatsApp.
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_impressao.dart';
import '../../services/auto_address.dart';
import '../../services/impressao_service.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/bora/bora_bottom_action_bar.dart';
import '../../widgets/bora/bora_primary_button.dart';
import 'impressao_estado_screen.dart';

/// Link do WhatsApp para orçamentos de grande formato. Em teste, o WhatsApp da Bora faz de loja
/// (caixa 111, Bloco 4.2); quando a A3 tiver o dela, muda-se aqui ou passa a vir da loja.
const String kImpressaoOrcamentoWhatsApp =
    'https://wa.me/351937501673?text=Ol%C3%A1%20A3%2C%20queria%20um%20or%C3%A7amento%20de%20impress%C3%A3o%20em%20grande%20formato';

class _Ficheiro {
  _Ficheiro({required this.nome, required this.bytes, required this.tipo, required this.paginas, this.capa});
  final String nome;
  final Uint8List bytes;
  final String tipo; // pdf | jpg | png
  final int paginas;
  final Uint8List? capa;
}

/// Conta as páginas de um PDF (rasteriza em resolução mínima). Null = não deu para ler.
Future<int?> contarPaginasPdf(Uint8List pdf) async {
  try {
    var n = 0;
    await for (final _ in Printing.raster(pdf, dpi: 4)) {
      n++;
    }
    return n > 0 ? n : null;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> capaPdf(Uint8List pdf) async {
  try {
    await for (final r in Printing.raster(pdf, pages: const [0], dpi: 40)) {
      return await r.toPng();
    }
  } catch (_) {}
  return null;
}

class ImpressaoEnviarScreen extends StatefulWidget {
  const ImpressaoEnviarScreen({super.key, required this.restaurantId, required this.lojaNome, this.service});
  final String restaurantId;
  final String lojaNome;
  final ImpressaoService? service;

  @override
  State<ImpressaoEnviarScreen> createState() => _ImpressaoEnviarScreenState();
}

class _ImpressaoEnviarScreenState extends State<ImpressaoEnviarScreen> {
  late final ImpressaoService _svc = widget.service ?? ImpressaoService();
  final List<_Ficheiro> _fich = [];
  final _intervalo = TextEditingController();
  final _morada = TextEditingController();
  final _nota = TextEditingController();
  ImpressaoLoja? _loja;
  bool _aLer = false;
  String _tamanho = 'A4';
  bool _cor = false;
  bool _frenteVerso = false;
  String _papel = 'normal';
  int _copias = 1;
  bool _todasPaginas = true;
  String _acabamento = 'nenhum';
  String _modo = 'levantar';
  String _metodo = 'cash';
  double? _lat;
  double? _lng;
  Map<String, dynamic>? _preco;
  String? _erroPreco;
  bool _aCotar = false;
  bool _aEnviar = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _svc.loja(widget.restaurantId).then((l) {
      if (mounted) setState(() => _loja = l);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _intervalo.dispose();
    _morada.dispose();
    _nota.dispose();
    super.dispose();
  }

  int get _paginasTotais => _fich.fold(0, (s, f) => s + f.paginas);

  /// Páginas a imprimir por cópia (com o intervalo, se houver só um ficheiro).
  int? get _paginas {
    if (_fich.isEmpty) return null;
    if (_todasPaginas || _fich.length > 1) return _paginasTotais;
    return paginasDoIntervalo(_intervalo.text, _fich.first.paginas)?.length;
  }

  Map<String, dynamic> get _opcoes => {
        'tamanho': _tamanho,
        'cor': _cor,
        'frente_verso': _frenteVerso,
        'papel': _papel,
        'copias': _copias,
        'paginas': _paginas,
        'acabamento': _acabamento,
        'modo': _modo,
        'lat': _lat,
        'lng': _lng,
      };

  void _recotar() {
    _debounce?.cancel();
    final p = _paginas;
    if (p == null || p < 1) {
      setState(() {
        _preco = null;
        _erroPreco = _fich.isEmpty ? null : 'Intervalo de páginas inválido. Ex.: 1-3, 5';
      });
      return;
    }
    setState(() => _aCotar = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await _svc.cotar(widget.restaurantId, _opcoes);
        if (mounted) setState(() {
          _preco = r;
          _erroPreco = null;
        });
      } on ImpressaoErro catch (e) {
        if (mounted) setState(() {
          _preco = null;
          _erroPreco = e.mensagem;
        });
      } finally {
        if (mounted) setState(() => _aCotar = false);
      }
    });
  }

  Future<void> _escolher() async {
    final max = _loja?.maxFicheiros ?? 10;
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    setState(() => _aLer = true);
    final ignorados = <String>[];
    for (final f in r.files) {
      if (_fich.length >= max) {
        ignorados.add('${f.name} (máximo $max ficheiros)');
        continue;
      }
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > 25 * 1024 * 1024) {
        ignorados.add('${f.name} (maior que 25 MB)');
        continue;
      }
      final ext = (f.extension ?? '').toLowerCase();
      if (ext == 'pdf') {
        final n = await contarPaginasPdf(bytes);
        if (n == null) {
          ignorados.add('${f.name} (PDF que não se consegue ler)');
          continue;
        }
        _fich.add(_Ficheiro(nome: f.name, bytes: bytes, tipo: 'pdf', paginas: n, capa: await capaPdf(bytes)));
      } else {
        _fich.add(_Ficheiro(nome: f.name, bytes: bytes, tipo: ext == 'png' ? 'png' : 'jpg', paginas: 1, capa: bytes));
      }
    }
    _depoisDeJuntar(ignorados);
  }

  void _depoisDeJuntar(List<String> ignorados) {
    if (!mounted) return;
    setState(() => _aLer = false);
    if (ignorados.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não entraram: ${ignorados.join('; ')}')));
    }
    _recotar();
  }

  /// "Tirar foto" (câmara) ou "Fotos da galeria" (várias de uma vez). Cada foto conta 1 página.
  /// No iPhone o image_picker devolve JPEG mesmo quando a foto da galeria é HEIC (há qualidade definida).
  Future<void> _juntarFotos(ImageSource fonte) async {
    final max = _loja?.maxFicheiros ?? 10;
    final vagas = max - _fich.length;
    if (vagas <= 0) return _aviso('Já tem $max ficheiros, que é o máximo.');
    List<XFile> fotos;
    try {
      if (fonte == ImageSource.camera) {
        final x = await SafeImagePicker.pickImage(
            source: ImageSource.camera, maxWidth: 3000, maxHeight: 3000, imageQuality: 90);
        fotos = x == null ? const <XFile>[] : <XFile>[x];
      } else {
        fotos = await SafeImagePicker.pickMultiImage(maxWidth: 3000, maxHeight: 3000, imageQuality: 90, limit: vagas);
      }
    } catch (_) {
      return _aviso(fonte == ImageSource.camera
          ? 'Não foi possível abrir a câmara. Tente pela galeria.'
          : 'Não foi possível abrir a galeria. Tente outra vez.');
    }
    if (fotos.isEmpty || !mounted) return;
    setState(() => _aLer = true);
    final ignorados = <String>[];
    var n = 0;
    for (final x in fotos) {
      n++;
      final nome = x.name.trim().isEmpty ? 'foto-$n.jpg' : x.name;
      if (_fich.length >= max) {
        ignorados.add('$nome (máximo $max ficheiros)');
        continue;
      }
      final bytes = await x.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        ignorados.add('$nome (maior que 25 MB)');
        continue;
      }
      final png = nome.toLowerCase().endsWith('.png');
      _fich.add(_Ficheiro(nome: nome, bytes: bytes, tipo: png ? 'png' : 'jpg', paginas: 1, capa: bytes));
    }
    _depoisDeJuntar(ignorados);
  }

  Future<void> _moradaAuto() async {
    if (_morada.text.trim().isNotEmpty) return;
    try {
      final m = await AutoAddress.descobrir();
      if (!mounted || m == null || _morada.text.trim().isNotEmpty) return;
      setState(() {
        _morada.text = m.morada;
        _lat = m.coords?.latitude;
        _lng = m.coords?.longitude;
      });
      _recotar();
    } catch (_) {
      // sem GPS: o campo fica para escrever. Nunca trava.
    }
  }

  Future<void> _enviar() async {
    if (_fich.isEmpty) return _aviso('Escolha pelo menos um ficheiro.');
    if (_paginas == null) return _aviso('O intervalo de páginas não está certo. Ex.: 1-3, 5');
    if (_modo == 'entrega' && _morada.text.trim().isEmpty) return _aviso('Falta a morada de entrega.');
    setState(() => _aEnviar = true);
    try {
      final enviados = <Map<String, dynamic>>[];
      for (final f in _fich) {
        final path = await _svc.subirFicheiro(
          bytes: f.bytes,
          extensao: f.tipo,
          contentType: f.tipo == 'pdf' ? 'application/pdf' : (f.tipo == 'png' ? 'image/png' : 'image/jpeg'),
        );
        enviados.add(ImpressaoFicheiro(path: path, nome: f.nome, paginas: f.paginas, tipo: f.tipo).toMap());
      }
      final r = await _svc.criar(widget.restaurantId, {
        'tipo': 'impressao',
        ..._opcoes,
        'ficheiros': enviados,
        'intervalo': (_todasPaginas || _fich.length > 1) ? null : _intervalo.text.trim(),
        'morada': _modo == 'entrega' ? _morada.text.trim() : null,
        'nota': _nota.text.trim(),
        'metodo': _metodo,
      });
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ImpressaoEstadoScreen(pedidoId: r['id'].toString(), lojaNome: widget.lojaNome),
      ));
    } on ImpressaoErro catch (e) {
      _aviso(e.mensagem);
    } catch (_) {
      _aviso('Não foi possível enviar. Tente outra vez.');
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ─────────────────────────────────────────── peças

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _escolhas<T>(List<(T, String)> ops, T atual, ValueChanged<T> mudar) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in ops)
            ChoiceChip(
              label: Text(o.$2),
              selected: o.$1 == atual,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontWeight: o.$1 == atual ? FontWeight.w800 : FontWeight.w500,
                color: o.$1 == atual ? AppColors.primaryDark : AppColors.textPrimary,
              ),
              onSelected: (_) {
                mudar(o.$1);
                _recotar();
              },
            ),
        ],
      );

  Widget _cartaoFicheiro(int i) {
    final f = _fich[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 46,
            height: 62,
            color: AppColors.background,
            child: f.capa != null
                ? Image.memory(f.capa!, fit: BoxFit.cover)
                : Icon(f.tipo == 'pdf' ? Icons.picture_as_pdf : Icons.image, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${f.paginas} ${f.paginas == 1 ? 'página' : 'páginas'}', style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
        IconButton(
          tooltip: 'Tirar',
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() => _fich.removeAt(i));
            _recotar();
          },
        ),
      ]),
    );
  }

  Widget _linhaPreco(String t, int? c, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w500, fontSize: forte ? 17 : 15))),
          Text(euros(c), style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w600, fontSize: forte ? 17 : 15)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final loja = _loja;
    final total = (_preco?['total_cents'] as num?)?.toInt();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Imprimir documentos')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Text('Envie os seus ficheiros e a ${widget.lojaNome} imprime. Vê o preço antes de enviar.',
            style: const TextStyle(color: AppColors.textSecondary)),
        _titulo('1. O que quer imprimir'),
        for (var i = 0; i < _fich.length; i++) _cartaoFicheiro(i),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('impressao_tirar_foto'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _aLer ? null : () => _juntarFotos(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tirar foto'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('impressao_fotos_galeria'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _aLer ? null : () => _juntarFotos(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Fotos da galeria'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('impressao_escolher_ficheiros'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: AppColors.primary),
            foregroundColor: AppColors.primaryDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _aLer ? null : _escolher,
          icon: _aLer
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_aLer ? 'A contar as páginas…' : 'Ficheiro PDF (ou imagem)'),
        ),
        if (_fich.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Total: $_paginasTotais ${_paginasTotais == 1 ? 'página' : 'páginas'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        _titulo('2. Como imprimir'),
        _escolhas<String>(const [('A4', 'A4'), ('A3', 'A3')], _tamanho, (v) => setState(() => _tamanho = v)),
        const SizedBox(height: 8),
        _escolhas<bool>(const [(false, 'Preto e branco'), (true, 'Cores')], _cor, (v) => setState(() => _cor = v)),
        const SizedBox(height: 8),
        _escolhas<bool>(const [(false, 'Só frente'), (true, 'Frente e verso')], _frenteVerso, (v) => setState(() => _frenteVerso = v)),
        const SizedBox(height: 8),
        _escolhas<String>(const [('normal', 'Papel normal 80 g'), ('cartolina', 'Cartolina'), ('fotografico', 'Fotográfico')], _papel,
            (v) => setState(() => _papel = v)),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Cópias', style: TextStyle(fontWeight: FontWeight.w700))),
          IconButton.filledTonal(
            onPressed: _copias > 1
                ? () {
                    setState(() => _copias--);
                    _recotar();
                  }
                : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 40, child: Text('$_copias', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton.filledTonal(
            onPressed: _copias < 500
                ? () {
                    setState(() => _copias++);
                    _recotar();
                  }
                : null,
            icon: const Icon(Icons.add),
          ),
        ]),
        if (_fich.length == 1 && _fich.first.paginas > 1) ...[
          const SizedBox(height: 8),
          _escolhas<bool>(const [(true, 'Todas as páginas'), (false, 'Só algumas')], _todasPaginas, (v) => setState(() => _todasPaginas = v)),
          if (!_todasPaginas)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _intervalo,
                onChanged: (_) => _recotar(),
                decoration: InputDecoration(
                  labelText: 'Páginas (ex.: 1-3, 5)',
                  helperText: 'O documento tem ${_fich.first.paginas} páginas',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text('Acabamento', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _escolhas<String>(
          const [('nenhum', 'Nenhum'), ('agrafar', 'Agrafar'), ('argolas', 'Encadernar com argolas'), ('plastificar', 'Plastificar')],
          _acabamento,
          (v) => setState(() => _acabamento = v),
        ),
        TextButton.icon(
          onPressed: () => launchUrl(Uri.parse(kImpressaoOrcamentoWhatsApp), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.request_quote),
          label: const Text('A2, A1, A0 e grandes formatos: pedir orçamento'),
        ),
        _titulo('3. Levantar ou receber'),
        _escolhas<String>([
          if (loja?.permiteLevantar ?? true) ('levantar', 'Levantar na loja (sem taxa de entrega)'),
          if (loja?.permiteEntrega ?? true) ('entrega', 'Entrega pelo Bora'),
        ], _modo, (v) {
          setState(() => _modo = v);
          if (v == 'entrega') _moradaAuto();
        }),
        if (_modo == 'entrega')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: _morada,
              onChanged: (_) {
                _lat = null;
                _lng = null;
              },
              decoration: const InputDecoration(labelText: 'Morada de entrega', border: OutlineInputBorder()),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _nota,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Nota para a loja (opcional)', border: OutlineInputBorder()),
        ),
        _titulo('4. Pagamento'),
        _escolhas<String>(const [('card', 'Cartão'), ('mbway', 'MB Way'), ('cash', 'Dinheiro')], _metodo, (v) => setState(() => _metodo = v)),
        _titulo('Preço'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: _fich.isEmpty
              ? const Text('Escolha os ficheiros para ver o preço.')
              : _erroPreco != null
                  ? Text(_erroPreco!, style: const TextStyle(color: Colors.red))
                  : _preco == null
                      ? const LinearProgressIndicator()
                      : Column(children: [
                          _linhaPreco('Impressão (${_paginas ?? 0} pág. × $_copias)', (_preco!['artigo_cents'] as num?)?.toInt()),
                          _linhaPreco('Taxa de serviço', (_preco!['taxa_servico_cents'] as num?)?.toInt()),
                          if (_modo == 'entrega') _linhaPreco('Entrega', (_preco!['taxa_entrega_cents'] as num?)?.toInt()),
                          const Divider(),
                          _linhaPreco('Total', total, forte: true),
                          if (_preco!['provisorio'] == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('Preços de referência: a loja ainda pode acertar a tabela.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ),
                        ]),
        ),
      ]),
      bottomNavigationBar: BoraBottomActionBar(children: [
        BoraPrimaryButton(
          key: const ValueKey('impressao_enviar'),
          label: total == null ? 'Enviar pedido' : 'Enviar pedido · ${euros(total)}',
          icon: Icons.send,
          loading: _aEnviar || _aCotar,
          onPressed: (_fich.isEmpty || _preco == null || _aEnviar) ? null : _enviar,
        ),
      ]),
    );
  }
}
