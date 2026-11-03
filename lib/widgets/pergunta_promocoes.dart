import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

/// Autorização de promoções (03/11/2026, missão boom-hamburguer-mes, bloco H).
///
/// Padrão Glovo/Uber: pergunta-se UMA vez — logo a seguir ao registo (o
/// cliente novo cai na página inicial) e aos clientes antigos que nunca
/// responderam, ao abrir a app. Nada vem pré-marcado: "Sim" ou "Agora não".
/// O servidor decide se falta perguntar (`marketing_pergunta_pendente`) e grava
/// a resposta (`set_marketing_opt_in`, que marca `marketing_respondido_em`).
/// Muda-se depois no Perfil.
class PerguntaPromocoes {
  PerguntaPromocoes._();

  static bool _jaVistaNestaSessao = false;

  @visibleForTesting
  static void esquecerParaTeste() => _jaVistaNestaSessao = false;

  /// Mostra a pergunta se o servidor disser que falta. Nunca lança.
  static Future<void> mostrarSeFaltar(
    BuildContext context, {
    Future<bool> Function()? pendente,
    Future<void> Function(bool aceita)? gravar,
  }) async {
    if (_jaVistaNestaSessao) return;
    bool falta;
    try {
      falta = pendente != null
          ? await pendente()
          : (await Supabase.instance.client.rpc('marketing_pergunta_pendente')) ==
              true;
    } catch (e) {
      debugPrint('[PerguntaPromocoes] pendente falhou: $e');
      return;
    }
    if (!falta || !context.mounted) return;
    _jaVistaNestaSessao = true;
    final aceita = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogoPromocoes(),
    );
    if (aceita == null) return;
    try {
      if (gravar != null) {
        await gravar(aceita);
      } else {
        await Supabase.instance.client
            .rpc('set_marketing_opt_in', params: {'p_opt_in': aceita});
      }
    } catch (e) {
      debugPrint('[PerguntaPromocoes] gravar falhou: $e');
    }
  }
}

class _DialogoPromocoes extends StatelessWidget {
  const _DialogoPromocoes();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('pergunta_promocoes'),
      title: Text('Promoções e novidades'.tr,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(
        'Queres receber promoções e novidades das lojas da Guarda? Podes mudar quando quiseres no Perfil.'
            .tr,
        style: const TextStyle(fontSize: 16, height: 1.35),
      ),
      actions: [
        TextButton(
          key: const Key('pergunta_promocoes_nao'),
          onPressed: () => Navigator.pop(context, false),
          child: Text('Agora não'.tr, style: const TextStyle(fontSize: 16)),
        ),
        FilledButton(
          key: const Key('pergunta_promocoes_sim'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Sim'.tr, style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
