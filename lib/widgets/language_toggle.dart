import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/bora_lang.dart';


/// Alternador de idioma "PT | EN" do app cliente.
///
/// Pensado para o slot `actions` da [BoraAppBar] (header verde), por isso a
/// variante clara é a predefinida: pastilha branca translúcida, com o idioma
/// activo a cheio. Não usa laranja de propósito — o acento laranja está
/// reservado à acção principal de cada ecrã (regra "1 laranja por ecrã").
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, this.onDark = true});

  /// True quando assenta sobre o header verde (predefinição).
  /// False para fundos claros — ex.: uma linha do ecrã de perfil.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final base = onDark ? Colors.white : AppColors.primary;
    return ValueListenableBuilder<AppLang>(
      valueListenable: BoraLang.notifier,
      builder: (context, lang, _) {
        return Semantics(
          // Identificador estável para testes E2E — não muda com o idioma.
          identifier: 'language_toggle',
          button: true,
          label: lang == AppLang.en
              ? 'Language: English. Tap to switch to Portuguese.'
              : 'Idioma: português. Toca para mudar para inglês.',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: BoraLang.toggle,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: base.withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Seg(
                        text: 'PT',
                        active: lang == AppLang.pt,
                        base: base,
                        onDark: onDark,
                      ),
                      _Seg(
                        text: 'EN',
                        active: lang == AppLang.en,
                        base: base,
                        onDark: onDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.text,
    required this.active,
    required this.base,
    required this.onDark,
  });

  final String text;
  final bool active;
  final Color base;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? base : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: active
              ? (onDark ? AppColors.primary : Colors.white)
              : base.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
