import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';

/// Ecrã "Esqueci-me da palavra-passe" — comum aos três papéis (cliente,
/// estafeta e parceiro). Pede o email e manda o Supabase enviar o link.
///
/// Regra de privacidade: a resposta é **sempre a mesma** quando o servidor
/// aceita o pedido, exista ou não a conta. Caso contrário este ecrã virava
/// um verificador de emails registados para quem o quisesse abusar.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// Email já escrito no ecrã de login, para não obrigar a repetir.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  bool _isProcessing = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final outcome =
        await context.read<AuthStore>().resetPassword(_emailController.text);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    switch (outcome) {
      case PasswordResetOutcome.ok:
        setState(() => _sent = true);
      case PasswordResetOutcome.rateLimited:
        _showError('Já pediu há pouco. Tente daqui a alguns minutos.');
      case PasswordResetOutcome.emailNotSent:
        _showError(
          'Não conseguimos enviar o email neste momento. '
          'Tente mais tarde ou fale connosco pelo apoio ao cliente.',
        );
      case PasswordResetOutcome.failed:
        _showError(
          'Não foi possível concluir o pedido. '
          'Verifique a ligação à internet e tente novamente.',
        );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl + 4,
            vertical: Spacing.xxl,
          ),
          child: _sent ? _buildSentState() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: BoraMascot(
              variant: BoraMascotVariant.logo,
              size: 72,
              semanticLabel: 'BORA',
            ),
          ),
          const SizedBox(height: Spacing.xxl + 4),
          const Text(
            'Esqueceu-se da palavra-passe?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.xs + 2),
          const Text(
            'Indique o email da sua conta Bora. Enviamos-lhe uma ligação '
            'para definir uma palavra-passe nova.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.xxl + 4),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isProcessing ? null : _submit(),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final email = (value ?? '').trim();
              if (email.isEmpty) return 'Indique o seu email.';
              if (!email.contains('@') || !email.contains('.')) {
                return 'Email inválido.';
              }
              return null;
            },
          ),
          const SizedBox(height: Spacing.xxl + 4),
          BoraPrimaryButton(
            label: 'Enviar ligação',
            loading: _isProcessing,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.xxl),
        const Center(
          child: Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        const Text(
          'Verifique o seu email',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        const Text(
          'Se este email estiver registado, enviámos-lhe uma ligação para '
          'definir uma palavra-passe nova. A ligação é válida durante 1 hora.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        const Text(
          'Não recebeu? Confirme a pasta de spam antes de pedir outra vez.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: Spacing.xxl + 4),
        BoraPrimaryButton(
          label: 'Voltar a entrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: Spacing.xs),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _sent = false),
            child: const Text('Usar outro email'),
          ),
        ),
      ],
    );
  }
}
