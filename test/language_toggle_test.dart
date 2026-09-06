import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/l10n/tr.dart';
import 'package:bora_app/widgets/language_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BoraLang.notifier.value = AppLang.pt;
  });
  tearDown(() => BoraLang.notifier.value = AppLang.pt);

  /// Monta a app do mesmo modo que o `main.dart`: um [ValueListenableBuilder]
  /// no idioma e um [KeyedSubtree] com a chave do idioma acima do Navigator.
  /// É esse par que faz o texto de TODAS as telas mudar, e não só o da tela
  /// onde o botão está — por isso o teste tem de o exercitar tal e qual.
  Widget _app(Widget toggle) => ValueListenableBuilder<AppLang>(
        valueListenable: BoraLang.notifier,
        builder: (_, __, ___) => MaterialApp(
          builder: (context, child) => KeyedSubtree(
            key: ValueKey<AppLang>(BoraLang.current),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            appBar: AppBar(actions: [toggle]),
            body: Text('Adicionar ao carrinho'.tr),
          ),
        ),
      );

  testWidgets('mostra PT e EN, e arranca em português', (tester) async {
    await tester.pumpWidget(_app(const LanguageToggle()));
    expect(find.text('PT'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(BoraLang.current, AppLang.pt);
  });

  testWidgets('um toque leva o ecrã inteiro para inglês, e outro traz de volta',
      (tester) async {
    await tester.pumpWidget(_app(const LanguageToggle()));
    expect(find.text('Adicionar ao carrinho'), findsOneWidget);

    await tester.tap(find.byType(LanguageToggle));
    await tester.pumpAndSettle();
    expect(BoraLang.current, AppLang.en);
    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.text('Adicionar ao carrinho'), findsNothing);

    await tester.tap(find.byType(LanguageToggle));
    await tester.pumpAndSettle();
    expect(BoraLang.current, AppLang.pt);
    expect(find.text('Adicionar ao carrinho'), findsOneWidget);
  });

  testWidgets('a escolha fica guardada no aparelho', (tester) async {
    await tester.pumpWidget(_app(const LanguageToggle()));
    await tester.tap(find.byType(LanguageToggle));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BoraLang.prefsKey), 'en');

    // Uma app nova, a arrancar do zero, lê o inglês de volta.
    BoraLang.notifier.value = AppLang.pt;
    await BoraLang.load();
    expect(BoraLang.current, AppLang.en);
  });

  testWidgets('idioma do aparelho não manda: sem escolha guardada abre em PT',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BoraLang.notifier.value = AppLang.en;
    await BoraLang.load();
    expect(BoraLang.current, AppLang.pt,
        reason: 'a app abre sempre em português até alguém tocar no botão');
  });

  testWidgets('o identificador para testes E2E não muda com o idioma',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const LanguageToggle()));
    expect(find.bySemanticsIdentifier('language_toggle'), findsOneWidget);

    await tester.tap(find.byType(LanguageToggle));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('language_toggle'), findsOneWidget);
    handle.dispose();
  });
}
