import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_colors.dart';
import '../screens/shared/comprovativo_atividade_screen.dart';
import '../services/driver_documentos.dart';
import '../services/driver_foto_upload.dart';
import '../services/estafeta_documentos_service.dart';
import '../utils/safe_image_picker.dart';

/// "Conta em análise": a lista do que falta, com um botão por item para tirar
/// e enviar a foto (ou escrever o número) ali mesmo — sem refazer o cadastro.
/// A regra do que falta é a mesma do painel do admin
/// ([documentosEmFaltaEstafeta]). Falha aberta: sem rede, não mostra nada.
class EstafetaDocumentosEmFalta extends StatefulWidget {
  const EstafetaDocumentosEmFalta({super.key, this.mostrarTudoEmOrdem = true});

  /// false no motorista TVDE: o "Recebemos todos os teus documentos" não pode
  /// aparecer ao lado da lista do que falta da conformidade TVDE.
  final bool mostrarTudoEmOrdem;

  @override
  State<EstafetaDocumentosEmFalta> createState() =>
      _EstafetaDocumentosEmFaltaState();
}

class _EstafetaDocumentosEmFaltaState extends State<EstafetaDocumentosEmFalta> {
  List<DocEmFalta>? _falta;
  bool _carregando = true;
  String? _aEnviar; // chave do item em curso (bloqueia o toque duplo)

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final f = await EstafetaDocumentosService.emFalta();
    if (!mounted) return;
    setState(() {
      _falta = f;
      _carregando = false;
    });
  }

  void _msg(String texto, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: ok ? AppColors.success : null,
      duration: Duration(seconds: ok ? 3 : 6),
    ));
  }

  Future<ImageSource?> _escolherOrigem() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accent),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accent),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviarFoto(DocEmFalta item) async {
    if (_aEnviar != null) return;
    final origem = await _escolherOrigem();
    if (origem == null || !mounted) return;
    final XFile? ficheiro;
    try {
      ficheiro = await SafeImagePicker.pickImage(
        source: origem,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (_) {
      _msg('Não foi possível abrir a câmara ou a galeria. Tenta de novo.');
      return;
    }
    if (ficheiro == null || !mounted) return;
    setState(() => _aEnviar = item.chave);
    try {
      final bytes = await ficheiro.readAsBytes();
      final url = await DriverFotoUpload.enviar(
        bytes: bytes,
        kind: item.kindFoto!,
        rotulo: item.rotulo.toLowerCase(),
      );
      await EstafetaDocumentosService.gravar(item.chave, url);
      _msg('${item.rotulo}: enviada. Obrigado!', ok: true);
      await _carregar();
    } on FotoEnvioException catch (e) {
      _msg(e.mensagem);
    } on EstafetaDocumentoException catch (e) {
      _msg(e.mensagem);
    } catch (_) {
      _msg('Não foi possível enviar. Verifica a ligação e tenta outra vez.');
    } finally {
      if (mounted) setState(() => _aEnviar = null);
    }
  }

  Future<void> _escreverTexto(DocEmFalta item) async {
    if (_aEnviar != null) return;
    final ctrl = TextEditingController();
    final valor = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.rotulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: item.chave == 'license_plate' ? 'AA-00-AA' : null,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (valor == null || valor.isEmpty || !mounted) return;
    setState(() => _aEnviar = item.chave);
    try {
      await EstafetaDocumentosService.gravar(item.chave, valor);
      _msg('${item.rotulo}: enviado. Obrigado!', ok: true);
      await _carregar();
    } on EstafetaDocumentoException catch (e) {
      _msg(e.mensagem);
    } finally {
      if (mounted) setState(() => _aEnviar = null);
    }
  }

  Future<void> _abrirComprovativo() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ComprovativoAtividadeScreen(),
    ));
    if (mounted) await _carregar();
  }

  Widget? _botao(DocEmFalta item) {
    final ocupado = _aEnviar != null;
    if (_aEnviar == item.chave) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (item.eFoto) {
      return FilledButton.icon(
        onPressed: ocupado ? null : () => _enviarFoto(item),
        icon: const Icon(Icons.camera_alt, size: 18),
        label: const Text('Enviar foto'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      );
    }
    if (item.chave == 'document_number' || item.chave == 'license_plate') {
      return OutlinedButton(
        onPressed: ocupado ? null : () => _escreverTexto(item),
        child: const Text('Escrever'),
      );
    }
    if (item.chave == 'atividade') {
      return OutlinedButton(
        onPressed: ocupado ? null : _abrirComprovativo,
        child: const Text('Enviar'),
      );
    }
    return null; // IBAN: pelo Suporte
  }

  Widget _linha(DocEmFalta item) {
    final botao = _botao(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.chave == 'iban'
                  ? '${item.rotulo} — fala connosco no Suporte'
                  : item.rotulo,
              style: const TextStyle(
                  color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
          if (botao != null) botao,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final falta = _falta;
    if (falta == null) return const SizedBox.shrink();
    if (falta.isEmpty) {
      if (!widget.mostrarTudoEmOrdem) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 10),
            Expanded(
              child: Text('Recebemos todos os teus documentos. Agora é só '
                  'esperar pela análise.'),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Falta enviar',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Sem isto não conseguimos aprovar a tua conta. Envia aqui mesmo.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final item in falta) _linha(item),
        ],
      ),
    );
  }
}
