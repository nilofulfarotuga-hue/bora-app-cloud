import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/notification_service.dart';
import '../stores/driver_store.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'driver_pending_screen.dart';
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
    text: kDebugMode ? 'driver@bora.app' : '',
  );
  final _passwordController = TextEditingController(
    text: kDebugMode ? '123456' : '',
  );
  bool _isProcessing = false;
  bool _obscurePassword = true;
  bool _hasPendingDraft = false;

  static const _kDraftKey = 'bora_app.signup_draft.driver';

  @override
  void initState() {
    super.initState();
    _checkPendingDraft();
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
                    if (!value.contains('@')) return 'Email inválido.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

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

                const SizedBox(height: 28),

                // ── Login button ──────────────────────────────────────
                BoraPrimaryButton(
                  label: 'Entrar',
                  loading: _isProcessing,
                  color: AppColors.accent,
                  onPressed: _submit,
                ),
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
                    child: const Text('Esqueci a palavra-passe'),
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
      authStore.logout();
      setState(() => _isProcessing = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
      );
      return;
    }

    if (approvalStatus == 'rejected') {
      final reason = driverRow?['rejection_reason'] as String? ?? '';
      authStore.logout();
      setState(() => _isProcessing = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DriverRejectedScreen(reason: reason)),
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────────────

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
              Text('Introduza o seu email no campo acima antes de continuar.'),
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
}
