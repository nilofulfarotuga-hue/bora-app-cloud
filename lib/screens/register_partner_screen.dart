import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../stores/partner_product_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'partner_login_screen.dart';
import 'pending_approval_screen.dart';

class RegisterPartnerScreen extends StatefulWidget {
  const RegisterPartnerScreen({super.key});

  @override
  State<RegisterPartnerScreen> createState() => _RegisterPartnerScreenState();
}

class _RegisterPartnerScreenState extends State<RegisterPartnerScreen> {
  final _formKey = GlobalKey<FormState>();

  // Step 1: Dados Básicos
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cuisineController = TextEditingController();
  BusinessCategory _selectedCategory = BusinessCategory.restaurant;
  ll.LatLng? _pickupCoords;

  // Step 2: Documentos (OPCIONAIS)
  final _nifController = TextEditingController();
  final _ibanController = TextEditingController();
  XFile? _ownerDocFile;
  XFile? _activityDocFile;

  // Step 3: Conta de Acesso
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _acceptedTerms = false;
  bool _obscurePassword = true;
  String? _emailInlineError;

  // Step 4: Logo/Confirmação
  XFile? _logoFile;

  final _imagePicker = ImagePicker();
  int _currentStep = 0;
  bool _isSubmitting = false;

  static const _kDraftKey = 'bora_app.signup_draft.partner';

  @override
  void initState() {
    super.initState();
    _recoverLostImage();
    _restoreDraft();
  }

  Future<void> _recoverLostImage() async {
    final lost = await _imagePicker.retrieveLostData();
    if (lost.isEmpty || !mounted) return;
    final file = lost.file;
    if (file == null) return;
    setState(() {
      if (_ownerDocFile == null) {
        _ownerDocFile = file;
      } else if (_activityDocFile == null) {
        _activityDocFile = file;
      } else {
        _logoFile = file;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _cuisineController.dispose();
    _nifController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  void _saveDraft() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('$_kDraftKey.name', _nameController.text);
      prefs.setString('$_kDraftKey.address', _addressController.text);
      prefs.setString('$_kDraftKey.phone', _phoneController.text);
      prefs.setString('$_kDraftKey.email', _emailController.text);
      prefs.setString('$_kDraftKey.cuisine', _cuisineController.text);
      prefs.setString('$_kDraftKey.category', _selectedCategory.name);
      prefs.setString('$_kDraftKey.nif', _nifController.text);
      prefs.setString('$_kDraftKey.iban', _ibanController.text);
    });
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('$_kDraftKey.name');
    if (name == null || !mounted) return;
    setState(() {
      if (name.isNotEmpty) _nameController.text = name;
      final address = prefs.getString('$_kDraftKey.address') ?? '';
      if (address.isNotEmpty) _addressController.text = address;
      final phone = prefs.getString('$_kDraftKey.phone') ?? '';
      if (phone.isNotEmpty) _phoneController.text = phone;
      final email = prefs.getString('$_kDraftKey.email') ?? '';
      if (email.isNotEmpty) _emailController.text = email;
      final cuisine = prefs.getString('$_kDraftKey.cuisine') ?? '';
      if (cuisine.isNotEmpty) _cuisineController.text = cuisine;
      final categoryName = prefs.getString('$_kDraftKey.category');
      if (categoryName != null) {
        try {
          _selectedCategory = BusinessCategory.values
              .firstWhere((c) => c.name == categoryName);
        } catch (_) {}
      }
      final nif = prefs.getString('$_kDraftKey.nif') ?? '';
      if (nif.isNotEmpty) _nifController.text = nif;
      final iban = prefs.getString('$_kDraftKey.iban') ?? '';
      if (iban.isNotEmpty) _ibanController.text = iban;
    });
  }

  void _clearDraft() {
    SharedPreferences.getInstance().then((prefs) {
      for (final key in [
        'name',
        'address',
        'phone',
        'email',
        'cuisine',
        'category',
        'nif',
        'iban'
      ]) {
        prefs.remove('$_kDraftKey.$key');
      }
    });
  }

  Future<void> _pickDocument(bool isOwnerDoc) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          if (isOwnerDoc) {
            _ownerDocFile = picked;
          } else {
            _activityDocFile = picked;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao seleccionar documento: $e')),
        );
      }
    }
  }

  Future<void> _pickLogo(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null && mounted) setState(() => _logoFile = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao seleccionar imagem: $e')),
        );
      }
    }
  }

  void _showLogoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accent),
              title: const Text('Tirar foto'),
              onTap: () {
                Navigator.pop(context);
                _pickLogo(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.accent),
              title: const Text('Escolher da galeria'),
              onTap: () {
                Navigator.pop(context);
                _pickLogo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _validateStep1() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique o nome do estabelecimento')),
      );
      return false;
    }
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique o endereço')),
      );
      return false;
    }
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o telefone')),
      );
      return false;
    }
    return true;
  }

  bool _validateStep3() {
    if (_emailController.text.trim().isEmpty ||
        !_emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email inválido')),
      );
      return false;
    }
    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha mínima de 6 caracteres')),
      );
      return false;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aceite os termos e condições')),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    final authStore = context.read<AuthStore>();

    try {
      // Upload logo se selecionado
      String? logoUrl;
      if (_logoFile != null) {
        try {
          final bytes = await _logoFile!.readAsBytes();
          final ext = _logoFile!.path.contains('.')
              ? _logoFile!.path.split('.').last.toLowerCase()
              : 'jpg';
          final response = await Supabase.instance.client.functions.invoke(
            'upload-restaurant-asset',
            body: {
              'restaurantId': 'temp-${DateTime.now().millisecondsSinceEpoch}',
              'kind': 'logo',
              'fileBase64': base64Encode(bytes),
              'contentType': 'image/$ext',
            },
          );
          if (response.status == 200 && response.data is Map) {
            final data = Map<String, dynamic>.from(response.data as Map);
            if (data['success'] == true) {
              logoUrl = data['public_url'] as String;
            }
          }
        } catch (e) {
          debugPrint('RegisterPartnerScreen: logo upload failed => $e');
        }
      }

      // Upload documentos se selecionados
      String? ownerDocUrl;
      String? activityDocUrl;

      if (_ownerDocFile != null) {
        try {
          final bytes = await _ownerDocFile!.readAsBytes();
          final ext = _ownerDocFile!.path.split('.').last.toLowerCase();
          final response = await Supabase.instance.client.functions.invoke(
            'upload-restaurant-asset',
            body: {
              'restaurantId': 'temp-${DateTime.now().millisecondsSinceEpoch}',
              'kind': 'owner_doc',
              'fileBase64': base64Encode(bytes),
              'contentType': 'image/$ext',
            },
          );
          if (response.status == 200 && response.data is Map) {
            final data = Map<String, dynamic>.from(response.data as Map);
            if (data['success'] == true) {
              ownerDocUrl = data['public_url'] as String;
            }
          }
        } catch (e) {
          debugPrint('RegisterPartnerScreen: owner_doc upload failed => $e');
        }
      }

      if (_activityDocFile != null) {
        try {
          final bytes = await _activityDocFile!.readAsBytes();
          final ext = _activityDocFile!.path.split('.').last.toLowerCase();
          final response = await Supabase.instance.client.functions.invoke(
            'upload-restaurant-asset',
            body: {
              'restaurantId': 'temp-${DateTime.now().millisecondsSinceEpoch}',
              'kind': 'activity_doc',
              'fileBase64': base64Encode(bytes),
              'contentType': 'image/$ext',
            },
          );
          if (response.status == 200 && response.data is Map) {
            final data = Map<String, dynamic>.from(response.data as Map);
            if (data['success'] == true) {
              activityDocUrl = data['public_url'] as String;
            }
          }
        } catch (e) {
          debugPrint('RegisterPartnerScreen: activity_doc upload failed => $e');
        }
      }

      // Registra parceiro com documentos
      final result =
          await authStore.registerPartnerWithDocumentsAsync(
        restaurantName: _nameController.text,
        address: _addressController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        password: _passwordController.text,
        cuisineType: _cuisineController.text,
        category: _selectedCategory.name,
        lat: _pickupCoords?.latitude,
        lng: _pickupCoords?.longitude,
        nif: _nifController.text.isEmpty ? null : _nifController.text,
        iban: _ibanController.text.isEmpty ? null : _ibanController.text,
        ownerDocUrl: ownerDocUrl,
        activityDocUrl: activityDocUrl,
        consentAcceptedAt: DateTime.now().toUtc(),
      );

      if (result == null) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        debugPrint('[RegisterPartnerScreen] registerPartnerWithDocumentsAsync returned null');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: Verifica email/password ou contacta support. Detalhes nos logs.')),
        );
        return;
      }

      _clearDraft();

      // Se logo foi enviado após creation, atualiza foto do restaurant
      if (logoUrl != null) {
        try {
          final restaurantId = result['restaurant_id'] as String;
          await Supabase.instance.client
              .from('restaurants')
              .update({'photo_url': logoUrl})
              .eq('id', restaurantId);
          await authStore.updateCurrentUserPhoto(logoUrl);
        } catch (e) {
          debugPrint('RegisterPartnerScreen: logo update post-creation => $e');
        }
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Navega para PendingApprovalScreen (não muda role aqui — PendingApprovalScreen
      // oferece opção de "Gerir a Minha Loja" que chama setRole quando necessário)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const PendingApprovalScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Criar conta de parceiro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
            if (_currentStep == 0 && !_validateStep1()) return;
            if (_currentStep == 2 && !_validateStep3()) return;
            if (_currentStep < 3) {
              setState(() => _currentStep++);
            } else {
              _submit();
            }
          },
          onStepCancel: _currentStep > 0
              ? () => setState(() => _currentStep--)
              : null,
          steps: [
            // Step 1: Dados Básicos
            Step(
              title: const Text('Dados do Estabelecimento'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Nome do estabelecimento',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AddressAutocompleteField(
                    controller: _addressController,
                    labelText: 'Endereço completo',
                    onSelected: (address, coords) {
                      setState(() => _pickupCoords = coords);
                      _saveDraft();
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cuisineController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cozinha',
                      prefixIcon: Icon(Icons.restaurant_menu),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BusinessCategory>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: BusinessCategory.values
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedCategory = value);
                      _saveDraft();
                    },
                  ),
                ],
              ),
            ),

            // Step 2: Documentos (OPCIONAIS)
            Step(
              title: const Text('Documentos (Opcionais)'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _nifController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'NIF (opcional)',
                      hintText: '9 dígitos',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _ibanController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'IBAN (opcional)',
                      hintText: 'PT + 22 dígitos',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _pickDocument(true),
                    child: Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: _ownerDocFile == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload_file,
                                    color: Colors.grey.shade600),
                                const SizedBox(height: 4),
                                const Text('Documento Proprietário (opcional)'),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green),
                                const SizedBox(width: 8),
                                Text(_ownerDocFile!.path.split('/').last),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _pickDocument(false),
                    child: Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: _activityDocFile == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload_file,
                                    color: Colors.grey.shade600),
                                const SizedBox(height: 4),
                                const Text('Documento Atividade (opcional)'),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green),
                                const SizedBox(width: 8),
                                Text(_activityDocFile!.path.split('/').last),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Step 3: Conta de Acesso
            Step(
              title: const Text('Conta de Acesso'),
              isActive: _currentStep >= 2,
              state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      _saveDraft();
                      if (_emailInlineError != null) {
                        setState(() => _emailInlineError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText: _emailInlineError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  CheckboxListTile(
                    value: _acceptedTerms,
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _acceptedTerms = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const TermsLinkText(),
                  ),
                ],
              ),
            ),

            // Step 4: Logo e Confirmação
            Step(
              title: const Text('Logo & Confirmação'),
              isActive: _currentStep >= 3,
              state: _currentStep > 3 ? StepState.complete : StepState.indexed,
              content: Column(
                children: [
                  GestureDetector(
                    onTap: _isSubmitting ? null : _showLogoOptions,
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        image: _logoFile != null
                            ? DecorationImage(
                                image: FileImage(File(_logoFile!.path)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: _logoFile == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined,
                                        color: Colors.grey.shade600, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Logo do estabelecimento\n(opcional)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey.shade700),
                                    ),
                                  ],
                                )
                              : const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.check_circle,
                                        color: Colors.green, size: 28),
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resumo:', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 12),
                          Text('Nome: ${_nameController.text}'),
                          Text('Email: ${_emailController.text}'),
                          if (_nifController.text.isNotEmpty)
                            Text('NIF: ${_nifController.text}'),
                          if (_ibanController.text.isNotEmpty)
                            Text('IBAN: ${_ibanController.text}'),
                          if (_ownerDocFile != null)
                            const Text('✓ Documento Proprietário'),
                          if (_activityDocFile != null)
                            const Text('✓ Documento Atividade'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  Text(
                    'Ao submeter, sua conta ficará pendente de análise (24-48h).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
