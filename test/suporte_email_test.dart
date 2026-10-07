import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [E-mail do suporte · 07/10/2026 · auditoria das 3 plataformas] O botão de
/// e-mail do ecrã de suporte não fazia nada no Android 11+: só abria o
/// `mailto:` se `canLaunchUrl` dissesse que sim, e sem `<queries>` para
/// `mailto` no manifesto ela diz sempre que não. O `legal_info_screen` já
/// tinha a lição; o suporte não.
void main() {
  test('o e-mail do suporte abre sem perguntar ao canLaunchUrl e avisa se falhar',
      () {
    final f = File('lib/screens/support_screen.dart').readAsStringSync();
    final i = f.indexOf('Future<void> _launchEmail()');
    expect(i, isNonNegative);
    final corpo = f.substring(i, f.indexOf('Future<void> _launchPhone()', i));
    expect(corpo, isNot(contains('await canLaunchUrl(')),
        reason: 'no Android 11+ o canLaunchUrl diz não a mailto: e o botão morre');
    expect(corpo, contains('launchUrl(uri'));
    expect(corpo, contains("'Escreve-nos para boraappbora@gmail.com'.tr"),
        reason: 'sem app de e-mail a pessoa tem de ver o endereço');
  });

  test('o telefone continua declarado no manifesto (DIAL tel)', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m, contains('android.intent.action.DIAL'));
    expect(m, contains('android:scheme="tel"'));
  });
}
