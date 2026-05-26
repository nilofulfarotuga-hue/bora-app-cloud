import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'client_login_screen.dart';
import 'welcome_address_screen.dart';

/// Sessão 2026-05-26 — refactor signup cliente alinhado com Uber/Glovo:
/// - Foto opcional REMOVIDA (causa de Activity recreation crash em Samsung A36).
///   Foto pode ser adicionada depois em ProfileScreen.
/// - Draft persistence (SharedPreferences) — sobrevive a kill do processo.
/// - Apple/Google Sign-In skeleton atrás de feature flag SOCIAL_AUTH_ENABLED.
/// - Após signup OK → navega para WelcomeAddressScreen (morada opcional).
class RegisterClientScreen extends StatefulWidget {
  const RegisterClientScreen({super.key});

  @override
  State<RegisterClientScreen> createState() => _RegisterClientScreenState();
}

class _RegisterClientScreenState extends State<RegisterClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  static const _kDraftKey = 'bora_app.signup_draft.client';

  /// Feature flag — quando true, mostra botões "Continuar com Google/Apple".
  /// Activação requer config externa (Apple Developer + Google Cloud +
  /// Supabase Auth providers). Ver docs/SIGNUP_SOCIAL_SETUP.md.
  static const bool _socialAuthEnabled =
      bool.fromEnvironment('SOCIAL_AUTH_ENABLED');

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  void _saveDraft() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('$_kDraftKey.name', _nameController.text);
      prefs.setString('$_kDraftKey.email', _emailController.text);
      prefs.setString('$_kDraftKey.phone', _phoneController.text);
      prefs.setString('$_kDraftKey.referral', _referralCodeController.text);
    });
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final name = prefs.getString('$_kDraftKey.name') ?? '';
    final email = prefs.getString('$_kDraftKey.email') ?? '';
    final phone = prefs.getString('$_kDraftKey.phone') ?? '';
    final referral = prefs.getString('$_kDraftKey.referral') ?? '';
    if (name.isEmpty && email.isEmpty && phone.isEmpty && referral.isEmpty) {
      return;
    }
    setState(() {
      if (name.isNotEmpty) _nameController.text = name;
      if (email.isNotEmpty) _emailController.text = email;
      if (phone.isNotEmpty) _phoneController.text = phone;
      if (referral.isNotEmpty) _referralCodeController.text = referral;
    });
  }

  void _clearDraft() {
    SharedPreferences.getInstance().then((prefs) {
      for (final key in ['name', 'email', 'phone', 'referral']) {
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
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text('Criar conta'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.xxl,
              Spacing.sm,
              Spacing.xxl,
              Spacing.xxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'BORA',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'A tua app de entregas',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),

                if (_socialAuthEnabled) ...[
                  _SocialAuthButton(
                    icon: Icons.apple,
                    label: 'Continuar com Apple',
                    onPressed: _isSubmitting ? null : _signInWithApple,
                  ),
                  const SizedBox(height: 12),
                  _SocialAuthButton(
                    icon: Icons.g_mobiledata_rounded,
                    label: 'Continuar com Google',
                    onPressed: _isSubmitting ? null : _signInWithGoogle,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: Colors.grey.shade300),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Spacing.md),
                        child: Text(
                          'ou regista-te por email',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: Colors.grey.shade300),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o seu nome.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Informe o seu email.';
                    }
                    if (!v.contains('@')) return 'Email inválido.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telemóvel',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o seu telemóvel.'
                      : null,
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
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Mínimo 6 caracteres.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmar palavra-passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) {
                      return 'As palavras-passe não coincidem.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _referralCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código de convite (opcional)',
                    hintText: 'Ex: BORA-ABC-1234',
                    prefixIcon: Icon(Icons.card_giftcard_outlined),
                  ),
                  onChanged: (_) => _saveDraft(),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _acceptedTerms,
                  onChanged: _isSubmitting
                      ? null
                      : (v) => setState(() => _acceptedTerms = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.accent,
                  title: const TermsLinkText(),
                ),
                const SizedBox(height: 16),
                BoraPrimaryButton(
                  label: 'Criar conta',
                  loading: _isSubmitting,
                  color: AppColors.primary,
                  onPressed: _acceptedTerms ? _submit : null,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Já tenho conta?',
                        style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ClientLoginScreen(),
                        ),
                      ),
                      child: const Text(
                        'Iniciar sessão',
                        style: TextStyle(
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithApple() async {
    // TODO(activate): Apple Sign-In requer:
    //  1. Apple Developer: Sign In with Apple capability enabled
    //  2. Service ID + Key + Domain registado
    //  3. Supabase Auth → Apple provider configurado com client_id + secret JWT
    //  4. iOS: adicionar Sign In with Apple ao Runner.entitlements
    //  5. Android: deeplink redirect URI configurado
    //  Ver docs/SIGNUP_SOCIAL_SETUP.md
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apple Sign-In — em configuração.')),
    );
  }

  Future<void> _signInWithGoogle() async {
    // TODO(activate): Google Sign-In requer:
    //  1. Google Cloud: OAuth 2.0 Client IDs (Android + iOS + Web)
    //  2. SHA-1 fingerprint do keystore release (já existe — ver project_keystore_release_2026_05_20)
    //  3. Supabase Auth → Google provider configurado com client_id + secret
    //  4. Adicionar package google_sign_in: ^6.x ao pubspec.yaml
    //  5. iOS: GIDClientID em Info.plist
    //  Ver docs/SIGNUP_SOCIAL_SETUP.md
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google Sign-In — em configuração.')),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    final error = await authStore.registerClientAsync(
      name: name,
      email: email,
      phone: phone,
      password: password,
      consentAcceptedAt: DateTime.now().toUtc(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _isSubmitting = false);
      final msg = error.contains('already registered')
          ? 'Este email já está registado.'
          : error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    // Código de convite (opcional). Falha não bloqueia signup.
    final referralCode = _referralCodeController.text.trim().toUpperCase();
    if (referralCode.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'client_register_with_referral',
          params: {'p_referral_code': referralCode},
        );
      } catch (e) {
        debugPrint('[Referral] Erro ao registar código "$referralCode": $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Código de convite inválido ou expirado — conta criada à mesma.'),
            ),
          );
        }
      }
    }

    await sessionStore.setRole(UserRole.client);
    _clearDraft();

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // Navega para WelcomeAddressScreen — morada opcional + onboarding tooltip.
    // Após WelcomeAddressScreen, _RootNavigator detecta currentClient != null
    // e renderiza ClientMainScreen.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WelcomeAddressScreen()),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: Colors.black87),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
