import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/legal_info_screen.dart';

/// Ecrã "Sobre / Informação legal" (missão ronda-fecho-2026-09-22, bloco D1).
///
/// Prova num telemóvel pequeno (360×800): quem opera a Bora, o NIF, a
/// entidade RAL e o Livro de Reclamações estão no ecrã, nada estoura, e cada
/// linha pede o endereço certo (mailto:, tel:, https:).
void main() {
  Future<void> abrirEcra(WidgetTester tester, {AbrirLigacao? abrir}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester
        .pumpWidget(MaterialApp(home: LegalInfoScreen(abrirLigacao: abrir)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'mostra operador, NIF, RAL e Livro de Reclamações a 360 px sem estourar',
      (tester) async {
    await abrirEcra(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Sobre / Informação legal'), findsOneWidget);
    // [fechar-tudo-2026-11-10 · E1] Desde 09/10/2026 opera a sociedade: o
    // NIF pessoal saiu do ecrã, entra o NIPC e a sede.
    expect(find.text('Danilo Fulfaro da Silva - Unipessoal Lda'),
        findsOneWidget);
    expect(find.textContaining('NIPC 519686233'), findsOneWidget);
    expect(find.textContaining('Sede: Rua do Torreão 14, 6300-610 Guarda'),
        findsOneWidget);
    expect(find.textContaining('322151171'), findsNothing);
    expect(find.textContaining('nome individual'), findsNothing);
    expect(find.textContaining('CNIACC'), findsOneWidget);
    expect(find.text('LIVRO DE RECLAMAÇÕES'), findsOneWidget);
    // [E2b] A plataforma europeia ODR fechou (Reg. (UE) 2024/3228).
    expect(find.textContaining('ODR'), findsNothing);
    expect(find.textContaining('ec.europa.eu'), findsNothing);
    // [11/11/2026] O aviso de IA saiu da fala do Amigo e está aqui.
    expect(find.textContaining('assistente virtual automático (inteligência artificial)'),
        findsOneWidget);
    expect(find.textContaining('Não substitui o apoio humano'), findsOneWidget);
  });

  testWidgets('cada linha pede o endereço certo (mailto, tel, https)',
      (tester) async {
    final pedidos = <Uri>[];
    await abrirEcra(tester, abrir: (uri) async {
      pedidos.add(uri);
      return true;
    });

    await tocar(tester, find.text('Email'));
    await tocar(tester, find.text('Telefone'));
    await tocar(tester, find.text('LIVRO DE RECLAMAÇÕES'));
    await tocar(tester, find.text('Termos e condições'));
    await tocar(tester, find.text('Política de privacidade'));

    expect(pedidos.map((u) => u.toString()).toList(), [
      'mailto:boraappbora@gmail.com',
      'tel:+351937501673',
      'https://www.livroreclamacoes.pt/Inicio/',
      'https://boraguarda.com/termos',
      'https://boraguarda.com/privacidade',
    ]);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Não foi possível abrir'), findsNothing);
  });

  testWidgets('sem plugin para abrir ligações, avisa em vez de rebentar',
      (tester) async {
    await abrirEcra(tester, abrir: (_) async => throw StateError('sem plugin'));

    await tocar(tester, find.text('LIVRO DE RECLAMAÇÕES'));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Não foi possível abrir'), findsOneWidget);
  });
}
