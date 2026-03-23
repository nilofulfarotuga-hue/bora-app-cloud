import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import 'driver_signup_screen.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'driver@bora.app');
  final _passwordController = TextEditingController(text: '123456');

  bool _isProcessing = false;
  bool _obscurePassword = true;

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
      appBar: AppBar(
        title: const Text('Entrar como estafeta'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use o email e a palavra-passe da sua conta de estafeta.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o email.';
                  }
                  if (!value.contains('@')) {
                    return 'Email inválido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
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
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a palavra-passe.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _submit,
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Entrar'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : _goToSignup,
                  child: const Text('Criar conta'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _forgotPassword,
                  child: const Text('Esqueci a palavra-passe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final driverStore = context.read<DriverStore>();
    final sessionStore = context.read<SessionStore>();

    final success = await authStore.loginDriverAsync(
      _emailController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email ou palavra-passe incorretos.')),
      );
      return;
    }

    final account = authStore.currentDriver;
    if (account != null) {
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      driverStore.configurePrimaryDriver(
        name: account.name,
        phone: account.phone,
        vehicleType: account.vehicleType,
        licensePlate: account.licensePlate,
        driverId: authUserId,
      );
    }

    await sessionStore.setRole(UserRole.driver);

    if (!mounted) return;
    setState(() => _isProcessing = false);
    // No Navigator call — RootNavigator reacts automatically.
  }

  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverSignupScreen()),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Introduza o seu email no campo acima antes de continuar.')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    await context.read<AuthStore>().resetDriverPassword(email);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Se existir uma conta com $email, receberá um email para redefinir a palavra-passe.'),
      ),
    );
  }
}
