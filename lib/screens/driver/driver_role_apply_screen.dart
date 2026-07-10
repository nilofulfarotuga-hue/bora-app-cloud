import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/safe_image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora.dart';

/// MULTI-PAPEL — candidatura a estafeta/motorista para um utilizador JÁ
/// autenticado (tipicamente uma profissional de limpeza a adicionar o 2.º
/// papel). Não cria conta nova: chama `driver_register_or_update` (auth.uid,
/// approval_status='pending'). Reaproveita nome/telefone via [prefill].
class DriverRoleApplyScreen extends StatefulWidget {
  const DriverRoleApplyScreen({super.key, this.prefill});

  final Map<String, dynamic>? prefill; // name/phone/email/nif/photo_url

  @override
  State<DriverRoleApplyScreen> createState() => _DriverRoleApplyScreenState();
}

class _DriverRoleApplyScreenState extends State<DriverRoleApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();

  // Valores aceites por drivers.vehicle_type.
  static const _vehicles = {
    'motorcycle': 'Mota / Scooter',
    'car': 'Carro (entregas)',
    'carro_passageiros': 'Carro (viagens / TVDE)',
  };
  String _vehicleType = 'motorcycle';

  XFile? _idDoc;
  XFile? _selfie;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _nameCtrl.text = (p['name'] as String?) ?? '';
      _phoneCtrl.text = (p['phone'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _plateCtrl.dispose();
    _ibanCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isDoc) async {
    final x = await SafeImagePicker.pickImage(
        source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
    if (x == null) return;
    setState(() {
      if (isDoc) {
        _idDoc = x;
      } else {
        _selfie = x;
      }
    });
  }

  Future<String?> _upload(XFile file, String tag) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final bytes = await file.readAsBytes();
    final path = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage.from('driver-documents').uploadBinary(
          path,
          bytes,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_idDoc == null || _selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Anexa o documento de identificação e uma selfie.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final docPath = await _upload(_idDoc!, 'id_doc');
      final selfiePath = await _upload(_selfie!, 'selfie');
      final res = await Supabase.instance.client.rpc(
        'driver_register_or_update',
        params: {
          'p_name': _nameCtrl.text.trim(),
          'p_phone': _phoneCtrl.text.trim(),
          'p_vehicle_type': _vehicleType,
          'p_license_plate': _plateCtrl.text.trim(),
          'p_document_type': 'Cartão Cidadão',
          'p_document_photo_url': docPath,
          'p_registration_selfie_url': selfiePath,
          'p_iban': _ibanCtrl.text.trim().isEmpty ? null : _ibanCtrl.text.trim(),
          'p_nif': (widget.prefill?['nif'] as String?),
        },
      );
      final ok = res is Map && res['success'] == true;
      if (!mounted) return;
      if (!ok) {
        final reason = res is Map ? res['reason'] : null;
        throw Exception(reason ?? 'erro');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Candidatura a estafeta enviada! Vamos rever em '
              'breve. 💚')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não foi possível enviar: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Ser estafeta / motorista'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Text(
              'Faz entregas e viagens quando quiseres — com a mesma conta. '
              'Só precisamos dos dados do teu veículo e documentos.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            if (widget.prefill != null) ...[
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Reaproveitámos o teu nome e telefone do perfil de '
                      'limpeza.',
                      style:
                          TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _nameCtrl,
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
            DropdownButtonFormField<String>(
              initialValue: _vehicleType,
              decoration: const InputDecoration(
                  labelText: 'Veículo',
                  prefixIcon: Icon(Icons.two_wheeler_outlined)),
              items: [
                for (final e in _vehicles.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _vehicleType = v ?? 'motorcycle'),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _plateCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Matrícula *',
                  prefixIcon: Icon(Icons.pin_outlined)),
              validator: (v) =>
                  (v ?? '').trim().length < 4 ? 'Indica a matrícula.' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _ibanCtrl,
              decoration: const InputDecoration(
                  labelText: 'IBAN (para pagamentos)',
                  prefixIcon: Icon(Icons.account_balance_outlined)),
            ),
            const SizedBox(height: Spacing.lg),
            _DocPicker(
              label: 'Documento de identificação (CC) *',
              picked: _idDoc != null,
              onTap: () => _pick(true),
            ),
            const SizedBox(height: Spacing.md),
            _DocPicker(
              label: 'Selfie de verificação *',
              picked: _selfie != null,
              onTap: () => _pick(false),
              preview: _selfie,
            ),
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              label: _busy ? 'A enviar…' : 'Enviar candidatura',
              icon: Icons.send,
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocPicker extends StatelessWidget {
  const _DocPicker({
    required this.label,
    required this.picked,
    required this.onTap,
    this.preview,
  });
  final String label;
  final bool picked;
  final VoidCallback onTap;
  final XFile? preview;

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
            if (preview != null && picked)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(preview!.path),
                    width: 36, height: 36, fit: BoxFit.cover),
              )
            else
              Icon(picked ? Icons.check_circle : Icons.upload_file,
                  color: picked ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(picked ? 'Anexado' : label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
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
