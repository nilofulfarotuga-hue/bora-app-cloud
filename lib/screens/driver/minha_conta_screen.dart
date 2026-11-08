import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_colors.dart';
import '../../services/driver_foto_upload.dart';
import '../../services/estafeta_documentos_service.dart';
import '../../services/minha_conta.dart';
import '../../services/minha_conta_service.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/driver_fiscal_card.dart';
import '../connect/connect_payments_screen.dart';
import '../shared/comprovativo_atividade_screen.dart';

/// "A MINHA CONTA" — o estafeta (e o motorista) vê tudo o que a conta precisa,
/// num semáforo: vermelho falta, amarelo em análise, verde em ordem. Cada
/// vermelho tem o botão para tratar ali mesmo; o servidor devolve o estado
/// novo e a linha fica verde sem reabrir a app.
///
/// Pedido do Danilo a 08/11/2026 (caso do Valdemir: aprovado, faltavam coisas
/// e não tinha onde as mandar). Os cartões do NIF e do recibo verde vivem aqui
/// e já não aparecem quando toca uma oferta. PT-PT, "tu".
class MinhaContaScreen extends StatefulWidget {
  const MinhaContaScreen({super.key, this.carregar, this.focar});

  /// Só para testes: troca o servidor.
  final Future<EstadoMinhaConta?> Function()? carregar;

  /// Chave do item a pôr em destaque (vem da folha do Online ou da barra).
  final String? focar;

  @override
  State<MinhaContaScreen> createState() => _MinhaContaScreenState();
}

class _MinhaContaScreenState extends State<MinhaContaScreen> {
  EstadoMinhaConta? _estado;
  bool _carregando = true;
  String? _aTratar; // chave em curso (bloqueia o toque duplo)

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final e =
        await (widget.carregar?.call() ?? MinhaContaService.carregar());
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

  /// Corre uma ação, mostra o resultado e volta a ler o servidor.
  Future<void> _tratar(ItemConta item, Future<bool> Function() acao) async {
    if (_aTratar != null) return;
    setState(() => _aTratar = item.chave);
    try {
      final gravou = await acao();
      if (gravou) {
        _msg('${item.rotulo}: recebido. Obrigado!', ok: true);
        MinhaContaService.versao.value++;
        await _carregar();
      }
    } on MinhaContaException catch (e) {
      _msg(e.mensagem);
    } on FotoEnvioException catch (e) {
      _msg(e.mensagem);
    } on EstafetaDocumentoException catch (e) {
      _msg(e.mensagem);
    } catch (_) {
      _msg('Não foi possível gravar. Verifica a ligação e tenta outra vez.');
    } finally {
      if (mounted) setState(() => _aTratar = null);
    }
  }

  // ── Ações ────────────────────────────────────────────────────────────────

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

  Future<bool> _enviarFoto(ItemConta item) async {
    final origem = await _escolherOrigem();
    if (origem == null || !mounted) return false;
    final XFile? ficheiro;
    try {
      ficheiro = await SafeImagePicker.pickImage(
          source: origem, maxWidth: 1200, imageQuality: 85);
    } catch (_) {
      throw const MinhaContaException(
          'Não foi possível abrir a câmara ou a galeria. Tenta de novo.');
    }
    if (ficheiro == null) return false;
    final bytes = await ficheiro.readAsBytes();
    final url = await DriverFotoUpload.enviar(
      bytes: bytes,
      kind: item.kindFoto!,
      rotulo: item.rotulo.toLowerCase(),
    );
    await MinhaContaService.gravarRegisto(item.chave, url);
    return true;
  }

  Future<String?> _pedirTexto(String titulo,
      {String? dica,
      TextInputType teclado = TextInputType.text,
      String? Function(String)? validar,
      TextCapitalization maiusculas = TextCapitalization.sentences}) async {
    final ctrl = TextEditingController();
    String? erro;
    final valor = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(titulo),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: teclado,
            textCapitalization: maiusculas,
            decoration: InputDecoration(
              hintText: dica,
              errorText: erro,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                final t = ctrl.text.trim();
                final e = t.isEmpty ? 'Escreve aqui primeiro.' : validar?.call(t);
                if (e != null) {
                  setD(() => erro = e);
                  return;
                }
                Navigator.pop(ctx, t);
              },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    return valor;
  }

  Future<bool> _escreverRegisto(ItemConta item) async {
    final v = await _pedirTexto(item.rotulo,
        dica: item.chave == 'license_plate' ? 'AA-00-AA' : null,
        maiusculas: TextCapitalization.characters);
    if (v == null) return false;
    await MinhaContaService.gravarRegisto(item.chave, v);
    return true;
  }

  Future<bool> _escreverMorada() async {
    final v = await _pedirTexto('Morada', dica: 'Rua, número, código postal');
    if (v == null) return false;
    await MinhaContaService.gravarLegal(morada: v);
    return true;
  }

  Future<bool> _escolherNascimento() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(hoje.year - 30, 1, 1),
      firstDate: DateTime(hoje.year - 90),
      lastDate: DateTime(hoje.year - 18, hoje.month, hoje.day),
      helpText: 'Data de nascimento',
    );
    if (d == null) return false;
    await MinhaContaService.gravarLegal(nascimento: d);
    return true;
  }

  Future<bool> _escreverIban() async {
    final v = await _pedirTexto(
      'IBAN para receberes',
      dica: 'PT50 0000 0000 0000 0000 0000 0',
      maiusculas: TextCapitalization.characters,
      validar: (t) => ibanPtValido(t)
          ? null
          : 'Confere o IBAN: PT seguido de 23 números.',
    );
    if (v == null) return false;
    await MinhaContaService.gravarLegal(iban: v);
    return true;
  }

  Future<bool> _confirmarFiscal() async {
    final r = await confirmarNifEAtividade(context);
    return r != null;
  }

  Future<bool> _abrirComprovativo() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ComprovativoAtividadeScreen(),
    ));
    await _carregar();
    return false; // o ecrã próprio já disse o resultado
  }

  Future<bool> _abrirStripe() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ConnectPaymentsScreen(connectRole: 'driver'),
    ));
    await _carregar();
    return false;
  }

  Future<bool> _comoPagar(ItemConta item) async {
    final cents = _estado?.dividaCents ?? 0;
    final pagou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Como pagar ${euros(cents)} à Bora',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                  'Envia por MB Way para o número da Bora. Depois carrega em '
                  '"Já paguei" e a nossa equipa confirma.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_iphone, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('MB Way: ${MinhaContaService.mbwayBora}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    IconButton(
                      tooltip: 'Copiar número',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: MinhaContaService.mbwayBora
                                .replaceAll(' ', '')));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Número copiado.')));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('minha_conta_ja_paguei'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check),
                  label: const Text('Já paguei'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (pagou != true) return false;
    await MinhaContaService.avisarQueJaPaguei(cents);
    _msg('Avisámos a equipa. Assim que confirmarmos o pagamento, isto fica '
        'verde.', ok: true);
    return false; // fica vermelho até o admin confirmar
  }

  /// O botão de cada linha (null = nada a fazer aqui).
  Widget? _botao(ItemConta item) {
    if (_aTratar == item.chave) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final ocupado = _aTratar != null;
    if (item.chave == 'stripe' && item.estado != EstadoItemConta.ok) {
      return _acao('Configurar', ocupado, () => _tratar(item, _abrirStripe));
    }
    if (item.estado != EstadoItemConta.falta) return null;
    if (item.eFoto) {
      return _acao('Enviar foto', ocupado,
          () => _tratar(item, () => _enviarFoto(item)),
          icone: Icons.camera_alt, cheio: true);
    }
    return switch (item.chave) {
      'document_number' || 'license_plate' => _acao('Escrever', ocupado,
          () => _tratar(item, () => _escreverRegisto(item))),
      'morada' => _acao('Escrever', ocupado, () => _tratar(item, _escreverMorada)),
      'nascimento' =>
        _acao('Escolher', ocupado, () => _tratar(item, _escolherNascimento)),
      'iban' => _acao('Escrever', ocupado, () => _tratar(item, _escreverIban)),
      'fiscal' =>
        _acao('Confirmar', ocupado, () => _tratar(item, _confirmarFiscal),
            cheio: true),
      'atividade' =>
        _acao('Enviar', ocupado, () => _tratar(item, _abrirComprovativo)),
      'divida' => _acao('Como pagar', ocupado,
          () => _tratar(item, () => _comoPagar(item)),
          cheio: true),
      _ => null,
    };
  }

  Widget _acao(String texto, bool ocupado, VoidCallback onTap,
      {IconData? icone, bool cheio = false}) {
    final cb = ocupado ? null : onTap;
    if (cheio) {
      return icone == null
          ? FilledButton(
              onPressed: cb,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(texto))
          : FilledButton.icon(
              onPressed: cb,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: Icon(icone, size: 18),
              label: Text(texto));
    }
    return OutlinedButton(onPressed: cb, child: Text(texto));
  }

  static (IconData, Color) _cor(EstadoItemConta e) => switch (e) {
        EstadoItemConta.ok => (Icons.check_circle, AppColors.success),
        EstadoItemConta.emAnalise => (Icons.hourglass_top, Colors.amber.shade800),
        EstadoItemConta.falta => (Icons.error, AppColors.error),
      };

  Widget _linha(ItemConta item) {
    final (icone, cor) = _cor(item.estado);
    final botao = _botao(item);
    final destaque = widget.focar == item.chave;
    final subtitulo = <String>{
      if (item.detalhe != null) item.detalhe!,
      if (item.bloqueiaOnline) 'Sem isto não podes ficar online.',
    }.join(' ');
    return Container(
      key: Key('minha_conta_item_${item.chave}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destaque ? cor : cor.withValues(alpha: 0.35),
          width: destaque ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icone, color: cor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.rotulo,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: item.emFalta && !item.opcional
                            ? AppColors.error
                            : AppColors.textPrimary)),
                if (subtitulo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitulo,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ),
              ],
            ),
          ),
          if (botao != null) ...[const SizedBox(width: 8), botao],
        ],
      ),
    );
  }

  Widget _cabecalho(EstadoMinhaConta e) {
    final falta = e.emFalta;
    final ok = falta.isEmpty;
    return Container(
      key: const Key('minha_conta_cabecalho'),
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ok
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.verified : Icons.assignment_late_outlined,
              color: ok ? AppColors.success : AppColors.error, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? 'Está tudo em ordem com a tua conta.'
                  : falta.length == 1
                      ? 'Falta tratar de 1 coisa. Toca no botão ao lado.'
                      : 'Faltam tratar ${falta.length} coisas. Toca no botão '
                          'ao lado de cada uma.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('A minha conta'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : e == null || e.itens.isEmpty
              ? _semResposta()
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _cabecalho(e),
                      for (final item in e.itens) ...[
                        _linha(item),
                        if (item.chave == 'recibo' && item.emFalta)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DriverReciboSecao(aoMarcar: () {
                              MinhaContaService.versao.value++;
                              _carregar();
                            }),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Para mudar alguma coisa que já está a verde (por exemplo '
                        'o IBAN), fala connosco no Suporte.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _semResposta() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Não conseguimos ler a tua conta agora. Verifica a ligação.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => _carregando = true);
                  _carregar();
                },
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
}
