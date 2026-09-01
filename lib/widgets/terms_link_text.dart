import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/tr.dart';

/// Rich text row used inside the consent checkbox at signup (BR §20.1).
///
/// Renders: "Aceito os [Termos] e a [Política de Privacidade]"
/// Both bracketed segments are tappable and open the URL in an external browser.
class TermsLinkText extends StatelessWidget {
  const TermsLinkText({
    super.key,
    this.termsUrl = 'https://bora.app/termos',
    this.privacyUrl = 'https://bora.app/privacidade',
  });

  final String termsUrl;
  final String privacyUrl;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final linkStyle = base?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: 'Aceito os '.tr),
          TextSpan(
            text: 'Termos'.tr,
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => _open(termsUrl),
          ),
          TextSpan(text: ' e a '.tr),
          TextSpan(
            text: 'Política de Privacidade'.tr,
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => _open(privacyUrl),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
