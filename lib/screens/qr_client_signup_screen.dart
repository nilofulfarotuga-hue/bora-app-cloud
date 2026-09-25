import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../stores/session_store.dart';
import 'register_client_screen.dart';

/// BLOCO D (2026-07-28) — destino dos QR codes impressos.
///
/// URL canónica (JÁ IMPRESSA — **não mudar**):
/// `https://bora-app-web.pages.dev/#/registo-cliente`
///
/// Quem lê o cartaz é cliente, por isso cai directo no formulário de registo
/// de CLIENTE, sem passar pelo ecrã "sou cliente / estafeta / parceiro".
/// Se já houver sessão iniciada, redirecciona para a home do cliente em vez
/// de mostrar o registo.
class QrClientSignupScreen extends StatefulWidget {
  const QrClientSignupScreen({super.key});

  /// Nome da rota. Constante única — o QR aponta para aqui.
  static const String routeName = '/registo-cliente';

  @override
  State<QrClientSignupScreen> createState() => _QrClientSignupScreenState();
}

class _QrClientSignupScreenState extends State<QrClientSignupScreen> {
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRedirect());
  }

  Future<void> _maybeRedirect() async {
    if (!mounted) return;
    final auth = context.read<AuthStore>();
    if (auth.currentClient == null) return;
    setState(() => _redirecting = true);
    // Garante o papel de cliente e devolve o controlo ao _RootNavigator, que
    // rende a ClientMainScreen sozinho (padrão widget-rebuild do main.dart —
    // nunca navegar à mão para a home).
    await context.read<SessionStore>().setRole(UserRole.client);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_redirecting) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    return const RegisterClientScreen();
  }
}
