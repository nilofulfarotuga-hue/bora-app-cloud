import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/admin/admin_revisoes_screen.dart';
import 'package:bora_app/screens/admin/admin_suspensao_comum.dart';
import 'package:bora_app/screens/legal_info_screen.dart';
import 'package:bora_app/screens/prestador/como_o_bora_decide_screen.dart';
import 'package:bora_app/screens/prestador/conta_suspensa_screen.dart';
import 'package:bora_app/services/prestador_suspensao_service.dart';
import 'package:bora_app/widgets/admin/papeis_da_pessoa.dart';

/// Missão app-fechar-2026-11-01, bloco B8 — suspensão e revisão humana
/// (Diretiva (UE) 2024/2831, art. 11.º). Sem rede: carregadores e ações
/// falsos injetados nos ecrãs.
void main() {
  // Linha como `prestador_minha_suspensao()` a devolve (contrato confirmado
  // em produção a 01/11/2026).
  final suspensaJson = <String, dynamic>{
    'id': 42,
    'tipo': 'suspensao_temporaria',
    'tipo_conta': 'limpeza',
    'estado': 'ativa',
    'motivo': 'Três cancelamentos tardios em 30 dias (pedidos 101, 102, 103).',
    'decidido_em': '2026-11-01T10:00:00Z',
    'ate': '2026-11-10T22:59:00Z',
    'decidido_por': 'Equipa Bora (responsável)',
    'revisao_pedida_em': null,
    'revisao_prazo': null,
    'revisao_resposta': null,
    'revisto_em': null,
    'pode_pedir_revisao': true,
    'contacto_whatsapp': '+351937501673',
    'contacto_email': 'boraappbora@gmail.com',
  };

  Future<void> abrirDialogo(WidgetTester tester, Widget dialogo) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showDialog<Object?>(context: ctx, builder: (_) => dialogo),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> telemovel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('modelo e regras', () {
    test('SuspensaoInfo lê o registo e o {suspensa:false}', () {
      final s = SuspensaoInfo.fromJson(suspensaJson);
      expect(s.suspensa, isTrue);
      expect(s.id, 42);
      expect(s.tipoConta, 'limpeza');
      expect(s.ate, isNotNull);
      expect(s.podePedirRevisao, isTrue);
      expect(s.titulo, 'A tua conta foi suspensa');

      final nada = SuspensaoInfo.fromJson({'suspensa': false});
      expect(nada.suspensa, isFalse);
      expect(nada.id, isNull);
    });

    test('pedido de revisão precisa de 5 letras; motivo de suspensão de 10',
        () {
      expect(validarPedidoRevisao('  abc  '), isNotNull);
      expect(validarPedidoRevisao('abcde'), isNull);
      expect(validarMotivoSuspensao('curto'), isNotNull);
      expect(validarMotivoSuspensao('  123456789  '), isNotNull);
      expect(validarMotivoSuspensao('Cancelou 3 vezes'), isNull);
    });

    test('traduz os erros do servidor (PT-PT na app, PT-BR no painel)', () {
      expect(
          traduzirErroSuspensaoOuNull(
              'escreve_o_teu_lado: conta o que aconteceu (mínimo 5 letras)'),
          contains('5 letras'));
      expect(
          traduzirErroSuspensaoOuNull(
              'SUSPENSAO_SEM_MOTIVO: escreve o motivo (mínimo 10 letras)'),
          contains('10 letras'));
      expect(traduzirErroSuspensaoOuNull('SUSPENSAO_SEM_HUMANO: suspensao'),
          contains('pessoa'));
      expect(traduzirErroSuspensaoOuNull('outra coisa qualquer'), isNull);
    });

    test('RevisaoPendente lê uma linha da vista admin_fila_revisoes', () {
      final r = RevisaoPendente.fromJson({
        'id': 7,
        'tipo_conta': 'estafeta',
        'entidade_tabela': 'drivers',
        'entidade_id': 'abcdef12-3456-7890',
        'tipo': 'suspensao',
        'estado': 'em_revisao',
        'motivo': 'Entregas marcadas sem ir ao cliente.',
        'factos': {'pedidos': 2},
        'revisao_pedida_em': '2026-11-01T12:00:00Z',
        'revisao_via': 'app',
        'revisao_texto': 'Fui sim, o cliente não abriu.',
        'revisao_prazo': '2026-11-08T12:00:00Z',
        'dias_restantes': '6.5',
        'atrasada': false,
      });
      expect(r.id, 7);
      expect(r.rotuloConta, 'Entregador');
      expect(r.rotuloTipo, 'Suspensão sem data de fim');
      expect(r.rotuloEstado, 'Revisão pedida');
      expect(r.diasRestantes, 6.5);
      expect(r.eProposta, isFalse);
      expect(r.factos['pedidos'], 2);
    });
  });

  group('app do prestador — "A minha conta foi suspensa"', () {
    testWidgets('mostra motivo, até quando, "Equipa Bora" e o botão',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(MaterialApp(
        home: ContaSuspensaScreen(
          textoSemRegisto: 'texto antigo',
          carregar: () async => SuspensaoInfo.fromJson(suspensaJson),
          pedirRevisao: (_) async => 'ok',
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('A tua conta foi suspensa'), findsOneWidget);
      expect(find.textContaining('Três cancelamentos tardios'), findsOneWidget);
      expect(find.textContaining('Até quando'), findsOneWidget);
      expect(find.textContaining('/11/2026'), findsWidgets);
      expect(find.textContaining('Equipa Bora'), findsWidgets);
      expect(find.text('Pedir revisão'), findsOneWidget);
      expect(find.text('texto antigo'), findsNothing);
      expect(find.text('WhatsApp da Bora'), findsOneWidget);
    });

    testWidgets('pedir revisão com menos de 5 letras NÃO envia; com 5 envia',
        (tester) async {
      await telemovel(tester);
      final enviados = <String>[];
      var leituras = 0;
      await tester.pumpWidget(MaterialApp(
        home: ContaSuspensaScreen(
          textoSemRegisto: 'texto antigo',
          carregar: () async {
            leituras++;
            return SuspensaoInfo.fromJson(suspensaJson);
          },
          pedirRevisao: (m) async {
            enviados.add(m);
            return 'Pedido registado. Uma pessoa da equipa Bora responde por '
                'escrito até 08/11.';
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('pedir-revisao')));
      await tester.tap(find.byKey(const ValueKey('pedir-revisao')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('texto-revisao')), '  abc ');
      await tester.ensureVisible(find.byKey(const ValueKey('enviar-revisao')));
      await tester.tap(find.byKey(const ValueKey('enviar-revisao')));
      await tester.pumpAndSettle();
      expect(enviados, isEmpty);
      expect(find.textContaining('pelo menos 5 letras'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('texto-revisao')),
          'Não cancelei, a cliente pediu para mudar a hora.');
      await tester.ensureVisible(find.byKey(const ValueKey('enviar-revisao')));
      await tester.tap(find.byKey(const ValueKey('enviar-revisao')));
      await tester.pumpAndSettle();
      expect(enviados, ['Não cancelei, a cliente pediu para mudar a hora.']);
      expect(find.textContaining('Pedido registado'), findsOneWidget);
      expect(leituras, 2, reason: 'relê o estado depois de pedir');
    });

    testWidgets('sem suspensão registada mostra o texto antigo e os contactos',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContaSuspensaView(
            textoSemRegisto: 'A tua conta está em revisão pela equipa Bora.',
            tituloSemRegisto: 'Conta suspensa para revisão',
            carregar: () async => SuspensaoInfo.semRegisto,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Conta suspensa para revisão'), findsOneWidget);
      expect(find.text('A tua conta está em revisão pela equipa Bora.'),
          findsOneWidget);
      expect(find.text('Pedir revisão'), findsNothing);
      expect(find.text('Email da Bora'), findsOneWidget);
    });

    testWidgets('registo de OUTRO papel não aparece neste ecrã',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContaSuspensaView(
            textoSemRegisto: 'texto antigo do estafeta',
            tiposConta: const {'estafeta', 'motorista'},
            carregar: () async => SuspensaoInfo.fromJson(suspensaJson),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('texto antigo do estafeta'), findsOneWidget);
      expect(find.textContaining('Três cancelamentos'), findsNothing);
    });

    testWidgets(
        'portão do parceiro: loja desligada mostra o motivo e deixa entrar',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(MaterialApp(
        home: PortaoContaSuspensa(
          desligado: true,
          carregar: () async => SuspensaoInfo.fromJson({
            ...suspensaJson,
            'tipo': 'suspensao',
            'tipo_conta': 'parceiro',
            'ate': null,
          }),
          child: const Scaffold(body: Text('PAINEL DA LOJA')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PAINEL DA LOJA'), findsNothing);
      expect(find.textContaining('Sem data de fim'), findsOneWidget);
      await tester.ensureVisible(find.text('Entrar no painel na mesma'));
      await tester.tap(find.text('Entrar no painel na mesma'));
      await tester.pumpAndSettle();
      expect(find.text('PAINEL DA LOJA'), findsOneWidget);
    });
  });

  group('Como o Bora decide', () {
    testWidgets('texto inteiro no ecrã e ligação em Sobre / Informação legal',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(const MaterialApp(home: LegalInfoScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      final linha = find.byKey(const ValueKey('legal-como-o-bora-decide'));
      await tester.ensureVisible(linha);
      await tester.tap(linha);
      await tester.pumpAndSettle();
      expect(find.byType(ComoOBoraDecideScreen), findsOneWidget);
      expect(find.text(ComoOBoraDecide.titulo), findsOneWidget);
      expect(find.text('1. Quem somos e como falar com uma pessoa'),
          findsOneWidget);
      expect(ComoOBoraDecide.seccoes.map((s) => s.$1),
          contains('4. O que tem sempre uma pessoa a decidir'));
      expect(tester.takeException(), isNull);
      expect(ComoOBoraDecide.seccoes, hasLength(7));
    });
  });

  group('painel — motivo obrigatório', () {
    testWidgets('diálogo "Suspender com motivo" recusa menos de 10 letras',
        (tester) async {
      final chamadas = <MotivoSuspensaoResultado>[];
      await abrirDialogo(
        tester,
        DialogoSuspenderComMotivo(
          nome: 'Maria Teste',
          tipos: kTipoDesativar,
          aoConfirmar: (r) async {
            chamadas.add(r);
            return null;
          },
        ),
      );

      await tester.enterText(
          find.byKey(const ValueKey('suspensao-motivo')), '123456789');
      await tester.tap(find.byKey(const ValueKey('suspensao-confirmar')));
      await tester.pumpAndSettle();
      expect(chamadas, isEmpty);
      expect(find.textContaining('pelo menos 10 letras'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('suspensao-motivo')),
          'Cliente queixou-se de mau trato no pedido 555.');
      await tester.tap(find.byKey(const ValueKey('suspensao-confirmar')));
      await tester.pumpAndSettle();
      expect(chamadas, hasLength(1));
      expect(chamadas.single.tipo, 'suspensao');
      expect(chamadas.single.motivo,
          'Cliente queixou-se de mau trato no pedido 555.');
      expect(find.byType(DialogoSuspenderComMotivo), findsNothing,
          reason: 'fecha quando o servidor aceita');
    });

    testWidgets('erro do servidor aparece dentro do diálogo, traduzido',
        (tester) async {
      await abrirDialogo(
        tester,
        DialogoSuspenderComMotivo(
          tipos: kTipoDesativar,
          aoConfirmar: (_) async =>
              throw Exception('SUSPENSAO_SEM_HUMANO: suspensao só pessoa'),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('suspensao-motivo')),
          'Documento de identificação falso.');
      await tester.tap(find.byKey(const ValueKey('suspensao-confirmar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suspensao-erro')), findsOneWidget);
      expect(find.textContaining('só uma pessoa da equipe'), findsOneWidget);
    });

    testWidgets('pedirMotivoAdmin com mínimo 10 não fecha com 9 letras',
        (tester) async {
      String? devolvido = 'nada';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  devolvido = await pedirMotivoAdmin(
                    ctx,
                    titulo: 'Suspender lavador?',
                    explicacao: 'x',
                    confirmar: 'Suspender',
                    minimo: 10,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('campo_motivo')), 'abcdefghi');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspender'));
      await tester.pumpAndSettle();
      expect(find.text('Escreva o motivo (mínimo 10 letras).'), findsOneWidget);
      expect(devolvido, 'nada');

      await tester.enterText(
          find.byKey(const ValueKey('campo_motivo')), 'Não apareceu 3 vezes');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspender'));
      await tester.pumpAndSettle();
      expect(devolvido, 'Não apareceu 3 vezes');
    });
  });

  group('painel — ecrã Revisões', () {
    final fila = [
      RevisaoPendente.fromJson({
        'id': 11,
        'tipo_conta': 'limpeza',
        'entidade_tabela': 'cleaners',
        'entidade_id': '11111111-aaaa',
        'tipo': 'suspensao',
        'estado': 'em_revisao',
        'motivo': 'Três cancelamentos tardios em 30 dias.',
        'revisao_pedida_em': '2026-11-01T09:00:00Z',
        'revisao_via': 'app',
        'revisao_texto': 'A cliente mudou a hora.',
        'revisao_prazo': '2026-11-08T09:00:00Z',
        'dias_restantes': 6.9,
        'atrasada': false,
      }),
      RevisaoPendente.fromJson({
        'id': 12,
        'tipo_conta': 'lavagem',
        'entidade_tabela': 'washers',
        'entidade_id': '22222222-bbbb',
        'tipo': 'proposta_automatica',
        'estado': 'pendente_decisao',
        'motivo': 'Nota média abaixo de 3,5 nos últimos 10 serviços.',
        'factos': {'nota_media': 3.2},
        'atrasada': false,
      }),
    ];

    testWidgets('mostra as linhas da fila com prazo e ações certas',
        (tester) async {
      await telemovel(tester);
      final respostas = <(int, String, String)>[];
      await tester.pumpWidget(MaterialApp(
        home: AdminRevisoesScreen(
          carregarFila: () async => fila,
          carregarAtivas: () async => const [],
          responder: (id, d, t, _) async => respostas.add((id, d, t)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Fila (2)'), findsOneWidget);
      expect(find.textContaining('Limpeza · Suspensão sem data de fim'),
          findsOneWidget);
      expect(find.text('Revisão pedida'), findsOneWidget);
      expect(find.text('Proposta automática'), findsWidgets);
      expect(find.textContaining('A cliente mudou a hora.'), findsOneWidget);
      expect(find.textContaining('faltam 6.9 dias'), findsOneWidget);
      expect(find.byKey(const ValueKey('responder-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('decidir-12')), findsOneWidget);

      // Responder: menos de 10 letras não envia.
      await tester.tap(find.byKey(const ValueKey('responder-11')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('decisao-texto')), 'curto');
      await tester.tap(find.byKey(const ValueKey('decisao-confirmar')));
      await tester.pumpAndSettle();
      expect(respostas, isEmpty);
      expect(find.textContaining('pelo menos 10 letras'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('decisao-texto')),
          'Vimos as mensagens: a cliente mudou a hora. Fica mantida por outros 2 casos.');
      await tester.tap(find.byKey(const ValueKey('decisao-confirmar')));
      await tester.pumpAndSettle();
      expect(respostas, hasLength(1));
      expect(respostas.single.$1, 11);
      expect(respostas.single.$2, 'mantida');
    });
  });
}
