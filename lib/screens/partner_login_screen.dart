import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/partner_appointments_store.dart';
import '../stores/restaurant_store.dart';
import '../services/biometric_auth_service.dart';
import '../services/login_prefs.dart';
import '../services/notification_service.dart';
import '../services/role_switch_helper.dart';
import '../stores/session_store.dart';
import '../widgets/biometric_enrollment_dialog.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'forgot_password_screen.dart';
import 'register_partner_screen.dart';
import 'role_choice_screen.dart';

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
  // L1 — true quando o email foi pré-preenchido com o último login.
  bool _prefilledFromMemory = false;

  // L3 — true quando o aparelho tem biometria E há sessão guardada.
  bool _biometricAvailable = false;
  // MULTI-PAPEL (2026-08-06) — quando `my_roles()` devolve 2+ papéis, o
  // ecrã de escolha é renderizado INLINE (não via Navigator.push): esta
  // tela é devolvida directamente por `PartnerEntryScreen`/`_RootNavigator`
  // (sem Navigator próprio), então um `pushReplacement` removeria o
  // `_RootNavigator` da árvore e travava a app depois de escolher o papel
  // (ver CLAUDE.md, "Navigation: _RootNavigator").
  List<Map<String, dynamic>>? _roleChoices;

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
        await bio.isDeviceCapable && await bio.isEnabledFor('partner');
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

    final token = await bio.readRefreshToken('partner');
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
      expectedRole: 'partner',
    );
    if (!mounted) return;

    if (error != null) {
      if (error == 'invalid') {
        await bio.disableFor('partner');
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

    final email = authStore.currentPartner?.email ?? '';
    if (email.isEmpty) {
      setState(() => _isProcessing = false);
      return;
    }
    await _finishPartnerLogin(email);
  }

  /// L1 — pré-preenche o campo de email com o último login bem-sucedido.
  Future<void> _prefillLastEmail() async {
    final remembered = await LoginPrefs.lastEmail('partner');
    if (remembered == null || !mounted) return;
    setState(() {
      _emailController.text = remembered;
      _prefilledFromMemory = true;
    });
  }

  /// L1 — "Entrar com outra conta": limpa campos + esquece o email guardado.
  Future<void> _useAnotherAccount() async {
    await LoginPrefs.clearLastEmail('partner');
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
    final roleChoices = _roleChoices;
    if (roleChoices != null) {
      return RoleChoiceScreen(roles: roleChoices);
    }
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Aceder como parceiro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: Form(
        key: _formKey,
        // L2 (2026-06-12) — AutofillGroup liga os campos ao gestor de
        // senhas do Android (Google Password Manager / Samsung Pass).
        child: AutofillGroup(
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
                autofillHints: const [AutofillHints.email],
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
              if (_prefilledFromMemory)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isProcessing ? null : _useAnotherAccount,
                    child: const Text('Entrar com outra conta'),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
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
              // ── L3 — biometria ──────────────────────────────────────
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
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _forgotPassword,
                  child: const Text('Esqueci-me da palavra-passe'),
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
              // AS TRÊS PORTAS IGUAIS (2026-08-29). O cliente e o estafeta
              // tinham este botão; o parceiro não, e quem lá caísse por engano
              // ficava sem saída à vista. Um cliente real caiu nas três portas
              // na mesma noite.
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _voltarAosPerfis,
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

  void _voltarAosPerfis() {
    context.read<SessionStore>().clearRole();
  }

  void _createAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegisterPartnerScreen(),
      ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _isProcessing = true);
    final authStore = context.read<AuthStore>();

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

    // L2 — sinaliza ao Android que o login terminou: dispara o prompt
    // "Guardar palavra-passe?" do gestor de senhas.
    TextInput.finishAutofillContext();

    // L1 — lembra o email para pré-preencher no próximo login.
    LoginPrefs.saveLastEmail('partner', _emailController.text).ignore();

    await _finishPartnerLogin(_emailController.text);
  }

  /// Pós-login partilhado (palavra-passe + biometria): resolve restaurante /
  /// service provider → FCM → opt-in biometria → setRole.
  Future<void> _finishPartnerLogin(String email) async {
    final authStore = context.read<AuthStore>();
    final restaurantStore = context.read<RestaurantStore>();
    final sessionStore = context.read<SessionStore>();
    final appointmentsStore = context.read<PartnerAppointmentsStore>();

    // Dono primeiro; o email da loja e so o recurso das lojas antigas
    // (ver a nota em partner_entry_screen).
    final restaurant = restaurantStore.restaurantByOwner(authStore.userId) ??
        restaurantStore.restaurantByEmail(email);
    if (restaurant != null) {
      authStore.setPartnerRestaurant(restaurant);

      // Persist FCM token for this partner device so push notifications work.
      NotificationService.instance.saveTokenForPartner(restaurant.id).ignore();
    } else {
      // No `restaurants` row. Two possibilities: (a) a Serviços/Barbearias
      // partner, whose home is the marcações hub (`service_providers`
      // record), or (b) a restaurant signup whose Edge Function call failed
      // after the auth account was already created (login works, but the
      // `restaurants` insert never happened). Rejecting login here used to
      // log the partner straight back out with a generic error — trapping
      // anyone in case (b), since they'd just log back in and hit the same
      // wall. Let both cases through: _RootNavigator → PartnerEntryScreen →
      // _PartnerNoRestaurantRouter resolves the marcações hub for (a) or the
      // registration wizard (already-authenticated resume, no email/senha
      // re-asked) for (b). Pre-warm the provider lookup here so
      // _PartnerNoRestaurantRouter's FutureBuilder resolves instantly
      // (loadMyProvider caches in the store) instead of showing a spinner.
      try {
        await appointmentsStore.loadMyProvider();
      } catch (_) {}
      // [Serviços 2026-07-28] Registo do token FCM TAMBÉM neste ramo. Até aqui
      // o parceiro só-serviços só era registado no initState do hub — quem
      // ficasse noutro ecrã (ou em análise) nunca aparecia em
      // `partner_push_tokens` e a Edge notify-service-provider não tinha
      // destino nenhum para o push de marcação. Verificado por SQL: 3 dos 5
      // prestadores tinham zero tokens.
      NotificationService.instance.savePushTokenForServicePartner().ignore();
      if (!mounted) return;
    }

    // L3 — oferece login biométrico (pergunta uma vez; antes do setRole
    // porque o _RootNavigator troca o ecrã assim que o papel muda).
    await maybeOfferBiometricEnrollment(context, 'partner');
    if (!mounted) return;

    // MULTI-PAPEL (2026-08-05): se `my_roles()` devolver mais do que um
    // papel utilizável (ex.: mr.kebab@bora.app é parceiro E cliente), mostra
    // o ecrã de escolha em vez de entrar direto como parceiro.
    final roles = await fetchUiRoles();
    if (!mounted) return;

    if (roles.length >= 2) {
      setState(() {
        _isProcessing = false;
        _roleChoices = roles;
      });
      return;
    }

    await sessionStore.setRole(UserRole.partner);

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (Navigator.canPop(context)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
