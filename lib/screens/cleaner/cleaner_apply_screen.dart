import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/maps_config.dart';
import '../../services/cleaner_upload_service.dart';
import '../../services/place_autocomplete_service.dart';
import '../../stores/cleaner_store.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora.dart';

/// LIMPEZA — candidatura a profissional de limpeza (cleaner_apply).
/// A aprovação é feita pelo admin no painel (paridade F5).
class CleanerApplyScreen extends StatefulWidget {
  const CleanerApplyScreen({super.key, this.prefill});

  /// MULTI-PAPEL: dados comuns (name/phone/email/nif/photo_url) vindos do papel
  /// de estafeta/motorista, para não obrigar a reescrever tudo. Ver
  /// `RolesService.mySummary().driverProfile`.
  final Map<String, dynamic>? prefill;

  @override
  State<CleanerApplyScreen> createState() => _CleanerApplyScreenState();
}

class _CleanerApplyScreenState extends State<CleanerApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double _radiusKm = 10;
  ll.LatLng? _baseCoords; // geocoding da zona base (matching por distância)

  XFile? _photo;
  XFile? _idDoc;
  bool _uploading = false;
  bool _isPicking = false;

  /// Foto já existente no outro papel (estafeta) — evita re-upload obrigatório.
  String _prefillPhotoUrl = '';
  bool get _fromOtherRole => widget.prefill != null;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'];
    if (name is String) _nameCtrl.text = name;

    // MULTI-PAPEL: pré-preencher a partir do papel de estafeta, se veio de lá.
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

  Future<void> _pick(bool isPhoto) async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final x = await SafeImagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() {
        if (isPhoto) {
          _photo = x;
        } else {
          _idDoc = x;
        }
      });
    } finally {
      _isPicking = false;
    }
  }

  /// Geocodifica a zona base reutilizando o MESMO serviço das outras moradas
  /// da app (Places/Geocoding). Se a profissional escolheu uma sugestão já
  /// temos coords; senão tentamos geocodificar o texto escrito. null é
  /// aceitável — o backend aceita e o admin pode ajustar depois.
  Future<ll.LatLng?> _resolveBaseCoords() async {
    if (_baseCoords != null) return _baseCoords;
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) return null;
    final svc = createPlaceAutocompleteService(googleApiKey);
    try {
      return await svc.geocodeAddress(addr);
    } catch (e) {
      debugPrint('CleanerApply geocode fallback falhou => $e');
      return null;
    } finally {
      svc.dispose();
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_photo == null && _prefillPhotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adiciona uma foto de perfil — os clientes escolhem '
              'pela foto.')));
      return;
    }
    if (_idDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Anexa um documento de identificação (BI/CC).')));
      return;
    }
    final store = context.read<CleanerStore>();
    setState(() => _uploading = true);
    // Marcador de fase: diz ONDE falhou (coords/uploads/apply) — para a
    // mensagem específica e para o log de diagnóstico.
    var stage = 'coords';
    try {
      final coords = await _resolveBaseCoords();
      if (!mounted) return;
      stage = 'uploads';
      // Uploads primeiro (foto pública + doc privado), depois a candidatura.
      // MULTI-PAPEL: se não escolheu nova foto, reutiliza a do papel de estafeta.
      final photoUrl = _photo != null
          ? await CleanerUploadService.uploadAvatar(_photo!)
          : _prefillPhotoUrl;
      final idPath = await CleanerUploadService.uploadDocument(_idDoc!, 'id_doc');
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
        docs: {if (idPath != null) 'id_doc': idPath},
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
      // PASSO 3: nunca só o genérico — mensagem específica conforme a causa.
      String friendly;
      if (msg.contains('application_already_exists')) {
        friendly = 'Já tens uma candidatura de limpeza.';
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
        // Mostra a causa REAL do Storage (statusCode + mensagem) — o toast
        // genérico escondia o erro e deixou-nos às cegas em 3 correções.
        final detail =
            e is StorageException ? ' [${e.statusCode}: ${e.message}]' : '';
        friendly = 'Falha ao enviar a foto do documento$detail. '
            'Tenta escolher ou tirar a foto de novo.';
      } else {
        friendly = 'Não foi possível enviar a candidatura. Tenta de novo — '
            'se continuar, avisa o suporte.';
      }
      debugPrint('CleanerApply submit FAILED stage=$stage error=$e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleanerStore>();
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Ser profissional de limpeza'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Text(
              'Trabalha quando queres, recebe 85% do valor de cada limpeza '
              'e constrói a tua carteira de clientes.',
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
                        'Já preenchemos os teus dados a partir do teu perfil de '
                        'estafeta. Só falta o que é específico da limpeza.',
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
                onTap: () => _pick(true),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.primaryWash,
                  backgroundImage: _photo != null
                      ? FileImage(File(_photo!.path)) as ImageProvider
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
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: Spacing.lg),
            _DocTile(
              label: 'Documento de identificação (BI/CC) *',
              picked: _idDoc != null,
              onTap: () => _pick(false),
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
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined)),
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
                // Editou à mão → invalida coords até nova seleção/geocode.
                if (_baseCoords != null) setState(() => _baseCoords = null);
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 12),
              child: Text(
                'Escolhe uma sugestão para te mostrarmos limpezas perto de ti.',
                style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Raio de serviço: ${_radiusKm.round()} km',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
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
                hintText:
                    'Ex.: 5 anos de experiência, cuidadosa com animais…',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              label: _uploading ? 'A enviar…' : 'Enviar candidatura',
              icon: Icons.send,
              loading: store.busy || _uploading,
              onPressed: _submit,
            ),
            const SizedBox(height: Spacing.md),
            const Text(
              'Depois de aprovada, define a tua disponibilidade semanal '
              'para começares a receber limpezas.',
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
