// Promoções com preço riscado (adendo 5 · item 4, 29/10/2026): a lógica pura.
// Sem rede e sem ecrãs: a decisão "a promoção está ativa agora?", o que o
// cliente vê (preço riscado, preço novo, a linha dos 30 dias), a cache da loja
// e as garantias da migração (interruptor desligado, servidor de preços intacto).
import 'dart:io';

import 'package:bora_app/models/promocao.dart';
import 'package:bora_app/services/promocoes_service.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _agora = DateTime.utc(2026, 10, 29, 12);

EstadoPromocao _estado({
  double preco = 10,
  double? promo = 7,
  bool ativada = true,
  DateTime? inicio,
  DateTime? fim,
  DateTime? agora,
}) =>
    estadoDaPromocao(
      preco: preco,
      precoPromocional: promo,
      ativada: ativada,
      inicio: inicio,
      fim: fim,
      agora: agora ?? _agora,
    );

void main() {
  group('promocaoAtivaAgora / estadoDaPromocao', () {
    test('ativa: começou e ainda não acabou', () {
      final ini = _agora.subtract(const Duration(hours: 1));
      final fim = _agora.add(const Duration(days: 1));
      expect(_estado(inicio: ini, fim: fim), EstadoPromocao.ativa);
      expect(
          promocaoAtivaAgora(
              preco: 10, precoPromocional: 7, inicio: ini, fim: fim, agora: _agora),
          isTrue);
    });

    test('ativa sem data de fim', () {
      expect(_estado(inicio: _agora.subtract(const Duration(days: 3))),
          EstadoPromocao.ativa);
    });

    test('agendada: ainda não começou', () {
      expect(_estado(inicio: _agora.add(const Duration(minutes: 1))),
          EstadoPromocao.agendada);
    });

    test('expirada: o fim é "até", não inclui o instante do fim', () {
      final ini = _agora.subtract(const Duration(days: 2));
      expect(_estado(inicio: ini, fim: _agora), EstadoPromocao.expirada);
      expect(_estado(inicio: ini, fim: _agora.add(const Duration(seconds: 1))),
          EstadoPromocao.ativa);
    });

    test('começa exatamente agora: já está ativa', () {
      expect(_estado(inicio: _agora), EstadoPromocao.ativa);
    });

    test('desligada pelo admin: não se aplica, mesmo dentro das datas', () {
      expect(
          _estado(
              ativada: false,
              inicio: _agora.subtract(const Duration(hours: 1))),
          EstadoPromocao.desligada);
    });

    test('sem data de início nunca é ativa (preço antigo de robô de catálogo)', () {
      expect(_estado(), EstadoPromocao.semDatas);
      expect(
          promocaoAtivaAgora(preco: 10, precoPromocional: 7, agora: _agora),
          isFalse);
    });

    test('preço promocional igual, acima, zero ou nulo: inválida', () {
      final ini = _agora.subtract(const Duration(hours: 1));
      expect(_estado(promo: 10, inicio: ini), EstadoPromocao.invalida);
      expect(_estado(promo: 12, inicio: ini), EstadoPromocao.invalida);
      expect(_estado(promo: 0, inicio: ini), EstadoPromocao.invalida);
      expect(_estado(promo: null, inicio: ini), EstadoPromocao.invalida);
    });
  });

  group('PromocaoProduto.fromRow', () {
    test('lê a linha do servidor (números como texto também)', () {
      final p = PromocaoProduto.fromRow({
        'product_id': 'p1',
        'price': '10.00',
        'discount_price': 7,
        'starts_at': '2026-10-29T10:00:00+00:00',
        'ends_at': null,
        'lowest_price_30d': 9.5,
      })!;
      expect(p.productId, 'p1');
      expect(p.preco, 10.0);
      expect(p.precoPromocional, 7.0);
      expect(p.inicio, DateTime.utc(2026, 10, 29, 10));
      expect(p.fim, isNull);
      expect(p.maisBaixo30d, 9.5);
    });

    test('devolve null sem id ou sem preços', () {
      expect(PromocaoProduto.fromRow({'price': 1, 'discount_price': 1}), isNull);
      expect(PromocaoProduto.fromRow({'product_id': 'x', 'price': 1}), isNull);
    });

    test('aindaValida: só olha para o fim', () {
      const sem = PromocaoProduto(productId: 'a', preco: 10, precoPromocional: 7);
      final acaba = PromocaoProduto(
          productId: 'a', preco: 10, precoPromocional: 7, fim: _agora);
      expect(sem.aindaValida(_agora), isTrue);
      expect(acaba.aindaValida(_agora.subtract(const Duration(seconds: 1))), isTrue);
      expect(acaba.aindaValida(_agora), isFalse);
    });
  });

  group('vistaDaPromocao (o que o cliente vê)', () {
    test('loja parceira: riscado = preço normal, atual = promocional, linha = preço normal', () {
      const p = PromocaoProduto(
          productId: 'a', preco: 10, precoPromocional: 7, maisBaixo30d: 10);
      final v = vistaDaPromocao(p, lojaParceira: true);
      expect(v.atual, 7.0);
      expect(v.riscado, 10.0);
      expect(v.maisBaixo30d, 10.0);
      expect(v.temReducao, isTrue);
      expect(percentagemDesconto(v), 30);
    });

    test('loja não parceira: tudo com o markup de 15 % (exibido = cobrado)', () {
      const p = PromocaoProduto(
          productId: 'a', preco: 4, precoPromocional: 3, maisBaixo30d: 4);
      final v = vistaDaPromocao(p, lojaParceira: false);
      expect(v.atual, 3.45);
      expect(v.riscado, 4.6);
      expect(v.maisBaixo30d, 4.6);
    });

    test('sem preço mais baixo do servidor: a linha usa o preço normal', () {
      const p = PromocaoProduto(productId: 'a', preco: 10, precoPromocional: 8);
      final v = vistaDaPromocao(p, lojaParceira: true);
      expect(v.riscado, 10.0);
      expect(v.maisBaixo30d, 10.0);
    });

    test('o mais baixo dos 30 dias é menor que o normal: é ele que se risca', () {
      const p = PromocaoProduto(
          productId: 'a', preco: 10, precoPromocional: 7, maisBaixo30d: 8);
      final v = vistaDaPromocao(p, lojaParceira: true);
      expect(v.riscado, 8.0);
      expect(v.maisBaixo30d, 8.0);
    });

    test('o novo preço não é menor que o mais baixo dos 30 dias: sem redução, sem riscado nem linha', () {
      const p = PromocaoProduto(
          productId: 'a', preco: 10, precoPromocional: 7, maisBaixo30d: 6);
      final v = vistaDaPromocao(p, lojaParceira: true);
      expect(v.atual, 7.0);
      expect(v.riscado, isNull);
      expect(v.maisBaixo30d, isNull);
      expect(v.temReducao, isFalse);
      expect(percentagemDesconto(v), isNull);
    });
  });

  group('PromocoesLoja (cache da app)', () {
    final linha = <String, dynamic>{
      'product_id': 'p1',
      'price': 10,
      'discount_price': 7,
      'starts_at': '2026-10-29T10:00:00Z',
      'ends_at': '2026-10-30T10:00:00Z',
      'lowest_price_30d': 10,
    };

    test('guarda o que o servidor devolve e dá o preço de catálogo promocional', () async {
      var agora = DateTime.utc(2026, 10, 29, 12);
      final loja = PromocoesLoja(
        buscar: (_) async => [linha],
        relogio: () => agora,
      );
      await loja.garantir('loja1');
      expect(loja.de('loja1', 'p1')?.precoPromocional, 7.0);
      expect(loja.precoDeCatalogo('loja1', 'p1', 10), 7.0);
      expect(loja.precoDeCatalogo('loja1', 'outro', 5), 5.0);
      expect(loja.precoDeCatalogo('outra_loja', 'p1', 10), 10.0);

      // Depois do fim a app deixa de a mostrar sem ir ao servidor.
      agora = DateTime.utc(2026, 10, 30, 10, 0, 1);
      expect(loja.de('loja1', 'p1'), isNull);
      expect(loja.precoDeCatalogo('loja1', 'p1', 10), 10.0);
    });

    test('servidor sem promoções (interruptor desligado): tudo como hoje', () async {
      final loja = PromocoesLoja(buscar: (_) async => const []);
      await loja.garantir('loja1');
      expect(loja.de('loja1', 'p1'), isNull);
      expect(loja.precoDeCatalogo('loja1', 'p1', 10), 10.0);
    });

    test('erro de rede ou migração por aplicar: vazio, sem lançar', () async {
      final loja = PromocoesLoja(
          buscar: (_) async => throw StateError('function does not exist'));
      await loja.garantir('loja1');
      expect(loja.de('loja1', 'p1'), isNull);
    });

    test('lê uma vez por loja e só volta a ler passados 2 minutos', () async {
      var chamadas = 0;
      var agora = DateTime.utc(2026, 10, 29, 12);
      final loja = PromocoesLoja(
        buscar: (_) async {
          chamadas++;
          return [linha];
        },
        relogio: () => agora,
      );
      await Future.wait([loja.garantir('loja1'), loja.garantir('loja1')]);
      await loja.garantir('loja1');
      expect(chamadas, 1);
      agora = agora.add(const Duration(minutes: 1, seconds: 59));
      await loja.garantir('loja1');
      expect(chamadas, 1);
      agora = agora.add(const Duration(seconds: 2));
      await loja.garantir('loja1');
      expect(chamadas, 2);
    });

    test('avisa quem está a ouvir só quando algo mudou', () async {
      var avisos = 0;
      final loja = PromocoesLoja(
        buscar: (_) async => [linha],
        relogio: () => DateTime.utc(2026, 10, 29, 12),
      )..addListener(() => avisos++);
      await loja.garantir('loja1');
      expect(avisos, 1);
      loja.esquecer(); // limpa a cache (e avisa)
      final antes = avisos;
      await loja.garantir('loja1');
      expect(avisos, antes + 1);
    });
  });

  group('migração 20261029200800_c4_promocoes', () {
    late String sql;
    setUpAll(() {
      sql = File('supabase/migrations/20261029200800_c4_promocoes.sql')
          .readAsStringSync()
          .toLowerCase();
    });

    test('o interruptor nasce desligado e nunca desfaz a escolha do admin', () {
      expect(sql, contains("'promotions_enabled', 'false'::jsonb"));
      expect(sql, contains('on conflict (key) do nothing'));
    });

    test('não toca no servidor de preços (isso é só proposta)', () {
      expect(sql, isNot(contains('function public.quote_order_pricing')));
      expect(sql, isNot(contains('function public.create_order')));
      expect(sql, isNot(contains('function public.pricing_calculate')));
      expect(sql, isNot(contains('function public.partner_store_share')));
    });

    test('tem o histórico, a regra dos 30 dias e as funções pedidas, fechadas a anon', () {
      for (final f in [
        'product_price_history',
        'product_lowest_price_30d',
        'partner_set_promotion',
        'admin_promotions_list',
        'store_active_promotions',
      ]) {
        expect(sql, contains(f), reason: f);
      }
      expect(sql, contains('discount_starts_at'));
      expect(sql, contains('discount_ends_at'));
      expect(sql, contains('discount_created_by'));
      expect(sql,
          contains('revoke all on function public.partner_set_promotion'));
      expect(sql, contains('revoke all on function public.admin_promotions_list'));
      // A única função aberta a anon é a leitura pública do catálogo.
      expect(RegExp(r'grant execute on function [^;]*\bto anon').allMatches(sql).length,
          1);
    });

    // 30/10/2026: a troca do preço no checkout foi aplicada com a autorização do
    // Danilo (adendo 11). A guarda passa a ser: só a migração autorizada a tem,
    // ela regista a autorização e converte o preço promocional para numeric
    // (discount_price é double precision na base).
    test('a troca do preço no checkout só está na migração autorizada', () {
      final dir = Directory('supabase/migrations');
      final pelaTroca = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .where((f) =>
              f.readAsStringSync().contains('product_promocao_ativa(p.id)'))
          .toList();
      expect(pelaTroca.map((f) => f.uri.pathSegments.last).toList(),
          ['20261030063000_c4_promocoes_servidor.sql'],
          reason: 'a troca do preço no checkout só entra pela migração autorizada');
      final sql = pelaTroca.single.readAsStringSync();
      expect(sql, contains('eu autorizo tudo'));
      expect(sql, contains('round(p.discount_price::numeric, 2)'));
      expect(sql, contains('bkp_fn_create_order_20261029'));
      expect(
          File('docs/propostas/missao-geral-2026-10-28/C4_promocoes/01_servidor_precos_proposta.sql')
              .existsSync(),
          isTrue);
      expect(
          File('docs/propostas/missao-geral-2026-10-28/C4_promocoes/00_LEIA-ME.md')
              .existsSync(),
          isTrue);
    });
  });
}
