// HOME: O ESQUELETO DAS FAIXAS NÃO PODE TRANSBORDAR.
//
// Achado a 05/10/2026 pelos autotestes do CI: Android #498/#499 ("Multiple
// exceptions (2)") e iOS #165 (a varredura acabou com 0 falhas mas o teste
// caiu na mesma). Os dois erros eram o mesmo: enquanto as lojas carregam, a
// home mostra `_RailEsqueleto`, uma Row com 3 cartões de 140 px + espaços
// (456 px) num ecrã de 379 px (Android) e 408 px (iPhone) — "A RenderFlex
// overflowed by 77/48 pixels" em lib/widgets/home/home_feed.dart. O build
// do AAB e o envio para a Apple não chegaram a correr.
import 'dart:async';

import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/home/home_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Segura todas as respostas do servidor de brincar: enquanto não se solta,
/// as lojas estão "a carregar" e a home mostra o esqueleto.
var _soltar = Completer<void>();

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      httpClient: MockClient((req) async {
        await _soltar.future;
        return http.Response('[]', 200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });

  // Larguras lógicas: telemóvel pequeno, o emulador do CI (379) e o
  // simulador iPhone do CI (408) já menos as margens da home.
  for (final largura in [320.0, 379.4, 408.0]) {
    testWidgets('esqueleto a carregar cabe em $largura px', (tester) async {
      tester.view.physicalSize = Size(largura, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = RestaurantStore();
      await tester.pumpWidget(ChangeNotifierProvider<RestaurantStore>.value(
        value: store,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeFeedSections(sessaoId: null),
            ),
          ),
        ),
      ));

      // As lojas ainda não chegaram: é o esqueleto que está no ecrã.
      expect(store.restaurantsLoadedOnce, isFalse);
      expect(tester.takeException(), isNull,
          reason: 'o esqueleto transbordou a $largura px');

      // Solta o servidor, desmonta e deixa correr o que ficou agendado.
      _soltar.complete();
      _soltar = Completer<void>();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
      tester.takeException();
    });
  }
}
