import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../screens/shared/comprovativo_atividade_screen.dart';
import '../screens/cleaner/cleaner_apply_screen.dart';
import '../screens/washer/washer_apply_screen.dart';
import '../services/driver_documentos.dart' show DocEmFalta;
import '../services/legal_fields_service.dart';
import '../services/prestador_documentos.dart';
import '../services/prestador_reenvio_service.dart';
import '../utils/safe_image_picker.dart';
import 'bora/bora.dart';
import 'bora_support_sheet.dart';
import 'legal_fields_section.dart';

/// "Candidatura em análise" da limpeza e da lavagem: o que falta, com um botão
/// por item para enviar ali mesmo — sem refazer o cadastro (missão
/// docs-reenvio-26-10; o mesmo que o estafeta tem desde 22/10).
/// A regra do que falta é a do painel do admin. Falha aberta: sem rede, não
/// mostra nada.
class PrestadorDocumentosEmFalta extends StatefulWidget {
  const PrestadorDocumentosEmFalta(
      {super.key, required this.papel, this.carregar});

  /// 'cleaner' (limpeza) ou 'washer' (lavagem).
  final String papel;

  /// Só para testes: substitui a leitura da base.
  @visibleForTesting
  final Future<EstadoReenvio?> Function()? carregar;

  @override
  State<PrestadorDocumentosEmFalta> createState() =>
      _PrestadorDocumentosEmFaltaState();
}

class _PrestadorDocumentosEmFaltaState
    extends State<PrestadorDocumentosEmFalta> {
  EstadoReenvio? _estado;
  bool _carregando = true;
  String? _aEnviar; // chave do item em curso (bloqueia o toque duplo)

  static const _enviado = 'Enviado. Vamos rever e avisamos-te.';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final e = await (widget.carregar?.call() ??
        PrestadorReenvioService.estado(widget.papel));
    if (!mounted) return;
    setState(() {
      _estado = e;
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
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Corre [acao] com o item marcado como "a enviar"; mensagem de sucesso ou
  /// a frase do erro (nunca calado) e recarrega a lista.
  Future<void> _comItem(DocEmFalta item, Future<void> Function() acao) async {
    setState(() => _aEnviar = item.chave);
    try {
      await acao();
      _msg(_enviado, ok: true);
      await _carregar();
    } on ReenvioException catch (e) {
      _msg(e.mensagem);
    } catch (e) {
      _msg(mensagemDeErroReenvio(e));
    } finally {
      if (mounted) setState(() => _aEnviar = null);
    }
  }

  Future<void> _enviarFoto(DocEmFalta item) async {
    if (_aEnviar != null) return;
    final origem = await _escolherOrigem();
    if (origem == null || !mounted) return;
    final XFile? ficheiro;
    try {
      ficheiro = await SafeImagePicker.pickImage(
        source: origem,
        maxWidth: 1400,
        imageQuality: 85,
      );
    } catch (_) {
      _msg('Não foi possível abrir a câmara ou a galeria. Tenta de novo.');
      return;
    }
    if (ficheiro == null || !mounted) return;
    final XFile escolhido = ficheiro;
    await _comItem(item,
        () => PrestadorReenvioService.enviarFoto(widget.papel, item, escolhido));
  }

  Future<void> _confirmarMateriais(DocEmFalta item) async {
    if (_aEnviar != null) return;
    final lista = widget.papel == 'cleaner'
        ? CleanerApplyScreen.materiaisObrigatorios
        : WasherApplyScreen.materiaisObrigatorios;
    final marcados = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Confirma os teus materiais'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.papel == 'cleaner'
                    ? 'Levas tudo isto contigo para cada limpeza?'
                    : 'Levas tudo isto contigo para cada lavagem?'),
                const SizedBox(height: Spacing.sm),
                for (final m in lista)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    value: marcados.contains(m),
                    title: Text(m),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        marcados.add(m);
                      } else {
                        marcados.remove(m);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: marcados.length == lista.length
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Confirmo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _comItem(item,
        () => PrestadorReenvioService.confirmarMateriais(widget.papel, lista));
  }

  Future<void> _preencherDadosFiscais() async {
    final linha = _estado?.linha;
    if (_aEnviar != null || linha == null) return;
    final gravou = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _DadosFiscaisScreen(papel: widget.papel, linha: linha),
    ));
    if (!mounted) return;
    if (gravou == true) _msg(_enviado, ok: true);
    await _carregar();
  }

  Future<void> _abrirComprovativo() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ComprovativoAtividadeScreen(),
    ));
    if (mounted) await _carregar();
  }

  void _abrirSuporte() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BoraSupportSheet(),
    );
  }

  Widget _botao(DocEmFalta item) {
    if (_aEnviar == item.chave) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final ocupado = _aEnviar != null;
    final como = comoEnviarPrestador(widget.papel, item.chave);
    if (como == ComoEnviar.suporte) {
      return OutlinedButton(
        onPressed: ocupado ? null : _abrirSuporte,
        child: const Text('Suporte'),
      );
    }
    final VoidCallback acao = switch (como) {
      ComoEnviar.foto => () => _enviarFoto(item),
      ComoEnviar.materiais => () => _confirmarMateriais(item),
      ComoEnviar.dadosFiscais => _preencherDadosFiscais,
      _ => _abrirComprovativo,
    };
    return FilledButton(
      onPressed: ocupado ? null : acao,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(como == ComoEnviar.dadosFiscais ? 'Preencher' : 'Enviar agora'),
    );
  }

  Widget _linha(DocEmFalta item) {
    final suporte =
        comoEnviarPrestador(widget.papel, item.chave) == ComoEnviar.suporte;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Falta: ${minusculaInicial(item.rotulo)}'
              '${suporte ? ' — envia pelo Suporte' : ''}',
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _botao(item),
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
    final falta = _estado?.falta;
    if (falta == null) return const SizedBox.shrink();
    if (falta.isEmpty) {
      return Container(
        width: double.infinity,
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
              child: Text('Recebemos tudo o que pedimos. Agora é só esperar '
                  'pela análise.'),
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
            'O que falta',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sem isto não conseguimos aprovar a tua candidatura. Envia aqui '
            'mesmo.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final item in falta) _linha(item),
        ],
      ),
    );
  }
}

/// Os dados legais e fiscais com o MESMO formulário e a mesma RPC do cadastro
/// (`provider_update_legal_fields`), já preenchidos com o que a pessoa deu.
class _DadosFiscaisScreen extends StatefulWidget {
  const _DadosFiscaisScreen({required this.papel, required this.linha});
  final String papel;
  final Map<String, dynamic> linha;

  @override
  State<_DadosFiscaisScreen> createState() => _DadosFiscaisScreenState();
}

class _DadosFiscaisScreenState extends State<_DadosFiscaisScreen> {
  late final LegalFieldsController _legal;
  bool _aGravar = false;

  @override
  void initState() {
    super.initState();
    final l = widget.linha;
    String t(String k) => l[k]?.toString().trim() ?? '';
    _legal = LegalFieldsController(
        birthDate: DateTime.tryParse(t('birth_date')));
    _legal.legalName.text = t('legal_name');
    _legal.nif.text = t('nif');
    _legal.address.text = t('address');
    _legal.iban.text = t('iban');
  }

  @override
  void dispose() {
    _legal.dispose();
    super.dispose();
  }

  void _msg(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _gravar() async {
    if (_aGravar) return;
    final falta = await _legal.validateAndReveal();
    if (falta != null) {
      _msg('Falta: $falta');
      return;
    }
    setState(() => _aGravar = true);
    try {
      await _legal.save(widget.papel);
      if (mounted) Navigator.pop(context, true);
    } on LegalFieldsException catch (e) {
      _msg(e.message);
    } catch (e) {
      _msg(LegalFieldsService.messageFor(e));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Dados fiscais'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            LegalFieldsSection(controller: _legal, enabled: !_aGravar),
            const SizedBox(height: Spacing.xl),
            BoraPrimaryButton(
              label: 'Gravar',
              icon: Icons.check,
              loading: _aGravar,
              onPressed: _aGravar ? null : _gravar,
            ),
          ],
        ),
      ),
    );
  }
}
