// Missão docs-reenvio-26-10: o ecrã "Candidatura em análise" da limpeza, da
// lavagem e do motorista TVDE mostra o que falta com o botão certo — num
// telemóvel estreito, sem rebentar o layout. A leitura da base é substituída.
import 'package:bora_app/services/driver_documentos.dart' show DocEmFalta;
import 'package:bora_app/services/prestador_documentos.dart';
import 'package:bora_app/services/prestador_reenvio_service.dart';
import 'package:bora_app/widgets/prestador_documentos_em_falta.dart';
import 'package:bora_app/widgets/tvde_conformidade_em_falta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _montar(WidgetTester tester, Widget filho) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: filho,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

EstadoReenvio _estado(String papel, Map<String, dynamic> linha,
        {bool atividade = false}) =>
    EstadoReenvio(
      linha: linha,
      falta: agruparDadosLegais(documentosEmFaltaPrestador(papel, linha,
          atividadeEmFalta: atividade)),
    );

void main() {
  testWidgets('lavador pendente sem nada: cada item com "Enviar agora" e os '
      'dados fiscais numa linha com "Preencher"', (tester) async {
    final linha = <String, dynamic>{
      'approval_status': 'pending',
      'docs': {},
      'nif': '215645154',
    };
    await _montar(
        tester,
        PrestadorDocumentosEmFalta(
          papel: 'washer',
          carregar: () async => _estado('washer', linha, atividade: true),
        ));

    expect(find.text('O que falta'), findsOneWidget);
    expect(find.text('Falta: foto de perfil'), findsOneWidget);
    expect(find.text('Falta: documento de identificação'), findsOneWidget);
    expect(find.text('Falta: carta de condução'), findsOneWidget);
    expect(find.text('Falta: confirmação dos materiais'), findsOneWidget);
    expect(find.text('Falta: comprovativo de atividade'), findsOneWidget);
    expect(find.textContaining('Falta: dados fiscais (nome legal, morada'),
        findsOneWidget);
    // foto, documento, carta, materiais e comprovativo → 5 "Enviar agora".
    expect(find.text('Enviar agora'), findsNWidgets(5));
    expect(find.text('Preencher'), findsOneWidget);
    expect(find.text('Suporte'), findsNothing);
    expect(tester.takeException(), isNull);

    // "Preencher" abre o formulário do cadastro já com o NIF que ele deu.
    await tester.ensureVisible(find.text('Preencher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preencher'));
    await tester.pumpAndSettle();
    expect(find.text('Dados fiscais'), findsOneWidget);
    expect(find.text('215645154'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Gravar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lavador: "Confirmar materiais" só deixa confirmar com tudo '
      'marcado', (tester) async {
    final linha = <String, dynamic>{
      'approval_status': 'pending',
      'photo_url': 'https://x/a.jpg',
      'docs': {'id_doc': 'u/id.jpg', 'driving_license': 'u/c.jpg'},
      'legal_name': 'Maria Teste',
      'nif': '215645154',
      'address': 'Rua de Teste 1, Guarda',
      'birth_date': '1990-01-01',
      'iban': 'PT50000201231234567890154',
      'dsa_self_certified_at': '2026-10-22T10:00:00Z',
    };
    await _montar(
        tester,
        PrestadorDocumentosEmFalta(
          papel: 'washer',
          carregar: () async => _estado('washer', linha),
        ));
    expect(find.text('Falta: confirmação dos materiais'), findsOneWidget);
    await tester.tap(find.text('Enviar agora'));
    await tester.pumpAndSettle();
    expect(find.text('Confirma os teus materiais'), findsOneWidget);
    final confirmo = find.widgetWithText(FilledButton, 'Confirmo');
    expect(tester.widget<FilledButton>(confirmo).onPressed, isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirma os teus materiais'), findsNothing);
  });

  testWidgets('limpeza: tudo pela app (documento e materiais pela RPC cleaner_reenviar_docs, 26/10)',
      (tester) async {
    final linha = <String, dynamic>{'approval_status': 'pending', 'docs': {}};
    await _montar(
        tester,
        PrestadorDocumentosEmFalta(
          papel: 'cleaner',
          carregar: () async => _estado('cleaner', linha),
        ));
    expect(find.text('Falta: documento de identificação'), findsOneWidget);
    expect(find.text('Falta: confirmação dos materiais'), findsOneWidget);
    expect(find.text('Suporte'), findsNothing);
    // foto de perfil + documento + materiais
    expect(find.text('Enviar agora'), findsNWidgets(3));
    expect(find.text('Preencher'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nada em falta: mensagem verde; sem rede: não mostra nada',
      (tester) async {
    await _montar(
        tester,
        PrestadorDocumentosEmFalta(
          papel: 'cleaner',
          carregar: () async => const EstadoReenvio(
              linha: {'approval_status': 'pending'}, falta: <DocEmFalta>[]),
        ));
    expect(find.textContaining('Recebemos tudo'), findsOneWidget);

    await _montar(
        tester,
        PrestadorDocumentosEmFalta(
          key: const ValueKey('sem-rede'),
          papel: 'cleaner',
          carregar: () async => null,
        ));
    expect(find.textContaining('Recebemos tudo'), findsNothing);
    expect(find.text('O que falta'), findsNothing);
  });

  testWidgets('motorista TVDE pendente: impedimentos do servidor e '
      '"Enviar agora" para a Conformidade', (tester) async {
    await _montar(
        tester,
        TvdeConformidadeEmFalta(
          carregar: () async => {
            'motivos': [
              {
                'codigo': 'cmtvde_em_falta',
                'rotulo': 'Certificado de motorista TVDE (CMTVDE) em falta'
              },
              {
                'codigo': 'contrato_operador_em_falta',
                'rotulo': 'Contrato escrito com o operador em falta'
              },
            ],
          },
        ));
    expect(find.text('Documentos TVDE em falta'), findsOneWidget);
    expect(
        find.text(
            'Falta: certificado de motorista TVDE (CMTVDE) em falta'),
        findsOneWidget);
    expect(find.text('Falta: contrato escrito com o operador em falta'),
        findsOneWidget);
    expect(find.byKey(const Key('tvde_conformidade_enviar_agora')),
        findsOneWidget);
    expect(find.text('Enviar agora'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motorista TVDE sem impedimentos: verde; erro: nada',
      (tester) async {
    await _montar(
        tester, TvdeConformidadeEmFalta(carregar: () async => {'motivos': []}));
    expect(find.textContaining('documentos TVDE estão completos'),
        findsOneWidget);

    await _montar(
        tester,
        TvdeConformidadeEmFalta(
            key: const ValueKey('erro'),
            carregar: () async => throw Exception('sem rede')));
    expect(find.textContaining('documentos TVDE'), findsNothing);
  });
}
