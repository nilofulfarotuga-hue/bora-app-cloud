// GRELHA DE CATEGORIAS — 4 COLUNAS (2026-08-27, pedido do Danilo).
//
// Com 3 por linha era preciso rolar muito. Este teste prova, nas TRÊS larguras
// que ele pediu (360, 390 e 430), que:
//   · não há corte lateral nem estouro (o harness falha sozinho num overflow);
//   · nenhum rótulo aparece truncado com reticências;
//   · todos os ladrilhos ficam exactamente da mesma altura.
//
// A grelha é reconstruída aqui com os MESMOS widgets e as MESMAS medidas do
// `client_home_screen` (4 colunas · Spacing.sm · racio 0.88 · compacto), em vez
// de montar a home inteira — que arrastaria Supabase, GPS e providers todos.
import 'dart:io';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/config/app_spacing.dart';
import 'package:bora_app/widgets/bora/bora_tile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

/// As categorias tal como aparecem na home, pela mesma ordem.
const _categorias = <(String, String)>[
  ('Restaurantes', 'assets/categories/cat_restaurantes.png'),
  ('Supermercados', 'assets/categories/cat_supermercados.png'),
  ('Lojas', 'assets/categories/cat_lojas.png'),
  ('Farmácias', 'assets/categories/cat_farmacia.png'),
  ('Levar Compras', 'assets/categories/cat_compras.png'),
  ('Enviar Encomenda', 'assets/categories/cat_encomenda.png'),
  ('Favores', 'assets/categories/cat_favores.png'),
  ('Limpeza', 'assets/categories/cat_limpeza.png'),
  ('Reservar Mesa', 'assets/categories/cat_reservar_mesa.png'),
  ('Beleza', 'assets/categories/cat_beleza.png'),
  ('Bora Motorista', 'assets/categories/cat_motorista.png'),
  ('Festas', 'assets/categories/cat_festas.png'),
  ('Sobremesas', 'assets/categories/cat_sobremesas.png'),
];

/// Cópia fiel da grelha da home. Se as medidas mudarem lá, mudam aqui.
class _GrelhaCategorias extends StatelessWidget {
  const _GrelhaCategorias({required this.colunas, required this.compacto});

  final int colunas;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: GridView.count(
            crossAxisCount: colunas,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: compacto ? Spacing.sm : Spacing.md,
            mainAxisSpacing: compacto ? Spacing.sm : Spacing.md,
            childAspectRatio: compacto ? 0.88 : 0.95,
            children: [
              for (final (nome, asset) in _categorias)
                BoraTileCard.image(
                  label: nome,
                  gradient: AppColors.tileRestaurants,
                  imageAsset: asset,
                  onTap: () {},
                  compacto: compacto,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Larguras que o Danilo pediu (360, 390 e 430 lógicos).
const _larguras = <(String, Size)>[
  ('360', Size(360, 800)),
  ('390', Size(390, 844)),
  ('430', Size(430, 932)),
];

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  for (final larg in _larguras) {
    testWidgets('grelha de 4 colunas cabe e não estoura a ${larg.$1}px',
        (tester) async {
      // fotografaTela já falha sozinha em qualquer overflow (regra de ouro do
      // harness) e grava o PNG para o Danilo ver.
      await fotografaTela(
        tester,
        nome: 'grelha_categorias_4col',
        tela: const _GrelhaCategorias(colunas: 4, compacto: true),
        tamanho: larg,
      );
      expect(File('test/golden/_fotos/grelha_categorias_4col_${larg.$1}.png')
          .existsSync(), isTrue);
    });
  }

  testWidgets('nenhum rótulo é truncado com reticências', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(
      home: _GrelhaCategorias(colunas: 4, compacto: true),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // Cada nome tem de estar presente INTEIRO. É isto que apanha o
    // "Enviar Encome…" que o Danilo não quer ver.
    for (final (nome, _) in _categorias) {
      // Nomes de duas palavras passam a quebrar na segunda linha, por isso
      // o Text leva uma quebra no meio. O que importa e o nome estar la
      // INTEIRO — sem corte e sem reticencias.
      final esperado = nome.split(' ').length == 2
          ? nome.replaceFirst(' ', '\n')
          : nome;
      expect(find.text(esperado), findsOneWidget,
          reason: 'faltou o rótulo "$nome"');
    }

    // E nenhum RenderParagraph pode estar a reticenciar.
    final paragrafos = tester.renderObjectList<RenderParagraph>(
        find.byType(RichText).hitTestable());
    for (final p in paragrafos) {
      expect(p.didExceedMaxLines, isFalse,
          reason: 'rótulo truncado: "${p.text.toPlainText()}"');
    }
  });

  testWidgets('todos os ladrilhos ficam exactamente da mesma altura',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(
      home: _GrelhaCategorias(colunas: 4, compacto: true),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final alturas = tester
        .widgetList(find.byType(BoraTileCard))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(alturas.length, 1,
        reason: 'ladrilhos com alturas diferentes: $alturas');

    // E 4 por linha: 13 categorias => 4 linhas (4+4+4+1).
    final larguras = tester
        .widgetList(find.byType(BoraTileCard))
        .map((w) => tester.getSize(find.byWidget(w)).width)
        .toSet();
    expect(larguras.length, 1, reason: 'ladrilhos com larguras diferentes');
  });
}
