// Enviar uma receita (ou um pedido especial) à farmácia — missão farmacias-2026-11-11.
// Receita: foto OU número + código de acesso; morada; nota; autorização lida e assinada com o dedo.
// Pedido especial ("Não encontra o produto? Peça aqui"): o que procura + foto opcional; sem assinatura.
// Quando falta alguma coisa: rola até lá e diz em palavras (PADRAO_BORA 1.2).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/auto_address.dart';
import '../../services/prescricao_service.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora_bottom_action_bar.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/farmacia/assinatura_dedo.dart';
import 'prescricao_estado_screen.dart';

class PrescricaoEnviarScreen extends StatefulWidget {
  const PrescricaoEnviarScreen({
    super.key,
    required this.restaurantId,
    required this.farmaciaNome,
    this.tipo = PrescricaoTipo.receita,
    this.repetirDe,
    this.service,
  });

  final String restaurantId;
  final String farmaciaNome;
  final PrescricaoTipo tipo;
  final PedidoPrescricao? repetirDe;
  final PrescricaoService? service;

  @override
  State<PrescricaoEnviarScreen> createState() => _PrescricaoEnviarScreenState();
}

/// "Não encontra o produto? Peça aqui".
class PedidoLivreScreen extends StatelessWidget {
  const PedidoLivreScreen({super.key, required this.restaurantId, required this.farmaciaNome});
  final String restaurantId;
  final String farmaciaNome;

  @override
  Widget build(BuildContext context) => PrescricaoEnviarScreen(
        restaurantId: restaurantId,
        farmaciaNome: farmaciaNome,
        tipo: PrescricaoTipo.pedidoLivre,
      );
}

class _PrescricaoEnviarScreenState extends State<PrescricaoEnviarScreen> {
  late final PrescricaoService _svc = widget.service ?? PrescricaoService();
  final _scroll = ScrollController();
  final _numero = TextEditingController();
  final _acesso = TextEditingController();
  final _opcao = TextEditingController();
  final _descricao = TextEditingController();
  final _morada = TextEditingController();
  final _nota = TextEditingController();
  final _assinatura = AssinaturaController();

  final _kReceita = GlobalKey();
  final _kDescricao = GlobalKey();
  final _kMorada = GlobalKey();
  final _kAutorizacao = GlobalKey();

  bool _porCodigos = false;
  Uint8List? _foto;
  String _fotoExt = 'jpg';
  String _fotoTipo = 'image/jpeg';
  double? _lat;
  double? _lng;
  bool _moradaTocada = false;
  bool _autorizo = false;
  bool _enviando = false;
  String? _erro;
  PrescricaoConsentimento? _cons;

  /// 17/11/2026: moradas guardadas da conta (com coordenadas), como no checkout.
  List<({String morada, double lat, double lng})> _guardadas = const [];

  bool get _eReceita => widget.tipo == PrescricaoTipo.receita;

  @override
  void initState() {
    super.initState();
    final r = widget.repetirDe;
    if (r != null) {
      _morada.text = r.morada ?? '';
      _lat = r.lat;
      _lng = r.lng;
      _nota.text = r.nota ?? '';
      _descricao.text = r.descricao ?? '';
      _moradaTocada = _morada.text.isNotEmpty;
    }
    _carregarMorada();
    _carregarConsentimento();
    _carregarGuardadas();
  }

  Future<void> _carregarGuardadas() async {
    final g = await _svc.moradasGuardadas();
    if (mounted && g.isNotEmpty) setState(() => _guardadas = g);
  }

  void _usarMorada(String morada, double? lat, double? lng) {
    setState(() {
      _morada.text = morada;
      _lat = lat;
      _lng = lng;
      _moradaTocada = true;
      _erro = null;
    });
  }

  /// app-15-11: se falhar, volta a tentar quando a pessoa carrega em Enviar
  /// (antes ficava "a carregar" para sempre e nunca dava para enviar).
  Future<String?> _carregarConsentimento() async {
    try {
      final c = await _svc.consentimento(widget.restaurantId);
      if (mounted) setState(() => _cons = c);
      return null;
    } catch (e) {
      return PrescricaoService.mensagemDe(e);
    }
  }

  Future<void> _carregarMorada() async {
    if (_moradaTocada) return;
    try {
      final m = await AutoAddress.descobrir();
      if (!mounted || m == null || _moradaTocada || _morada.text.trim().isNotEmpty) return;
      setState(() {
        _morada.text = m.morada;
        _lat = m.coords?.latitude;
        _lng = m.coords?.longitude;
      });
    } catch (_) {
      // GPS negado/sem sinal: o campo fica para escrever. Nunca trava.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_numero, _acesso, _opcao, _descricao, _morada, _nota]) {
      c.dispose();
    }
    _assinatura.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto(ImageSource fonte) async {
    try {
      final x = await SafeImagePicker.pickImage(source: fonte, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final nome = x.name.toLowerCase();
      setState(() {
        _foto = bytes;
        if (nome.endsWith('.png')) {
          _fotoExt = 'png';
          _fotoTipo = 'image/png';
        } else if (nome.endsWith('.webp')) {
          _fotoExt = 'webp';
          _fotoTipo = 'image/webp';
        } else {
          _fotoExt = 'jpg';
          _fotoTipo = 'image/jpeg';
        }
        _erro = null;
      });
    } catch (_) {
      _mostrarErro('Não foi possível abrir a câmara. Tente pela galeria.', null);
    }
  }

  void _mostrarErro(String texto, GlobalKey? alvo) {
    setState(() => _erro = texto);
    final ctx = alvo?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    // Validação na ordem do ecrã: o primeiro que falta é o que se mostra.
    if (_eReceita) {
      final temCodigos = _numero.text.trim().isNotEmpty && _acesso.text.trim().isNotEmpty;
      if (_porCodigos ? !temCodigos : _foto == null) {
        return _mostrarErro(
            _porCodigos ? 'Falta o número da receita ou o código de acesso.' : 'Falta a foto da receita.',
            _kReceita);
      }
    } else if (_descricao.text.trim().isEmpty) {
      return _mostrarErro('Escreva o que procura.', _kDescricao);
    }
    if (_morada.text.trim().isEmpty) {
      return _mostrarErro('Falta a morada de entrega.', _kMorada);
    }
    // 17/11/2026: sem coordenadas o servidor recusa no fim (FALTA_LOCALIZACAO), depois da
    // foto e da assinatura. Diz-se já, no campo da morada.
    if (_lat == null || _lng == null) {
      return _mostrarErro('Escolha a morada numa das sugestões (ou uma morada guardada) para o estafeta a encontrar no mapa.', _kMorada);
    }
    // Farmácia fechada: o servidor recusa; avisa-se antes de subir fotos.
    final fechada = _cons?.avisoFechada;
    if (fechada != null) {
      return _mostrarErro(fechada, null);
    }
    if (_eReceita) {
      if (_cons == null) {
        final erro = await _carregarConsentimento();
        if (_cons == null) {
          return _mostrarErro(erro ?? 'A carregar a autorização. Tente outra vez daqui a nada.', _kAutorizacao);
        }
      }
      if (!_autorizo) {
        return _mostrarErro('Falta marcar "Li e autorizo".', _kAutorizacao);
      }
      if (_assinatura.vazia) {
        return _mostrarErro('Falta a sua assinatura.', _kAutorizacao);
      }
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      String? fotoPath;
      String? assinaturaPath;
      if (_foto != null && (!_eReceita || !_porCodigos)) {
        fotoPath = await _svc.subirFicheiro(
          bytes: _foto!,
          sufixo: _eReceita ? 'receita' : 'pedido',
          extensao: _fotoExt,
          contentType: _fotoTipo,
        );
      }
      if (_eReceita) {
        final png = await _assinatura.exportarPng();
        if (png == null) throw PrescricaoErro('Falta a sua assinatura.');
        assinaturaPath = await _svc.subirFicheiro(
          bytes: png,
          sufixo: 'assinatura',
          extensao: 'png',
          contentType: 'image/png',
        );
      }
      final id = await _svc.criar(
        restaurantId: widget.restaurantId,
        tipo: widget.tipo,
        receitaFotoPath: _eReceita ? fotoPath : null,
        receitaNumero: _eReceita && _porCodigos ? _numero.text : null,
        receitaCodigoAcesso: _eReceita && _porCodigos ? _acesso.text : null,
        receitaCodigoOpcao: _eReceita && _porCodigos ? _opcao.text : null,
        descricao: _eReceita ? null : _descricao.text,
        pedidoFotoPath: _eReceita ? null : fotoPath,
        morada: _morada.text,
        lat: _lat,
        lng: _lng,
        nota: _nota.text,
        assinaturaPath: assinaturaPath,
        consentimentoVersao: _eReceita ? _cons?.versao : null,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PrescricaoEstadoScreen(prescricaoId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarErro(PrescricaoService.mensagemDe(e), null);
    }
  }

  InputDecoration _deco(String rotulo, {String? ajuda}) => InputDecoration(
        labelText: rotulo,
        helperText: ajuda,
        helperMaxLines: 2,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );

  Widget _escolhaReceita() {
    Widget opcao(bool codigos, IconData icone, String texto) {
      final sel = _porCodigos == codigos;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _porCodigos = codigos),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.primaryWash : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? AppColors.primary : AppColors.dividerStrong, width: sel ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icone, color: sel ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 6),
              Text(texto, textAlign: TextAlign.center, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      opcao(false, Icons.photo_camera_outlined, 'Foto da receita'),
      const SizedBox(width: 10),
      opcao(true, Icons.pin_outlined, 'Tenho o número e os códigos'),
    ]);
  }

  Widget _blocoFoto({required String vazio}) {
    if (_foto != null) {
      return Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_foto!, height: 200, width: double.infinity, fit: BoxFit.cover),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Tirar a foto',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _foto = null),
            ),
          ),
        ),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerStrong),
      ),
      child: Column(children: [
        Text(vazio, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: () => _escolherFoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Tirar foto'),
          ),
          OutlinedButton.icon(
            onPressed: () => _escolherFoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Escolher da galeria'),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _eReceita ? 'Tenho receita' : 'Pedir à farmácia';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(titulo)),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 17/11/2026: farmácia fechada diz-se logo à entrada, não no fim.
          if (_cons?.avisoFechada != null)
            Container(
              key: const Key('prescricao_farmacia_fechada'),
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(children: [
                const Icon(Icons.schedule, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_cons!.avisoFechada!,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.35)),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.local_pharmacy_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _eReceita
                      ? 'A ${widget.farmaciaNome} vê a receita e diz-lhe se tem os medicamentos e quanto custam. '
                          'Só paga depois de confirmar.'
                      : 'Diga o que procura. A ${widget.farmaciaNome} confirma se tem e o preço. '
                          'Só paga depois de confirmar.',
                  style: const TextStyle(color: AppColors.textPrimary, height: 1.35),
                ),
              ),
            ]),
          ),
          if (_eReceita) ...[
            _titulo('A sua receita'),
            KeyedSubtree(
              key: _kReceita,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _escolhaReceita(),
                const SizedBox(height: 12),
                if (!_porCodigos)
                  _blocoFoto(vazio: 'Tire uma foto nítida da receita (papel ou ecrã do telemóvel).')
                else ...[
                  TextField(
                    controller: _numero,
                    keyboardType: TextInputType.number,
                    decoration: _deco('Número da receita'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _acesso,
                    keyboardType: TextInputType.number,
                    decoration: _deco('Código de acesso e dispensa'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _opcao,
                    keyboardType: TextInputType.number,
                    decoration: _deco('Código de direito de opção (se tiver)'),
                  ),
                ],
              ]),
            ),
          ] else ...[
            _titulo('O que procura?'),
            KeyedSubtree(
              key: _kDescricao,
              child: TextField(
                controller: _descricao,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: _deco('Nome do produto, marca, tamanho…'),
              ),
            ),
            _titulo('Foto (opcional)'),
            _blocoFoto(vazio: 'Se tiver a caixa ou uma foto do produto, ajuda a farmácia.'),
          ],
          _titulo('Onde entregamos'),
          KeyedSubtree(
            key: _kMorada,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // 17/11/2026: o mesmo campo de moradas dos Favores (sugestões com coordenadas;
              // a morada escrita procura-se no mapa ao sair do campo). Antes era texto livre e,
              // ao escrever, perdia as coordenadas → o servidor recusava com FALTA_LOCALIZACAO.
              AddressAutocompleteField(
                key: const Key('prescricao_morada'),
                controller: _morada,
                exigirCoordenadas: true,
                labelText: 'Morada',
                prefixIcon: const Icon(Icons.location_on_outlined),
                helperText: _lat == null
                    ? 'Escolha uma sugestão para o estafeta a encontrar no mapa.'
                    : 'Preenchida sozinha quando possível. Pode mudar.',
                onChanged: (_) {
                  _moradaTocada = true;
                  if (_lat != null || _lng != null) {
                    setState(() {
                      _lat = null;
                      _lng = null;
                    });
                  }
                },
                onSelected: (m, c) => _usarMorada(m, c?.latitude, c?.longitude),
              ),
              if (_guardadas.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Moradas guardadas', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final g in _guardadas)
                    ActionChip(
                      avatar: const Icon(Icons.home_outlined, size: 18),
                      label: Text(g.morada.length > 38 ? '${g.morada.substring(0, 38)}…' : g.morada),
                      onPressed: () => _usarMorada(g.morada, g.lat, g.lng),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nota,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: _deco('Nota para a farmácia (opcional)'),
          ),
          if (_eReceita) ...[
            _titulo('Autorização'),
            KeyedSubtree(
              key: _kAutorizacao,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    _cons?.texto ?? 'A carregar…',
                    style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
                  ),
                ),
                CheckboxListTile(
                  value: _autorizo,
                  onChanged: (v) => setState(() => _autorizo = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  title: const Text('Li e autorizo'),
                ),
                AssinaturaDedo(controller: _assinatura),
              ]),
            ),
          ],
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_erro!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      bottomNavigationBar: BoraBottomActionBar(
        color: Colors.white,
        children: [
          BoraPrimaryButton(
            label: 'Enviar à farmácia',
            icon: Icons.send_outlined,
            loading: _enviando,
            onPressed: _enviando ? null : _enviar,
          ),
        ],
      ),
    );
  }
}
