// O AMIGO — ecrã do rosto, entrada na home e voz (missão m11-amigo-rosto, 09/11/2026).
import 'dart:async';

import 'package:bora_app/screens/client/assistant/amigo_bora_entrada.dart';
import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/amigo/amigo_boca.dart';
import 'package:bora_app/widgets/amigo/amigo_rosto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voz falsa: fala cada palavra a 120 ms e avisa o início, as palavras e o fim.
class _VozFalsa extends AmigoMotorVoz {
  _VozFalsa({this.nome = 'Voz de teste (pt-PT)'});
  final String? nome;
  final List<String> ditas = [];
  bool parada = false;

  @override
  Future<String?> preparar(double velocidade) async => nome;

  @override
  Future<void> falar(String texto) async {
    ditas.add(texto);
    parada = false;
    scheduleMicrotask(() => aoComecar?.call());
    var t = 0;
    for (final m in RegExp(r'\S+').allMatches(texto)) {
      t += 120;
      final inicio = m.start;
      Timer(Duration(milliseconds: t), () {
        if (!parada) aoPalavra?.call(inicio);
      });
    }
    Timer(Duration(milliseconds: t + 150), () {
      if (!parada) aoAcabar?.call();
    });
  }

  @override
  Future<void> parar() async => parada = true;
}

class _OuvidoFalso extends AmigoOuvido {
  _OuvidoFalso(this.frase);
  final String frase;
  @override
  Future<bool> iniciar({required void Function() aoParar}) async => true;
  @override
  Future<void> ouvir(void Function(String texto, bool fim) aoOuvir) async {
    Timer(const Duration(milliseconds: 200), () => aoOuvir('quero um', false));
    Timer(const Duration(milliseconds: 400), () => aoOuvir(frase, true));
  }

  @override
  Future<void> parar() async {}
}

class _CerebroFalso extends AmigoCerebro {
  final List<String> enviadas = [];
  final List<String> eventos = [];
  final List<String?> guardadas = [];
  int deixas = 0;

  @override
  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) async =>
      AssistantReply.fromJson({
        'texto': 'Boa noite, Ana! Sou o Amigo Bora. Se te apetecer, preparo-te o do costume do Boom.',
        'emocao': 'alegre',
        'saudacao': 'simples',
      });

  @override
  Future<AssistantReply> enviar({
    required String? conversationId,
    required String mensagem,
    double? lat,
    double? lng,
    bool apartamento = false,
  }) async {
    enviadas.add(mensagem);
    deixas++;
    return AssistantReply.fromJson({
      'conversation_id': 'c-1',
      'texto': 'Tenho um hambúrguer clássico no Boom. Queres que prepare?',
      'emocao': 'alegre',
      'deixa': {
        'id': 'd-$deixas',
        'tipo': deixas.isOdd ? 'promocao' : 'parceiro_novo',
        'texto': deixas.isOdd ? 'Já viste? Pizza a metade hoje.' : 'Novidade na Bora: chegou o Fuku.',
        'acao': {'tipo': 'abrir_loja', 'destino': 'fuku'},
      },
    });
  }

  @override
  Future<(String?, List<AssistantReply>)> conversaRecente() async =>
      (null, const <AssistantReply>[]);

  @override
  Future<void> guardarConversa(String? id) async => guardadas.add(id);

  @override
  Future<void> evento(String tipo, {int? duracaoS}) async => eventos.add(tipo);
}

Future<void> _correr(WidgetTester tester, Duration d) async {
  final fim = d.inMilliseconds;
  for (var t = 0; t < fim; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssistantFlags.reset();
  });

  group('a cara certa para cada momento', () {
    test('estado do ecrã → expressão', () {
      expect(amigoEmocaoParaEstado(fase: AmigoFase.aOuvir), AmigoEmocao.aOuvir);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.aPensar), AmigoEmocao.pensativo);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.acordar), AmigoEmocao.alegre);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.aFalar, erro: true), AmigoEmocao.confuso);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.aFalar, aDizerDeixa: true), AmigoEmocao.alegre);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.aFalar), AmigoEmocao.aFalar);
      expect(amigoEmocaoParaEstado(fase: AmigoFase.parado), AmigoEmocao.neutro);
    });

    test('o servidor manda quando diz; sem ele decide-se pela resposta', () {
      AssistantReply r(Map<String, dynamic> j) => AssistantReply.fromJson(j);
      expect(
          amigoEmocaoParaEstado(
              fase: AmigoFase.aFalar, resposta: r({'texto': 'Ok', 'emocao': 'surpreso'})),
          AmigoEmocao.surpreso);
      expect(
          amigoEmocaoParaEstado(
              fase: AmigoFase.aFalar, resposta: r({'texto': 'Não encontrei nada perto de ti.'})),
          AmigoEmocao.triste);
      expect(
          amigoEmocaoParaEstado(
              fase: AmigoFase.aFalar, resposta: r({'texto': 'Hum?', 'handoff': true})),
          AmigoEmocao.confuso);
      expect(
          amigoEmocaoParaEstado(
              fase: AmigoFase.aFalar, resposta: r({'texto': 'A loja está fechada agora.'})),
          AmigoEmocao.triste);
      // emoção estranha do servidor: cai na regra da app
      expect(
          amigoEmocaoParaEstado(
              fase: AmigoFase.aFalar, resposta: r({'texto': 'Olá', 'emocao': 'zangado'})),
          AmigoEmocao.aFalar);
    });
  });

  group('voz', () {
    _vozTardia();
    _aprendeVelocidade();
    test('escolhe sempre pt-PT, nunca pt-BR', () {
      expect(
          escolherVozPtPt([
            {'name': 'Google português do Brasil', 'locale': 'pt-BR'},
            {'name': 'pt-pt-x-sfs-local', 'locale': 'pt-PT'},
          ])?['locale'],
          'pt-PT');
      expect(
          escolherVozPtPt([
            {'name': 'Microsoft Helia - Portuguese (Portugal)', 'locale': 'pt-PT'},
            {'name': 'Microsoft Raquel Online (Natural) - Portuguese (Portugal)', 'locale': 'pt-PT'},
          ])?['name'],
          contains('Raquel'),
          reason: 'a voz natural (a do protótipo do Dipsy) primeiro');
      expect(escolherVozPtPt([
        {'name': 'Luciana', 'locale': 'pt-BR'},
        {'name': 'Samantha', 'locale': 'en-US'},
      ]), isNull, reason: 'sem pt-PT: só legenda, nunca pt-BR nem inglês');
      expect(escolherVozPtPt([
        {'name': 'Joana', 'locale': 'pt_PT', 'quality': 'enhanced'},
      ])?['name'], 'Joana');
      // o que o Chrome do Android devolve (emulador, 09/11)
      expect(escolherVozPtPt([
        {'name': 'Portuguese Brazil', 'locale': 'pt_BR'},
        {'name': 'Portuguese Portugal', 'locale': 'pt_PT'},
      ])?['name'], 'Portuguese Portugal');
    });

    testWidgets('sem voz pt-PT fala por legenda e a boca mexe-se na mesma', (tester) async {
      final voz = AmigoVoz(motor: _VozFalsa(nome: null));
      await voz.preparar();
      expect(voz.temVozPtPt, isFalse);
      var acabou = false;
      unawaited(voz.falar('Olá, eu sou o Amigo.').then((_) => acabou = true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(voz.legenda.value, 'Olá, eu sou o Amigo.');
      expect(voz.bocaAgora(), isNotNull);
      await tester.pump(const Duration(seconds: 4));
      expect(acabou, isTrue);
      expect(voz.bocaAgora(), isNull);
      voz.dispose();
    });

    testWidgets('o botão de som fica lembrado', (tester) async {
      final voz = AmigoVoz(motor: _VozFalsa());
      await voz.preparar();
      expect(voz.somLigado.value, isTrue);
      await voz.alternarSom();
      final p = await SharedPreferences.getInstance();
      expect(p.getBool(kAmigoSomKey), isFalse);
      final outra = AmigoVoz(motor: _VozFalsa());
      await outra.preparar();
      expect(outra.somLigado.value, isFalse);
      voz.dispose();
      outra.dispose();
    });
  });

  group('ecrã do Amigo', () {
    _vozBloqueadaNoTelemovel();
    _mensagemInicial();
    _voltar();
    Future<(_CerebroFalso, _VozFalsa, List<int>)> abrir(WidgetTester tester,
        {Size tamanho = const Size(390, 844)}) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cerebro = _CerebroFalso();
      final motor = _VozFalsa();
      final verConversa = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: AmigoScreen(
          cerebro: cerebro,
          voz: AmigoVoz(motor: motor),
          ouvido: _OuvidoFalso('quero um hambúrguer'),
          aoVerConversa: () => verConversa.add(1),
        ),
      ));
      return (cerebro, motor, verConversa);
    }

    testWidgets('acorda, sorri e diz a saudação pelo nome, com legenda', (tester) async {
      final (cerebro, motor, _) = await abrir(tester);
      expect(cerebro.eventos, contains('abrir'));
      await _correr(tester, const Duration(milliseconds: 900));
      expect(motor.ditas.first, startsWith('Boa noite, Ana!'));
      expect(find.byKey(const Key('amigo-legenda')), findsOneWidget);
      expect(find.textContaining('do costume do Boom', findRichText: true), findsOneWidget);
      expect(find.bySemanticsLabel('Amigo, alegre'), findsOneWidget);
      await _correr(tester, const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _correr(tester, const Duration(milliseconds: 300));
      expect(cerebro.eventos, contains('fim'));
    });

    testWidgets('escrever: pensa, responde a falar e diz a deixa em voz com cartão',
        (tester) async {
      final (cerebro, motor, _) = await abrir(tester);
      await _correr(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('amigo-escrever')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('amigo-caixa-texto')), 'quero um hambúrguer');
      await tester.tap(find.byKey(const Key('amigo-enviar')));
      await tester.pump();
      expect(cerebro.enviadas, ['quero um hambúrguer']);
      expect(cerebro.eventos, contains('escrita'));
      await _correr(tester, const Duration(seconds: 4));
      expect(motor.ditas, contains('Tenho um hambúrguer clássico no Boom. Queres que prepare?'));
      expect(motor.ditas.last, 'Já viste? Pizza a metade hoje.',
          reason: 'no fim diz a deixa em voz');
      expect(find.byKey(const Key('amigo-deixa-cartao')), findsOneWidget);
      expect(cerebro.guardadas, contains('c-1'));
      // segunda conversa → outra deixa (a rotação vem do servidor)
      await tester.tap(find.byKey(const Key('amigo-escrever')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('amigo-caixa-texto')), 'e uma bebida');
      await tester.tap(find.byKey(const Key('amigo-enviar')));
      await _correr(tester, const Duration(seconds: 4));
      expect(motor.ditas.last, 'Novidade na Bora: chegou o Fuku.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _correr(tester, const Duration(milliseconds: 300));
    });

    testWidgets('microfone: ouve, envia por voz e conta como voz', (tester) async {
      final (cerebro, _, _) = await abrir(tester);
      await _correr(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('amigo-microfone')));
      await tester.pump();
      expect(find.bySemanticsLabel('Amigo, a ouvir'), findsOneWidget);
      await _correr(tester, const Duration(milliseconds: 600));
      expect(cerebro.enviadas, ['quero um hambúrguer']);
      expect(cerebro.eventos, contains('voz'));
      await _correr(tester, const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _correr(tester, const Duration(milliseconds: 300));
    });

    testWidgets('"Ver conversa" guarda a conversa e abre o chat escrito', (tester) async {
      final (cerebro, _, ver) = await abrir(tester);
      await _correr(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('amigo-escrever')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('amigo-caixa-texto')), 'olá');
      await tester.tap(find.byKey(const Key('amigo-enviar')));
      await _correr(tester, const Duration(seconds: 4));
      await tester.tap(find.byKey(const Key('amigo-ver-conversa')));
      await _correr(tester, const Duration(milliseconds: 300));
      expect(ver, [1]);
      expect(cerebro.guardadas.last, 'c-1');
      await tester.pumpWidget(const SizedBox());
      await _correr(tester, const Duration(milliseconds: 300));
    });

    testWidgets('ecrã pequeno (320x568) e com o teclado aberto não estoura', (tester) async {
      final (_, _, _) = await abrir(tester, tamanho: const Size(320, 568));
      await _correr(tester, const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('amigo-escrever')));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await _correr(tester, const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _correr(tester, const Duration(milliseconds: 300));
    });
  });

  group('home', () {
    testWidgets('rosto ligado: o rostinho vivo com "Sou o Amigo. Fala comigo"', (tester) async {
      var abriu = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmigoBoraEntrada(abrir: () => abriu++)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('amigo-rosto-entrada')), findsOneWidget);
      expect(find.byKey(const Key('amigo-bora-botao')), findsNothing,
          reason: '"Ajuda-me a escolher" sem rosto saiu');
      expect(find.byType(AmigoRosto), findsOneWidget);
      await tester.tap(find.byKey(const Key('amigo-rosto-entrada')));
      expect(abriu, 1);
    });

    testWidgets('rosto desligado no painel: volta o botão de 08/11', (tester) async {
      AssistantFlags.aplicar({'assistant_enabled': true, 'amigo_rosto_ativo': false});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AmigoBoraEntrada())));
      await tester.pump();
      expect(find.byKey(const Key('amigo-bora-botao')), findsOneWidget);
      expect(find.byKey(const Key('amigo-rosto-entrada')), findsNothing);
    });

    testWidgets('assistente desligado: nada aparece (nem o mosaico)', (tester) async {
      AssistantFlags.aplicar({'assistant_enabled': false});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AmigoBoraEntrada())));
      await tester.pump();
      expect(find.byType(AmigoRosto), findsNothing);
      expect(amigoMosaicoVisivel(), isFalse);
    });

    test('mosaico: segue os três interruptores', () {
      AssistantFlags.aplicar({'assistant_enabled': true});
      expect(amigoMosaicoVisivel(), isTrue, reason: 'sem linha no servidor vale o padrão (ligado)');
      AssistantFlags.aplicar({'assistant_enabled': true, 'amigo_mosaico_categorias': false});
      expect(amigoMosaicoVisivel(), isFalse);
      AssistantFlags.aplicar({'assistant_enabled': true, 'amigo_rosto_ativo': false});
      expect(amigoMosaicoVisivel(), isFalse);
    });

    test('definições do painel chegam à app', () {
      AssistantFlags.aplicar({
        'assistant_enabled': true,
        'amigo_rosto_variante': 'rosto',
        'amigo_voz_velocidade': 1.4,
        'amigo_voz_ligada_por_defeito': false,
      });
      expect(AssistantFlags.rostoVariante.value, 'rosto');
      expect(AssistantFlags.vozVelocidade.value, 1.4);
      expect(AssistantFlags.vozPorDefeito.value, isFalse);
      AssistantFlags.aplicar({'assistant_enabled': true, 'amigo_voz_velocidade': 9});
      expect(AssistantFlags.vozVelocidade.value, 2, reason: 'limite 0,5–2');
    });

    testWidgets('mosaico "Amigo" na grelha de 4 colunas não estoura', (tester) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var abriu = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GridView.count(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.88,
            padding: const EdgeInsets.all(16),
            children: [
              AmigoMosaico(onTap: () => abriu++),
              for (var i = 0; i < 3; i++) const ColoredBox(color: Colors.green),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('amigo-mosaico')));
      expect(abriu, 1);
      expect(find.text('Amigo'), findsOneWidget);
    });
  });
}

/// Voz que só aparece à segunda procura (como no Chrome do Android).
class _VozTardia extends AmigoMotorVoz {
  int procuras = 0;
  final ditas = <String>[];
  @override
  Future<String?> preparar(double velocidade) async => ++procuras >= 2 ? 'Portuguese Portugal' : null;
  @override
  Future<void> falar(String texto) async {
    ditas.add(texto);
    scheduleMicrotask(() => aoComecar?.call());
    Timer(const Duration(milliseconds: 300), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

void _vozTardia() {
  testWidgets('voz que chega tarde: procura outra vez antes de falar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final motor = _VozTardia();
    final voz = AmigoVoz(motor: motor);
    await voz.preparar();
    expect(voz.temVozPtPt, isFalse);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2100)));
    unawaited(voz.falar('Olá!'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    expect(voz.temVozPtPt, isTrue);
    expect(motor.ditas, ['Olá!'], reason: 'falou com a voz que apareceu');
    voz.dispose();
  });
}

/// Motor sem eventos de palavra que fala ao dobro do tempo estimado.
class _VozLentaSemEventos extends AmigoMotorVoz {
  @override
  Future<String?> preparar(double velocidade) async => 'Portuguese Portugal';
  @override
  Future<void> falar(String texto) async {
    scheduleMicrotask(() => aoComecar?.call());
    final est = AmigoFala(texto).duracaoEstimada;
    Timer(Duration(milliseconds: (est * 2).round()), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

void _aprendeVelocidade() {
  testWidgets('sem eventos de palavra: aprende a velocidade real da voz', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var agora = 0.0;
    final voz = AmigoVoz(motor: _VozLentaSemEventos(), relogio: () => agora);
    await voz.preparar();
    for (var i = 0; i < 3; i++) {
      var fim = false;
      unawaited(voz.falar('O teu hambúrguer chega em vinte e cinco minutos.').then((_) => fim = true));
      while (!fim) {
        agora += 50;
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    expect(voz.ajusteVelocidade, lessThan(0.75), reason: 'a voz real é mais lenta: a boca abranda');
    expect(voz.ajusteVelocidade, greaterThan(0.45));
    voz.dispose();
  });
}

void _mensagemInicial() {
  testWidgets('"Pede ao Amigo": abre com a pesquisa já escrita e envia-a depois da saudação',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cerebro = _CerebroFalso();
    await tester.pumpWidget(MaterialApp(
      home: AmigoScreen(
        cerebro: cerebro,
        voz: AmigoVoz(motor: _VozFalsa()),
        ouvido: _OuvidoFalso('x'),
        mensagemInicial: 'Não encontrei "gelado" no McDonald\'s. Procura noutras lojas.',
      ),
    ));
    await _correr(tester, const Duration(seconds: 4));
    expect(cerebro.enviadas, ['Não encontrei "gelado" no McDonald\'s. Procura noutras lojas.']);
    await tester.pumpWidget(const SizedBox());
    await _correr(tester, const Duration(seconds: 5));
  });
}

/// 11/11/2026 (ordem do Danilo, no iPhone): a seta quase não se via e ele não
/// conseguia sair. Botão "Voltar" grande e o gesto de deslizar do iOS.
void _voltar() {
  Future<_CerebroFalso> abrirPorCima(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cerebro = _CerebroFalso();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('casa-abrir-amigo'),
              // o mesmo caminho do abrirAmigo (amigo_bora_entrada.dart)
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AmigoScreen(
                  cerebro: cerebro,
                  voz: AmigoVoz(motor: _VozFalsa()),
                  ouvido: _OuvidoFalso('x'),
                ),
              )),
              child: const Text('Casa'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('casa-abrir-amigo')));
    await _correr(tester, const Duration(seconds: 2));
    expect(find.byType(AmigoScreen), findsOneWidget);
    return cerebro;
  }

  testWidgets('botão "Voltar" bem visível: tem a palavra, 48 px e sai do ecrã', (tester) async {
    final cerebro = await abrirPorCima(tester);
    final botao = find.byKey(const Key('amigo-voltar'));
    expect(botao, findsOneWidget);
    expect(find.descendant(of: botao, matching: find.text('Voltar')), findsOneWidget);
    expect(find.descendant(of: botao, matching: find.byIcon(Icons.arrow_back_rounded)), findsOneWidget);
    final tam = tester.getSize(botao);
    expect(tam.height, greaterThanOrEqualTo(48));
    expect(tam.width, greaterThanOrEqualTo(48));
    // o aviso de IA está no cabeçalho, por baixo do nome, e não na fala
    expect(find.text('Amigo Bora'), findsOneWidget);
    expect(find.text('assistente virtual'), findsOneWidget);
    expect(find.textContaining('inteligência artificial', findRichText: true), findsNothing);
    await tester.tap(botao);
    await _correr(tester, const Duration(seconds: 1));
    expect(find.byType(AmigoScreen), findsNothing);
    expect(find.text('Casa'), findsOneWidget);
    expect(cerebro.eventos, contains('fim'));
    await _correr(tester, const Duration(seconds: 6));
  });

  testWidgets('iPhone: deslizar da esquerda também sai do Amigo', (tester) async {
    await abrirPorCima(tester);
    await tester.dragFrom(const Offset(4, 420), const Offset(320, 0));
    await _correr(tester, const Duration(seconds: 1));
    expect(find.byType(AmigoScreen), findsNothing);
    expect(find.text('Casa'), findsOneWidget);
    await _correr(tester, const Duration(seconds: 6));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

/// Motor como o Safari sem toque: nunca avisa que começou; a 2.ª vez fala.
class _VozBloqueada extends AmigoMotorVoz {
  final ditas = <String>[];
  @override
  Future<String?> preparar(double velocidade) async => 'Joana (pt-PT)';
  @override
  Future<void> falar(String texto) async {
    ditas.add(texto);
    if (ditas.length == 1) {
      aoErro?.call('not-allowed');
      return;
    }
    scheduleMicrotask(() => aoComecar?.call());
    Timer(const Duration(milliseconds: 400), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

void _vozBloqueadaNoTelemovel() {
  testWidgets('Safari sem toque: mostra "Toca para ouvir" e o toque repete a saudação',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final motor = _VozBloqueada();
    final voz = AmigoVoz(motor: motor);
    await tester.pumpWidget(MaterialApp(
      home: AmigoScreen(cerebro: _CerebroFalso(), voz: voz, ouvido: _OuvidoFalso('x')),
    ));
    await _correr(tester, const Duration(seconds: 2));
    expect(voz.precisaDeToque.value, isTrue);
    expect(find.text('Toca para ouvir'), findsOneWidget);
    await tester.tapAt(const Offset(200, 300));
    await _correr(tester, const Duration(seconds: 1));
    expect(motor.ditas.length, 2, reason: 'a saudação foi repetida depois do toque');
    expect(motor.ditas.last, startsWith('Boa noite, Ana!'));
    expect(voz.precisaDeToque.value, isFalse);
    expect(find.text('Som'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _correr(tester, const Duration(seconds: 6));
  });

  testWidgets('sem voz pt-PT: o botão diz "Sem voz"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: AmigoScreen(
          cerebro: _CerebroFalso(), voz: AmigoVoz(motor: _VozFalsa(nome: null)), ouvido: _OuvidoFalso('x')),
    ));
    await _correr(tester, const Duration(seconds: 1));
    expect(find.text('Sem voz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _correr(tester, const Duration(seconds: 8));
  });
}
