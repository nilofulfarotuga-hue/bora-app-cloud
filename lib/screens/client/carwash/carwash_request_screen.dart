import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../models/carwash_models.dart';
import '../../../services/carwash_upload_service.dart';
import '../../../services/location_service.dart';
import '../../../stores/carwash_store.dart';
import '../../../utils/safe_image_picker.dart';
import '../../../widgets/address_autocomplete_field.dart';
import 'carwash_tracking_screen.dart';

/// LAVAGEM AUTO — passo 2: onde está o carro, dados do carro, quando e pagamento.
///
/// REGRA DE 24/08, INVIOLÁVEL: a localização NUNCA trava o pedido.
/// O campo de escrever a morada está em primeiro plano; "Usar a minha
/// localização" é só um atalho opcional. GPS negado, desligado ou lento não
/// impede nada — o cliente escreve a morada e segue.
class CarwashRequestScreen extends StatefulWidget {
  const CarwashRequestScreen({
    super.key,
    required this.serviceType,
    required this.quote,
  });

  final CarwashServiceType serviceType;
  final CarwashQuote? quote;

  @override
  State<CarwashRequestScreen> createState() => _CarwashRequestScreenState();
}

class _CarwashRequestScreenState extends State<CarwashRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final _addressCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _carCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _pickupNotesCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _locating = false;

  // Quando
  static const _chips = ['Agora', 'Daqui a 30 min', 'Daqui a 1 h', 'Escolher dia e hora'];
  int _whenChip = 0;
  DateTime? _customWhen;

  String _payment = 'cash';

  XFile? _clientPhoto;
  bool _submitting = false;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _plateCtrl.dispose();
    _carCtrl.dispose();
    _colorCtrl.dispose();
    _pickupNotesCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── localização: atalho, nunca obrigação ───────────────────────────────────
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc == null) {
        _softInfo('Não conseguimos apanhar a localização. '
            'Escreva a morada aqui em baixo — funciona na mesma.');
        return;
      }
      final addr = await LocationService.reverseGeocode(loc, googleApiKey);
      if (!mounted) return;
      setState(() {
        _lat = loc.latitude;
        _lng = loc.longitude;
        if (addr != null && addr.trim().isNotEmpty) _addressCtrl.text = addr;
      });
    } catch (_) {
      _softInfo('Não conseguimos apanhar a localização. '
          'Escreva a morada aqui em baixo — funciona na mesma.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _softInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  DateTime _resolveWhen() {
    final now = DateTime.now();
    return switch (_whenChip) {
      1 => now.add(const Duration(minutes: 30)),
      2 => now.add(const Duration(hours: 1)),
      3 => _customWhen ?? now.add(const Duration(hours: 2)),
      _ => now,
    };
  }

  Future<void> _pickCustomWhen() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (t == null || !mounted) return;
    setState(() {
      _customWhen = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      _whenChip = 3;
    });
  }

  Future<void> _pickClientPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto agora'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    final f = await SafeImagePicker.pickImage(
      source: src,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (f != null && mounted) setState(() => _clientPhoto = f);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final store = context.read<CarwashStore>();
    try {
      final when = _resolveWhen();
      final booking = await store.createBooking(
        serviceType: widget.serviceType,
        plate: _plateCtrl.text.trim(),
        clientPhone: _phoneCtrl.text.trim(),
        whenMode: _whenChip == 0 ? 'now' : 'later',
        scheduledAt: when,
        addressStreet: _addressCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        paymentMethod: _payment,
        carMakeModel: _carCtrl.text.trim(),
        carColor: _colorCtrl.text.trim(),
        pickupNotes: _pickupNotesCtrl.text.trim(),
      );
      if (booking == null || !mounted) return;

      // Foto do cliente é opcional: se falhar o upload, o pedido segue na mesma.
      if (_clientPhoto != null) {
        try {
          final path = await CarwashUploadService.upload(
            _clientPhoto!,
            bookingId: booking.id,
            kind: 'client',
            tag: 'livre',
          );
          await store.attachClientPhoto(booking.id, path);
        } catch (_) {/* opcional — nunca estraga o pedido */}
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CarwashTrackingScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      _softInfo(_erroPt(e.toString()));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _erroPt(String raw) {
    if (raw.contains('out_of_service_area')) {
      return 'Essa morada está fora da nossa zona. De momento só fazemos '
          'recolhas até 8 km do centro da Guarda.';
    }
    if (raw.contains('carwash_disabled')) {
      return 'A Lavagem Auto está fechada de momento.';
    }
    if (raw.contains('card_mbway_not_enabled')) {
      return 'Cartão e MB WAY ainda não estão disponíveis nesta categoria. '
          'Escolha dinheiro.';
    }
    if (raw.contains('plate_required')) return 'Falta a matrícula.';
    if (raw.contains('phone_required')) return 'Falta o telemóvel.';
    return 'Não foi possível criar o pedido. Tente outra vez.';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CarwashStore>();
    final q = widget.quote;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.serviceType.label),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(Spacing.lg),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(
                    q == null
                        ? 'Pedir lavagem'
                        : 'Pedir lavagem · ${q.totalEur.toStringAsFixed(2)} €',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            // ── ONDE ESTÁ O CARRO ────────────────────────────────────────────
            const _Titulo('Onde está o carro'),
            AddressAutocompleteField(
              controller: _addressCtrl,
              labelText: 'Morada onde vamos buscar',
              prefixIcon: const Icon(Icons.place_outlined),
              onSelected: (address, ll.LatLng? coords) {
                setState(() {
                  _lat = coords?.latitude;
                  _lng = coords?.longitude;
                });
              },
              // Escrever à mão limpa as coordenadas antigas, mas nunca bloqueia.
              onChanged: (_) => setState(() {
                _lat = null;
                _lng = null;
              }),
              validator: (v) => (v == null || v.trim().length < 4)
                  ? 'Escreva a morada onde está o carro'
                  : null,
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _locating ? null : _useMyLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: const Text('Usar a minha localização'),
              ),
            ),

            const SizedBox(height: Spacing.lg),

            // ── DADOS DO CARRO ───────────────────────────────────────────────
            const _Titulo('O carro'),
            TextFormField(
              controller: _plateCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: const InputDecoration(
                labelText: 'Matrícula',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              validator: (v) => (v == null || v.trim().length < 4)
                  ? 'Escreva a matrícula'
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _carCtrl,
              decoration: const InputDecoration(
                labelText: 'Marca e modelo (opcional)',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _colorCtrl,
              decoration: const InputDecoration(
                labelText: 'Cor (opcional)',
                prefixIcon: Icon(Icons.palette_outlined),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _pickupNotesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Onde está e com quem fica a chave',
                hintText: 'Ex.: garagem do prédio, chave com o porteiro',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'O seu telemóvel',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) => (v == null || v.trim().length < 9)
                  ? 'Escreva o seu telemóvel'
                  : null,
            ),

            const SizedBox(height: Spacing.lg),

            // ── FOTO OPCIONAL ────────────────────────────────────────────────
            _FotoOpcional(
              foto: _clientPhoto,
              onPick: _pickClientPhoto,
              onClear: () => setState(() => _clientPhoto = null),
            ),

            const SizedBox(height: Spacing.lg),

            // ── QUANDO ───────────────────────────────────────────────────────
            const _Titulo('Quando'),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (var i = 0; i < _chips.length; i++)
                  ChoiceChip(
                    label: Text(i == 3 && _customWhen != null
                        ? '${_customWhen!.day}/${_customWhen!.month} às '
                            '${_customWhen!.hour.toString().padLeft(2, '0')}:'
                            '${_customWhen!.minute.toString().padLeft(2, '0')}'
                        : _chips[i]),
                    selected: _whenChip == i,
                    onSelected: (_) {
                      if (i == 3) {
                        _pickCustomWhen();
                      } else {
                        setState(() => _whenChip = i);
                      }
                    },
                  ),
              ],
            ),

            const SizedBox(height: Spacing.lg),

            // ── PAGAMENTO ────────────────────────────────────────────────────
            const _Titulo('Pagamento'),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'cash',
              groupValue: _payment,
              onChanged: (v) => setState(() => _payment = v!),
              title: const Text('Dinheiro'),
              subtitle: const Text('Paga ao lavador na entrega'),
              secondary: const Icon(Icons.payments_outlined),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'card',
              groupValue: _payment,
              onChanged: store.stripeEnabled
                  ? (v) => setState(() => _payment = v!)
                  : null,
              title: const Text('Cartão'),
              subtitle: Text(store.stripeEnabled
                  ? 'Pagamento seguro'
                  : 'Disponível brevemente'),
              secondary: const Icon(Icons.credit_card),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'mbway',
              groupValue: _payment,
              onChanged: store.stripeEnabled
                  ? (v) => setState(() => _payment = v!)
                  : null,
              title: const Text('MB WAY'),
              subtitle: Text(store.stripeEnabled
                  ? 'Recebe um pedido na app MB WAY'
                  : 'Disponível brevemente'),
              secondary: const Icon(Icons.phone_iphone),
            ),

            if (q != null) ...[
              const SizedBox(height: Spacing.lg),
              Container(
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Total a pagar',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text('${q.totalEur.toStringAsFixed(2)} €',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xs),
              const Text('Recolha e entrega incluídas. Sem taxas por cima.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );
}

/// Foto do carro — OPCIONAL. Convite leve, sem asterisco nem aviso legal.
/// Se o cliente não juntar, o pedido segue igual e não se volta a perguntar.
class _FotoOpcional extends StatelessWidget {
  const _FotoOpcional({
    required this.foto,
    required this.onPick,
    required this.onClear,
  });

  final XFile? foto;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_outlined,
                  color: AppColors.textSecondary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  foto == null
                      ? 'Quer juntar uma foto do carro?'
                      : 'Foto juntada',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              if (foto == null)
                TextButton(onPressed: onPick, child: const Text('Juntar'))
              else
                TextButton(onPressed: onClear, child: const Text('Remover')),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          const Text(
            'Se quiser, junte uma foto de como o carro está agora. '
            'É rápido e fica tudo claro entre nós desde o início.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Matrícula sempre em maiúsculas.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
