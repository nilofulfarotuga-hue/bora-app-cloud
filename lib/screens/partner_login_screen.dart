import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/partner_appointments_store.dart';
import '../stores/restaurant_store.dart';
import '../services/notification_service.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'register_partner_screen.dart';

class PartnerLoginScreen extends StatefulWidget {
  const PartnerLoginScreen({super.key});

  @override
  State<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends State<PartnerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isProcessing = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Aceder como parceiro',
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
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Utilize o email registado para gerir o seu negócio.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.xxl),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o email do parceiro.';
                  }
                  if (!value.contains('@')) {
                    return 'Email inválido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() {
                      _obscurePassword = !_obscurePassword;
                    }),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a palavra-passe.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Spacing.xxxl),
              BoraPrimaryButton(
                label: 'Entrar',
                loading: _isProcessing,
                onPressed: _isProcessing ? null : _submit,
              ),
              const SizedBox(height: Spacing.xs),
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _forgotPassword,
                  child: const Text('Esqueceu a palavra-passe?'),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _createAccount,
                  child: const Text(
                    'Não tens conta? Criar conta de parceiro',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegisterPartnerScreen(),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Introduza o seu email no campo acima antes de continuar.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    await context.read<AuthStore>().resetPassword(email);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Se existir uma conta com $email, receberá um email para redefinir a palavra-passe.'),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _isProcessing = true);
    final authStore = context.read<AuthStore>();
    final restaurantStore = context.read<RestaurantStore>();
    final sessionStore = context.read<SessionStore>();
    final appointmentsStore = context.read<PartnerAppointmentsStore>();

    final success = await authStore.loginPartnerAsync(
      _emailController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciais inválidas.')),
      );
      return;
    }

    final restaurant = restaurantStore.restaurantByEmail(_emailController.text);
    if (restaurant != null) {
      authStore.setPartnerRestaurant(restaurant);

      // Persist FCM token for this partner device so push notifications work.
      NotificationService.instance.saveTokenForPartner(restaurant.id).ignore();
    } else {
      // No `restaurants` row. A Serviços/Barbearias partner owns a
      // `service_providers` record instead — let it through so _RootNavigator →
      // PartnerEntryScreen routes to the marcações hub. Reject only when the
      // account has neither a restaurant nor a service provider.
      final hasServiceProvider = await _hasServiceProvider(appointmentsStore);
      if (!mounted) return;
      if (!hasServiceProvider) {
        authStore.logout();
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Não encontramos o restaurante associado a este email.'),
          ),
        );
        return;
      }
    }

    await sessionStore.setRole(UserRole.partner);

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (Navigator.canPop(context)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// True when the logged-in partner owns a `service_providers` record
  /// (Serviços/Barbearias vertical). Lets service-only partners — who have no
  /// `restaurants` row — into the app instead of rejecting login.
  Future<bool> _hasServiceProvider(PartnerAppointmentsStore store) async {
    try {
      return (await store.loadMyProvider()) != null;
    } catch (_) {
      return false;
    }
  }
}
