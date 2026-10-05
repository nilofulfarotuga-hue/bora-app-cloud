import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [ronda 04/10 · fechado a 05/10/2026] Dois pedidos que os agentes da ronda
/// deixaram uns aos outros e que ninguém chegou a fazer (só fonte — o efeito
/// no servidor prova-se em SQL):
///
///  • despacho A6 — o serviço em segundo plano do estafeta bate o sinal pelo
///    caminho com segredo (`driver_heartbeat_segredo`), que só aceita o
///    próprio; o caminho antigo fica de reserva para o sinal nunca se perder.
///  • admin-dinheiro — apagar um rascunho de pagamento pede confirmação e
///    fica na auditoria (sem rascunho, um pagamento que entre não vira pedido).
void main() {
  group('sinal do estafeta em segundo plano', () {
    final src = File('lib/services/foreground_service.dart').readAsStringSync();

    test('com sessão guarda o segredo, e ao ficar offline apaga-o', () {
      expect(src, contains("rpc('driver_heartbeat_segredo_obter')"));
      expect(src, contains('unawaited(_guardarSegredoDoBatimento());'),
          reason: 'ficar online nunca espera por esta chamada');
      expect(src, contains('removeData(key: _kSegredoBatimento)'));
    });

    test('bate primeiro com o segredo e só depois pelo caminho antigo', () {
      final comSegredo =
          src.indexOf('await _batimentoComSegredo(url, apiKey, driverId)');
      final antigo = src.indexOf('rest/v1/rpc/driver_heartbeat_by_id');
      expect(comSegredo, greaterThan(0));
      expect(antigo, greaterThan(comSegredo),
          reason: 'o caminho antigo é a reserva, não o primeiro');
      expect(src, contains('if (!bateuComSegredo) {'));
      expect(src, contains("rest/v1/rpc/driver_heartbeat_segredo'"));
    });
  });

  test('apagar rascunho de pagamento pede confirmação e fica na auditoria', () {
    final src = File('lib/screens/admin/admin_orphan_payments_screen.dart')
        .readAsStringSync();
    final pergunta = src.indexOf('showDialog<bool>(');
    final apaga = src.indexOf(".from('payment_drafts')");
    final nadaSaiu = src.indexOf('if (apagados.isEmpty) {');
    final regista = src.indexOf("'rascunho_pagamento_excluido'");

    expect(pergunta, greaterThan(0));
    expect(apaga, greaterThan(pergunta), reason: 'pergunta-se ANTES de apagar');
    expect(src, contains('if (ok != true || !mounted) return;'));
    // A base, sem permissão, apaga zero linhas SEM dar erro (medido a 05/10:
    // a tabela só tem política de leitura). Só se regista o que saiu mesmo.
    expect(src.indexOf(".select('id')", apaga), greaterThan(apaga));
    expect(nadaSaiu, greaterThan(apaga));
    expect(regista, greaterThan(nadaSaiu),
        reason: 'nunca se regista uma exclusão que não aconteceu');
  });

  test('"parceiro chama estafeta" desligado no servidor diz-se ao parceiro por palavras', () {
    // Interruptor `dispatch_parceiro_chama_estafeta_ligado` (05/10/2026): o
    // fecho ainda lança estes pedidos como pedido normal em dinheiro. Enquanto
    // estiver desligado a função responde `indisponivel` — e o ecrã não pode
    // mandar "tentar de novo".
    final ecra =
        File('lib/screens/partner_call_driver_screen.dart').readAsStringSync();
    final caso = ecra.indexOf("case 'indisponivel':");
    expect(caso, greaterThan(0));
    expect(ecra.indexOf('ainda não está disponível', caso), greaterThan(caso));

    final migracao = File(
            'supabase/migrations/20261005061548_parceiro_chama_estafeta_interruptor.sql')
        .readAsStringSync();
    expect(migracao, contains("'dispatch_parceiro_chama_estafeta_ligado', 'false'::jsonb"));
    expect(migracao, contains("''error'', ''indisponivel''"));
  });
}
