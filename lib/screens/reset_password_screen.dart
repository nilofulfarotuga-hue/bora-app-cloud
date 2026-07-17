import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';

/// Ecrã aberto pelo deep link `pt.boraapp.bora://reset-password` depois de o
/// utilizador tocar no link do email de recuperação de senha (Supabase Auth
/// `resetPasswordForEmail`). Nessa altura já existe uma sessão de recovery
/// válida (`AuthChangeEvent.passwordRecovery`) — este ecrã só pede a nova
/// palavra-passe e chama `auth.updateUser`.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isProcessing = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      // Termina a sessão de recovery — o utilizador volta a entrar com a
      // palavra-passe nova pelo ecrã de login normal.
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Palavra-passe alterada. Entre com a nova palavra-passe.')),
      );
      if (navigator.canPop()) {
        navigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível alterar a palavra-passe: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
                const SizedBox(height: 56),
                const Center(
                  child: BoraMascot(
                    variant: BoraMascotVariant.logo,
                    size: 72,
                    semanticLabel: 'BORA',
                  ),
                ),
                const SizedBox(height: Spacing.xxl + 4),
                const Text(
                  'Nova palavra-passe',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xs + 2),
                const Text(
                  'Defina a nova palavra-passe da sua conta Bora.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.xxl + 4),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Nova palavra-passe',
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
                      return 'Informe a nova palavra-passe.';
                    }
                    if (value.length < 6) return 'Mínimo 6 caracteres.';
                    return null;
                  },
                ),
                const SizedBox(height: Spacing.lg),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscurePassword,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar palavra-passe',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'As palavras-passe não coincidem.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Spacing.xxl + 4),
                BoraPrimaryButton(
                  label: 'Guardar nova palavra-passe',
                  loading: _isProcessing,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
