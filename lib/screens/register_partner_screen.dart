import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

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
  final _photoUrlController = TextEditingController();
  final _cuisineController = TextEditingController();

  BusinessCategory _selectedCategory = BusinessCategory.restaurant;
  ll.LatLng? _pickupCoords;

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;

  /// Shown inline under the email field when Supabase rejects a duplicate.
  String? _emailInlineError;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _photoUrlController.dispose();
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
      photoUrl: _photoUrlController.text,
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
        photoUrl: _photoUrlController.text,
        cuisineType: _cuisineController.text,
        category: _selectedCategory,
        lat: _pickupCoords?.latitude,
        lng: _pickupCoords?.longitude,
      );

      /// SALVA restaurante no AuthStore
      authStore.setPartnerRestaurant(restaurant);

      /// Seleciona restaurante no store de produtos
      partnerProductStore.selectRestaurant(restaurant);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar restaurante: $error')),
      );

      return;
    }

    await sessionStore.setRole(UserRole.partner);

    if (!mounted) return;
    setState(() => _isSubmitting = false);
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
                  TextFormField(
                    controller: _photoUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL da foto do restaurante',
                      prefixIcon: Icon(Icons.image_outlined),
                      helperText: 'Obrigatório — imagem visível aos clientes',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Adicione uma foto do restaurante';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cuisineController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cozinha',
                      prefixIcon: Icon(Icons.restaurant_menu),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BusinessCategory>(
                    initialValue: _selectedCategory,
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
                      // Clear inline duplicate error as soon as the user edits.
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
