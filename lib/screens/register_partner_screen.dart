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
import '../stores/session_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'partner_login_screen.dart';

/// BUG 7: partner photo is optional during registration. When the field is
/// left blank, save with this Bora-branded placeholder URL (green+orange
/// shopping-bag SVG hosted on the project assets bucket). Partner can update
/// the photo at any time from the partner profile screen.
const String _kPartnerPlaceholderPhoto =
    'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/branding/partner-placeholder.png';

class RegisterPartnerScreen extends StatefulWidget {
  const RegisterPartnerScreen({super.key});

  @override
  State<RegisterPartnerScreen> createState() => _RegisterPartnerScreenState();
}

class _RegisterPartnerScreenState extends State<RegisterPartnerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cuisineController = TextEditingController();

  XFile? _logoFile;
  final _imagePicker = ImagePicker();

  BusinessCategory _selectedCategory = BusinessCategory.restaurant;
  ll.LatLng? _pickupCoords;

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;

  /// Shown inline under the email field when Supabase rejects a duplicate.
  String? _emailInlineError;

  static const _kDraftKey = 'bora_app.signup_draft.partner';

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _cuisineController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    // Clear previous inline email error on each submit attempt.
    setState(() {
      _isSubmitting = true;
      _emailInlineError = null;
    });

    final authStore = context.read<AuthStore>();
    final restaurantStore = context.read<RestaurantStore>();
    final partnerProductStore = context.read<PartnerProductStore>();
    final sessionStore = context.read<SessionStore>();

    // Async: waits for Supabase signUp confirmation before proceeding.
    final error = await authStore.registerPartnerAsync(
      restaurantName: _nameController.text,
      address: _addressController.text,
      phone: _phoneController.text,
      email: _emailController.text,
      password: _passwordController.text,
      photoUrl: _kPartnerPlaceholderPhoto,
      cuisineType: _cuisineController.text,
      consentAcceptedAt: DateTime.now().toUtc(),
    );

    if (error != null) {
      // Email-duplicate errors are shown inline under the email field AND
      // as a SnackBar so the user sees exactly which field to fix.
      final isEmailError = error.toLowerCase().contains('email') ||
          error.toLowerCase().contains('already registered') ||
          error.toLowerCase().contains('parceiro registado');

      if (isEmailError && mounted) {
        setState(() {
          _isSubmitting = false;
          _emailInlineError = error;
        });
        // Scroll is handled by the Form — just force revalidation to display the
        // inline error. Also show a SnackBar for visibility.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      return;
    }

    final partner = authStore.currentPartner;

    if (partner == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      final restaurant = await restaurantStore.registerPartnerRestaurant(
        name: _nameController.text,
        address: _addressController.text,
        phone: _phoneController.text,
        email: partner.email,
        photoUrl: _kPartnerPlaceholderPhoto,
        cuisineType: _cuisineController.text,
        category: _selectedCategory,
        lat: _pickupCoords?.latitude,
        lng: _pickupCoords?.longitude,
      );

      /// SALVA restaurante no AuthStore
      authStore.setPartnerRestaurant(restaurant);

      /// Seleciona restaurante no store de produtos
      partnerProductStore.selectRestaurant(restaurant);

      /// Upload logo se o utilizador tirou/escolheu foto
      if (_logoFile != null) {
        try {
          final bytes = await _logoFile!.readAsBytes();
          final ext = _logoFile!.path.contains('.')
              ? _logoFile!.path.split('.').last.toLowerCase()
              : 'jpg';
          final path = 'logo/${restaurant.id}.$ext';
          final storage = Supabase.instance.client.storage;
          await storage.from('restaurant-assets').uploadBinary(
                path,
                bytes,
                fileOptions:
                    FileOptions(upsert: true, contentType: 'image/$ext'),
              );
          final url = storage.from('restaurant-assets').getPublicUrl(path);
          await Supabase.instance.client
              .from('restaurants')
              .update({'photo_url': url})
              .eq('id', restaurant.id);
          authStore.updateCurrentUserPhoto(url);
        } catch (e) {
          debugPrint('RegisterPartnerScreen: logo upload failed => $e');
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar restaurante: $error')),
      );

      return;
    }

    await sessionStore.setRole(UserRole.partner);
    _clearDraft();

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conta criada com sucesso!')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
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

  void _saveDraft() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('$_kDraftKey.name', _nameController.text);
      prefs.setString('$_kDraftKey.address', _addressController.text);
      prefs.setString('$_kDraftKey.phone', _phoneController.text);
      prefs.setString('$_kDraftKey.email', _emailController.text);
      prefs.setString('$_kDraftKey.cuisine', _cuisineController.text);
      prefs.setString('$_kDraftKey.category', _selectedCategory.name);
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
        'category'
      ]) {
        prefs.remove('$_kDraftKey.$key');
      }
    });
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
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registe o seu estabelecimento para começar a vender com a BORA.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Dados do estabelecimento',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    onChanged: (_) => _saveDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Nome do estabelecimento',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Indique o nome do estabelecimento';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AddressAutocompleteField(
                    controller: _addressController,
                    labelText: 'Endereço completo',
                    onSelected: (address, coords) {
                      setState(() => _pickupCoords = coords);
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Indique o endereço';
                      }
                      return null;
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
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o telefone';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // ── Logo do estabelecimento ───────────────────────────
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
                  const SizedBox(height: 32),
                  Text(
                    'Dados de acesso',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
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
                      errorStyle: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return 'Email inválido';
                      }
                      return null;
                    },
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
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Senha mínima de 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: Spacing.xxl),
                  CheckboxListTile(
                    value: _acceptedTerms,
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _acceptedTerms = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const TermsLinkText(),
                  ),
                  const SizedBox(height: Spacing.md),
                  BoraPrimaryButton(
                    label: 'Criar conta',
                    loading: _isSubmitting,
                    onPressed:
                        (_isSubmitting || !_acceptedTerms) ? null : _submit,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Já tem um parceiro registado?'),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PartnerLoginScreen(),
                            ),
                          );
                        },
                        child: const Text('Iniciar sessão'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
