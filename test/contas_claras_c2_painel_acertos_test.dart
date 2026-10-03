import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [contas-claras · C2 · 21/09/2026] O que estes testes trancam no painel
/// "Dinheiro e acertos" (só fonte — o servidor prova-se em SQL, ver
/// `.claude/.ai/provas/contas-claras-20260921/c2-painel-admin-prova.sql`):
///
///  1. Reabrir um acerto passa SEMPRE por `admin_reabrir_acerto` (motivo
///     obrigatório, auditoria, semana travada no servidor) — o antigo
///     `admin_unmark_settlement`, que desfazia sem motivo e sem trava, saiu
///     deste ecrã.
///  2. O recálculo do estafeta é pedido ao servidor (`compute_driver_settlement`
///     com o timestamp exacto da semana), nunca somado na app.
///  3. As colunas novas do acerto (corridas TVDE, ganhos das corridas, dinheiro
///     em mão nas corridas, compras adiantadas) e os avisos do fecho
///     (`admin_avisos_fecho`) estão no ecrã.
///  4. O aviso "pedido no vermelho" tem rota: `/admin/orders/{id}` abre o
///     detalhe do pedido em `main.dart`.
///
/// Cicatriz: a 19/09 uma linha marcada "paga" por engano (clique de teste, sem
/// referência nem nota) travou o fecho de 21/09 e o recibo saiu com 6,52 em
/// vez de 43,52 — e ninguém sabia porquê, porque "Desfazer" não deixava rasto.
void main() {
  final ecra = File('lib/screens/admin/admin_acertos_semana_screen.dart')
      .readAsStringSync();
  final main = File('lib/main.dart').readAsStringSync();
  final inbox = File('lib/screens/admin/admin_notifications_inbox_screen.dart')
      .readAsStringSync();

  group('reabrir acerto com motivo', () {
    test('o ecrã chama admin_reabrir_acerto com o motivo e já não usa o unmark',
        () {
      expect(ecra, contains("rpc('admin_reabrir_acerto'"));
      expect(ecra, contains("'p_motivo': motivo"));
      expect(ecra, isNot(contains('admin_unmark_settlement')));
    });

    test('o recálculo é pedido ao servidor com o timestamp da semana', () {
      expect(ecra, contains("rpc('compute_driver_settlement'"));
      expect(ecra, contains("'p_week_start': m['week_start_at']"));
      expect(ecra, contains("'p_persist': true"));
    });

    test('semana travada fica visível no botão', () {
      expect(ecra, contains("reabrir_permitido"));
      expect(ecra, contains("'Travado'"));
    });
  });

  group('colunas novas e avisos', () {
    test('as quatro parcelas do acerto vivo aparecem na linha do estafeta', () {
      expect(ecra, contains("acerto['corridas_n']"));
      expect(ecra, contains("acerto['corridas_cents']"));
      expect(ecra, contains("acerto['corridas_em_mao_cents']"));
      expect(ecra, contains("acerto['reembolsos_cents']"));
    });

    test('os avisos do fecho vêm de admin_avisos_fecho e o vermelho abre o pedido',
        () {
      expect(ecra, contains("rpc('admin_avisos_fecho'"));
      expect(ecra, contains("fecho_aviso_linha_travada_falhou"));
      expect(ecra, contains('AdminOrderDetailScreen(orderId: orderId)'));
    });

    test('reenviar recibos continua a chamar admin_resend_weekly_digest', () {
      expect(ecra, contains("rpc('admin_resend_weekly_digest'"));
    });
  });

  group('rota do aviso', () {
    test('/admin/orders/{id} abre o detalhe do pedido', () {
      expect(main, contains("name.startsWith('/admin/orders/')"));
      expect(main, contains('AdminOrderDetailScreen(orderId: id)'));
    });

    test('a caixa de avisos dá nome ao pedido no vermelho', () {
      expect(inbox, contains("case 'pedido_no_vermelho':"));
      expect(inbox, contains("'Pedido no vermelho'"));
    });
  });
}
