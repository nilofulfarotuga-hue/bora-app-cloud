/// "Comprovativo de atividade" — o prestador envia o NIF e uma foto ou PDF do
/// comprovativo de atividade aberta nas Finanças (Bloco C · 20/10/2026).
///
/// Um ecrã só para todos os papéis (estafeta, motorista TVDE, limpeza, lavagem,
/// serviços): a verdade é por pessoa (`provider_atividade`, por `user_id`).
/// Abre-se pelo aviso no ecrã principal do prestador, pelo push "Falta o
/// comprovativo de atividade" (gancho único `NotificationService.abrirTrabalho`
/// com a categoria 'atividade') e como último passo da candidatura.
///
/// PADRAO §1.26: nada aqui espera sem tecto — o carregamento tem limite de
/// tempo e botão "Tentar outra vez"; escolher o ficheiro nunca põe o ecrã a
/// rodar; uma recusa de câmara explica o que fazer. Na web usa-se o seletor de
/// ficheiros (o da galeria do image_picker não volta quando se cancela).
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_colors.dart';
import '../../services/atividade_service.dart';
import '../../utils/safe_image_picker.dart';

typedef CarregarAtividade = Future<AtividadeEstado?> Function();
typedef EnviarAtividade = Future<EnvioAtividade> Function(
    {required String nif, required Uint8List bytes});

class ComprovativoAtividadeScreen extends StatefulWidget {
  const ComprovativoAtividadeScreen({
    super.key,
    this.modoCadastro = false,
    this.carregar,
    this.enviar,
  });

  /// Último passo da candidatura: mostra "Fazer depois".
  final bool modoCadastro;

  /// Injeção para os testes (por defeito, o servidor).
  final CarregarAtividade? carregar;
  final EnviarAtividade? enviar;

  /// Depois de uma candidatura nova: se o comprovativo conta para a aprovação
  /// e ainda falta, abre este ecrã como último passo. Sem rede, segue em frente
  /// (o aviso no ecrã principal e o push tratam do resto).
  static Future<void> depoisDaCandidatura(BuildContext context) async {
    final e = await AtividadeService.carregar();
    if (!context.mounted || e == null) return;
    if (!e.ePrestador || !e.obrigatoria || !e.precisaDeEnviar) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ComprovativoAtividadeScreen(modoCadastro: true),
    ));
  }

  @override
  State<ComprovativoAtividadeScreen> createState() =>
      _ComprovativoAtividadeScreenState();
}

class _ComprovativoAtividadeScreenState
    extends State<ComprovativoAtividadeScreen> {
  final _nifCtrl = TextEditingController();
  AtividadeEstado? _estado;
  bool _carregando = true;
  bool _falhouCarga = false;
  Uint8List? _bytes;
  String? _nomeFicheiro;
  String? _aviso; // erro ou explicação inline (PT-PT)
  bool _enviando = false;
  bool _aEscolher = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nifCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhouCarga = false;
    });
    AtividadeEstado? e;
    try {
      e = await (widget.carregar ?? AtividadeService.carregar)()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      e = null;
    }
    if (!mounted) return;
    setState(() {
      _estado = e;
      _carregando = false;
      _falhouCarga = e == null;
      if (e != null && _nifCtrl.text.isEmpty) {
        _nifCtrl.text = e.nif ?? e.nifSugerido ?? '';
      }
    });
  }

  void _usar(Uint8List bytes, String nome) {
    final problema = problemaDoComprovativo(bytes);
    setState(() {
      if (problema != null) {
        _bytes = null;
        _nomeFicheiro = null;
        _aviso = problema;
      } else {
        _bytes = bytes;
        _nomeFicheiro = nome;
        _aviso = null;
      }
    });
  }

  Future<void> _foto(ImageSource fonte) async {
    if (_aEscolher) return;
    _aEscolher = true;
    try {
      // imageQuality/maxWidth fazem o image_picker devolver JPEG (também no
      // iPhone, onde a câmara grava HEIC).
      final x = await SafeImagePicker.pickImage(
        source: fonte,
        maxWidth: 2200,
        imageQuality: 85,
      );
      if (x == null || !mounted) return;
      _usar(await x.readAsBytes(), x.name);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final semAcesso = e.code.contains('denied') || e.code.contains('access');
      setState(() => _aviso = semAcesso
          ? (fonte == ImageSource.camera
              ? 'A app não tem acesso à câmara. Permite o acesso nas definições do '
                  'telemóvel, ou escolhe a foto da galeria ou um PDF.'
              : 'A app não tem acesso às fotos. Permite o acesso nas definições do '
                  'telemóvel, ou tira uma foto ou escolhe um PDF.')
          : 'Não foi possível abrir a ${fonte == ImageSource.camera ? 'câmara' : 'galeria'}. '
              'Tenta outra vez ou escolhe um PDF.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _aviso =
          'Não foi possível ler a foto. Tenta outra vez ou escolhe um PDF.');
    } finally {
      _aEscolher = false;
    }
  }

  Future<void> _ficheiro() async {
    if (_aEscolher) return;
    _aEscolher = true;
    try {
      final r = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            kIsWeb ? const ['pdf', 'jpg', 'jpeg', 'png'] : const ['pdf'],
        withData: true,
      );
      final f = (r == null || r.files.isEmpty) ? null : r.files.first;
      final bytes = f?.bytes;
      if (f == null || !mounted) return;
      if (bytes == null) {
        setState(
            () => _aviso = 'Não foi possível ler o ficheiro. Tenta outra vez.');
        return;
      }
      _usar(bytes, f.name);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _aviso = 'Não foi possível abrir os ficheiros. Tenta outra vez.');
    } finally {
      _aEscolher = false;
    }
  }

  Future<void> _enviar() async {
    // Guarda de reentrada LOCAL (PADRAO §3.13): toque duplo não envia duas vezes.
    if (_enviando) return;
    final erroNif = validarNifAtividade(_nifCtrl.text);
    if (erroNif != null) {
      setState(() => _aviso = erroNif);
      return;
    }
    final bytes = _bytes;
    if (bytes == null) {
      setState(
          () => _aviso = 'Escolhe primeiro a foto ou o PDF do comprovativo.');
      return;
    }
    setState(() {
      _enviando = true;
      _aviso = null;
    });
    EnvioAtividade r;
    try {
      r = await (widget.enviar ?? AtividadeService.enviar)(
          nif: _nifCtrl.text, bytes: bytes);
    } catch (e) {
      r = EnvioAtividade.falhou(mensagemDoErroAtividade(e));
    }
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (r.ok) {
        _estado = r.estado;
        _bytes = null;
        _nomeFicheiro = null;
      } else {
        _aviso = r.erro;
      }
    });
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Comprovativo enviado. Vamos ver e avisamos-te. 💚')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.modoCadastro
        ? 'Último passo: comprovativo de atividade'
        : 'Comprovativo de atividade';
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: SafeArea(child: _corpo()),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    final e = _estado;
    if (_falhouCarga || e == null) {
      return _Centro(
        icone: Icons.wifi_off,
        texto: 'Não foi possível carregar. Verifica a ligação.',
        botao: FilledButton(
          key: const Key('atividade-tentar'),
          onPressed: _carregar,
          child: const Text('Tentar outra vez'),
        ),
        rodape: _fazerDepois(),
      );
    }
    if (!e.ePrestador) {
      return _Centro(
        icone: Icons.info_outline,
        texto:
            'Esta conta ainda não tem nenhum trabalho no Bora. Faz primeiro a '
            'candidatura em «Quero trabalhar no Bora».',
        rodape: _fazerDepois(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CartaoEstado(estado: e),
        const SizedBox(height: 16),
        if (e.podeEnviar) ..._formulario(e),
        const SizedBox(height: 16),
        const _ComoAbrir(),
        if (widget.modoCadastro) ...[
          const SizedBox(height: 8),
          _fazerDepois() ?? const SizedBox.shrink(),
        ],
      ],
    );
  }

  Widget? _fazerDepois() {
    if (!widget.modoCadastro) return null;
    return TextButton(
      key: const Key('atividade-fazer-depois'),
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Text(
          'Fazer depois (a candidatura fica à espera do comprovativo)'),
    );
  }

  List<Widget> _formulario(AtividadeEstado e) => [
        TextField(
          key: const Key('atividade-nif'),
          controller: _nifCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: const InputDecoration(
            labelText: 'NIF (número de contribuinte)',
            helperText: 'O mesmo NIF da atividade aberta nas Finanças.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Comprovativo (foto ou PDF, até 10 MB)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!kIsWeb)
              OutlinedButton.icon(
                key: const Key('atividade-camara'),
                onPressed: _enviando ? null : () => _foto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tirar foto'),
              ),
            if (!kIsWeb)
              OutlinedButton.icon(
                key: const Key('atividade-galeria'),
                onPressed: _enviando ? null : () => _foto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Escolher da galeria'),
              ),
            OutlinedButton.icon(
              key: const Key('atividade-ficheiro'),
              onPressed: _enviando ? null : _ficheiro,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label:
                  const Text(kIsWeb ? 'Escolher foto ou PDF' : 'Escolher PDF'),
            ),
          ],
        ),
        if (_nomeFicheiro != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$_nomeFicheiro · ${((_bytes?.length ?? 0) / 1024).ceil()} KB',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: 12),
          Text(_aviso!,
              key: const Key('atividade-aviso'),
              style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('atividade-enviar'),
            onPressed: _enviando ? null : _enviar,
            child: _enviando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(e.status == AtividadeStatus.recusada
                    ? 'Enviar de novo'
                    : 'Enviar comprovativo'),
          ),
        ),
      ];
}

class _CartaoEstado extends StatelessWidget {
  const _CartaoEstado({required this.estado});
  final AtividadeEstado estado;

  @override
  Widget build(BuildContext context) {
    final (cor, icone) = switch (estado.status) {
      AtividadeStatus.aprovada => (AppColors.success, Icons.verified_outlined),
      AtividadeStatus.recusada => (AppColors.error, Icons.cancel_outlined),
      AtividadeStatus.emAnalise when estado.temDocumento => (
          AppColors.info,
          Icons.hourglass_top_outlined
        ),
      _ => (AppColors.warning, Icons.description_outlined),
    };
    return Container(
      key: const Key('atividade-estado'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estado: ${estado.rotulo}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(estado.explicacao),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComoAbrir extends StatelessWidget {
  const _ComoAbrir();

  @override
  Widget build(BuildContext context) {
    return const ExpansionTile(
      key: Key('atividade-como-abrir'),
      tilePadding: EdgeInsets.zero,
      title: Text('Ainda não tens atividade aberta? Vê como se faz'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '• É grátis online, no Portal das Finanças: entra com o NIF e a senha, '
              'vai a «Todos os Serviços» → «Início de Atividade» → «Entregar '
              'declaração».\n'
              '• Também podes ir a uma repartição de Finanças ou a uma Loja do '
              'Cidadão, com o documento de identificação e o NIF.\n'
              '• Depois, envia aqui a foto ou o PDF do comprovativo.\n'
              '• Dúvidas sobre o código da atividade? Pergunta no Suporte da app ou '
              'confirma na repartição de Finanças.',
            ),
          ),
        ),
      ],
    );
  }
}

class _Centro extends StatelessWidget {
  const _Centro(
      {required this.icone, required this.texto, this.botao, this.rodape});
  final IconData icone;
  final String texto;
  final Widget? botao;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (botao != null) ...[const SizedBox(height: 16), botao!],
            if (rodape != null) ...[const SizedBox(height: 8), rodape!],
          ],
        ),
      ),
    );
  }
}
