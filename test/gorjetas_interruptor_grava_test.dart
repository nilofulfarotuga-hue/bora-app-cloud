import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 18] O interruptor das gorjetas grava.
///
/// Cicatriz (26/10): o painel fazia UPDATE direto a platform_settings, que só
/// tem política de leitura — 0 linhas mudadas e o ecrã dizia que tinha
/// gravado. Agora: admin_update_setting (auditada) + releitura do servidor.
void main() {
  test('grava pela admin_update_setting e relê o que ficou', () {
    final s = File('lib/screens/admin/admin_gorjetas_screen.dart').readAsStringSync();
    expect(s.contains(".from('platform_settings')\n          .update("), isFalse);
    expect(s.contains("rpc('admin_update_setting'"), isTrue);
    final corpo = s.substring(s.indexOf('Future<void> _mudarLigada'));
    expect(corpo.indexOf("'get_setting'"), greaterThan(corpo.indexOf("'admin_update_setting'")),
        reason: 'relê depois de gravar');
    expect(corpo.contains('Não deu para mudar'), isTrue, reason: 'mostra o erro se falhar');
  });
}
