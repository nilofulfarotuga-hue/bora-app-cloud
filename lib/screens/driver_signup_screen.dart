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
import '../stores/session_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
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

  // Step 2: Conta
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  bool _accountCreated = false;

  // Step 3: Documentos
  String _documentType = 'Cartão Cidadão';
  final _documentNumberController = TextEditingController();
  XFile? _selfieFile;
  XFile? _documentPhotoFile;
  XFile? _vehicleDocFile;
  XFile? _vehiclePhotoFile;

  // Step 4: Veículo + Pagamento
  VehicleType _vehicleType = VehicleType.motorcycle;
  final _licensePlateController = TextEditingController();
  final _ibanController = TextEditingController();
  final _mbwayPhoneController = TextEditingController();

  bool _isProcessing = false;
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
    _phoneController.dispose();
    _addressController.dispose();
    _nifController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _documentNumberController.dispose();
    _licensePlateController.dispose();
    _ibanController.dispose();
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
      prefs.setString('$_kDraftKey.step', _currentStep.toString());
      prefs.setBool('$_kDraftKey.accountCreated', _accountCreated);
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
      _accountCreated = prefs.getBool('$_kDraftKey.accountCreated') ?? false;
      final step = int.tryParse(prefs.getString('$_kDraftKey.step') ?? '');
      if (step != null && step >= 0 && step <= 3) _currentStep = step;
    });
  }

  void _clearDraft() {
    SharedPreferences.getInstance().then((prefs) {
      for (final key in [
        'name', 'email', 'phone', 'address', 'nif',
        'docType', 'docNumber', 'vehicleType', 'plate', 'iban', 'mbway',
        'step', 'accountCreated',
      ]) {
        prefs.remove('$_kDraftKey.$key');
      }
    });
    context.read<SessionStore>().clearDriverSignupDraft();
  }

  // ── Photo helpers ──────────────────────────────────────────────────────────

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

  // ── Step 2: Create account ─────────────────────────────────────────────────

  Future<void> _createAccount() async {
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
      final consentAcceptedAt = DateTime.now().toUtc();

      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'bora_role': 'driver',
          'bora_name': name,
          'bora_phone': phone,
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

      // RPC with basic data to create driver row (approval_status=pending)
      final address = _addressController.text.trim();
      final nif = _nifController.text.trim();
      await supabase.rpc('driver_register_or_update', params: {
        'p_name': name,
        'p_phone': phone,
        'p_vehicle_type': 'motorcycle',
        'p_address': address.isEmpty ? null : address,
        'p_nif': nif.isEmpty ? null : nif,
      });

      // Persist driver in AuthStore so _RootNavigator sees driver != null
      final authStore = context.read<AuthStore>();
      authStore.persistDriverFromSignup(DriverAccount(
        name: name,
        email: email,
        phone: phone,
        vehicleType: VehicleType.motorcycle,
        licensePlate: '',
        password: password,
      ));

      setState(() {
        _accountCreated = true;
        _isProcessing = false;
        _currentStep = 2;
      });
      _saveDraft();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta criada! Podes adicionar fotos e dados.')),
        );
      }
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

  // ── Step 4: Final submit ───────────────────────────────────────────────────

  Future<void> _submitFinal() async {
    setState(() => _isProcessing = true);
    FocusScope.of(context).unfocus();

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id ?? '';

      // Upload photos — falha de upload NUNCA bloqueia o submit.
      // Se falhar, o campo fica null e o Danilo valida/pede a foto depois.
      String? selfieUrl;
      if (_selfieFile != null) {
        try {
          selfieUrl = await _uploadPhoto(_selfieFile!, userId, 'selfie');
        } catch (_) {}
      }
      String? docUrl;
      if (_documentPhotoFile != null) {
        try {
          docUrl = await _uploadPhoto(_documentPhotoFile!, userId, 'document');
        } catch (_) {}
      }
      String? vehicleDocUrl;
      if (_vehicleDocFile != null) {
        try {
          vehicleDocUrl =
              await _uploadPhoto(_vehicleDocFile!, userId, 'vehicle_doc');
        } catch (_) {}
      }
      String? vehicleUrl;
      if (_vehiclePhotoFile != null) {
        try {
          vehicleUrl = await _uploadPhoto(_vehiclePhotoFile!, userId, 'vehicle');
        } catch (_) {}
      }

      final iban = _ibanController.text.replaceAll(' ', '').toUpperCase();
      final mbwayPhone = _mbwayPhoneController.text.trim();
      final licensePlate = _vehicleType != VehicleType.bicycle
          ? _licensePlateController.text.trim().toUpperCase()
          : '';

      // RPC update with all remaining data
      final rpcRes = await supabase.rpc('driver_register_or_update', params: {
        'p_name': _nameController.text.trim(),
        'p_phone': _phoneController.text.trim(),
        // R1: usar o mapeamento canónico (carPassengers → 'carro_passageiros'),
        // NUNCA o enum cru (.name daria 'carPassengers' e o dispatch falharia).
        'p_vehicle_type': _vehicleType.dbValue,
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
        'p_nif': _nifController.text.trim().isEmpty
            ? null
            : _nifController.text.trim(),
        'p_mbway_phone': mbwayPhone.isEmpty ? null : mbwayPhone,
        'p_address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
      });

      final rpcMap =
          rpcRes is Map ? rpcRes.cast<String, dynamic>() : <String, dynamic>{};
      final ok = (rpcMap['success'] as bool?) ?? false;
      if (!ok) {
        final reason = (rpcMap['reason'] as String?) ?? 'unknown';
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no registo: $reason')),
        );
        return;
      }

      if (!mounted) return;

      // Clear draft + logout → DriverPendingScreen (limpa a stack do signup
      // para não voltar ao login nem ficar preso — estilo Glovo).
      // L3 — limpeza pós-registo, não "Sair": preserva biometria.
      context.read<AuthStore>().logout(wipeBiometrics: false);
      _clearDraft();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Candidatura de Estafeta'),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep == 0) {
              // Nunca bloqueia — avança mesmo com campos vazios (Danilo valida
              // manualmente depois). Ver regra "cadastro nunca bloqueia".
              setState(() => _currentStep = 1);
              return;
            }
            if (_currentStep == 1) {
              if (!_accountCreated) {
                _createAccount();
              } else {
                setState(() => _currentStep = 2);
              }
              return;
            }
            if (_currentStep < 3) {
              setState(() => _currentStep++);
              _saveDraft();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              // Don't go back to step 1 (account) if already created
              if (_currentStep == 2 && _accountCreated) {
                // Can still go back to step 1 for viewing, just skip step 2
              }
              setState(() => _currentStep--);
            }
          },
          onStepTapped: (step) {
            // Allow tapping any step (no restrictions)
            setState(() => _currentStep = step);
          },
          controlsBuilder: (context, details) {
            if (_currentStep == 1 && !_accountCreated) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: BoraPrimaryButton(
                  label: 'Criar Conta',
                  loading: _isProcessing,
                  color: AppColors.primary,
                  onPressed: _acceptedTerms ? _createAccount : null,
                ),
              );
            }
            if (_currentStep == 3) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: BoraPrimaryButton(
                  label: 'Enviar Candidatura',
                  loading: _isProcessing,
                  color: AppColors.primary,
                  onPressed: _submitFinal,
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
                  TextFormField(
                    controller: _nameController,
                    onChanged: (_) => _saveDraft(),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    // Sem validator bloqueante — cadastro nunca trava.
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone (opcional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nifController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'NIF (opcional)',
                      prefixIcon: Icon(Icons.badge_outlined),
                      helperText: '9 dígitos sem espaços',
                    ),
                    // Aviso visual apenas (helperText) — nunca bloqueia o avanço.
                  ),
                  const SizedBox(height: 12),
                  AddressAutocompleteField(
                    controller: _addressController,
                    onSelected: (_, __) => _saveDraft(),
                    onChanged: (_) => _saveDraft(),
                    labelText: 'Morada (opcional)',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                ],
              ),
            ),

            // ── STEP 2: Conta de Acesso ─────────────────────────────
            Step(
              title: const Text('Conta de Acesso'),
              subtitle: _accountCreated
                  ? const Text('Conta criada ✓')
                  : null,
              isActive: _currentStep >= 1,
              state: _accountCreated ? StepState.complete : StepState.indexed,
              content: _accountCreated
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: AppColors.primary),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Conta criada com sucesso. Podes continuar a preencher os restantes dados.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
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
                            if (v == null || v.trim().isEmpty) {
                              return 'Obrigatório';
                            }
                            final t = v.trim();
                            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$')
                                .hasMatch(t)) {
                              return 'Email inválido';
                            }
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
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) => v != _passwordController.text
                              ? 'Palavras-passe não coincidem'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: _acceptedTerms,
                          onChanged: _isProcessing
                              ? null
                              : (v) =>
                                  setState(() => _acceptedTerms = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.accent,
                          title: const TermsLinkText(),
                        ),
                      ],
                    ),
            ),

            // ── STEP 3: Documentos (todos opcionais) ────────────────
            Step(
              title: const Text('Documentos & Fotos'),
              subtitle: const Text('Todos opcionais'),
              isActive: _currentStep >= 2,
              state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  // Selfie
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
                                  Text('Selfie (opcional)',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _documentType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento de identificação',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: const [
                      'Cartão Cidadão',
                      'Bilhete de Identidade',
                      'Título de Residência',
                      'Passaporte',
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
                      labelText: 'Número do documento (opcional)',
                      prefixIcon: Icon(Icons.numbers),
                      helperText: 'Número do CC ou BI sem espaços',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    label: 'Foto do Cartão de Cidadão (frente) — opcional',
                    file: _documentPhotoFile,
                    onTap: () =>
                        _showPhotoOptions((f) => _documentPhotoFile = f),
                  ),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    label:
                        'Foto do documento do veículo (carta de condução ou livrete) — opcional',
                    file: _vehicleDocFile,
                    onTap: () => _showPhotoOptions((f) => _vehicleDocFile = f),
                  ),
                  const SizedBox(height: 12),
                  _PhotoPicker(
                    label:
                        'Foto do veículo (mota, bicicleta ou carro) — opcional',
                    file: _vehiclePhotoFile,
                    onTap: () =>
                        _showPhotoOptions((f) => _vehiclePhotoFile = f),
                  ),
                ],
              ),
            ),

            // ── STEP 4: Veículo + Pagamento + Submeter ──────────────
            Step(
              title: const Text('Veículo & Pagamento'),
              isActive: _currentStep >= 3,
              content: Column(
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
                      ButtonSegment(
                        value: VehicleType.carPassengers,
                        label: Text('Carro — Passageiros'),
                        icon: Icon(Icons.local_taxi),
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
                        labelText: 'Matrícula (opcional)',
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
                      helperText: 'IBAN português para receber pagamentos',
                    ),
                    // Sem validator bloqueante — Danilo confirma o IBAN depois.
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mbwayPhoneController,
                    onChanged: (_) => _saveDraft(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Número MBWay para receber pagamentos (opcional)',
                      prefixIcon: Icon(Icons.phone_android),
                      hintText: '+351 9XX XXX XXX',
                    ),
                    // Sem validator bloqueante — cadastro nunca trava.
                  ),
                ],
              ),
            ),
          ],
        ),
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
                  Flexible(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                ],
              ),
      ),
    );
  }
}
