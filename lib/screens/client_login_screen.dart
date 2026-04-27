import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/notification_service.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'register_client_screen.dart';

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(
    text: kDebugMode ? 'cliente@bora.app' : '',
  );
  final _passwordController = TextEditingController(
    text: kDebugMode ? '123456' : '',
  );
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl + 4,
            vertical: Spacing.xxl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Spacing.xxxl),

                // ── Logo ──────────────────────────────────────────────
                Center(
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'BO',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                        TextSpan(
                          text: 'RA',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: AppColors.accent,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                const Center(
                  child: Text(
                    'Área do Cliente',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.huge - 8),

                // ── Title ─────────────────────────────────────────────
                const Text(
                  'Iniciar sessão',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xs + 2),
                const Text(
                  'Entre com a sua conta de cliente',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),

                const SizedBox(height: Spacing.xxl + 4),

                // ── Email ─────────────────────────────────────────────
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o seu email.';
                    }
                    if (!value.contains('@')) return 'Email inválido.';
                    return null;
                  },
                ),
                const SizedBox(height: Spacing.lg),

                // ── Password ──────────────────────────────────────────
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Palavra-passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
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

                const SizedBox(height: Spacing.xxl + 4),

                // ── Login button ──────────────────────────────────────
                BoraPrimaryButton(
                  label: 'Entrar',
                  loading: _isProcessing,
                  onPressed: _submit,
                ),
                const SizedBox(height: Spacing.xs),

                // ── Forgot password ───────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: _isProcessing ? null : _forgotPassword,
                    child: const Text('Esqueceu a palavra-passe?'),
                  ),
                ),
                const SizedBox(height: Spacing.xs),

                // ── Create account ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterClientScreen(),
                              ),
                            ),
                    child: const Text('Criar conta'),
                  ),
                ),

                const SizedBox(height: Spacing.lg),
                Center(
                  child: TextButton(
                    onPressed: _isProcessing ? null : _backToRoles,
                    child: const Text('← Voltar à escolha de perfil'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _backToRoles() {
    final sessionStore = context.read<SessionStore>();
    sessionStore.clearRole();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    final success = await authStore.loginClientAsync(
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

    // Persist FCM token for this client device so push notifications work.
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null) {
      NotificationService.instance.saveTokenForClient(authUser.id).ignore();
    }

    await sessionStore.setRole(UserRole.client);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    // No Navigator call — RootNavigator reacts automatically.
  }
}
