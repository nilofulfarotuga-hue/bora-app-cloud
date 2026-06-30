// FAVORES (errand) — Fase 3 UI Cliente
// Wizard 3 passos com rodapé sticky live (quote_order_pricing).
// UX 1–7: cards Normal/Expresso com tempos, paragem 1 linha, placeholder
// "Ex.: Vai à Farmácia Holon…", mensagem amigável forçar >€40, breakdown
// "ver detalhe", disclaimer receita-positiva (G1), resumo final com "~".
// Meta: a avó consegue pedir sem ajuda.
//
// 2026-06-21 — coords REAIS via autocomplete (sem placeholders fixos):
//   • Local do favor → BusinessAutocompleteField (RPC search_businesses)
//   • Entrega / paragem em casa → AddressAutocompleteField (Google)
//   • distância multi-segmento real (casa→favor→entrega) via MapsService
//   • guard de submissão + geocode fallback (texto livre) antes de submeter
//   • 8.4 atalhos de favores · 8.1 foto opcional "do que comprar"
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/maps_config.dart';
import '../services/location_service.dart';
import '../services/maps_service.dart';
import '../services/order_photo_upload_service.dart';
import '../services/payment_service.dart';
import '../services/place_autocomplete_service.dart';
import '../stores/cart_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/business_autocomplete_field.dart';
import 'payment_method_screen.dart';

enum _ErrandStep { what, where, when }

/// Dados para pré-preenchimento (N3 "Pedir de novo" no histórico).
class ErrandPrefill {
  const ErrandPrefill({
    required this.description,
    required this.location,
    this.hasPurchase = false,
    this.estimatedCents = 0,
    this.speed = 'normal',
    this.homeStop = false,
    this.homeStopReason,
  });

  final String description;
  final String location;
  final bool hasPurchase;
  final int estimatedCents;
  final String speed;
  final bool homeStop;
  final String? homeStopReason;
}

class ErrandFormScreen extends StatefulWidget {
  const ErrandFormScreen({super.key, this.prefill});

  /// N3 — pré-preenche o wizard a partir de um pedido anterior.
  final ErrandPrefill? prefill;

  @override
  State<ErrandFormScreen> createState() => _ErrandFormScreenState();
}

class _ErrandFormScreenState extends State<ErrandFormScreen> {
  _ErrandStep _step = _ErrandStep.what;
  final _descCtrl = TextEditingController();
  final _descFocus = FocusNode();
  final _estimateCtrl = TextEditingController();
  final _errandLocationCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _homeCtrl = TextEditingController();

  bool _hasPurchase = false;
  bool _homeStop = false;
  String _homeStopReason = 'cartao'; // receita | cartao | dinheiro | outro
  String _speed = 'normal'; // normal | express

  // Coordenadas REAIS — preenchidas pelo autocomplete ou geocode. NUNCA fixas.
  LatLng? _errandLocation;
  LatLng? _dropoff;
  LatLng? _home;

  // Distância real do percurso (soma dos segmentos casa→favor→entrega).
  double _routeDistanceKm = 0;

  // 8.1 — foto opcional do que comprar.
  File? _requestPhotoFile;
  String? _requestPhotoUrl;
  bool _uploadingPhoto = false;

  Map<String, dynamic>? _quote;
  bool _quoting = false;
  String? _geoError;

  final _payment = PaymentService();
  late final PlaceAutocompleteService _geocoder;

  static const _maxAdvanceCents = 4000; // €40 — força paragem-casa
  static const _maxCashCents = 4000; // limite cash global

  @override
  void initState() {
    super.initState();
    _geocoder = createPlaceAutocompleteService(googleApiKey);
    final p = widget.prefill;
    if (p != null) {
      _descCtrl.text = p.description;
      _errandLocationCtrl.text = p.location;
      _hasPurchase = p.hasPurchase;
      if (p.estimatedCents > 0) {
        _estimateCtrl.text = (p.estimatedCents / 100).toStringAsFixed(2);
      }
      _speed = p.speed;
      _homeStop = p.homeStop;
      if (p.homeStopReason != null) _homeStopReason = p.homeStopReason!;
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _descFocus.dispose();
    _estimateCtrl.dispose();
    _errandLocationCtrl.dispose();
    _dropoffCtrl.dispose();
    _homeCtrl.dispose();
    _geocoder.dispose();
    super.dispose();
  }

  int get _estimatedCents {
    final raw = _estimateCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw) ?? 0;
    return (v * 100).round();
  }

  bool get _forcedHomeStopByEstimate =>
      _hasPurchase && _estimatedCents > _maxAdvanceCents;

  bool get _homeActive => _homeStop || _forcedHomeStopByEstimate;

  // ── Distância multi-segmento + quote ────────────────────────────────────
  Future<void> _computeRouteDistance() async {
    final favor = _errandLocation;
    final drop = _dropoff;
    if (favor == null || drop == null) {
      _routeDistanceKm = 0;
      return;
    }
    final legs = <List<LatLng>>[];
    if (_homeActive && _home != null) {
      legs.add([_home!, favor]); // casa → local do favor
    }
    legs.add([favor, drop]); // local do favor → entrega
    double total = 0;
    for (final leg in legs) {
      final km = await MapsService.getDistanceKm(leg[0], leg[1]) ??
          const Distance().as(LengthUnit.Kilometer, leg[0], leg[1]);
      total += km;
    }
    _routeDistanceKm = total;
  }

  Future<void> _refreshQuote() async {
    if (_errandLocation == null || _dropoff == null || _routeDistanceKm <= 0) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _quoting = true);
    final input = <String, dynamic>{
      'service_type': 'errand',
      'distance_km': _routeDistanceKm,
      'errand_speed': _speed,
      'errand_home_stop': _homeActive,
      'errand_home_stop_reason': _homeActive ? _homeStopReason : null,
      'errand_has_purchase': _hasPurchase,
      'errand_estimated_purchase_cents': _estimatedCents,
      'errand_location_lat': _errandLocation!.latitude,
      'errand_location_lng': _errandLocation!.longitude,
      'dropoff_lat': _dropoff!.latitude,
      'dropoff_lng': _dropoff!.longitude,
      if (_homeActive && _home != null) ...{
        'pickup_lat': _home!.latitude,
        'pickup_lng': _home!.longitude,
      },
    };
    final q = await _payment.quoteOrder(input);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _quoting = false;
    });
  }

  Future<void> _recomputeDistanceAndQuote() async {
    await _computeRouteDistance();
    await _refreshQuote();
  }

  /// Passo 1 — só o estimado/compra afeta o quote (distância inalterada).
  /// setState garante que o footer re-avalia `_canProceed()` a cada tecla
  /// (descrição / valor estimado), sem depender de mexer no toggle.
  void _onWhatChanged() {
    setState(() {
      if (_forcedHomeStopByEstimate && !_homeStop) {
        _homeStop = true;
        _homeStopReason = 'dinheiro';
      }
    });
    if (_errandLocation != null && _dropoff != null) _refreshQuote();
  }

  // ── Coords (autocomplete) ───────────────────────────────────────────────
  void _onErrandLocationSelected(String name, LatLng coords) {
    setState(() {
      _errandLocation = coords;
      _geoError = null;
    });
    _recomputeDistanceAndQuote();
  }

  void _onDropoffSelected(String address, LatLng? coords) {
    if (coords == null) return;
    setState(() {
      _dropoff = coords;
      _geoError = null;
    });
    _recomputeDistanceAndQuote();
  }

  void _onHomeSelected(String address, LatLng? coords) {
    if (coords == null) return;
    setState(() {
      _home = coords;
      _geoError = null;
    });
    _recomputeDistanceAndQuote();
  }

  Future<void> _useMyLocationForHome() async {
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Não consegui obter a tua localização. Ativa o GPS ou escreve a morada.'),
      ));
      return;
    }
    setState(() {
      _home = loc;
      _homeCtrl.text = 'A obter morada…';
      _geoError = null;
    });
    final addr = await LocationService.reverseGeocode(loc, googleApiKey);
    if (!mounted) return;
    setState(() => _homeCtrl.text = addr ?? 'A minha localização atual');
    _recomputeDistanceAndQuote();
  }

  // ── Geocode fallback (texto livre) — guard de submissão ─────────────────
  Future<bool> _ensureCoords() async {
    setState(() => _geoError = null);
    if (_errandLocation == null) {
      final c = await _geocodeOrNull(_errandLocationCtrl.text);
      if (c == null) return _failGeo('o local do favor');
      _errandLocation = c;
    }
    if (_dropoff == null) {
      final c = await _geocodeOrNull(_dropoffCtrl.text);
      if (c == null) return _failGeo('a morada de entrega');
      _dropoff = c;
    }
    if (_homeActive && _home == null) {
      final c = await _geocodeOrNull(_homeCtrl.text);
      if (c == null) return _failGeo('a morada da paragem em casa');
      _home = c;
    }
    return true;
  }

  Future<LatLng?> _geocodeOrNull(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return await _geocoder.geocodeAddress(t);
    } catch (_) {
      return null;
    }
  }

  bool _failGeo(String what) {
    if (mounted) {
      setState(() => _geoError =
          'Não consegui localizar $what. Escolhe uma sugestão da lista.');
    }
    return false;
  }

  // ── 8.1 Foto opcional ───────────────────────────────────────────────────
  Future<void> _pickRequestPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    final x =
        await ImagePicker().pickImage(source: src, imageQuality: 70, maxWidth: 1200);
    if (x == null) return;
    final file = File(x.path);
    setState(() {
      _requestPhotoFile = file;
      _uploadingPhoto = true;
    });
    try {
      final url = await OrderPhotoUploadService.uploadOrderPhoto(
        photoFile: file,
        pathPrefix: 'errand_request',
      );
      if (!mounted) return;
      setState(() {
        _requestPhotoUrl = url;
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _requestPhotoFile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _removeRequestPhoto() {
    setState(() {
      _requestPhotoFile = null;
      _requestPhotoUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pedir um favor'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepHeader(current: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _stepBody(),
              ),
            ),
            _PriceFooter(
              quote: _quote,
              loading: _quoting,
              estimateApprox: _hasPurchase,
              onNext: _canProceed() ? _next : null,
              onBack: _step == _ErrandStep.what ? null : _back,
              nextLabel: _step == _ErrandStep.when
                  ? 'Continuar para pagamento'
                  : 'Próximo',
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case _ErrandStep.what:
        return _descCtrl.text.trim().isNotEmpty &&
            (!_hasPurchase || _estimatedCents > 0) &&
            !_uploadingPhoto;
      case _ErrandStep.where:
        // Texto livre permitido — geocodificado em _next. Exige texto em cada
        // campo obrigatório (e na paragem em casa, se ativa).
        final favorOk = _errandLocation != null ||
            _errandLocationCtrl.text.trim().isNotEmpty;
        final dropOk =
            _dropoff != null || _dropoffCtrl.text.trim().isNotEmpty;
        final homeOk = !_homeActive ||
            _home != null ||
            _homeCtrl.text.trim().isNotEmpty;
        return favorOk && dropOk && homeOk;
      case _ErrandStep.when:
        return _quote != null && !_quoting;
    }
  }

  void _next() {
    if (_step == _ErrandStep.what) {
      setState(() => _step = _ErrandStep.where);
    } else if (_step == _ErrandStep.where) {
      _advanceFromWhere();
    } else {
      _goToCheckout();
    }
  }

  Future<void> _advanceFromWhere() async {
    final ok = await _ensureCoords();
    if (!ok || !mounted) return;
    await _recomputeDistanceAndQuote();
    if (!mounted) return;
    setState(() => _step = _ErrandStep.when);
  }

  void _back() {
    if (_step == _ErrandStep.where) {
      setState(() => _step = _ErrandStep.what);
    } else if (_step == _ErrandStep.when) {
      setState(() => _step = _ErrandStep.where);
    }
  }

  Future<void> _goToCheckout() async {
    final quote = _quote;
    if (quote == null) return;
    // Defensivo: coords já resolvidas no passo where→when, mas nunca submeter
    // sem coords reais.
    if (_errandLocation == null || _dropoff == null || (_homeActive && _home == null)) {
      final ok = await _ensureCoords();
      if (!ok || !mounted) return;
    }
    // D4: cash > €40 com compra adiantada sem paragem-dinheiro = forçar paragem.
    final customerCents =
        ((quote['customer_total'] as num?)?.toDouble() ?? 0) * 100;
    if (_hasPurchase &&
        !(_homeStop && _homeStopReason == 'dinheiro') &&
        customerCents > _maxCashCents) {
      _showFriendlyCashDialog();
      return;
    }
    final cart = context.read<CartStore>();
    cart.configureErrandSession(
      description: _descCtrl.text.trim(),
      location: _errandLocationCtrl.text.trim(),
      locationCoords: _errandLocation!,
      dropoff: _dropoff!,
      home: _homeActive ? _home : null,
      homeStopReason: _homeActive ? _homeStopReason : null,
      speed: _speed,
      hasPurchase: _hasPurchase,
      estimatedCents: _estimatedCents,
      quote: quote,
      distanceKm: _routeDistanceKm,
      dropoffStreet: _dropoffCtrl.text.trim(),
      requestPhotoUrl: _requestPhotoUrl,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentMethodScreen()),
    );
  }

  void _showFriendlyCashDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compra acima de €40'),
        content: const Text(
            'Como a compra é mais de €40, eu passo primeiro em tua casa para levantar o dinheiro. Fica mais seguro para os dois 🙂\n\nVais pagar mais €2 pela paragem.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar a escolher'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _homeStop = true;
                _homeStopReason = 'dinheiro';
              });
              Navigator.pop(context);
              _recomputeDistanceAndQuote();
            },
            child: const Text('Ativar paragem em casa'),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case _ErrandStep.what:
        return _StepWhat(
          descCtrl: _descCtrl,
          descFocus: _descFocus,
          estimateCtrl: _estimateCtrl,
          hasPurchase: _hasPurchase,
          requestPhotoFile: _requestPhotoFile,
          uploadingPhoto: _uploadingPhoto,
          onShortcut: (text) {
            setState(() {
              _descCtrl.text = text;
              _descCtrl.selection =
                  TextSelection.collapsed(offset: text.length);
            });
            _descFocus.requestFocus();
          },
          onPickPhoto: _pickRequestPhoto,
          onRemovePhoto: _removeRequestPhoto,
          onHasPurchaseChanged: (v) {
            setState(() => _hasPurchase = v);
            _onWhatChanged();
          },
          onChanged: _onWhatChanged,
        );
      case _ErrandStep.where:
        return _StepWhere(
          errandLocationCtrl: _errandLocationCtrl,
          dropoffCtrl: _dropoffCtrl,
          homeCtrl: _homeCtrl,
          homeStop: _homeActive,
          forced: _forcedHomeStopByEstimate,
          homeStopReason: _homeStopReason,
          homeConfirmed: _home != null,
          geoError: _geoError,
          onHomeStopChanged: (v) {
            if (_forcedHomeStopByEstimate) return;
            setState(() => _homeStop = v);
            _recomputeDistanceAndQuote();
          },
          onReasonChanged: (r) {
            setState(() => _homeStopReason = r);
            _refreshQuote();
          },
          onErrandLocationSelected: _onErrandLocationSelected,
          onErrandLocationCleared: () {
            if (_errandLocation != null) setState(() => _errandLocation = null);
          },
          onDropoffSelected: _onDropoffSelected,
          onDropoffCleared: () {
            if (_dropoff != null) setState(() => _dropoff = null);
          },
          onHomeSelected: _onHomeSelected,
          onHomeCleared: () {
            if (_home != null) setState(() => _home = null);
          },
          onUseMyLocationForHome: _useMyLocationForHome,
        );
      case _ErrandStep.when:
        return _StepWhen(
          speed: _speed,
          quote: _quote,
          hasPurchase: _hasPurchase,
          homeStop: _homeActive,
          estimateCents: _estimatedCents,
          onSpeedChanged: (s) {
            setState(() => _speed = s);
            _refreshQuote();
          },
        );
    }
  }
}

// ── PASSO 1: O QUÊ ────────────────────────────────────────────────────────
class _StepWhat extends StatelessWidget {
  const _StepWhat({
    required this.descCtrl,
    required this.descFocus,
    required this.estimateCtrl,
    required this.hasPurchase,
    required this.requestPhotoFile,
    required this.uploadingPhoto,
    required this.onShortcut,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    required this.onHasPurchaseChanged,
    required this.onChanged,
  });

  final TextEditingController descCtrl;
  final FocusNode descFocus;
  final TextEditingController estimateCtrl;
  final bool hasPurchase;
  final File? requestPhotoFile;
  final bool uploadingPhoto;
  final ValueChanged<String> onShortcut;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;
  final ValueChanged<bool> onHasPurchaseChanged;
  final VoidCallback onChanged;

  static const _shortcuts = <(String, IconData, String)>[
    ('Farmácia', Icons.local_pharmacy_outlined, 'Vai à farmácia e compra '),
    (
      'Levantar encomenda',
      Icons.inventory_2_outlined,
      'Levanta a minha encomenda em '
    ),
    ('Pagar conta', Icons.receipt_long_outlined, 'Vai pagar esta conta: '),
    (
      'Buscar/entregar chaves',
      Icons.vpn_key_outlined,
      'Vai buscar/entregar as chaves em '
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('O que precisas?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        // 8.4 — atalhos de favores comuns (pré-preenchem a descrição).
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _shortcuts
              .map((s) => ActionChip(
                    avatar: Icon(s.$2, size: 18),
                    label: Text(s.$1),
                    onPressed: () => onShortcut(s.$3),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descCtrl,
          focusNode: descFocus,
          maxLines: 4,
          maxLength: 500,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText:
                'Ex.: Vai à Farmácia Holon na Sé e compra Ben-u-ron 1g',
            labelText: 'Descreve o favor',
          ),
        ),
        const SizedBox(height: 8),
        // 8.1 — foto opcional do que comprar.
        _RequestPhoto(
          file: requestPhotoFile,
          uploading: uploadingPhoto,
          onPick: onPickPhoto,
          onRemove: onRemovePhoto,
        ),
        const SizedBox(height: 16),
        // G5 — disclaimer + receita positiva (G1)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryWash,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Text(
            'Não é permitido pedir itens ilegais ou armas.\n'
            'Para medicamentos com receita, ativa a paragem em tua casa no próximo passo '
            'para o estafeta recolher a receita.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Este favor inclui uma compra?'),
          subtitle: const Text('Ex.: comprar algo na loja'),
          value: hasPurchase,
          onChanged: onHasPurchaseChanged,
        ),
        if (hasPurchase) ...[
          const SizedBox(height: 8),
          TextField(
            controller: estimateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Valor estimado da compra',
              hintText: 'Ex.: 15',
              prefixText: '€ ',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'É só uma estimativa — pagas o valor exato do talão.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _RequestPhoto extends StatelessWidget {
  const _RequestPhoto({
    required this.file,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final File? file;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return OutlinedButton.icon(
        onPressed: uploading ? null : onPick,
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Adicionar foto do que comprar (opcional)'),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file!, width: 64, height: 64, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            uploading ? 'A enviar foto…' : 'Foto adicionada ✓',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        if (uploading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...[
          TextButton(onPressed: onPick, child: const Text('Trocar')),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remover foto',
          ),
        ],
      ],
    );
  }
}

// ── PASSO 2: ONDE ─────────────────────────────────────────────────────────
class _StepWhere extends StatelessWidget {
  const _StepWhere({
    required this.errandLocationCtrl,
    required this.dropoffCtrl,
    required this.homeCtrl,
    required this.homeStop,
    required this.forced,
    required this.homeStopReason,
    required this.homeConfirmed,
    required this.geoError,
    required this.onHomeStopChanged,
    required this.onReasonChanged,
    required this.onErrandLocationSelected,
    required this.onErrandLocationCleared,
    required this.onDropoffSelected,
    required this.onDropoffCleared,
    required this.onHomeSelected,
    required this.onHomeCleared,
    required this.onUseMyLocationForHome,
  });

  final TextEditingController errandLocationCtrl;
  final TextEditingController dropoffCtrl;
  final TextEditingController homeCtrl;
  final bool homeStop;
  final bool forced;
  final String homeStopReason;
  final bool homeConfirmed;
  final String? geoError;
  final ValueChanged<bool> onHomeStopChanged;
  final ValueChanged<String> onReasonChanged;
  final void Function(String, LatLng) onErrandLocationSelected;
  final VoidCallback onErrandLocationCleared;
  final void Function(String, LatLng?) onDropoffSelected;
  final VoidCallback onDropoffCleared;
  final void Function(String, LatLng?) onHomeSelected;
  final VoidCallback onHomeCleared;
  final VoidCallback onUseMyLocationForHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Onde é o favor?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        BusinessAutocompleteField(
          controller: errandLocationCtrl,
          labelText: 'Local do favor',
          hintText: 'Ex.: Farmácia Holon ou uma morada',
          prefixIcon: const Icon(Icons.place_outlined),
          includeAddresses: true,
          onSelected: onErrandLocationSelected,
          onChanged: (_) => onErrandLocationCleared(),
        ),
        const SizedBox(height: 12),
        AddressAutocompleteField(
          controller: dropoffCtrl,
          labelText: 'Onde entregar',
          prefixIcon: const Icon(Icons.home_outlined),
          onSelected: onDropoffSelected,
          onChanged: (_) => onDropoffCleared(),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(forced
              ? 'Paragem em tua casa (obrigatória)'
              : 'Precisas que eu passe primeiro em tua casa?'),
          subtitle: Text(forced
              ? 'Como a compra é mais de €40, passo em tua casa para levantar o dinheiro. +€2.'
              : '(buscar receita, cartão ou dinheiro) — +€2'),
          value: homeStop,
          onChanged: forced ? null : onHomeStopChanged,
        ),
        if (homeStop) ...[
          const SizedBox(height: 8),
          const Text('Motivo:', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: const ['receita', 'cartao', 'dinheiro', 'outro']
                .map((r) => ChoiceChip(
                      label: Text(_reasonLabel(r)),
                      selected: homeStopReason == r,
                      onSelected: (_) => onReasonChanged(r),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          AddressAutocompleteField(
            controller: homeCtrl,
            labelText: 'Morada da paragem em casa',
            prefixIcon: const Icon(Icons.house_outlined),
            onSelected: onHomeSelected,
            onChanged: (_) => onHomeCleared(),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onUseMyLocationForHome,
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Usar a minha localização atual'),
          ),
          if (homeConfirmed)
            const Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 6),
                Text('Morada da paragem definida',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
        ],
        if (geoError != null) ...[
          const SizedBox(height: 12),
          Text(geoError!, style: const TextStyle(color: AppColors.error)),
        ],
      ],
    );
  }

  static String _reasonLabel(String r) {
    switch (r) {
      case 'receita':
        return 'Receita médica';
      case 'cartao':
        return 'Cartão';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return 'Outro';
    }
  }
}

// ── PASSO 3: QUANDO + PAGAR ───────────────────────────────────────────────
class _StepWhen extends StatelessWidget {
  const _StepWhen({
    required this.speed,
    required this.quote,
    required this.hasPurchase,
    required this.homeStop,
    required this.estimateCents,
    required this.onSpeedChanged,
  });

  final String speed;
  final Map<String, dynamic>? quote;
  final bool hasPurchase;
  final bool homeStop;
  final int estimateCents;
  final ValueChanged<String> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Quando precisas?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _SpeedCard(
          title: '🕐  Normal',
          subtitle: 'Até 3 horas',
          price: '€6',
          tagline: 'Escolhe Normal se não tens pressa.',
          selected: speed == 'normal',
          onTap: () => onSpeedChanged('normal'),
        ),
        const SizedBox(height: 10),
        _SpeedCard(
          title: '⚡  Expresso',
          subtitle: '45 a 60 minutos',
          price: '€10',
          tagline: 'Vai logo. Custa um pouco mais.',
          selected: speed == 'express',
          onTap: () => onSpeedChanged('express'),
        ),
        const SizedBox(height: 24),
        if (q != null) _Breakdown(quote: q, hasPurchase: hasPurchase),
      ],
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.tagline,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String price;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryWash : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(tagline, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Text(price,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.quote, required this.hasPurchase});
  final Map<String, dynamic> quote;
  final bool hasPurchase;

  @override
  Widget build(BuildContext context) {
    final base = (quote['base_fee'] as num?)?.toDouble() ?? 0;
    final home = (quote['home_stop_fee'] as num?)?.toDouble() ?? 0;
    final km = (quote['km_extra_fee'] as num?)?.toDouble() ?? 0;
    final purchase = (quote['purchase_estimate'] as num?)?.toDouble() ?? 0;
    final total = (quote['customer_total'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _Row(label: 'Favor', value: base),
          if (home > 0) _Row(label: 'Paragem em casa', value: home),
          if (km > 0) _Row(label: 'Km extra', value: km),
          if (hasPurchase) _Row(label: 'Compra (estimada)', value: purchase),
          const Divider(),
          _Row(
            label: hasPurchase ? 'Total ~' : 'Total',
            value: total,
            strong: true,
          ),
          if (hasPurchase) ...[
            const SizedBox(height: 4),
            const Text(
              'O valor da compra ajusta-se ao talão real.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false});
  final String label;
  final double value;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: strong ? 16 : 14,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

// ── Cabeçalho de progresso ────────────────────────────────────────────────
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});
  final _ErrandStep current;
  @override
  Widget build(BuildContext context) {
    final idx = _ErrandStep.values.indexOf(current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= idx;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Rodapé sticky com preço live ──────────────────────────────────────────
class _PriceFooter extends StatelessWidget {
  const _PriceFooter({
    required this.quote,
    required this.loading,
    required this.estimateApprox,
    required this.onNext,
    required this.onBack,
    required this.nextLabel,
  });

  final Map<String, dynamic>? quote;
  final bool loading;
  final bool estimateApprox;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final total = (quote?['customer_total'] as num?)?.toDouble();
    final priceLabel = total == null
        ? 'desde €6'
        : '${estimateApprox ? "~" : ""}€${total.toStringAsFixed(2)}';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.shadowNav,
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total', style: TextStyle(color: AppColors.textSecondary)),
              Row(children: [
                Text(priceLabel,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                if (loading) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ]),
            ],
          ),
          const Spacer(),
          if (onBack != null) ...[
            TextButton(onPressed: onBack, child: const Text('Voltar')),
            const SizedBox(width: 8),
          ],
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            child: Text(nextLabel),
          ),
        ],
      ),
    );
  }
}
