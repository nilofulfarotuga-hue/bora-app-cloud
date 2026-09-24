// Recibos por viagem (painel admin) — fecho-manha-2026-09-24, bloco 6.
// Prova as peças puras do ecrã: a linha vinda da RPC admin_tvde_recibos_listar,
// o filtro enviados/com falha e a leitura do interruptor tvde_recibo_email_auto
// (jsonb pode chegar como bool, "true" ou 1).
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/admin/admin_tvde_recibos_screen.dart';

void main() {
  final linhas = [
    ReciboLinha.fromMap({
      'ride_id': '65dca9af-9be1-46c6-bcc7-c62c8674411e',
      'email': 'passageiro@exemplo.pt',
      'enviado_em': '2026-09-23T18:40:06.46+00:00',
      'ok': true,
      'detalhe': 'resend 01a0cf90',
      'preco_eur': '7.50',
      'motorista': 'Danilo',
      'origem': 'Guarda',
      'destino': 'Gonçalo',
    }),
    ReciboLinha.fromMap({
      'ride_id': 'ba0dc6a0-efd4-47b3-a660-61e59360d2bc',
      'email': null,
      'enviado_em': null,
      'ok': false,
      'detalhe': 'sem_email',
      'preco_eur': null,
    }),
  ];

  test('a linha lê os campos da RPC e aguenta nulos', () {
    expect(linhas[0].precoEur, 7.5);
    expect(linhas[0].enviadoEm, isNotNull);
    expect(linhas[0].motorista, 'Danilo');
    expect(linhas[1].email, isNull);
    expect(linhas[1].enviadoEm, isNull);
    expect(linhas[1].precoEur, 0);
    expect(linhas[1].ok, isFalse);
  });

  test('filtro: todos, só enviados, só com falha', () {
    expect(filtrarRecibos(linhas, 'todos').length, 2);
    expect(filtrarRecibos(linhas, 'ok').map((r) => r.rideId), [linhas[0].rideId]);
    expect(filtrarRecibos(linhas, 'falhou').map((r) => r.rideId), [linhas[1].rideId]);
  });

  test('o interruptor lê jsonb em qualquer forma e cai no defeito quando não sabe', () {
    expect(lerBool(true, porDefeito: false), isTrue);
    expect(lerBool('true', porDefeito: false), isTrue);
    expect(lerBool('"false"', porDefeito: true), isFalse);
    expect(lerBool(0, porDefeito: true), isFalse);
    expect(lerBool(null, porDefeito: true), isTrue);
    expect(lerBool('talvez', porDefeito: false), isFalse);
  });
}
