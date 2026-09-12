import '../../utils/io_compat.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/maps_config.dart';
import '../../services/place_autocomplete_service.dart';
import '../../services/provider_upload_service.dart';
import '../../stores/washer_store.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora.dart';

/// LAVAGEM AUTO — candidatura a lavador.
///
/// Copiado do `CleanerApplyScreen`, que está provado desde Julho: mesma ordem
/// de campos, mesmo tratamento de erro por fase, mesma exigência de foto e de
/// documento. As diferenças são as do ofício — carta de condução em vez de só
/// o cartão de cidadão, e a lista de material é a da lavagem.
///
/// Até 2026-08-29 este ecrã não existia. A categoria estava aberta ao público
/// e um lavador novo não tinha por onde se inscrever.
class WasherApplyScreen extends StatefulWidget {
  const WasherApplyScreen({super.key, this.prefill});

  /// MULTI-PAPEL: dados comuns (name/phone/email/nif/photo_url) vindos de outro
  /// papel que a pessoa já tenha, para não obrigar a reescrever tudo.
  final Map<String, dynamic>? prefill;

  @override
  State<WasherApplyScreen> createState() => _WasherApplyScreenState();
}

class _WasherApplyScreenState extends State<WasherApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double _radiusKm = 10;
  ll.LatLng? _baseCoords;

  XFile? _photo;
  XFile? _idDoc;
  XFile? _licenseDoc;
  bool _uploading = false;
  bool _isPicking = false;

  /// O lavador vai ao carro do cliente e leva tudo consigo. Se faltar material,
  /// o serviço não se faz — por isso confirma-se antes, não depois.
  static const _requiredMaterials = <String>[
    'Aspirador portátil',
    'Balde e luva de lavagem',
    'Champô auto e desengordurante',
    'Panos de microfibra',
    'Escova de jantes',
    'Rodo de silicone',
    'Depósito de água próprio',
  ];
  final Set<String> _materialsChecked = {};
  bool get _allMaterialsChecked =>
      _materialsChecked.length == _requiredMaterials.length;

  String _prefillPhotoUrl = '';
  bool get _fromOtherRole => widget.prefill != null;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'];
    if (name is String) _nameCtrl.text = name;

    final p = widget.prefill;
    if (p != null) {
      if ((p['name'] as String?)?.isNotEmpty == true) _nameCtrl.text = p['name'];
      if ((p['phone'] as String?)?.isNotEmpty == true) {
        _phoneCtrl.text = p['phone'];
      }
      if ((p['email'] as String?)?.isNotEmpty == true) {
        _emailCtrl.text = p['email'];
      }
      if ((p['nif'] as String?)?.isNotEmpty == true) _nifCtrl.text = p['nif'];
      _prefillPhotoUrl = (p['photo_url'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nifCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(void Function(XFile) onPicked) async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final x = await SafeImagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => onPicked(x));
    } finally {
      _isPicking = false;
    }
  }

  Future<ll.LatLng?> _resolveBaseCoords() async {
    if (_baseCoords != null) return _baseCoords;
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) return null;
    final svc = createPlaceAutocompleteService(googleApiKey);
    try {
      return await svc.geocodeAddress(addr);
    } catch (e) {
      debugPrint('WasherApply geocode fallback falhou => $e');
      return null;
    } finally {
      svc.dispose();
    }
  }

  Future<void> _submit() async {
    // Guarda de reentrada LOCAL (PADRAO_BORA.md 3.13) — nunca `store.busy`.
    if (_uploading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_photo == null && _prefillPhotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adiciona uma foto de perfil — os clientes entregam o '
              'carro a quem veem.')));
      return;
    }
    if (_idDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Anexa um documento de identificação (BI/CC).')));
      return;
    }
    if (_licenseDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Anexa a carta de condução — vais conduzir o carro do '
              'cliente.')));
      return;
    }
    if (!_allMaterialsChecked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Confirma que tens todo o material de lavagem.')));
      return;
    }
    final store = context.read<WasherStore>();
    setState(() => _uploading = true);
    // Marcador de fase: diz ONDE falhou (coords/uploads/apply).
    var stage = 'coords';
    try {
      final coords = await _resolveBaseCoords();
      if (!mounted) return;
      stage = 'uploads';
      final photoUrl = _photo != null
          ? await ProviderUploadService.uploadAvatar(_photo!)
          : _prefillPhotoUrl;
      final idPath = await ProviderUploadService.uploadDocument(
          _idDoc!, 'id_doc',
          bucket: ProviderUploadService.bucketLavador);
      final licPath = await ProviderUploadService.uploadDocument(
          _licenseDoc!, 'driving_license',
          bucket: ProviderUploadService.bucketLavador);
      if (!mounted) return;
      stage = 'apply';
      await store.apply(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        nif: _nifCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        baseAddress: _addressCtrl.text.trim(),
        baseLat: coords?.latitude,
        baseLng: coords?.longitude,
        serviceRadiusKm: _radiusKm,
        photoUrl: photoUrl ?? '',
        docs: {
          if (idPath != null) 'id_doc': idPath,
          if (licPath != null) 'driving_license': licPath,
          'materials_ok': true,
          'materials_list': _requiredMaterials,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Candidatura enviada! Vamos rever em breve. 💚')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      String friendly;
      if (msg.contains('application_already_exists')) {
        friendly = 'Já tens uma candidatura de lavagem.';
      } else if (msg.contains('washer_banned')) {
        friendly = 'A tua conta de lavador está bloqueada. Fala com o suporte.';
      } else if (msg.contains('name_required')) {
        friendly = 'Indica o teu nome completo.';
      } else if (msg.contains('phone_required')) {
        friendly = 'Indica um telemóvel válido (9+ dígitos).';
      } else if (msg.contains('not_authenticated') || msg.contains('42501')) {
        friendly = 'A tua sessão expirou. Volta a entrar e tenta de novo.';
      } else if (msg.contains('empty_file')) {
        friendly = 'Não foi possível ler a imagem do documento. '
            'Tira ou escolhe a foto de novo.';
      } else if (msg.contains('Duplicate') || msg.contains('already exists')) {
        friendly = 'Este documento já tinha sido enviado. Tenta com outra foto.';
      } else if (stage == 'uploads' ||
          msg.contains('StorageException') ||
          msg.contains('row-level security') ||
          msg.contains('Bucket') ||
          msg.contains('Unauthorized') ||
          msg.contains('storage')) {
        final detail =
            e is StorageException ? ' [${e.statusCode}: ${e.message}]' : '';
        friendly = 'Falha ao enviar a foto do documento$detail. '
            'Tenta escolher ou tirar a foto de novo.';
      } else {
        friendly = 'Não foi possível enviar a candidatura. Tenta de novo — '
            'se continuar, avisa o suporte.';
      }
      debugPrint('WasherApply submit FAILED stage=$stage error=$e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Lavar carros com o Bora'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Text(
              'Vais ter com o cliente, lavas o carro onde ele estiver e '
              'devolves. Trabalhas quando queres e recebes por lavagem.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            if (_fromOtherRole) ...[
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                    SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Já preenchemos os teus dados a partir do perfil que '
                        'já tens. Só falta o que é específico da lavagem.',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Center(
              child: GestureDetector(
                onTap: () => _pick((x) => _photo = x),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.primaryWash,
                  backgroundImage: _photo != null
                      ? boraLocalImage(_photo!.path)
                      : (_prefillPhotoUrl.isNotEmpty
                          ? NetworkImage(_prefillPhotoUrl)
                          : null),
                  child: (_photo == null && _prefillPhotoUrl.isEmpty)
                      ? const Icon(Icons.add_a_photo,
                          color: AppColors.primary, size: 28)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            const Center(
              child: Text('Foto de perfil *',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: Spacing.lg),
            _DocTile(
              label: 'Documento de identificação (BI/CC) *',
              picked: _idDoc != null,
              onTap: () => _pick((x) => _idDoc = x),
            ),
            const SizedBox(height: Spacing.md),
            _DocTile(
              label: 'Carta de condução *',
              picked: _licenseDoc != null,
              onTap: () => _pick((x) => _licenseDoc = x),
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nome completo *',
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Indica o teu nome.' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Telemóvel *',
                  prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) => (v ?? '').trim().length < 9
                  ? 'Indica um telemóvel válido.'
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _nifCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'NIF',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'Necessário para os recibos.'),
            ),
            const SizedBox(height: Spacing.md),
            AddressAutocompleteField(
              controller: _addressCtrl,
              labelText: 'Zona base (morada ou localidade)',
              prefixIcon: const Icon(Icons.home_outlined),
              onSelected: (address, coords) {
                setState(() => _baseCoords = coords);
              },
              onChanged: (_) {
                if (_baseCoords != null) setState(() => _baseCoords = null);
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 12),
              child: Text(
                'Escolhe uma sugestão para te mostrarmos lavagens perto de ti.',
                style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Raio de serviço: ${_radiusKm.round()} km',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Slider(
              value: _radiusKm,
              min: 5,
              max: 50,
              divisions: 9,
              activeColor: AppColors.primary,
              label: '${_radiusKm.round()} km',
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Apresentação (opcional)',
                hintText: 'Ex.: detalhe interior, polimento, 3 anos a lavar…',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const Text('Material obrigatório',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.xs),
            const Text(
              'Levas tudo contigo — o cliente não põe nada. Confirma que tens:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.xs),
            for (final m in _requiredMaterials)
              CheckboxListTile(
                value: _materialsChecked.contains(m),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _materialsChecked.add(m);
                  } else {
                    _materialsChecked.remove(m);
                  }
                }),
                title:
                    Text(m, style: const TextStyle(color: AppColors.textPrimary)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
              ),
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              label: _uploading ? 'A enviar…' : 'Enviar candidatura',
              icon: Icons.send,
              loading: _uploading,
              onPressed: _submit,
            ),
            const SizedBox(height: Spacing.md),
            const Text(
              'Depois de aprovada, define a tua disponibilidade semanal para '
              'começares a receber lavagens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.label,
    required this.picked,
    required this.onTap,
  });
  final String label;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: picked ? AppColors.primary : AppColors.divider,
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(picked ? Icons.check_circle : Icons.upload_file,
                color: picked ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                picked ? 'Documento anexado' : label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
            if (picked)
              const Text('Trocar',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600))
            else
              const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
