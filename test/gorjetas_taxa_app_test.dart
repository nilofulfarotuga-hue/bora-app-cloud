// Gorjetas — regra do Danilo de 30/10/2026 (missão gorjetas-taxa-2026-10-30), lado da app.
//
// O que se prova, com o servidor trocado por um de mentira:
//  1. o que o estafeta/motorista vê: gorjeta paga depois por cartão/MB Way →
//     "Gorjeta 2,00 € · taxa do pagamento −0,28 € · recebes 1,72 €"; a do
//     carrinho e a de dinheiro → inteiras; o total soma o que ele recebe;
//  2. o texto do carrinho: "vai toda para o estafeta." quando vai junto da
//     compra; "… e é cobrada à parte." quando não vai (interruptor desligado ou
//     pedido pago todo com saldo) — com o inglês das duas;
//  3. a marcação da gorjeta antes do pagamento só sai com o interruptor
//     ligado, com o nome e os parâmetros certos (SDK verdadeiro);
//  4. o interruptor lê-se da chave certa, e em erro fica desligado;
//  5. o servidor a dizer "already_exists" (gorjeta já paga junto da compra) não
//     aparece ao cliente como "não foi cobrada".
import 'dart:convert';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/services/tip_service.dart';
import 'package:bora_app/widgets/gorjetas_recebidas_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servidor de mentira: guarda cada pedido (caminho + corpo) e responde [resposta].
SupabaseClient servidorFalso(List<(String, Object?)> pedidos,
    {Object? resposta = const {'ok': true}, int estado = 200}) {
  return SupabaseClient(
    'http://127.0.0.1:1',
    'teste',
    httpClient: MockClient((r) async {
      pedidos.add((r.url.path, r.body.isEmpty ? null : jsonDecode(r.body)));
      return http.Response(jsonEncode(resposta), estado,
          headers: {'content-type': 'application/json'}, request: r);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 1. O que o estafeta/motorista vê ─────────────────────────────────────
  group('GorjetaRecebida (o que ele recebe)', () {
    // A gorjeta real de 29/10 (corrida TVDE, MB Way, paga depois): 200 − 28.
    final depoisMbway = GorjetaRecebida.daLinha({
      'amount_cents': 200,
      'liquido_prestador_cents': 172,
      'method': 'mbway',
      'target': 'tvde',
    });
    final doCarrinho = GorjetaRecebida.daLinha({
      'amount_cents': 200,
      'liquido_prestador_cents': 200,
      'method': 'card',
      'target': 'order',
    });
    final emDinheiro = GorjetaRecebida.daLinha({
      'amount_cents': 100,
      'liquido_prestador_cents': 100,
      'method': 'cash',
      'target': 'order',
    });

    test('paga depois por MB Way: 2,00 € − 0,28 € = 1,72 €', () {
      expect(depoisMbway.valorCents, 200);
      expect(depoisMbway.recebeCents, 172);
      expect(depoisMbway.taxaCents, 28);
      expect(depoisMbway.temTaxa, isTrue);
      expect(depoisMbway.detalhe,
          'Gorjeta 2,00 € · taxa do pagamento −0,28 € · recebes 1,72 €');
    });

    test('a do carrinho e a de dinheiro chegam inteiras (só o valor)', () {
      expect(doCarrinho.recebeCents, 200);
      expect(doCarrinho.temTaxa, isFalse);
      expect(doCarrinho.detalhe, isNull);
      expect(emDinheiro.recebeCents, 100);
      expect(emDinheiro.temTaxa, isFalse);
      expect(emDinheiro.detalhe, isNull);
    });

    test('taxa ainda por chegar: o líquido estimado pelo servidor manda', () {
      // 2,00 € com a estimativa da coluna gerada (25 + ceil(1,5 %) = 28).
      final estimada = GorjetaRecebida.daLinha(
          {'amount_cents': 200, 'liquido_prestador_cents': 172, 'method': 'card'});
      expect(estimada.taxaCents, 28);
      // Sem a coluna (resposta antiga): nunca inventa taxa.
      final semColuna = GorjetaRecebida.daLinha({'amount_cents': 300});
      expect(semColuna.recebeCents, 300);
      expect(semColuna.temTaxa, isFalse);
    });

    test('o total é a soma do que ele recebe, não do bruto', () {
      expect(GorjetaRecebida.total([depoisMbway, doCarrinho, emDinheiro]), 472);
      expect(GorjetaRecebida.eurCents(472), '4,72 €');
    });

    test('a linha com a taxa tem inglês', () {
      BoraLang.notifier.value = AppLang.en;
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      expect(depoisMbway.detalhe, 'Tip 2,00 € · payment fee −0,28 € · you get 1,72 €');
      expect(
          kStringsEn['As de cartão e MB WAY entram no acerto da semana. Nas dadas depois, sai a taxa do pagamento.'],
          isNotNull);
    });
  });

  // ── 2. O texto e o total do carrinho ─────────────────────────────────────
  group('carrinho', () {
    test('vai junto só com o interruptor ligado e algo a pagar', () {
      expect(TipService.vaiJuntoDaCompra(junto: false, restoAPagarEur: 12), isFalse);
      expect(TipService.vaiJuntoDaCompra(junto: true, restoAPagarEur: 12), isTrue);
      // Pago todo com saldo Bora: continua à parte, como antes.
      expect(TipService.vaiJuntoDaCompra(junto: true, restoAPagarEur: 0), isFalse);
    });

    test('texto com e sem a gorjeta junto da compra (PT e EN)', () {
      expect(TipService.textoDoCarrinho(vaiJunto: true),
          'A gorjeta vai toda para o estafeta.');
      expect(TipService.textoDoCarrinho(vaiJunto: false),
          'A gorjeta vai toda para o estafeta e é cobrada à parte.');

      BoraLang.notifier.value = AppLang.en;
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      expect(TipService.textoDoCarrinho(vaiJunto: true),
          'The whole tip goes to the courier.');
      expect(TipService.textoDoCarrinho(vaiJunto: false),
          'The whole tip goes to the courier and is charged separately.');
    });

    test('o total mostrado leva a gorjeta; sem nada a pagar, não', () {
      expect(TipService.totalComGorjeta(12.00, 200), closeTo(14.00, 0.001));
      expect(TipService.totalComGorjeta(12.00, 0), 12.00);
      expect(TipService.totalComGorjeta(0, 200), 0);
    });
  });

  // ── 3. Marcação antes do pagamento (SDK verdadeiro, servidor falso) ──────
  group('marcarAntesDoPagamento', () {
    test('interruptor desligado: nenhuma chamada, nada marcado', () async {
      final pedidos = <(String, Object?)>[];
      final r = await TipService.marcarAntesDoPagamento(
        junto: false,
        tipCents: 200,
        restoAPagarEur: 12,
        cliente: servidorFalso(pedidos),
      );
      expect(r, 0);
      expect(pedidos, isEmpty);
    });

    test('ligado: client_preparar_gorjeta_checkout com a gorjeta', () async {
      final pedidos = <(String, Object?)>[];
      final r = await TipService.marcarAntesDoPagamento(
        junto: true,
        tipCents: 200,
        restoAPagarEur: 12,
        cliente: servidorFalso(pedidos),
      );
      expect(r, 200);
      expect(pedidos, hasLength(1));
      expect(pedidos.single.$1, endsWith('/rpc/client_preparar_gorjeta_checkout'));
      expect(pedidos.single.$2, {'p_tip_cents': 200});
    });

    test('ligado sem gorjeta ou pago todo com saldo: limpa (0)', () async {
      final pedidos = <(String, Object?)>[];
      final cli = servidorFalso(pedidos);
      expect(
          await TipService.marcarAntesDoPagamento(
              junto: true, tipCents: 0, restoAPagarEur: 12, cliente: cli),
          0);
      expect(
          await TipService.marcarAntesDoPagamento(
              junto: true, tipCents: 200, restoAPagarEur: 0, cliente: cli),
          0);
      expect(pedidos.map((p) => p.$2), [
        {'p_tip_cents': 0},
        {'p_tip_cents': 0},
      ]);
    });

    test('servidor recusa: não rebenta e diz que nada ficou marcado', () async {
      final pedidos = <(String, Object?)>[];
      final r = await TipService.marcarAntesDoPagamento(
        junto: true,
        tipCents: 200,
        restoAPagarEur: 12,
        cliente: servidorFalso(pedidos,
            resposta: {'message': 'function not found', 'code': 'PGRST202'}, estado: 404),
      );
      expect(r, 0);
      expect(pedidos, hasLength(1));
    });

    test('servidor diz ok=false: nada marcado', () async {
      final r = await TipService.marcarAntesDoPagamento(
        junto: true,
        tipCents: 200,
        restoAPagarEur: 12,
        cliente: servidorFalso([], resposta: {'ok': false, 'motivo': 'valor_invalido'}),
      );
      expect(r, 0);
    });
  });

  // ── 4. O interruptor ─────────────────────────────────────────────────────
  group('juntoDoPagamento', () {
    test('lê tips_checkout_junto_pagamento; em erro fica desligado', () async {
      final pedidos = <(String, Object?)>[];
      expect(
          await TipService.juntoDoPagamento(
              cliente: servidorFalso(pedidos, resposta: true)),
          isTrue);
      expect(pedidos.single.$1, endsWith('/rpc/get_setting'));
      expect(pedidos.single.$2, {'p_key': 'tips_checkout_junto_pagamento'});

      expect(
          await TipService.juntoDoPagamento(
              cliente: servidorFalso([], resposta: false)),
          isFalse);
      expect(
          await TipService.juntoDoPagamento(
              cliente: servidorFalso([], resposta: {'message': 'x'}, estado: 500)),
          isFalse);
    });
  });

  // ── 5. Gorjeta já paga junto da compra ───────────────────────────────────
  group('cobrar', () {
    test('already_exists: diz que foi incluída, não que falhou', () async {
      final pedidos = <(String, Object?)>[];
      final r = await TipService.cobrar(
        target: 'order',
        id: 'pedido-1',
        cents: 200,
        moment: 'checkout',
        cliente: servidorFalso(pedidos,
            resposta: {'ok': true, 'note': 'already_exists'}),
      );
      expect(r.ok, isTrue);
      expect(r.mensagem, 'Gorjeta de 2,00 € incluída no pagamento do pedido. Obrigado!');
      expect(pedidos.single.$1, endsWith('/functions/v1/charge-tip'));
      expect(pedidos.single.$2, {
        'action': 'create',
        'target': 'order',
        'id': 'pedido-1',
        'amountCents': 200,
        'moment': 'checkout',
      });
    });
  });
}
