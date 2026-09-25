/// MULTI-PAPEL (2026-07-31) — o mesmo email pode ser cliente + estafeta +
/// parceiro.
///
/// Antes, qualquer registo com um email já existente rebentava com
/// `"User already registered"` e o utilizador ficava preso. Agora pedimos a
/// palavra-passe, autenticamos, e o fluxo segue para criar apenas a linha do
/// papel em falta (`drivers` / `restaurants` / `service_providers` /
/// `cleaners`). O papel em si é atribuído pelo servidor
/// (trigger `trg_grant_role_*` → `user_roles`).
///
/// SEGURANÇA — dois pontos que não se negoceiam:
///  1. NUNCA criar um perfil sem autenticar. Sem `signIn` com sucesso, o
///     fluxo pára.
///  2. NUNCA revelar, num ecrã não autenticado, se um email existe. Este
///     diálogo só aparece DEPOIS de o `signUp` ter falhado com
///     "already registered" — ou seja, para quem escreveu o email nesse
///     momento — e a mensagem de erro de palavra-passe errada é a mesma quer
///     a conta exista quer não ("Email ou palavra-passe incorretos.").
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/auth_links.dart';

/// A conta já existia e o utilizador autenticou-se com sucesso?
enum ExistingAccountOutcome {
  /// Autenticado — o chamador pode criar a linha do papel em falta.
  signedIn,

  /// Cancelou ou falhou a autenticação — não criar nada.
  aborted,
}

/// True quando o erro do `signUp` significa "este email já tem conta".
bool isEmailAlreadyRegistered(Object error) {
  final msg = error is AuthException
      ? error.message.toLowerCase()
      : error.toString().toLowerCase();
  return msg.contains('already registered') ||
      msg.contains('user already') ||
      msg.contains('already been registered');
}

/// Pede a palavra-passe da conta existente e autentica.
///
/// [perfil] é o papel que está a ser adicionado, em PT-PT e minúsculas
/// ("estafeta", "parceiro", "cliente") — entra na frase do diálogo.
Future<ExistingAccountOutcome> promptSignInToAddProfile({
  required BuildContext context,
  required String email,
  required String perfil,
}) async {
  final ctrl = TextEditingController();
  var busy = false;
  String? erro;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Já tens conta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Já tens conta com este email. Introduz a tua palavra-passe '
              'para adicionares este perfil.',
              style: TextStyle(color: Colors.grey.shade800),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              email,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: 'Palavra-passe',
                border: const OutlineInputBorder(),
                errorText: erro,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await Supabase.instance.client.auth
                              .resetPasswordForEmail(
                            email,
                            redirectTo: passwordResetRedirect,
                          );
                        } catch (_) {
                          // Silencioso de propósito: não confirmar nem
                          // desmentir a existência da conta.
                        }
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Se existir conta com este email, enviámos um '
                              'link de recuperação.',
                            ),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      },
                child: const Text('Esqueci-me da palavra-passe'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: busy
                ? null
                : () async {
                    final pw = ctrl.text;
                    if (pw.isEmpty) {
                      setLocal(() => erro = 'Escreve a palavra-passe.');
                      return;
                    }
                    setLocal(() {
                      busy = true;
                      erro = null;
                    });
                    try {
                      await Supabase.instance.client.auth.signInWithPassword(
                        email: email,
                        password: pw,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (_) {
                      // Mensagem única — não distingue "email não existe" de
                      // "palavra-passe errada" (sem enumeração de contas).
                      setLocal(() {
                        busy = false;
                        erro = 'Email ou palavra-passe incorretos.';
                      });
                    }
                  },
            child: Text(busy ? 'A entrar…' : 'Adicionar perfil de $perfil'),
          ),
        ],
      ),
    ),
  );

  ctrl.dispose();

  // Cinto e suspensórios: só devolve signedIn se HÁ MESMO sessão.
  final hasSession = Supabase.instance.client.auth.currentSession != null;
  return (ok == true && hasSession)
      ? ExistingAccountOutcome.signedIn
      : ExistingAccountOutcome.aborted;
}
