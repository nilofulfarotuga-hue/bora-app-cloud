import 'package:bora_app/widgets/driver_push_warning_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ronda-fecho-2026-09-22 · A8] Estafeta ONLINE sem aparelho registado para
/// notificações não recebe pedidos — e antes não sabia. O Ney esteve 24 h
/// "online" no iPhone sem uma única oferta (16/09).
///
/// A verificação é injectada (`checker`) de propósito: o cartão real pergunta
/// ao servidor (`meu_estado_push`), e o teste não precisa de Supabase.
void main() {
  const aviso = DriverPushWarningCard.textoAviso;
  const botao = DriverPushWarningCard.textoBotao;

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('online e sem aparelho registado → mostra o aviso e o botão',
      (tester) async {
    await pump(
      tester,
      DriverPushWarningCard(isOnline: true, checker: () async => false),
    );
    await tester.pump();
    expect(find.text(aviso), findsOneWidget);
    expect(find.text(botao), findsOneWidget);
  });

  testWidgets('online e com aparelho registado → não desenha nada',
      (tester) async {
    await pump(
      tester,
      DriverPushWarningCard(isOnline: true, checker: () async => true),
    );
    await tester.pump();
    expect(find.text(aviso), findsNothing);
    expect(find.byKey(const Key('driver_push_warning_card')), findsNothing);
  });

  testWidgets('offline → nem pergunta ao servidor nem avisa', (tester) async {
    var chamadas = 0;
    await pump(
      tester,
      DriverPushWarningCard(
        isOnline: false,
        checker: () async {
          chamadas++;
          return false;
        },
      ),
    );
    await tester.pump();
    expect(chamadas, 0);
    expect(find.text(aviso), findsNothing);
  });

  testWidgets('servidor falha → não desenha nada e não rebenta',
      (tester) async {
    await pump(
      tester,
      DriverPushWarningCard(
        isOnline: true,
        checker: () async => throw Exception('sem rede'),
      ),
    );
    await tester.pump();
    expect(find.text(aviso), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'o botão volta a registar e o cartão esconde-se quando o token aparece',
      (tester) async {
    var temToken = false;
    var reativou = 0;
    await pump(
      tester,
      DriverPushWarningCard(
        isOnline: true,
        checker: () async => temToken,
        reativar: () async {
          reativou++;
          temToken = true;
        },
      ),
    );
    await tester.pump();
    expect(find.text(aviso), findsOneWidget);

    await tester.tap(find.text(botao));
    await tester.pump();
    await tester.pump();

    expect(reativou, 1);
    expect(find.text(aviso), findsNothing);
  });

  testWidgets('o botão sem sucesso diz que continua sem aparelho',
      (tester) async {
    await pump(
      tester,
      DriverPushWarningCard(
        isOnline: true,
        checker: () async => false,
        reativar: () async {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text(botao));
    await tester.pump();
    await tester.pump();

    expect(find.text(aviso), findsOneWidget);
    expect(find.textContaining('Ainda sem aparelho registado'), findsOneWidget);
    expect(find.text(botao), findsOneWidget); // volta a estar carregável
  });

  testWidgets('volta a perguntar a cada 2 minutos enquanto online',
      (tester) async {
    var chamadas = 0;
    await pump(
      tester,
      DriverPushWarningCard(
        isOnline: true,
        checker: () async {
          chamadas++;
          return true;
        },
      ),
    );
    await tester.pump();
    expect(chamadas, 1);

    await tester.pump(const Duration(minutes: 2, seconds: 1));
    await tester.pump();
    expect(chamadas, 2);
  });

  testWidgets('passa a offline → o aviso desaparece', (tester) async {
    var online = true;
    late StateSetter mudar;
    await pump(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          mudar = setState;
          return DriverPushWarningCard(
            isOnline: online,
            checker: () async => false,
          );
        },
      ),
    );
    await tester.pump();
    expect(find.text(aviso), findsOneWidget);

    mudar(() => online = false);
    await tester.pump();
    expect(find.text(aviso), findsNothing);
  });
}
