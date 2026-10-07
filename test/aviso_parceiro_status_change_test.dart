import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Aviso ao parceiro · 07/10/2026 · auditoria das 3 plataformas] Quando o
/// admin força a loja aberta/fechada ou muda o horário, o servidor chama
/// `_notify_partner_status_change` → Edge `notify-partner` com
/// `kind = 'status_change'`. Até 07/10 o pedido nunca saía (migration
/// 20261007105848). Ao passar a sair, o verificador independente apanhou a
/// outra metade: no Android o aviso é só de dados e a app só desenhava os tipos
/// que conhece — `status_change` não estava em lado nenhum, e o parceiro com a
/// app em fundo não via nada (com a app aberta ouvia um bip sem texto).
void main() {
  final app = File('lib/services/notification_service.dart').readAsStringSync();

  test('o servidor manda o aviso com o tipo status_change', () {
    final sql = File(
            'supabase/migrations/20261007105848_notify_partner_status_change_chave_do_cofre.sql')
        .readAsStringSync();
    expect(sql, contains("'kind', 'status_change'"));
    final edge = File('supabase/functions/notify-partner/index.ts').readAsStringSync();
    expect(edge, contains('type: kind'),
        reason: 'o notify-partner passa o kind como data.type');
  });

  test('a app desenha o status_change (em fundo e aberta), com o texto do servidor',
      () {
    final i = app.indexOf('const Set<String> _kPersistentCategoryTypes');
    expect(i, isNonNegative);
    final conjunto = app.substring(i, app.indexOf('};', i));
    expect(conjunto, contains("'status_change'"),
        reason: 'sem esta entrada o Android não mostra nada');
    final caso = app.indexOf("case 'status_change':");
    expect(caso, isNonNegative, reason: 'falta o ramo que desenha o aviso');
    final ramo = app.substring(caso, app.indexOf('return;', caso));
    expect(ramo, contains("data['title']"));
    expect(ramo, contains("data['body']"));
  });
}
