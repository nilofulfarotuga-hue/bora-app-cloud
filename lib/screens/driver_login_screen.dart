import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/biometric_auth_service.dart';
import '../services/login_prefs.dart';
import '../services/notification_service.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import '../widgets/biometric_enrollment_dialog.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'driver_pending_screen.dart';
import 'forgot_password_screen.dart';
import 'driver_rejected_screen.dart';
import 'driver_signup_screen.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(
    text: '',
  );
  final _passwordController = TextEditingController(
    text: '',
  );
  bool _isProcessing = false;
  bool _obscurePassword = true;
  bool _hasPendingDraft = false;
  // L1 — true quando o email foi pré-preenchido com o último login.
  bool _prefilledFromMemory = false;

  static const _kDraftKey = 'bora_app.signup_draft.driver';

  // L3 — true quando o aparelho tem biometria E há sessão guardada.
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkPendingDraft();
    _prefillLastEmail();
    _checkBiometric();
  }

  /// L3 — mostra o botão "Entrar com biometria" se o aparelho suporta e o
  /// login biométrico foi ativado neste papel.
  Future<void> _checkBiometric() async {
    final bio = BiometricAuthService.instance;
    final available =
        await bio.isDeviceCapable && await bio.isEnabledFor('driver');
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

    final token = await bio.readRefreshToken('driver');
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
      expectedRole: 'driver',
    );
    if (!mounted) return;

    if (error != null) {
      if (error == 'invalid') {
        await bio.disableFor('driver');
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

    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) {
      setState(() => _isProcessing = false);
      return;
    }

    debugPrint('[DriverLogin] biometric restore OK uid=${authUser.id}');
    await _finishDriverLogin(authUser);
  }

  /// L1 — pré-preenche o campo de email com o último login bem-sucedido.
  Future<void> _prefillLastEmail() async {
    final remembered = await LoginPrefs.lastEmail('driver');
    if (remembered == null || !mounted) return;
    setState(() {
      _emailController.text = remembered;
      _prefilledFromMemory = true;
    });
  }

  /// L1 — "Entrar com outra conta": limpa campos + esquece o email guardado.
  Future<void> _useAnotherAccount() async {
    await LoginPrefs.clearLastEmail('driver');
    if (!mounted) return;
    setState(() {
      _prefilledFromMemory = false;
      _emailController.clear();
      _passwordController.clear();
    });
  }

  Future<void> _checkPendingDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('$_kDraftKey.name') ?? '';
    if (name.isNotEmpty && mounted) {
      setState(() => _hasPendingDraft = true);
    }
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
                if (_hasPendingDraft)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _goToSignup,
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(Icons.edit_note, color: AppColors.accent),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tens uma candidatura em progresso. Continuar?',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 32),

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
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Área do Estafeta',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // ── Title ─────────────────────────────────────────────
                const Text(
                  'Entrar como estafeta',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use o email e palavra-passe da sua conta.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),

                const SizedBox(height: 28),

                // ── Email ─────────────────────────────────────────────
                Semantics(
                  identifier: 'fld_email',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o email.';
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
                const SizedBox(height: 16),

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

                const SizedBox(height: 28),

                // ── Login button ──────────────────────────────────────
                Semantics(
                  identifier: 'btn_entrar_driver',
                  child: BoraPrimaryButton(
                    label: 'Entrar',
                    loading: _isProcessing,
                    color: AppColors.accent,
                    onPressed: _submit,
                  ),
                ),
                // ── L3 — biometria ────────────────────────────────────
                if (_biometricAvailable) ...[
                  const SizedBox(height: Spacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _biometricLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Entrar com biometria'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),

                // ── Create account ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _goToSignup,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(
                          color: AppColors.accent, width: 1.5),
                    ),
                    child: const Text('Criar conta'),
                  ),
                ),

                const SizedBox(height: Spacing.md),
                Center(
                  child: TextButton(
                    onPressed: _isProcessing ? null : _forgotPassword,
                    child: const Text('Esqueci-me da palavra-passe'),
                  ),
                ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final authStore = context.read<AuthStore>();

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

    // L2 — sinaliza ao Android que o login terminou: dispara o prompt
    // "Guardar palavra-passe?" do gestor de senhas.
    TextInput.finishAutofillContext();

    // L1 — lembra o email para pré-preencher no próximo login.
    LoginPrefs.saveLastEmail('driver', _emailController.text).ignore();

    // Guard: confirm that Supabase session is the real driver, not a guest
    // fallback. loginDriverAsync always calls signInWithPassword, but this
    // double-check prevents any race where the session was overwritten.
    final authUser = Supabase.instance.client.auth.currentUser;
    final authMeta = authUser?.userMetadata ?? {};
    final isRealDriver = authUser != null && authMeta['bora_role'] == 'driver';

    if (!isRealDriver) {
      debugPrint(
          '[DriverLogin] auth.currentUser is not a real driver — aborting. uid=${authUser?.id}');
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de autenticação. Tente novamente.')),
      );
      return;
    }

    debugPrint('[DriverLogin] auth.currentUser.id=${authUser.id}');

    await _finishDriverLogin(authUser);
  }

  /// Pós-login partilhado (palavra-passe + biometria): approval gate →
  /// configura DriverStore → FCM → opt-in biometria → setRole.
  Future<void> _finishDriverLogin(User authUser) async {
    final authStore = context.read<AuthStore>();
    final driverStore = context.read<DriverStore>();
    final sessionStore = context.read<SessionStore>();

    // ── Verificar approval_status ────────────────────────────────────────
    Map<String, dynamic>? driverRow;
    try {
      driverRow = await Supabase.instance.client
          .from('drivers')
          .select('approval_status, rejection_reason')
          .eq('id', authUser.id)
          .maybeSingle();
    } catch (_) {}

    if (!mounted) return;

    final approvalStatus =
        driverRow?['approval_status'] as String? ?? 'approved';

    if (approvalStatus == 'pending') {
      // L3 — bounce de aprovação, não "Sair": preserva biometria.
      authStore.logout(wipeBiometrics: false);
      setState(() => _isProcessing = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
      );
      return;
    }

    if (approvalStatus == 'rejected') {
      final reason = driverRow?['rejection_reason'] as String? ?? '';
      // L3 — bounce de aprovação, não "Sair": preserva biometria.
      authStore.logout(wipeBiometrics: false);
      setState(() => _isProcessing = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DriverRejectedScreen(reason: reason)),
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────────────

    // L3 — o restauro biométrico não passa por loginDriverAsync, por isso
    // _currentDriverStatus ficaria no default 'pending' e o driver_home
    // mostrava o ecrã de análise a um estafeta aprovado. Idempotente no
    // caminho com palavra-passe.
    await authStore.refreshApprovalStatus();
    if (!mounted) return;

    final account = authStore.currentDriver;
    if (account != null) {
      driverStore.configurePrimaryDriver(
        name: account.name,
        phone: account.phone,
        vehicleType: account.vehicleType,
        licensePlate: account.licensePlate,
        driverId: authUser.id,
      );
    }

    // Persist FCM token so the dispatch engine can notify this driver via push.
    // Fire-and-forget: non-critical, must not block navigation.
    NotificationService.instance.saveTokenForDriver(authUser.id);

    // L3 — oferece login biométrico (pergunta uma vez; antes do setRole
    // porque o _RootNavigator troca o ecrã assim que o papel muda).
    await maybeOfferBiometricEnrollment(context, 'driver');
    if (!mounted) return;

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

  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }
}
