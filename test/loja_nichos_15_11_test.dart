// loja-nichos-15-11 (ordem do Danilo 15/11 18:52/18:56, via Claude.ai 19:00):
// a Loja Online por nichos e subcategorias, os mais vendidos à frente,
// o pagamento preenchido com o perfil e as moradas guardadas.
import 'dart:io';

import 'package:bora_app/models/client_address.dart';
import 'package:bora_app/models/loja_online_produto.dart';
import 'package:bora_app/screens/client/loja_online/checkout_loja_online_screen.dart';
import 'package:bora_app/screens/client/loja_online/loja_online_screen.dart';
import 'package:bora_app/services/loja_online_pagamento_service.dart';
import 'package:bora_app/services/loja_online_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _p(String id,
        {String nicho = 'n-pets',
        String? sub,
        int vendas = 0,
        int listas = 0,
        int? ordem,
        bool destaque = false,
        String titulo = ''}) =>
    {
      'id': id,
      'nicho_id': nicho,
      'titulo': titulo.isEmpty ? 'Produto $id' : titulo,
      'preco_bora_cents': 1000,
      'prazo_min_dias': 7,
      'prazo_max_dias': 17,
      'ativo': true,
      'destaque': destaque,
      'criado_em': '2026-11-15T12:00:00Z',
      if (sub != null) 'subcategoria_id': sub,
      'vendas_loja': vendas,
      'cj_listas': listas,
      if (ordem != null) 'ordem_manual': ordem,
    };

LojaOnlineProduto _prod(String id,
        {String nicho = 'n-pets',
        String? sub,
        int vendas = 0,
        int listas = 0,
        int? ordem,
        bool destaque = false}) =>
    LojaOnlineProduto.fromJson(_p(id,
        nicho: nicho,
        sub: sub,
        vendas: vendas,
        listas: listas,
        ordem: ordem,
        destaque: destaque));

const _pets = LojaOnlineNicho(id: 'n-pets', slug: 'pets', nome: 'Pets', ordem: 10);
const _casa = LojaOnlineNicho(id: 'n-casa', slug: 'casa', nome: 'Casa', ordem: 20);
const _cao = LojaOnlineSubcategoria(
    id: 's-cao', nichoId: 'n-pets', slug: 'cao', nome: 'Cão', ordem: 10);
const _gato = LojaOnlineSubcategoria(
    id: 's-gato', nichoId: 'n-pets', slug: 'gato', nome: 'Gato', ordem: 20);
const _peixe = LojaOnlineSubcategoria(
    id: 's-peixe', nichoId: 'n-pets', slug: 'peixe', nome: 'Peixe e aquário', ordem: 30);

void main() {
  group('mais vendidos à frente', () {
    test('posição fixa, depois vendas reais, depois ranking da CJ', () {
      final l = [
        _prod('a', listas: 9000),
        _prod('b', vendas: 3),
        _prod('c', ordem: 2),
        _prod('d', vendas: 3, listas: 10),
        _prod('e', ordem: 1),
        _prod('f', listas: 50, destaque: true),
      ]..sort(compararMaisVendidos);
      expect(l.map((p) => p.id).toList(), ['e', 'c', 'd', 'b', 'a', 'f']);
    });

    test('lê as colunas novas e tolera a falta delas', () {
      final p = _prod('x', sub: 's-cao', vendas: 4, listas: 7, ordem: 3);
      expect(p.subcategoriaId, 's-cao');
      expect(p.vendasLoja, 4);
      expect(p.cjListas, 7);
      expect(p.ordemManual, 3);
      final antigo = LojaOnlineProduto.fromJson({'id': 'y', 'titulo': 'Y'});
      expect(antigo.subcategoriaId, isNull);
      expect(antigo.ordemManual, isNull);
      expect(antigo.vendasLoja, 0);
      expect(LojaOnlineNicho.fromJson({'id': 'n', 'slug': 'pets'}).publico, isFalse);
    });
  });

  group('vitrine com subcategorias', () {
    test('só as subcategorias com produtos, por ordem; filtro por subcategoria', () {
      final v = LojaOnlineVitrine.montar(
        [_pets],
        [
          _prod('g1', sub: 's-gato', listas: 5),
          _prod('c1', sub: 's-cao', listas: 50),
          _prod('c2', sub: 's-cao', listas: 500),
          _prod('solto'),
        ],
        [_peixe, _gato, _cao],
      );
      final g = v.porNicho.single;
      expect(g.subcategorias.map((s) => s.slug).toList(), ['cao', 'gato'],
          reason: 'Peixe ainda sem produtos não aparece');
      expect(g.produtos.first.id, 'c2', reason: 'o mais vendido primeiro');
      expect(g.daSubcategoria('s-cao').map((p) => p.id).toList(), ['c2', 'c1']);
      expect(g.daSubcategoria(null).length, 4);
    });

    testWidgets('dois nichos: separadores no topo; subcategoria filtra a grelha',
        (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final servico = LojaOnlineService(
        lerVisivel: () async => true,
        lerDefinicoes: (_) async => {kLojaOnlineChaveInterruptor: true},
        lerAtivos: (t) async {
          if (t == kLojaOnlineTabelaNichos) {
            return [
              {'id': 'n-pets', 'slug': 'pets', 'nome': 'Pets', 'ordem': 10},
              {'id': 'n-casa', 'slug': 'casa', 'nome': 'Casa', 'ordem': 20},
            ];
          }
          if (t == kLojaOnlineTabelaSubcategorias) {
            return [
              {'id': 's-cao', 'nicho_id': 'n-pets', 'slug': 'cao', 'nome': 'Cão', 'ordem': 10},
              {'id': 's-gato', 'nicho_id': 'n-pets', 'slug': 'gato', 'nome': 'Gato', 'ordem': 20},
            ];
          }
          return [
            _p('c1', sub: 's-cao', titulo: 'Copo limpa-patas'),
            _p('g1', sub: 's-gato', titulo: 'Túnel para gatos'),
            _p('k1', nicho: 'n-casa', titulo: 'Organizador de gaveta'),
          ];
        },
      );
      await tester.pumpWidget(MaterialApp(home: LojaOnlineScreen(service: servico)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('loja_online_nichos')), findsOneWidget);
      expect(find.text('Organizador de gaveta'), findsNothing,
          reason: 'abre no primeiro nicho (Pets)');
      expect(find.text('Copo limpa-patas'), findsWidgets);
      expect(find.text('Os mais vendidos primeiro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('loja_online_sub_gato')));
      await tester.pumpAndSettle();
      expect(find.text('Túnel para gatos'), findsWidgets);
      expect(find.descendant(of: find.byType(GridView), matching: find.text('Copo limpa-patas')),
          findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Casa'));
      await tester.pumpAndSettle();
      expect(find.text('Organizador de gaveta'), findsOneWidget);
    });
  });

  group('pagamento preenchido sozinho', () {
    test('código postal e localidade da morada escolhida nas sugestões', () {
      final p = lojaOnlinePartesDaMorada('Rua do Torreão 14, 6300-610 Guarda, Portugal');
      expect(p.codigoPostal, '6300-610');
      expect(p.localidade, 'Guarda');
      final sem = lojaOnlinePartesDaMorada('Rua sem código');
      expect(sem.codigoPostal, isNull);
    });

    testWidgets('nome, telemóvel e a morada predefinida já vêm escritos',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final morada = ClientAddress(
        id: 'm1',
        userId: 'u1',
        label: 'Casa',
        address: 'Rua do Torreão 14, 6300-610 Guarda, Portugal',
        street: 'Rua do Torreão 14',
        city: 'Guarda',
        postalCode: '6300-610',
        isDefault: true,
        createdAt: DateTime.utc(2026, 11, 1),
        updatedAt: DateTime.utc(2026, 11, 1),
      );
      await tester.pumpWidget(MaterialApp(
        home: CheckoutLojaOnlineScreen(
          produto: _prod('c1'),
          servico: LojaOnlinePagamentoService(invocar: (f, b) async => null),
          perfil: () async => LojaOnlinePerfil(
              nome: 'Ana Sousa', telefone: '912345678', moradas: [morada]),
        ),
      ));
      await tester.pumpAndSettle();
      String texto(String k) {
        final w = tester.widget(find.byKey(Key(k)));
        if (w is TextField) return w.controller!.text;
        return tester
            .widget<TextField>(find.descendant(
                of: find.byKey(Key(k)), matching: find.byType(TextField)))
            .controller!
            .text;
      }
      expect(texto('loja_online_nome'), 'Ana Sousa');
      expect(texto('loja_online_telefone'), '912345678');
      expect(texto('loja_online_morada'), 'Rua do Torreão 14');
      expect(texto('loja_online_cp'), '6300-610');
      expect(texto('loja_online_localidade'), 'Guarda');
      expect(find.byKey(const Key('loja_online_morada_guardada_m1')), findsOneWidget);
    });
  });

  group('servidor (proposta N1) e código', () {
    test('a proposta N1 tem o que a app chama', () {
      final sql = File(
              'docs/propostas/loja-nichos-15-11/N1_nichos_subcategorias_vendas.PROPOSTA.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(sql, contains('create table if not exists public.loja_online_subcategorias'));
      expect(sql, contains('add column if not exists publico boolean not null default false'));
      expect(sql, contains('function public.loja_online_nicho_visivel(p_nicho_id uuid)'));
      expect(sql, contains('function public.admin_loja_online_nicho_publico(p_nicho_id uuid, p_publico boolean, p_motivo text)'));
      expect(sql, contains('function public.admin_loja_online_produto_ordem(p_id uuid, p_ordem_manual integer, p_motivo text)'));
      expect(sql, contains('trg_loja_online_conta_venda'));
      final codigo = sql.split('\n').map((l) => l.split('--').first).join('\n');
      expect(codigo, isNot(contains('current_user')));
      expect(kLojaOnlineColunasClienteNichos, isNot(contains('custo')));
      for (final c in ['subcategoria_id', 'cj_listas', 'vendas_loja', 'ordem_manual']) {
        expect(kLojaOnlineColunasClienteNichos, contains(c));
        expect(sql, contains(c));
      }
    });
  });
}
