import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/biometric_auth_service.dart';
import '../services/login_prefs.dart';
import '../services/notification_service.dart';
import '../services/role_switch_helper.dart';
import '../stores/session_store.dart';
import '../widgets/biometric_enrollment_dialog.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'forgot_password_screen.dart';
import 'register_client_screen.dart';
import 'role_choice_screen.dart';

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(
    text: '',
  );
  final _passwordController = TextEditingController(
    text: '',
  );
  bool _isProcessing = false;
  bool _obscurePassword = true;
  // L1 — true quando o email foi pré-preenchido com o último login.
  bool _prefilledFromMemory = false;
  // L3 — true quando o aparelho tem biometria E há sessão guardada.
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _prefillLastEmail();
    _checkBiometric();
  }

  /// L3 — mostra o botão "Entrar com biometria" se o aparelho suporta e o
  /// login biométrico foi ativado neste papel.
  Future<void> _checkBiometric() async {
    final bio = BiometricAuthService.instance;
    final available =
        await bio.isDeviceCapable && await bio.isEnabledFor('client');
    if (mounted && available) {
      setState(() => _biometricAvailable = true);
    }
  }

  /// L3 — digital/rosto → restaura a sessão Supabase guardada → entra.
  /// Fallback sempre disponível: os campos de palavra-passe continuam ali.
  Future<void> _biometricLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final bio = BiometricAuthService.instance;
    final authStore = context.read<AuthStore>();
    final messenger = ScaffoldMessenger.of(context);

    final ok =
        await bio.authenticate('Entra na Bora com a tua digital ou rosto');
    if (!mounted) return;
    if (!ok) {
      setState(() => _isProcessing = false);
      return;
    }

    final token = await bio.readRefreshToken('client');
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _biometricAvailable = false;
        _isProcessing = false;
      });
      return;
    }

    final error = await authStore.restoreSessionWithRefreshToken(
      token,
      expectedRole: 'client',
    );
    if (!mounted) return;

    if (error != null) {
      if (error == 'invalid') {
        await bio.disableFor('client');
      }
      if (!mounted) return;
      setState(() {
        if (error == 'invalid') _biometricAvailable = false;
        _isProcessing = false;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(error == 'invalid'
            ? 'Sessão biométrica expirada. Entra com a palavra-passe.'
            : 'Sem ligação. Tenta novamente.'),
      ));
      return;
    }

    // Mesmos passos pós-login do caminho com palavra-passe.
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null) {
      NotificationService.instance.saveTokenForClient(authUser.id).ignore();
    }

    await _finishClientLogin();
  }

  /// L1 — pré-preenche o campo de email com o último login bem-sucedido.
  Future<void> _prefillLastEmail() async {
    final remembered = await LoginPrefs.lastEmail('client');
    if (remembered == null || !mounted) return;
    setState(() {
      _emailController.text = remembered;
      _prefilledFromMemory = true;
    });
  }

  /// L1 — "Entrar com outra conta": limpa campos + esquece o email guardado.
  Future<void> _useAnotherAccount() async {
    await LoginPrefs.clearLastEmail('client');
    if (!mounted) return;
    setState(() {
      _prefilledFromMemory = false;
      _emailController.clear();
      _passwordController.clear();
    });
  }

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
            // L2 (2026-06-12) — AutofillGroup liga os campos ao gestor de
            // senhas do Android (Google Password Manager / Samsung Pass).
            child: AutofillGroup(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),

                // ── Logo ──────────────────────────────────────────────
                const Center(
                  child: BoraMascot(
                    variant: BoraMascotVariant.logo,
                    size: 72,
                    semanticLabel: 'BORA',
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
                Semantics(
                  identifier: 'fld_email',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
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
                ),
                if (_prefilledFromMemory)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed:
                          _isProcessing ? null : _useAnotherAccount,
                      child: const Text('Entrar com outra conta'),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),

                // ── Password ──────────────────────────────────────────
                Semantics(
                  identifier: 'fld_password',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Palavra-passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Informe a palavra-passe.';
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: Spacing.xxl + 4),

                // ── Login button ──────────────────────────────────────
                Semantics(
                  identifier: 'btn_entrar',
                  child: BoraPrimaryButton(
                    label: 'Entrar',
                    loading: _isProcessing,
                    onPressed: _submit,
                  ),
                ),
                // ── L3 — biometria ────────────────────────────────────
                if (_biometricAvailable) ...[
                  const SizedBox(height: Spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _biometricLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Entrar com biometria'),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.xs),

                // ── Forgot password ───────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: _isProcessing ? null : _forgotPassword,
                    child: const Text('Esqueci-me da palavra-passe'),
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
      ),
    );
  }

  void _backToRoles() {
    final sessionStore = context.read<SessionStore>();
    sessionStore.clearRole();
  }

  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();

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

    // L2 — sinaliza ao Android que o login terminou: dispara o prompt
    // "Guardar palavra-passe?" do gestor de senhas.
    TextInput.finishAutofillContext();

    // L1 — lembra o email para pré-preencher no próximo login.
    LoginPrefs.saveLastEmail('client', _emailController.text).ignore();

    // Persist FCM token for this client device so push notifications work.
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null) {
      NotificationService.instance.saveTokenForClient(authUser.id).ignore();
    }

    // L3 — oferece login biométrico (pergunta uma vez; antes do setRole
    // porque o _RootNavigator troca o ecrã assim que o papel muda).
    await maybeOfferBiometricEnrollment(context, 'client');
    if (!mounted) return;

    await _finishClientLogin();
  }

  /// Pós-login partilhado (palavra-passe + biometria). MULTI-PAPEL
  /// (2026-08-05): se `my_roles()` devolver mais do que um papel utilizável
  /// (ex.: mr.kebab@bora.app é parceiro E cliente), mostra o ecrã de escolha
  /// em vez de entrar direto como cliente.
  Future<void> _finishClientLogin() async {
    final sessionStore = context.read<SessionStore>();

    final roles = await fetchUiRoles();
    if (!mounted) return;

    if (roles.length >= 2) {
      setState(() => _isProcessing = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoleChoiceScreen(roles: roles)),
      );
      return;
    }

    await sessionStore.setRole(UserRole.client);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    // No Navigator call — RootNavigator reacts automatically.
  }
}
