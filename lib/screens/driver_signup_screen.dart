import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../models/driver_model.dart';
import '../widgets/address_autocomplete_field.dart';
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

  // Step 1: Dados pessoais
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+351');
  final _addressController = TextEditingController();
  final _nifController = TextEditingController();

  // Step 2: Documentos
  String _documentType = 'Cartão Cidadão';
  final _documentNumberController = TextEditingController();

  // Step 3: Conta + Pagamento
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  VehicleType _vehicleType = VehicleType.motorcycle;
  final _licensePlateController = TextEditingController();
  final _ibanController = TextEditingController();
  final _mbwayPhoneController = TextEditingController();

  // Fotos
  XFile? _selfieFile;
  XFile? _documentPhotoFile;
  XFile? _vehicleDocFile;
  XFile? _vehiclePhotoFile;

  bool _isProcessing = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  int _currentStep = 0;

  final _imagePicker = ImagePicker();

  static const _kDraftKey = 'bora_app.signup_draft.driver';

  @override
  void initState() {
    super.initState();
    _recoverLostImage();
    _restoreDraft();
  }

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
    _addressController.dispose();
    _nifController.dispose();
    _mbwayPhoneController.dispose();
    super.dispose();
  }

  Future<void> _recoverLostImage() async {
    final lost = await _imagePicker.retrieveLostData();
    if (lost.isEmpty || !mounted) return;
    final file = lost.file;
    if (file == null) return;
    setState(() {
      if (_selfieFile == null) {
        _selfieFile = file;
      } else if (_documentPhotoFile == null) {
        _documentPhotoFile = file;
      } else if (_vehicleDocFile == null) {
        _vehicleDocFile = file;
      } else {
        _vehiclePhotoFile = file;
      }
    });
  }

  void _saveDraft() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('$_kDraftKey.name', _nameController.text);
      prefs.setString('$_kDraftKey.email', _emailController.text);
      prefs.setString('$_kDraftKey.phone', _phoneController.text);
      prefs.setString('$_kDraftKey.address', _addressController.text);
      prefs.setString('$_kDraftKey.nif', _nifController.text);
      prefs.setString('$_kDraftKey.docType', _documentType);
      prefs.setString('$_kDraftKey.docNumber', _documentNumberController.text);
      prefs.setString('$_kDraftKey.vehicleType', _vehicleType.name);
      prefs.setString('$_kDraftKey.plate', _licensePlateController.text);
      prefs.setString('$_kDraftKey.iban', _ibanController.text);
      prefs.setString('$_kDraftKey.mbway', _mbwayPhoneController.text);
    });
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('$_kDraftKey.name');
    if (name == null || !mounted) return;
    setState(() {
      if (name.isNotEmpty) _nameController.text = name;
      final email = prefs.getString('$_kDraftKey.email') ?? '';
      if (email.isNotEmpty) _emailController.text = email;
      final phone = prefs.getString('$_kDraftKey.phone') ?? '';
      if (phone.isNotEmpty) _phoneController.text = phone;
      final address = prefs.getString('$_kDraftKey.address') ?? '';
      if (address.isNotEmpty) _addressController.text = address;
      final nif = prefs.getString('$_kDraftKey.nif') ?? '';
      if (nif.isNotEmpty) _nifController.text = nif;
      final docType = prefs.getString('$_kDraftKey.docType');
      if (docType != null) _documentType = docType;
      final docNumber = prefs.getString('$_kDraftKey.docNumber') ?? '';
      if (docNumber.isNotEmpty) _documentNumberController.text = docNumber;
      final vehicleTypeName = prefs.getString('$_kDraftKey.vehicleType');
      if (vehicleTypeName != null) {
        try {
          _vehicleType =
              VehicleType.values.firstWhere((v) => v.name == vehicleTypeName);
        } catch (_) {}
      }
      final plate = prefs.getString('$_kDraftKey.plate') ?? '';
      if (plate.isNotEmpty) _licensePlateController.text = plate;
      final iban = prefs.getString('$_kDraftKey.iban') ?? '';
      if (iban.isNotEmpty) _ibanController.text = iban;
      final mbway = prefs.getString('$_kDraftKey.mbway') ?? '';
      if (mbway.isNotEmpty) _mbwayPhoneController.text = mbway;
    });
  }

  void _clearDraft() {
    SharedPreferences.getInstance().then((prefs) {
      for (final key in [
        'name', 'email', 'phone', 'address', 'nif',
        'docType', 'docNumber', 'vehicleType', 'plate', 'iban', 'mbway',
      ]) {
        prefs.remove('$_kDraftKey.$key');
      }
    });
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

  Future<String?> _uploadPhoto(XFile file, String userId, String tag) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : 'jpg';
    final response = await Supabase.instance.client.functions.invoke(
      'upload-driver-document',
      body: {
        'kind': tag,
        'fileBase64': base64Encode(bytes),
        'contentType': 'image/$ext',
      },
    );
    if (response.status != 200 || response.data is! Map) {
      throw Exception(
          'upload-driver-document HTTP ${response.status}: ${response.data}');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true) {
      throw Exception('Upload falhou: ${data['error'] ?? 'unknown'}');
    }
    return (data['signed_url'] ?? data['url'] ?? data['path']) as String?;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aceita os termos para continuar.')),
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
      final address = _addressController.text.trim();
      final nif = _nifController.text.trim();
      final iban = _ibanController.text.replaceAll(' ', '').toUpperCase();
      final mbwayPhone = _mbwayPhoneController.text.trim();
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

      // 2. Upload das fotos (apenas as que foram preenchidas)
      String? selfieUrl;
      if (_selfieFile != null) {
        selfieUrl = await _uploadPhoto(_selfieFile!, userId, 'selfie');
      }
      String? docUrl;
      if (_documentPhotoFile != null) {
        docUrl = await _uploadPhoto(_documentPhotoFile!, userId, 'document');
      }
      String? vehicleDocUrl;
      if (_vehicleDocFile != null) {
        vehicleDocUrl =
            await _uploadPhoto(_vehicleDocFile!, userId, 'vehicle_doc');
      }
      String? vehicleUrl;
      if (_vehiclePhotoFile != null) {
        vehicleUrl = await _uploadPhoto(_vehiclePhotoFile!, userId, 'vehicle');
      }

      // 3. Registo via RPC driver_register_or_update (ON CONFLICT user_id).
      final rpcRes = await supabase.rpc(
        'driver_register_or_update',
        params: {
          'p_name': name,
          'p_phone': phone,
          'p_vehicle_type': _vehicleType.name,
          'p_license_plate': licensePlate.isEmpty ? null : licensePlate,
          'p_document_type': _documentType,
          'p_document_number': _documentNumberController.text.trim().isEmpty
              ? null
              : _documentNumberController.text.trim(),
          'p_document_photo_url': docUrl,
          'p_vehicle_photo_url': vehicleUrl,
          'p_vehicle_doc_url': vehicleDocUrl,
          'p_registration_selfie_url': selfieUrl,
          'p_iban': iban.isEmpty ? null : iban,
          'p_nif': nif.isEmpty ? null : nif,
          'p_mbway_phone': mbwayPhone.isEmpty ? null : mbwayPhone,
          'p_address': address.isEmpty ? null : address,
        },
      );

      final rpcMap =
          rpcRes is Map ? rpcRes.cast<String, dynamic>() : <String, dynamic>{};
      final ok = (rpcMap['success'] as bool?) ?? false;
      if (!ok) {
        final reason = (rpcMap['reason'] as String?) ?? 'unknown';
        final friendly = switch (reason) {
          'unauthenticated' =>
            'Sessão não encontrada. Faz login e tenta de novo.',
          'missing_required_fields' =>
            'Faltam dados obrigatórios. Preenche tudo e tenta de novo.',
          'invalid_vehicle_type' => 'Tipo de veículo inválido.',
          _ => 'Não foi possível concluir o registo: $reason',
        };
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly)),
        );
        return;
      }

      if (!mounted) return;

      // 4. Limpar sessão auth
      context.read<AuthStore>().logout();
      _clearDraft();

      // 5. Ir para ecrã pendente
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final msg = e.message.toLowerCase().contains('already registered') ||
              e.message.toLowerCase().contains('user already')
          ? 'Este email já tem uma candidatura. Faz login ou usa um email diferente.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // ── Step validation (non-blocking — just guides the user) ───────────────
  bool _validateStep1() {
    return _nameController.text.trim().isNotEmpty;
  }

  bool _validateStep3() {
    final email = _emailController.text.trim();
    final pw = _passwordController.text;
    final confirm = _confirmController.text;
    if (email.isEmpty || pw.isEmpty) return false;
    if (pw.length < 6) return false;
    if (pw != confirm) return false;
    return true;
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
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep == 0 && !_validateStep1()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('O nome é obrigatório.')),
              );
              return;
            }
            if (_currentStep == 2 && !_validateStep3()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Email, password (mín. 6 chars) e confirmação são obrigatórios.')),
              );
              return;
            }
            if (_currentStep < 3) {
              setState(() => _currentStep++);
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) setState(() => _currentStep--);
          },
          onStepTapped: (step) => setState(() => _currentStep = step),
          controlsBuilder: (context, details) {
            if (_currentStep == 3) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: BoraPrimaryButton(
                  label: 'Enviar Candidatura',
                  loading: _isProcessing,
                  color: AppColors.primary,
                  onPressed: _acceptedTerms ? _submit : null,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Continuar'),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Voltar'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            // ── STEP 1: Dados Pessoais ──────────────────────────────
            Step(
              title: const Text('Dados Pessoais'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  // Selfie circular
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
                                  width: 120,
                                  height: 120,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt,
                                      size: 32, color: AppColors.accent),
                                  SizedBox(height: 4),
                                  Text('Selfie',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    onChanged: (_) => _saveDraft(),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AddressAutocompleteField(
                    controller: _addressController,
                    onSelected: (_, __) => _saveDraft(),
                    onChanged: (_) => _saveDraft(),
                    labelText: 'Morada',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nifController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'NIF (opcional)',
                      prefixIcon: Icon(Icons.badge_outlined),
                      hintText: '123456789',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (!RegExp(r'^\d{9}$').hasMatch(v.trim())) {
                        return 'NIF deve ter 9 dígitos';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),

            // ── STEP 2: Documentos (todos opcionais) ────────────────
            Step(
              title: const Text('Documentos'),
              subtitle: const Text('Todos opcionais'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
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
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _documentType = v!);
                      _saveDraft();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _documentNumberController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Número do documento',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    label: 'Foto do CC / BI',
                    file: _documentPhotoFile,
                    onTap: () =>
                        _showPhotoOptions((f) => _documentPhotoFile = f),
                  ),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    label: 'Documento do veículo',
                    file: _vehicleDocFile,
                    onTap: () => _showPhotoOptions((f) => _vehicleDocFile = f),
                  ),
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

            // ── STEP 3: Conta + Pagamento ───────────────────────────
            Step(
              title: const Text('Conta & Pagamento'),
              isActive: _currentStep >= 2,
              state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Obrigatório';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Palavra-passe *',
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
                      labelText: 'Confirmar palavra-passe *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) => v != _passwordController.text
                        ? 'Palavras-passe não coincidem'
                        : null,
                  ),
                  const SizedBox(height: 16),
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
                    onSelectionChanged: (s) {
                      setState(() {
                        _vehicleType = s.first;
                        if (_vehicleType == VehicleType.bicycle) {
                          _licensePlateController.clear();
                        }
                      });
                      _saveDraft();
                    },
                  ),
                  if (_vehicleType != VehicleType.bicycle) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _licensePlateController,
                      onChanged: (_) => _saveDraft(),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Matrícula',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ibanController,
                    onChanged: (_) => _saveDraft(),
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'IBAN (opcional)',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                      hintText: 'PT50...',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final clean = v.replaceAll(' ', '').toUpperCase();
                      if (!RegExp(r'^PT\d{21}$').hasMatch(clean)) {
                        return 'IBAN PT inválido (PT + 21 dígitos)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mbwayPhoneController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telemóvel MBWay (opcional)',
                      prefixIcon: Icon(Icons.phone_android),
                      hintText: '+351 9XX XXX XXX',
                    ),
                  ),
                ],
              ),
            ),

            // ── STEP 4: Termos & Submeter ───────────────────────────
            Step(
              title: const Text('Submeter'),
              isActive: _currentStep >= 3,
              state: _currentStep == 3 ? StepState.indexed : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Resumo
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resumo da candidatura',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const Divider(),
                          _summaryRow('Nome', _nameController.text),
                          _summaryRow('Telefone', _phoneController.text),
                          _summaryRow('Morada', _addressController.text),
                          _summaryRow('Email', _emailController.text),
                          _summaryRow('Veículo', _vehicleType.name),
                          if (_licensePlateController.text.isNotEmpty)
                            _summaryRow(
                                'Matrícula', _licensePlateController.text),
                          _summaryRow(
                            'Fotos',
                            [
                              if (_selfieFile != null) 'Selfie',
                              if (_documentPhotoFile != null) 'CC/BI',
                              if (_vehicleDocFile != null) 'Doc. veículo',
                              if (_vehiclePhotoFile != null) 'Veículo',
                            ].join(', ').ifEmpty('Nenhuma'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

extension _StringEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
