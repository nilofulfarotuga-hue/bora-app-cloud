import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/multi_role_signup.dart';
import '../stores/session_store.dart';
import '../utils/contact_validators.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/terms_link_text.dart';
import 'client_login_screen.dart';
import 'welcome_address_screen.dart';

import '../l10n/tr.dart';

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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Text('Criar conta'.tr),
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
                const BoraMascot(
                  variant: BoraMascotVariant.logo,
                  size: 56,
                  semanticLabel: 'BORA',
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'A tua app de entregas'.tr,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSubtle),
                ),
                const SizedBox(height: 24),

                if (_socialAuthEnabled) ...[
                  _SocialAuthButton(
                    icon: Icons.apple,
                    label: 'Continuar com Apple'.tr,
                    onPressed: _isSubmitting ? null : _signInWithApple,
                  ),
                  const SizedBox(height: 12),
                  _SocialAuthButton(
                    icon: Icons.g_mobiledata_rounded,
                    label: 'Continuar com Google'.tr,
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
                          'ou regista-te por email'.tr,
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
                  decoration: InputDecoration(
                    labelText: 'Nome completo'.tr,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) => validarNomeCliente(v)?.tr,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email'.tr,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Informe o seu email.'.tr;
                    }
                    if (!v.contains('@')) return 'Email inválido.'.tr;
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telemóvel'.tr,
                    prefixIcon: const Icon(Icons.phone_rounded),
                  ),
                  onChanged: (_) => _saveDraft(),
                  validator: (v) => validarTelemovelPt(v)?.tr,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Palavra-passe'.tr,
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
                      ? 'Mínimo 6 caracteres.'.tr
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmar palavra-passe'.tr,
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
                      return 'As palavras-passe não coincidem.'.tr;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _referralCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Código de convite (opcional)'.tr,
                    hintText: 'Ex: BORA-ABC-1234'.tr,
                    prefixIcon: const Icon(Icons.card_giftcard_outlined),
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
                  label: 'Criar conta'.tr,
                  loading: _isSubmitting,
                  color: AppColors.primary,
                  onPressed: _acceptedTerms ? _submit : null,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Já tenho conta?'.tr,
                        style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ClientLoginScreen(),
                        ),
                      ),
                      child: Text(
                        'Iniciar sessão'.tr,
                        style: const TextStyle(
                            color: AppColors.accent,
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
      SnackBar(content: Text('Apple Sign-In — em configuração.'.tr)),
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
      SnackBar(content: Text('Google Sign-In — em configuração.'.tr)),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    // Grava sempre os 9 dígitos nacionais: o mesmo número escrito como
    // "+351 912 345 678" ou "912345678" tem de dar a MESMA ficha.
    final phone = normalizarTelemovelPt(_phoneController.text) ??
        _phoneController.text.trim();

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
      // MULTI-PAPEL (2026-07-31): estafeta/parceiro que também quer ser
      // cliente. Pede a palavra-passe, autentica e acrescenta só o papel de
      // cliente (não precisa de aprovação nem de linha em tabela nenhuma).
      if (isEmailAlreadyRegistered(error)) {
        final outcome = await promptSignInToAddProfile(
          context: context,
          email: email,
          perfil: 'cliente',
        );
        if (!mounted) return;
        if (outcome != ExistingAccountOutcome.signedIn) {
          setState(() => _isSubmitting = false);
          return; // Nunca criar perfil sem autenticar.
        }
        try {
          await Supabase.instance.client.rpc('add_client_role_to_me');
        } catch (e) {
          debugPrint('add_client_role_to_me falhou => $e');
        }
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }

    // Código (opcional). Falha nunca bloqueia o signup.
    //
    // O campo aceita DOIS tipos de código e o utilizador não tem de saber a
    // diferença: código de amigo (referral) e código promocional (ex.: o
    // BEMVINDO da publicidade). Tenta-se primeiro o referral; se o código não
    // existir nessa tabela, tenta-se o promocional antes de desistir.
    final referralCode = _referralCodeController.text.trim().toUpperCase();
    if (referralCode.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'client_register_with_referral',
          params: {'p_referral_code': referralCode},
        );
      } catch (e) {
        debugPrint('[Referral] "$referralCode" não é código de amigo => $e');
        if (e.toString().contains('invalid_referral_code')) {
          await _tentarCodigoPromocional(referralCode);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Código de convite inválido ou expirado — conta criada à mesma.'.tr),
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

  /// Segunda tentativa para o código escrito no registo: código promocional.
  ///
  /// Usa a MESMA RPC do ecrã "Tenho um código" (Perfil) — não há aqui nenhuma
  /// lógica de crédito de tokens, só a chamada. Falha nunca bloqueia o signup.
  Future<void> _tentarCodigoPromocional(String codigo) async {
    try {
      final res = await Supabase.instance.client
          .rpc('client_redeem_promo_tokens', params: {'p_code': codigo});
      if (!mounted) return;

      final m = res is Map ? res.cast<String, dynamic>() : const <String, dynamic>{};
      if ((m['valid'] as bool?) ?? false) {
        final tokens = (m['tokens_granted'] as num?)?.toInt() ?? 0;
        final euros = (m['euro_value'] as num?)?.toDouble() ?? (tokens * 0.005);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recebeste {0} tokens (≈€{1}) — já estão na tua conta.'.trArgs([tokens, euros.toStringAsFixed(2)])),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_motivoEmPortugues(m['reason'] as String?))),
      );
    } catch (e) {
      debugPrint('[Promo] "$codigo" falhou => $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível usar o código — conta criada à mesma.'.tr),
          ),
        );
      }
    }
  }

  String _motivoEmPortugues(String? motivo) {
    switch (motivo) {
      case 'not_found':
        return 'Código não encontrado — conta criada à mesma.'.tr;
      case 'already_used':
        return 'Já tinhas usado este código — conta criada à mesma.'.tr;
      case 'expired':
        return 'Código expirado — conta criada à mesma.'.tr;
      case 'inactive':
        return 'Código já não está activo — conta criada à mesma.'.tr;
      case 'max_uses_reached':
        return 'Este código atingiu o limite de utilizações — conta criada à mesma.'.tr;
      default:
        return 'Não foi possível usar o código — conta criada à mesma.'.tr;
    }
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
