import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/driver_model.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'driver_pending_screen.dart';

class DriverSignupScreen extends StatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  State<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends State<DriverSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Dados pessoais
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController(text: '+351');
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Documento
  String _documentType = 'Cartão Cidadão';
  final _documentNumberController = TextEditingController();

  // Veículo
  VehicleType _vehicleType = VehicleType.motorcycle;
  final _licensePlateController = TextEditingController();

  // Pagamento
  final _ibanController = TextEditingController();

  // Fotos
  XFile? _selfieFile;
  XFile? _documentPhotoFile;
  XFile? _vehiclePhotoFile;

  bool _isProcessing = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _documentNumberController.dispose();
    _licensePlateController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({
    required ImageSource source,
    required void Function(XFile) onPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null && mounted) setState(() => onPicked(picked));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao seleccionar imagem: $e')),
        );
      }
    }
  }

  void _showPhotoOptions(void Function(XFile) onPicked) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accent),
              title: const Text('Câmara'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(source: ImageSource.camera, onPicked: onPicked);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.accent),
              title: const Text('Galeria'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(source: ImageSource.gallery, onPicked: onPicked);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isValidIBAN(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    if (clean.length != 25) return false;
    if (!clean.startsWith('PT50')) return false;
    return RegExp(r'^\d{21}$').hasMatch(clean.substring(4));
  }

  Future<String?> _uploadPhoto(XFile file, String userId, String tag) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/$tag.$ext';
    final storage = Supabase.instance.client.storage;
    await storage.from('driver-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return storage.from('driver-documents').createSignedUrl(
          path,
          60 * 60 * 24 * 365, // 1 year
        );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selfieFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adiciona a tua selfie.')),
      );
      return;
    }
    if (_documentPhotoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adiciona a foto do documento.')),
      );
      return;
    }
    if (_vehicleType != VehicleType.bicycle && _vehiclePhotoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adiciona a foto do veículo.')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    FocusScope.of(context).unfocus();

    try {
      final supabase = Supabase.instance.client;
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final iban = _ibanController.text.replaceAll(' ', '').toUpperCase();
      final licensePlate = _vehicleType != VehicleType.bicycle
          ? _licensePlateController.text.trim().toUpperCase()
          : '';
      final consentAcceptedAt = DateTime.now().toUtc();

      // 1. Criar conta Supabase Auth
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'bora_role': 'driver',
          'bora_name': name,
          'bora_phone': phone,
          'bora_vehicle_type': _vehicleType.name,
          'bora_license_plate': licensePlate,
          'bora_consent_accepted_at': consentAcceptedAt.toIso8601String(),
          'bora_consent_version': AuthStore.currentConsentVersion,
        },
      );

      final user = res.user;
      if (user == null) throw Exception('Não foi possível criar a conta.');

      if (res.session == null) {
        await supabase.auth
            .signInWithPassword(email: email, password: password);
      }

      final userId = user.id;

      // 2. Upload das fotos
      final selfieUrl = await _uploadPhoto(_selfieFile!, userId, 'selfie');
      final docUrl =
          await _uploadPhoto(_documentPhotoFile!, userId, 'document');
      String? vehicleUrl;
      if (_vehiclePhotoFile != null) {
        vehicleUrl = await _uploadPhoto(_vehiclePhotoFile!, userId, 'vehicle');
      }

      // 3. Upsert row na tabela drivers com todos os campos
      await supabase.from('drivers').upsert({
        'id': userId,
        'user_id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'vehicle_type': _vehicleType.name,
        'license_plate': licensePlate,
        'is_online': false,
        'lat': 38.7223,
        'lng': -9.1393,
        'consent_accepted_at': consentAcceptedAt.toIso8601String(),
        'consent_version': AuthStore.currentConsentVersion,
        'photo_url': selfieUrl,
        'document_type': _documentType,
        'document_number': _documentNumberController.text.trim(),
        'document_photo_url': docUrl,
        if (vehicleUrl != null) 'vehicle_photo_url': vehicleUrl,
        'iban': iban,
        'approval_status': 'pending',
      });

      if (!mounted) return;

      // 4. Limpar sessão auth (evita que RootNavigator salte para DriverHomeScreen)
      context.read<AuthStore>().logout();

      // 5. Ir para ecrã pendente
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Candidatura de Estafeta',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── SECÇÃO 1: Dados Pessoais ───────────────────────────────
              _SectionCard(
                title: 'Dados Pessoais',
                child: Column(
                  children: [
                    // Selfie circular 120px
                    Center(
                      child: GestureDetector(
                        onTap: () => _showPhotoOptions((f) => _selfieFile = f),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surface,
                            border: Border.all(
                              color: _selfieFile != null
                                  ? AppColors.primary
                                  : AppColors.divider,
                              width: 2,
                            ),
                          ),
                          child: _selfieFile != null
                              ? ClipOval(
                                  child: Image.file(
                                    File(_selfieFile!.path),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt,
                                        size: 32, color: AppColors.accent),
                                    SizedBox(height: 4),
                                    Text(
                                      'Selfie',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Obrigatório'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Obrigatório';
                        if (!v.contains('@')) return 'Email inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) => (v == null ||
                              v.replaceAll(RegExp(r'\D'), '').length < 9)
                          ? 'Número inválido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Palavra-passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Obrigatório';
                        if (v.length < 6) return 'Mínimo 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirmar palavra-passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) => v != _passwordController.text
                          ? 'Palavras-passe não coincidem'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── SECÇÃO 2: Documento ────────────────────────────────────
              _SectionCard(
                title: 'Documento de Identificação',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _documentType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de documento',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: const [
                        'Cartão Cidadão',
                        'Bilhete de Identidade',
                        'Passaporte',
                        'Título de Residência',
                      ]
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _documentType = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _documentNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Número do documento',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Obrigatório'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _PhotoPicker(
                      label: 'Foto do documento',
                      file: _documentPhotoFile,
                      onTap: () =>
                          _showPhotoOptions((f) => _documentPhotoFile = f),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── SECÇÃO 3: Veículo ──────────────────────────────────────
              _SectionCard(
                title: 'Veículo',
                child: Column(
                  children: [
                    SegmentedButton<VehicleType>(
                      segments: const [
                        ButtonSegment(
                          value: VehicleType.motorcycle,
                          label: Text('Moto'),
                          icon: Icon(Icons.two_wheeler),
                        ),
                        ButtonSegment(
                          value: VehicleType.car,
                          label: Text('Carro'),
                          icon: Icon(Icons.directions_car),
                        ),
                        ButtonSegment(
                          value: VehicleType.bicycle,
                          label: Text('Bicicleta'),
                          icon: Icon(Icons.pedal_bike),
                        ),
                      ],
                      selected: {_vehicleType},
                      onSelectionChanged: (s) => setState(() {
                        _vehicleType = s.first;
                        if (_vehicleType == VehicleType.bicycle) {
                          _licensePlateController.clear();
                        }
                      }),
                    ),
                    if (_vehicleType != VehicleType.bicycle) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _licensePlateController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Matrícula',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                        ),
                        validator: (v) {
                          if (_vehicleType == VehicleType.bicycle) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Obrigatório'
                              : null;
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    _PhotoPicker(
                      label: 'Foto do veículo',
                      file: _vehiclePhotoFile,
                      onTap: () =>
                          _showPhotoOptions((f) => _vehiclePhotoFile = f),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── SECÇÃO 4: Pagamento ────────────────────────────────────
              _SectionCard(
                title: 'Dados de Pagamento',
                child: TextFormField(
                  controller: _ibanController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'IBAN Português',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                    hintText: 'PT50XXXXXXXXXXXXXXXXXXXXX',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório';
                    if (!_isValidIBAN(v)) {
                      return 'IBAN inválido (PT50 + 21 dígitos = 25 caracteres)';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16),

              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: _isProcessing
                    ? null
                    : (v) => setState(() => _acceptedTerms = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.accent,
                title: const TermsLinkText(),
              ),
              const SizedBox(height: 12),

              BoraPrimaryButton(
                label: 'Submeter Candidatura',
                loading: _isProcessing,
                color: AppColors.primary,
                onPressed: _acceptedTerms ? _submit : null,
              ),
              const SizedBox(height: Spacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.label,
    required this.file,
    required this.onTap,
  });

  final String label;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file != null ? AppColors.primary : AppColors.divider,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: file != null
            ? Image.file(File(file!.path),
                fit: BoxFit.cover, width: double.infinity)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.accent, size: 28),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
      ),
    );
  }
}
