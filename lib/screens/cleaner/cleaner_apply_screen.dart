import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/cleaner_upload_service.dart';
import '../../stores/cleaner_store.dart';
import '../../widgets/bora/bora.dart';

/// LIMPEZA — candidatura a profissional de limpeza (cleaner_apply).
/// A aprovação é feita pelo admin no painel (paridade F5).
class CleanerApplyScreen extends StatefulWidget {
  const CleanerApplyScreen({super.key});

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

  final _picker = ImagePicker();
  XFile? _photo;
  XFile? _idDoc;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'];
    if (name is String) _nameCtrl.text = name;
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
    final x = await _picker.pickImage(
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
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_photo == null) {
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
    try {
      // Uploads primeiro (foto pública + doc privado), depois a candidatura.
      final photoUrl = await CleanerUploadService.uploadAvatar(_photo!);
      final idPath = await CleanerUploadService.uploadDocument(_idDoc!, 'id_doc');
      if (!mounted) return;
      await store.apply(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        nif: _nifCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        baseAddress: _addressCtrl.text.trim(),
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
      String friendly = 'Não foi possível enviar a candidatura.';
      if (msg.contains('application_already_exists')) {
        friendly = 'Já tens uma candidatura ativa.';
      } else if (msg.contains('phone_required')) {
        friendly = 'Indica um telefone válido.';
      } else if (msg.contains('name_required')) {
        friendly = 'Indica o teu nome completo.';
      }
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
            const SizedBox(height: Spacing.lg),
            Center(
              child: GestureDetector(
                onTap: () => _pick(true),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.primaryWash,
                  backgroundImage:
                      _photo != null ? FileImage(File(_photo!.path)) : null,
                  child: _photo == null
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
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                  labelText: 'Zona base (morada ou localidade)',
                  prefixIcon: Icon(Icons.home_outlined),
                  helperText:
                      'Usada para te mostrar limpezas perto de ti.'),
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
