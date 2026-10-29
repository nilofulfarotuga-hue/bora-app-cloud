// Robô "fiscal de documentos" (missão final-app-2026-10-29, adendo 3): o painel
// do Danilo e as apps dos candidatos. Sem rede: o servidor é trocado por uma
// porta de mentira e os nomes são inventados.
import 'dart:typed_data';

import 'package:bora_app/screens/admin/admin_robo_documentos_screen.dart';
import 'package:bora_app/screens/shared/comprovativo_atividade_screen.dart';
import 'package:bora_app/services/atividade_service.dart';
import 'package:bora_app/services/robo_documentos.dart';
import 'package:bora_app/services/robo_documentos_service.dart';
import 'package:bora_app/widgets/admin_documentos.dart';
import 'package:bora_app/widgets/admin_robo_documentos.dart';
import 'package:bora_app/widgets/robo_documentos_estado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VereditoRobo vered({
  int id = 1,
  String campo = 'provider_atividade.documento_path',
  String decisao = 'errado',
  String acao = 'nenhuma',
  String modo = 'sombra',
  String? detetado = 'cartao_cidadao',
  double conf = 0.97,
  String? nome,
  String? userId,
}) =>
    VereditoRobo(
      id: id,
      campo: campo,
      decisao: decisao,
      acao: acao,
      modo: modo,
      tipoDetetado: detetado,
      confianca: conf,
      nome: nome,
      userId: userId,
      criadoEm: DateTime.utc(2026, 10, 29, 15, 0),
    );

/// Um ecrã alto: o ecrã do robô tem o histórico muito abaixo e a lista só constrói o que se vê.
void ecraAlto(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget app(Widget filho) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: filho)));

class ApiFalsa implements RoboAdminApi {
  ApiFalsa({this.cfg = const {}, this.prontosLista = const [], this.hist = const []});
  Map<String, dynamic> cfg;
  List<Map<String, dynamic>> prontosLista;
  List<VereditoRobo> hist;
  final List<String> chamadas = [];

  @override
  Future<Map<String, dynamic>> config() async => cfg;

  @override
  Future<Map<String, dynamic>> definir(String chave, Object valor) async {
    chamadas.add('definir:$chave=$valor');
    cfg = {...cfg, if (chave == 'robo_documentos_ativo') 'ativo': valor, if (chave == 'robo_documentos_modo') 'modo': valor};
    cfg = {...cfg, 'a_agir': cfg['ativo'] == true && cfg['modo'] == 'ativo'};
    return cfg;
  }

  @override
  Future<List<Map<String, dynamic>>> prontos() async => prontosLista;

  @override
  Future<List<VereditoRobo>> historico({String? userId, int limite = 100}) async => hist;

  @override
  Future<void> desfazer(int id) async => chamadas.add('desfazer:$id');

  @override
  Future<Map<String, dynamic>> lembrar(String userId) async {
    chamadas.add('lembrar:$userId');
    return {'ok': true, 'faltas': ['comprovativo de atividade']};
  }

  @override
  Future<Map<String, dynamic>> analisarPendentes() async {
    chamadas.add('analisar');
    return {'ok': true, 'candidatos': 7};
  }
}

void main() {
  group('veredito ao lado do documento (painel)', () {
    testWidgets('mostra a frase do robô e só dá "Desfazer" quando ele já agiu', (t) async {
      var desfeitos = 0;
      await t.pumpWidget(app(Column(children: [
        RoboVereditoChip(veredito: vered(), onDesfazer: (_) async => desfeitos++),
        RoboVereditoChip(
            veredito: vered(id: 2, acao: 'recusado', modo: 'ativo'),
            onDesfazer: (_) async => desfeitos++),
      ])));
      expect(find.text('Robô: parece um cartão de cidadão, não é o comprovativo das Finanças (97% de certeza)'),
          findsNWidgets(2));
      expect(find.textContaining('Modo sombra: só olhou'), findsOneWidget);
      expect(find.byKey(const Key('robo-desfazer')), findsOneWidget);
      await t.tap(find.byKey(const Key('robo-desfazer')));
      expect(desfeitos, 1);
    });

    testWidgets('DocFoto mostra o chip junto ao ficheiro', (t) async {
      await t.pumpWidget(app(DocFoto(
        titulo: 'Foto do veículo',
        urlOrPath: 'driver-documents/u1/vehicle_1.pdf',
        obrigatoria: true,
        veredito: vered(campo: 'drivers.vehicle_photo_url', detetado: 'titulo_residencia'),
      )));
      expect(find.byKey(const Key('robo-veredito')), findsOneWidget);
      expect(find.textContaining('parece um título de residência, não é uma foto do veículo'), findsOneWidget);
    });

    testWidgets('comprovativo errado: aviso vermelho e botão "Aprovar mesmo assim"', (t) async {
      var aprovou = false;
      await t.pumpWidget(app(DocComprovativoAtividade(
        atividade: const {'documento_path': 'u1/c.pdf', 'documento_tipo': 'pdf', 'atividade_status': 'em_analise'},
        falta: false,
        onAprovar: () => aprovou = true,
        veredito: vered(),
      )));
      expect(find.byKey(const Key('robo-aviso-botao-aprovar')), findsOneWidget);
      expect(find.text('Aprovar mesmo assim (o robô diz errado)'), findsOneWidget);
      // A decisão continua a ser só do Danilo: o botão funciona.
      await t.tap(find.byKey(const Key('aprovar-comprovativo')));
      expect(aprovou, isTrue);
    });

    testWidgets('comprovativo certo ou sem veredito: botão normal, sem aviso', (t) async {
      await t.pumpWidget(app(Column(children: [
        DocComprovativoAtividade(
          atividade: const {'documento_path': 'u1/c.pdf', 'documento_tipo': 'pdf', 'atividade_status': 'em_analise'},
          falta: false,
          onAprovar: () {},
          veredito: vered(decisao: 'ok', detetado: 'comprovativo_atividade_AT'),
        ),
      ])));
      expect(find.byKey(const Key('robo-aviso-botao-aprovar')), findsNothing);
      expect(find.text('Aprovar comprovativo'), findsOneWidget);
    });

    testWidgets('diálogo de aprovar: bloco vermelho só quando há documento errado', (t) async {
      final errada = {'_robo': ultimoPorCampo([
        {'id': 1, 'campo': 'provider_atividade.documento_path', 'decisao': 'errado', 'tipo_detectado': 'cartao_cidadao', 'confianca': 0.99}
      ])};
      await t.pumpWidget(app(Column(children: [RoboAvisoAprovar(linha: errada), const RoboAvisoAprovar(linha: {})])));
      expect(find.byKey(const Key('robo-aviso-aprovar')), findsOneWidget);
      expect(find.textContaining('O robô diz que há documento errado'), findsOneWidget);
    });

    testWidgets('o 400 do servidor vira mensagem clara ANTES de chamar (falta aprovar o comprovativo)', (t) async {
      final linha = {
        '_atividade': {'obrigatoria': true, 'atividade_status': 'em_analise', 'documento_path': 'u1/c.pdf'},
        '_robo': ultimoPorCampo([
          {'id': 1, 'campo': 'provider_atividade.documento_path', 'decisao': 'errado', 'tipo_detectado': 'cartao_cidadao', 'confianca': 1}
        ]),
      };
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })));
      var seguiu = true;
      final fut = avisarSeAtividadePorAprovar(ctx, linha).then((v) => seguiu = v);
      await t.pumpAndSettle();
      expect(find.text('Falta aprovar o comprovativo de atividade'), findsOneWidget);
      expect(find.textContaining('Robô: parece um cartão de cidadão'), findsOneWidget);
      await t.tap(find.text('Entendi'));
      await t.pumpAndSettle();
      await fut;
      expect(seguiu, isFalse);
    });
  });

  group('ecrã do robô (Danilo)', () {
    final cfgBase = {
      'ativo': false, 'modo': 'sombra', 'confianca_min': 0.85, 'limite_dia': 200,
      'a_agir': false, 'analises_24h': 16, 'total': 16,
    };

    testWidgets('mostra prontos para aprovar, histórico e o estado "só olha"', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(
        cfg: cfgBase,
        prontosLista: [
          {'user_id': 'u9', 'nome': 'Rui Teste Pinto', 'papeis': ['estafeta']},
        ],
        hist: [vered(nome: 'Maria Teste Silva', userId: 'u1')],
      );
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('O robô só OLHA'), findsOneWidget);
      expect(find.text('Prontos para aprovar (1)'), findsOneWidget);
      expect(find.text('Rui Teste Pinto'), findsOneWidget);
      expect(find.text('Histórico (1)'), findsOneWidget);
      expect(find.textContaining('Maria Teste Silva · Comprovativo de atividade'), findsOneWidget);
      expect(find.textContaining('só olhou'), findsOneWidget);
    });

    testWidgets('ligar o robô pede confirmação e só depois grava', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(cfg: cfgBase);
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('robo-interruptor')));
      await t.pumpAndSettle();
      expect(find.text('Ligar o robô?'), findsOneWidget);
      expect(api.chamadas, isEmpty);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(api.chamadas, isEmpty);
      await t.tap(find.byKey(const Key('robo-interruptor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ligar'));
      await t.pumpAndSettle();
      expect(api.chamadas, ['definir:robo_documentos_ativo=true']);
    });

    testWidgets('com tudo ligado e em modo ativo diz que ESTÁ A AGIR', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(cfg: {...cfgBase, 'ativo': true, 'modo': 'ativo', 'a_agir': true});
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('O robô ESTÁ A AGIR'), findsOneWidget);
    });

    testWidgets('"Lembrar este" pede confirmação e manda só àquela pessoa', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(cfg: cfgBase, hist: [vered(nome: 'Maria Teste Silva', userId: 'u1')]);
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('robo-menu-1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Lembrar este'));
      await t.pumpAndSettle();
      expect(find.text('Lembrar Maria Teste Silva?'), findsOneWidget);
      await t.tap(find.text('Lembrar'));
      await t.pumpAndSettle();
      expect(api.chamadas, ['lembrar:u1']);
    });

    testWidgets('"Analisar pendentes" pede confirmação e só olha', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(cfg: cfgBase);
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('robo-analisar')));
      await t.tap(find.byKey(const Key('robo-analisar')));
      await t.pumpAndSettle();
      expect(find.textContaining('Não manda mensagens nem muda nenhum estado'), findsOneWidget);
      await t.tap(find.text('Analisar'));
      await t.pumpAndSettle();
      expect(api.chamadas, ['analisar']);
    });

    testWidgets('desfazer o que o robô fez: confirma e chama o servidor', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(cfg: cfgBase, hist: [vered(id: 5, acao: 'recusado', modo: 'ativo', nome: 'Maria Teste Silva', userId: 'u1')]);
      await t.pumpWidget(MaterialApp(home: AdminRoboDocumentosScreen(api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('robo-menu-5')));
      await t.pumpAndSettle();
      await t.tap(find.text('Desfazer decisão do robô'));
      await t.pumpAndSettle();
      expect(find.text('Desfazer a decisão do robô?'), findsOneWidget);
      await t.tap(find.text('Desfazer'));
      await t.pumpAndSettle();
      expect(api.chamadas, ['desfazer:5']);
    });
  });

  group('app do candidato', () {
    testWidgets('com o robô em sombra não aparece nada', (t) async {
      await t.pumpWidget(app(RoboDocumentosEstadoCard(
          carregar: () async => const EstadoDocumentosApp(ativo: false))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('robo-estado-documentos')), findsNothing);
    });

    testWidgets('mostra o estado por documento, o motivo e reenvia SÓ aquele', (t) async {
      final reenviados = <String>[];
      await t.pumpWidget(app(RoboDocumentosEstadoCard(
        carregar: () async => const EstadoDocumentosApp(ativo: true, itens: [
          DocumentoEstadoApp(
              campo: 'provider_atividade.documento_path',
              decisao: 'errado',
              motivoPt: 'Enviaste o cartão de cidadão no lugar do comprovativo de atividade das Finanças.'),
          DocumentoEstadoApp(campo: 'drivers.registration_selfie_url', decisao: 'ok'),
          DocumentoEstadoApp(campo: 'drivers.vehicle_photo_url', decisao: 'duvida'),
        ]),
        aoReenviar: (campo) async => reenviados.add(campo),
      )));
      await t.pumpAndSettle();
      expect(find.text('Estado dos teus documentos'), findsOneWidget);
      expect(find.text('Precisa de ser enviado de novo'), findsOneWidget);
      expect(find.text('Recebido e parece certo'), findsOneWidget);
      expect(find.text('Em análise'), findsOneWidget);
      expect(find.textContaining('Enviaste o cartão de cidadão no lugar do comprovativo'), findsOneWidget);
      // Só o documento errado tem botão.
      expect(find.text('Enviar de novo'), findsOneWidget);
      await t.tap(find.byKey(const Key('robo-reenviar-provider_atividade.documento_path')));
      await t.pumpAndSettle();
      expect(reenviados, ['provider_atividade.documento_path']);
    });
  });

  group('verificação na hora ao enviar o comprovativo', () {
    final pdf = Uint8List.fromList('%PDF-1.4 teste'.codeUnits);
    const estado = AtividadeEstado(ePrestador: true, nifSugerido: '245123458');

    Widget ecra({required EnviarAtividade enviar, required ConfirmarEnvioAtividade confirmar}) => MaterialApp(
          home: ComprovativoAtividadeScreen(
            carregar: () async => estado,
            enviar: enviar,
            confirmarEnvio: confirmar,
            ficheiroInicial: pdf,
          ),
        );

    EnvioAtividade aviso() => const EnvioAtividade.avisoDoRobo(
          avisoRobo: 'Isto parece um cartão de cidadão, não o comprovativo das Finanças. Escolhe outro ficheiro.',
          caminho: 'u1/comprovativo_1.pdf',
        );

    testWidgets('o robô diz que não é: mostra o aviso e deixa escolher outro', (t) async {
      var enviou = 0;
      var confirmou = 0;
      await t.pumpWidget(ecra(
        enviar: ({required nif, required bytes}) async {
          enviou++;
          return aviso();
        },
        confirmar: ({required nif, required caminho}) async {
          confirmou++;
          return const EnvioAtividade.falhou('não devia chamar');
        },
      ));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('atividade-enviar')));
      await t.tap(find.byKey(const Key('atividade-enviar')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atividade-aviso-robo')), findsOneWidget);
      expect(find.text('Isto parece um cartão de cidadão, não o comprovativo das Finanças. Escolhe outro ficheiro.'),
          findsOneWidget);
      await t.tap(find.byKey(const Key('atividade-escolher-outro')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atividade-aviso-robo')), findsNothing);
      expect(enviou, 1);
      expect(confirmou, 0);
    });

    testWidgets('quem insiste ("enviar mesmo assim") regista o mesmo ficheiro', (t) async {
      String? caminhoConfirmado;
      await t.pumpWidget(ecra(
        enviar: ({required nif, required bytes}) async => aviso(),
        confirmar: ({required nif, required caminho}) async {
          caminhoConfirmado = caminho;
          return const EnvioAtividade.ok(AtividadeEstado(ePrestador: true, status: AtividadeStatus.emAnalise, temDocumento: true));
        },
      ));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('atividade-enviar')));
      await t.tap(find.byKey(const Key('atividade-enviar')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('atividade-enviar-mesmo-assim')));
      await t.pumpAndSettle();
      expect(caminhoConfirmado, 'u1/comprovativo_1.pdf');
      expect(find.textContaining('Comprovativo enviado'), findsOneWidget);
    });

    testWidgets('o robô não achou problema: segue como dantes, sem diálogo', (t) async {
      await t.pumpWidget(ecra(
        enviar: ({required nif, required bytes}) async =>
            const EnvioAtividade.ok(AtividadeEstado(ePrestador: true, status: AtividadeStatus.emAnalise, temDocumento: true)),
        confirmar: ({required nif, required caminho}) async => const EnvioAtividade.falhou('não devia chamar'),
      ));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('atividade-enviar')));
      await t.tap(find.byKey(const Key('atividade-enviar')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atividade-aviso-robo')), findsNothing);
      expect(find.textContaining('Comprovativo enviado'), findsOneWidget);
    });
  });
}
