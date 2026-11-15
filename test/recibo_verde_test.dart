import 'dart:io';
import 'dart:typed_data';

import 'package:bora_app/screens/admin/admin_recibo_retido.dart';
import 'package:bora_app/services/recibo_verde_service.dart';
import 'package:bora_app/widgets/recibo_verde_secao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão 12 recibos-verdes-15-11 (R2): o recibo verde com PDF nas apps.
void main() {
  group('ReciboVerdeService.caminho', () {
    test('{user_id}/{ano}-{mês com 2 dígitos}.{ext}', () {
      expect(ReciboVerdeService.caminho('u1', 2026, 11, 'Recibo.PDF'),
          'u1/2026-11.pdf');
      expect(ReciboVerdeService.caminho('u1', 2027, 1, 'foto.jpeg'),
          'u1/2027-01.jpeg');
      expect(ReciboVerdeService.caminho('u1', 2026, 12, 'x.png'),
          'u1/2026-12.png');
    });

    test('só PDF, JPG e PNG', () {
      expect(ReciboVerdeService.extensaoOuNull('a.docx'), isNull);
      expect(ReciboVerdeService.extensaoOuNull('semextensao'), isNull);
      expect(ReciboVerdeService.tipoMime('pdf'), 'application/pdf');
      expect(ReciboVerdeService.tipoMime('jpg'), 'image/jpeg');
      expect(ReciboVerdeService.tipoMime('png'), 'image/png');
    });
  });

  group('ReciboVerdeService.enviarEMarcar', () {
    test('envia o ficheiro primeiro e só depois marca, com o caminho', () async {
      final ordem = <String>[];
      String? caminhoEnviado;
      Map<String, dynamic>? params;
      final r = await ReciboVerdeService.enviarEMarcar(
        ano: 2026,
        mes: 11,
        numero: ' FR 12 ',
        bytes: Uint8List.fromList([1, 2, 3]),
        nomeFicheiro: 'recibo.pdf',
        userId: 'u1',
        enviar: (c, b, m) async {
          ordem.add('enviar');
          caminhoEnviado = c;
          expect(m, 'application/pdf');
        },
        marcar: (p) async {
          ordem.add('marcar');
          params = p;
          return {'ok': true, 'tem_pdf': true};
        },
      );
      expect(ordem, ['enviar', 'marcar']);
      expect(caminhoEnviado, 'u1/2026-11.pdf');
      expect(params!['p_pdf_path'], 'u1/2026-11.pdf');
      expect(params!['p_numero'], 'FR 12');
      expect(params!['p_year'], 2026);
      expect(params!['p_month'], 11);
      expect(r['tem_pdf'], true);
    });

    test('se o envio falhar, não marca', () async {
      var marcou = false;
      await expectLater(
        ReciboVerdeService.enviarEMarcar(
          ano: 2026,
          mes: 11,
          numero: 'FR 1',
          bytes: Uint8List(1),
          nomeFicheiro: 'r.pdf',
          userId: 'u1',
          enviar: (c, b, m) async => throw Exception('rede'),
          marcar: (p) async => marcou = true,
        ),
        throwsException,
      );
      expect(marcou, isFalse);
    });

    test('sem número, ficheiro errado ou grande: nem envia', () async {
      var enviou = false;
      Future<void> enviar(String c, Uint8List b, String m) async =>
          enviou = true;
      for (final caso in [
        ('  ', 'r.pdf', 1, 'numero_em_falta'),
        ('FR 1', 'r.docx', 1, 'ficheiro_tipo'),
        ('FR 1', 'r.pdf', ReciboVerdeService.tamanhoMaximo + 1, 'ficheiro_grande'),
      ]) {
        await expectLater(
          ReciboVerdeService.enviarEMarcar(
            ano: 2026,
            mes: 11,
            numero: caso.$1,
            bytes: Uint8List(caso.$3),
            nomeFicheiro: caso.$2,
            userId: 'u1',
            enviar: enviar,
            marcar: (p) async => null,
          ),
          throwsA(predicate((e) => e.toString().contains(caso.$4))),
        );
      }
      expect(enviou, isFalse);
    });
  });

  group('ReciboVerdeService.mensagemDoErro', () {
    test('cada erro do contrato tem uma frase simples', () {
      expect(ReciboVerdeService.mensagemDoErro('numero_em_falta'),
          contains('número'));
      expect(ReciboVerdeService.mensagemDoErro('pdf_nao_encontrado'),
          contains('não chegou'));
      expect(ReciboVerdeService.mensagemDoErro('pdf_caminho_invalido'),
          contains('não chegou'));
      expect(ReciboVerdeService.mensagemDoErro('ficheiro_grande'),
          contains('10 MB'));
      expect(ReciboVerdeService.mensagemDoErro('sem_sessao'),
          contains('sessão'));
      expect(ReciboVerdeService.mensagemDoErro('outra coisa'),
          contains('tenta outra vez'));
    });

    test('servidor antigo (função em falta) é reconhecido', () {
      expect(
          ReciboVerdeService.faltaFuncaoNoServidor(
              'PostgrestException(code: PGRST202, message: Could not find the function)'),
          isTrue);
      expect(ReciboVerdeService.faltaFuncaoNoServidor('timeout'), isFalse);
    });
  });

  group('ReciboVerdeCard', () {
    Map<String, dynamic> resumo() => {
          'nome_mes': 'novembro',
          'adquirente': {'nome': 'Empresa Teste', 'nif': '000000000'},
          'regras': {
            'anexar_texto': 'Anexe o recibo na app, em Ganhos, até 10/12/2026.',
            'iva_texto': 'IVA: isento',
          },
        };
    Map<String, dynamic> prestador({String estado = 'em_falta'}) => {
          'total': 63.9,
          'linhas': [
            {'nome': 'Entregas', 'quantidade': 5, 'valor': 23.9},
            {'nome': 'Limpezas', 'quantidade': 2, 'valor': 40},
          ],
          'descricao': 'Serviços prestados em novembro de 2026',
          'estado': estado,
          'precisa_recibo': true,
        };
    Widget app(Widget w) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: w)));

    testWidgets('total em grande, linhas por serviço e a quem passar', (t) async {
      await t.pumpWidget(app(ReciboVerdeCard(
          resumo: resumo(), prestador: prestador(), onMarcar: () {})));
      expect(find.text('Recibo verde de novembro'), findsOneWidget);
      expect(find.text('63,90 €'), findsOneWidget);
      expect(find.textContaining('Entregas: 5'), findsOneWidget);
      expect(find.textContaining('Limpezas: 2'), findsOneWidget);
      expect(find.textContaining('Passa o recibo a Empresa Teste, NIF 000000000'),
          findsOneWidget);
      expect(find.textContaining('até 10/12/2026'), findsOneWidget);
      expect(find.text('Já passei o recibo'), findsOneWidget);
    });

    testWidgets('marcado sem PDF: avisa que falta o ficheiro', (t) async {
      await t.pumpWidget(app(ReciboVerdeCard(
          resumo: resumo(),
          prestador: prestador(estado: 'sem_pdf'),
          onMarcar: () {})));
      expect(find.textContaining('Falta anexar o PDF'), findsOneWidget);
    });

    testWidgets('retido: o valor guardado em grande e o texto do servidor',
        (t) async {
      await t.pumpWidget(app(const ReciboRetidoAviso(trava: {
        'retido': true,
        'texto_app': 'O teu pagamento fica guardado.',
        'por_pagar': {'total_cents': 3527},
        'meses_em_falta': [
          {'nome': 'novembro de 2026'}
        ],
      })));
      expect(find.text('35,27 €'), findsOneWidget);
      expect(find.text('O teu pagamento fica guardado.'), findsOneWidget);
      expect(find.textContaining('novembro de 2026'), findsOneWidget);
    });
  });

  group('Painel: Retido (PT-BR)', () {
    test('o motivo vem do erro do servidor, sem o prefixo', () {
      const e = 'PostgrestException(message: recibo_verde_em_falta: Retido — falta o recibo verde de novembro de 2026, code: P0001)';
      expect(eErroReciboVerde(e), isTrue);
      expect(motivoReciboVerde(e), startsWith('Retido — falta o recibo verde de novembro'));
      expect(eErroReciboVerde('admin_required'), isFalse);
    });

    test('a semana pedida é o dia de Lisboa', () {
      expect(adminDataSemana('2026-12-07'), '2026-12-07');
      // Inverno: Lisboa = UTC.
      expect(adminDataSemana('2026-12-07T00:00:00+00:00'), '2026-12-07');
      // Verão: a meia-noite de Lisboa é 23:00 UTC do dia anterior.
      expect(adminDataSemana('2026-06-07T23:00:00+00:00'), '2026-06-08');
      expect(adminDataSemana(DateTime(2026, 12, 14)), '2026-12-14');
    });

    Widget app(Widget w) => MaterialApp(home: Scaffold(body: w));

    testWidgets('linha retida mostra o motivo e o botão Soltar', (t) async {
      await t.pumpWidget(app(AdminReciboRetidoLinha(
        linha: const {'retido': true, 'retido_motivo': 'Retido — falta o recibo verde de novembro de 2026'},
        subjectType: 'driver',
        subjectId: 'd1',
        weekStart: '2026-12-07',
        aoSoltar: () {},
      )));
      expect(find.textContaining('falta o recibo verde de novembro'), findsOneWidget);
      expect(find.text('Soltar'), findsOneWidget);
    });

    testWidgets('linha solta ou sem retenção: sem botão', (t) async {
      await t.pumpWidget(app(AdminReciboRetidoLinha(
        linha: const {'retido': false, 'retido_solto': true, 'retido_solto_motivo': 'chegou por e-mail'},
        subjectType: 'user',
        subjectId: 'u1',
        weekStart: '2026-12-07',
        aoSoltar: () {},
      )));
      expect(find.textContaining('chegou por e-mail'), findsOneWidget);
      expect(find.text('Soltar'), findsNothing);
      await t.pumpWidget(app(AdminReciboRetidoLinha(
        linha: const {'retido': false},
        subjectType: 'user',
        subjectId: 'u1',
        weekStart: '2026-12-07',
        aoSoltar: () {},
      )));
      expect(find.text('Soltar'), findsNothing);
    });
  });

  test('o NIF da Bora nunca está escrito no código do recibo', () {
    for (final f in [
      'lib/widgets/recibo_verde_secao.dart',
      'lib/services/recibo_verde_service.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(RegExp(r"'\d{9}'").hasMatch(src), isFalse, reason: f);
    }
  });
}
