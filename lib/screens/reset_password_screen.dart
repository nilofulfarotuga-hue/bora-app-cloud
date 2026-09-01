import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/auth_links.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'forgot_password_screen.dart';

import '../l10n/tr.dart';

/// Ecrã de definição da nova palavra-passe. Serve os dois caminhos por onde o
/// utilizador pode aqui chegar:
///
///  * **Web** — o link do email abre `…/#/redefinir-palavra-passe` no browser.
///    O token vem na própria URL e é este ecrã que o troca por uma sessão.
///  * **Telemóvel** — o deep link legado `pt.boraapp.bora://reset-password`
///    faz o SDK emitir `AuthChangeEvent.passwordRecovery`; quando o `main.dart`
///    empurra este ecrã já existe sessão de recovery e não há nada a trocar.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  static const String routeName = passwordResetRouteName;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _LinkState { resolving, ready, invalid }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isProcessing = false;
  bool _done = false;

  _LinkState _linkState = _LinkState.resolving;
  String _invalidMessage = '';

  /// [Bloco 7, 30/08] Fluxo `token_hash` (à prova de prefetch): o link do email
  /// traz `?token_hash=…&type=recovery` e NÃO passa pelo `/verify` de uso
  /// único. Guardamos o hash e só o trocamos por sessão (`verifyOTP`) quando a
  /// pessoa carrega em "Guardar" — um prefetch do Gmail ou um duplo clique já
  /// não gastam o link (caso real de 30/08: o `/verify` foi consumido às
  /// 10:38:58 antes de a pessoa sequer ver o ecrã, e os cliques seguintes
  /// davam 403 "One-time token not found").
  String? _tokenHash;

  @override
  void initState() {
    super.initState();
    _resolveRecoverySession();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Descobre se temos uma sessão de recovery válida.
  ///
  /// O Supabase devolve o token de formas diferentes conforme o fluxo:
  ///  * PKCE — `?code=…` na query string;
  ///  * implícito — `#access_token=…&refresh_token=…` no fragmento;
  ///  * erro (link expirado ou já usado) — `#error=…&error_code=…`.
  ///
  /// Como o `redirectTo` já leva um fragmento (`#/redefinir-palavra-passe`), o
  /// Supabase acrescenta o dele a seguir e a URL fica com dois `#`. Por isso a
  /// leitura é feita à mão a partir de `Uri.base` em vez de confiar só no
  /// router do Flutter.
  Future<void> _resolveRecoverySession() async {
    final auth = Supabase.instance.client.auth;

    // Caminho do telemóvel: o SDK já criou a sessão a partir do deep link.
    if (auth.currentSession != null) {
      setState(() => _linkState = _LinkState.ready);
      return;
    }

    final params = _paramsFromUrl();

    final errorCode = params['error_code'] ?? params['error'];
    if (errorCode != null) {
      setState(() {
        _linkState = _LinkState.invalid;
        _invalidMessage = _messageForErrorCode(errorCode);
      });
      return;
    }

    // [Bloco 7] Link novo com `token_hash`: não se troca nada agora — o link
    // só é gasto no "Guardar" (verifyOTP). Mostrar já os dois campos.
    final tokenHash = params['token_hash'];
    if (tokenHash != null && tokenHash.isNotEmpty) {
      _tokenHash = tokenHash;
      setState(() => _linkState = _LinkState.ready);
      return;
    }

    try {
      final code = params['code'];
      final refreshToken = params['refresh_token'];

      if (code != null && code.isNotEmpty) {
        await auth.exchangeCodeForSession(code);
      } else if (refreshToken != null && refreshToken.isNotEmpty) {
        await auth.setSession(refreshToken);
      } else {
        setState(() {
          _linkState = _LinkState.invalid;
          _invalidMessage =
              'Esta ligação não é válida. Peça uma nova ligação para redefinir a palavra-passe.'.tr;
        });
        return;
      }

      if (!mounted) return;
      setState(() => _linkState = _LinkState.ready);
    } catch (e) {
      debugPrint('ResetPasswordScreen: troca de token falhou => $e');
      if (!mounted) return;
      setState(() {
        _linkState = _LinkState.invalid;
        _invalidMessage =
            'Esta ligação expirou ou já foi utilizada. As ligações de recuperação são válidas durante 1 hora e só podem ser usadas uma vez.'.tr;
      });
    }
  }

  /// Junta os parâmetros da query string e do(s) fragmento(s) da URL actual.
  Map<String, String> _paramsFromUrl() {
    final uri = Uri.base;
    final params = <String, String>{...uri.queryParameters};

    // O fragmento pode ser só a rota (`/redefinir-palavra-passe`), ou a rota
    // seguida do fragmento do Supabase (`/rota#access_token=…`).
    var fragment = uri.fragment;
    final secondHash = fragment.indexOf('#');
    if (secondHash >= 0) {
      fragment = fragment.substring(secondHash + 1);
    } else if (fragment.startsWith('/')) {
      // Só a rota, sem token — pode ainda haver `?code=` dentro do fragmento.
      final queryStart = fragment.indexOf('?');
      fragment = queryStart >= 0 ? fragment.substring(queryStart + 1) : '';
    }

    if (fragment.isNotEmpty) {
      params.addAll(Uri.splitQueryString(fragment));
    }
    return params;
  }

  String _messageForErrorCode(String code) {
    if (code.contains('expired')) {
      return 'Esta ligação expirou. As ligações de recuperação são válidas durante 1 hora — peça uma nova.'.tr;
    }
    return 'Esta ligação já não pode ser usada. Peça uma nova ligação para redefinir a palavra-passe.'.tr;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final auth = Supabase.instance.client.auth;
      // [Bloco 7] Fluxo token_hash: é AGORA, no toque em "Guardar", que o link
      // se gasta — verifyOTP troca o hash por uma sessão de recuperação. Se o
      // hash já tiver sido usado/expirado, cai no catch e o ecrã diz como
      // pedir um email novo.
      if (_tokenHash != null && auth.currentSession == null) {
        await auth.verifyOTP(
          type: OtpType.recovery,
          tokenHash: _tokenHash,
        );
      }
      await auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      // Termina a sessão de recovery — o utilizador volta a entrar com a
      // palavra-passe nova pelo ecrã de login normal.
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      // [Bloco 7] Link gasto/expirado detetado no verifyOTP: em vez de um
      // snackbar solto, o ecrã inteiro passa a "Ligação inválida" com o botão
      // "Pedir nova ligação" — a pessoa sabe logo o que fazer.
      if (_tokenHash != null && _isSpentLinkError(e)) {
        setState(() {
          _isProcessing = false;
          _linkState = _LinkState.invalid;
          _invalidMessage =
              'Esta ligação expirou ou já foi utilizada. Peça um email novo para redefinir a palavra-passe.'.tr;
        });
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_submitErrorMessage(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// O verifyOTP devolve estes erros quando o token_hash já não serve.
  bool _isSpentLinkError(Object e) {
    if (e is! AuthException) return false;
    final msg = e.message.toLowerCase();
    return msg.contains('expired') ||
        msg.contains('not found') ||
        msg.contains('invalid') ||
        (e.code ?? '').contains('otp');
  }

  String _submitErrorMessage(Object e) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('should be different') ||
          msg.contains('same as the old')) {
        return 'A nova palavra-passe tem de ser diferente da anterior.'.tr;
      }
      if (msg.contains('expired') || msg.contains('session')) {
        return 'A sessão de recuperação expirou. Peça uma nova ligação.'.tr;
      }
      if (msg.contains('weak') || msg.contains('at least')) {
        return 'Escolha uma palavra-passe mais forte (mínimo 6 caracteres).'.tr;
      }
    }
    return 'Não foi possível alterar a palavra-passe. Tente novamente.'.tr;
  }

  void _pedirNovaLigacao() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  void _voltarAoLogin() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // Web: este ecrã é a raiz (veio do link do email).
      Navigator.of(context).pushNamedAndRemoveUntil('/role', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Na web o ecrã é largo; sem isto os campos esticavam de ponta a
            // ponta do monitor.
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xxl + 4,
                vertical: Spacing.xxl,
              ),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_linkState) {
      case _LinkState.resolving:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: Center(child: CircularProgressIndicator()),
        );
      case _LinkState.invalid:
        return _buildInvalid();
      case _LinkState.ready:
        return _done ? _buildDone() : _buildForm();
    }
  }

  Widget _buildInvalid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Center(
          child: BoraMascot(
            variant: BoraMascotVariant.logo,
            size: 72,
            semanticLabel: 'BORA',
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        const Icon(Icons.link_off, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: Spacing.lg),
        Text(
          'Ligação inválida'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          _invalidMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: Spacing.xxl + 4),
        BoraPrimaryButton(
          label: 'Pedir nova ligação'.tr,
          onPressed: _pedirNovaLigacao,
        ),
        const SizedBox(height: Spacing.xs),
        Center(
          child: TextButton(
            onPressed: _voltarAoLogin,
            child: Text('Voltar a entrar'.tr),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Center(
          child: Icon(Icons.check_circle_outline,
              size: 72, color: AppColors.primary),
        ),
        const SizedBox(height: Spacing.xxl),
        Text(
          'Palavra-passe alterada'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'Já pode entrar na sua conta Bora com a palavra-passe nova.'.tr,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: Spacing.xxl + 4),
        BoraPrimaryButton(
          label: 'Entrar'.tr,
          onPressed: _voltarAoLogin,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          const Center(
            child: BoraMascot(
              variant: BoraMascotVariant.logo,
              size: 72,
              semanticLabel: 'BORA',
            ),
          ),
          const SizedBox(height: Spacing.xxl + 4),
          Text(
            'Nova palavra-passe'.tr,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.xs + 2),
          Text(
            'Defina a nova palavra-passe da sua conta Bora. Mínimo 6 caracteres.'.tr,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.xxl + 4),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Nova palavra-passe'.tr,
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
                return 'Informe a nova palavra-passe.'.tr;
              }
              if (value.length < 6) return 'Mínimo 6 caracteres.'.tr;
              return null;
            },
          ),
          const SizedBox(height: Spacing.lg),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Confirmar palavra-passe'.tr,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'As palavras-passe não coincidem.'.tr;
              }
              return null;
            },
          ),
          const SizedBox(height: Spacing.xxl + 4),
          BoraPrimaryButton(
            label: 'Guardar nova palavra-passe'.tr,
            loading: _isProcessing,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
