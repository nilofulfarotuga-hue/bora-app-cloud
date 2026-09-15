// IDIOMA EN — as mesmas telas, em inglês, sem estourar (2026-09-01).
//
// O inglês é quase sempre mais curto do que o português, mas nem sempre: há
// rótulos que crescem. Este teste corre o harness de fotos com o idioma posto
// em EN e deixa a regra de ouro fazer o trabalho — overflow lança FlutterError
// e o teste falha sozinho.
//
// Cobre as superfícies APERTADAS, que são onde um texto mais comprido dói:
//   · o ecrã de escolha de perfil (a primeira coisa que se vê);
//   · a grelha de categorias da home, a 4 colunas, nas 3 larguras;
//   · o painel de privacidade, que é modal e tapa tudo.
import 'dart:io';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/config/app_spacing.dart';
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/l10n/tr.dart';
import 'package:bora_app/screens/role_screen.dart';
import 'package:bora_app/stores/consent_store.dart';
import 'package:bora_app/widgets/bora/bora_tile_card.dart';
import 'package:bora_app/widgets/consent_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fabrica_de_fotos.dart';

/// Os ladrilhos tal como a home os constrói. O rótulo guardado é PT (é chave do
/// mapa `semanticsIds` dos testes E2E) e a tradução acontece no desenho — por
/// isso aqui aparece `.tr`, igual ao `label: t.label.tr` do ecrã real.
const _categorias = <(String, String)>[
  ('Restaurantes', 'assets/categories/cat_restaurantes.png'),
  ('Supermercados', 'assets/categories/cat_supermercados.png'),
  ('Lojas', 'assets/categories/cat_lojas.png'),
  ('Farmácia', 'assets/categories/cat_farmacia.png'),
  ('Levar\nCompras', 'assets/categories/cat_compras.png'),
  ('Enviar\nEncomenda', 'assets/categories/cat_encomenda.png'),
  ('Favores', 'assets/categories/cat_favores.png'),
  ('Limpeza', 'assets/categories/cat_limpeza.png'),
  ('Reservar\nMesa', 'assets/categories/cat_reservar_mesa.png'),
  ('Beleza', 'assets/categories/cat_beleza.png'),
  ('Bora\nMotorista', 'assets/categories/cat_motorista.png'),
  ('Festas', 'assets/categories/cat_festas.png'),
  ('Sobremesas', 'assets/categories/cat_sobremesas.png'),
];

class _GrelhaEn extends StatelessWidget {
  const _GrelhaEn();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Spacing.sm,
            mainAxisSpacing: Spacing.sm,
            childAspectRatio: 0.88,
            children: [
              for (final (nome, asset) in _categorias)
                BoraTileCard.image(
                  label: nome.tr,
                  gradient: AppColors.tileRestaurants,
                  imageAsset: asset,
                  onTap: () {},
                  compacto: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _larguras = <(String, Size)>[
  ('360', Size(360, 800)),
  ('390', Size(390, 844)),
  ('430', Size(430, 932)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  setUp(() => BoraLang.notifier.value = AppLang.en);
  tearDown(() => BoraLang.notifier.value = AppLang.pt);

  for (final tamanho in kTamanhos) {
    testWidgets('escolha de perfil em EN — ${tamanho.$1} sem estouro',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'en_role',
        tela: const RoleScreen(),
        tamanho: tamanho,
      );
      expect(
        File('test/golden/_fotos/en_role_${tamanho.$1}.png').existsSync(),
        isTrue,
      );
    });
  }

  for (final larg in _larguras) {
    testWidgets('grelha de categorias em EN cabe a ${larg.$1}px',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'en_grelha_categorias',
        tela: const _GrelhaEn(),
        tamanho: larg,
      );
    });
  }

  testWidgets('nenhum rótulo de categoria é cortado em EN', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: _GrelhaEn()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // O nome tem de estar INTEIRO — sem reticências, que é o que denuncia
    // "Send Parc…" num ladrilho estreito de 4 colunas.
    for (final (nome, _) in _categorias) {
      expect(find.text(nome.tr), findsOneWidget,
          reason: 'o ladrilho "${nome.tr}" não aparece inteiro em inglês');
    }
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('painel de privacidade em EN não estoura no ecrã pequeno',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'en_consentimento',
      tela: ChangeNotifierProvider<ConsentStore>(
        create: (_) => ConsentStore(),
        child: const ConsentBanner(child: SizedBox.expand()),
      ),
      tamanho: kTamanhos.first,
    );
  });
}
