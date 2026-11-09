// O AMIGO — voz do servidor (pendências 09/11/2026, bloco I): com voz pt-PT no aparelho usa
// o aparelho; sem pt-PT pede o áudio à Edge amigo-voz e toca-o com a boca a mexer; quando o
// servidor diz "usa o aparelho" fica a legenda, sem erro.
import 'dart:async';
import 'dart:typed_data';

import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:bora_app/services/amigo_voz_servidor.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/amigo/amigo_boca.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A voz do aparelho (falsa). nome null = o aparelho não tem voz pt-PT.
class _Aparelho extends AmigoMotorVoz {
  _Aparelho({this.nome});
  final String? nome;
  final ditas = <String>[];
  @override
  Future<String?> preparar(double velocidade) async => nome;
  @override
  Future<void> falar(String texto) async {
    ditas.add(texto);
    scheduleMicrotask(() => aoComecar?.call());
    Timer(const Duration(milliseconds: 300), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

/// A Edge amigo-voz (falsa): responde ao fim de 100 ms.
class _Servidor implements AmigoVozServidorCliente {
  _Servidor(this.responder);
  final AmigoAudioResposta Function(int n) responder;
  final pedidos = <String>[];
  @override
  Future<AmigoAudioResposta> pedir(String texto, {double velocidade = 1}) async {
    pedidos.add(texto);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return responder(pedidos.length);
  }
}

/// O tocador (falso): toca [duracaoMs] e avisa o início (com a duração) e o fim.
class _Tocador extends AmigoTocador {
  _Tocador({this.duracaoMs = 2000, this.recusarPrimeira = false, this.semAudio = false});
  final double duracaoMs;
  final bool recusarPrimeira;

  /// O aparelho não toca áudio nenhum (como o WebKit do Windows: NotSupportedError).
  final bool semAudio;
  final tocados = <AmigoAudio>[];
  Timer? _t;
  bool libertado = false;
  @override
  Future<void> tocar(
    AmigoAudio audio, {
    required void Function(double? duracaoMs) aoComecar,
    required void Function() aoAcabar,
    required void Function(String motivo) aoErro,
  }) async {
    tocados.add(audio);
    if (semAudio) {
      aoErro('erro-audio: NotSupportedError');
      return;
    }
    if (recusarPrimeira && tocados.length == 1) {
      aoErro('not-allowed');
      return;
    }
    aoComecar(duracaoMs);
    _t = Timer(Duration(milliseconds: duracaoMs.round()), aoAcabar);
  }

  @override
  Future<void> parar() async => _t?.cancel();

  @override
  void libertar() => libertado = true;
}

AmigoAudio _mp3() => AmigoAudio(bytes: Uint8List.fromList([1, 2, 3]), base64: 'AQID', origem: 'google');
AmigoAudioResposta _ok(int _) => AmigoAudioResposta.audio(_mp3());

AmigoMotorVozComServidor _motor({
  String? nomeAparelho,
  required _Servidor servidor,
  required _Tocador tocador,
  bool ligado = true,
  _Aparelho? aparelho,
}) =>
    AmigoMotorVozComServidor(
      aparelho: aparelho ?? _Aparelho(nome: nomeAparelho),
      servidor: servidor,
      tocador: () => tocador,
      servidorLigado: () async => ligado,
    );

/// Avança o relógio da voz e o do teste juntos, de 50 em 50 ms.
Future<void> _andar(WidgetTester tester, void Function(double) somar, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    somar(50);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssistantFlags.reset();
  });

  group('resposta da Edge amigo-voz', () {
    test('áudio, "usa o aparelho" (definitivo ou não) e lixo', () {
      final a = amigoRespostaDoServidor({'ok': true, 'audio_base64': 'AQID', 'origem': 'cache'});
      expect(a.usarAparelho, isFalse);
      expect(a.audio!.bytes, [1, 2, 3]);
      expect(a.audio!.origem, 'cache');
      final d = amigoRespostaDoServidor({'ok': false, 'usar_aparelho': true, 'motivo': 'desligado'});
      expect(d.usarAparelho, isTrue);
      expect(d.definitivo, isTrue);
      for (final m in ['teto', 'sem_chave', 'limite_utilizador']) {
        expect(amigoRespostaDoServidor({'ok': false, 'motivo': m}).definitivo, isTrue, reason: m);
      }
      final g = amigoRespostaDoServidor({'ok': false, 'usar_aparelho': true, 'motivo': 'erro_google'});
      expect(g.usarAparelho, isTrue);
      expect(g.definitivo, isFalse, reason: 'erro passageiro: a frase seguinte volta a tentar');
      expect(amigoRespostaDoServidor('<html>').usarAparelho, isTrue);
      expect(amigoRespostaDoServidor({'ok': true, 'audio_base64': '%%%'}).usarAparelho, isTrue);
      expect(amigoRespostaDoServidor(null).usarAparelho, isTrue);
    });

    test('o interruptor do painel chega à app (sem a linha: desligado)', () {
      AssistantFlags.aplicar({'assistant_enabled': true});
      expect(AssistantFlags.vozServidor.value, isFalse);
      AssistantFlags.aplicar({'assistant_enabled': true, 'amigo_voz_servidor_ativo': true});
      expect(AssistantFlags.vozServidor.value, isTrue);
    });

    test('a boca estica para acabar com o áudio real', () {
      final f = AmigoFala('Olá, eu sou o Amigo da Bora.');
      final est = f.duracaoEstimada;
      f.comecou(0);
      f.ajustarDuracao(est * 2);
      expect(f.palavraEm(est), lessThan(f.palavras.length - 1), reason: 'a meio do áudio ainda vai a meio');
      expect(f.palavraEm(est * 2), f.palavras.length - 1);
    });
  });

  group('qual voz', () {
    testWidgets('com voz pt-PT no aparelho: usa o aparelho e nunca chama o servidor', (tester) async {
      final aparelho = _Aparelho(nome: 'Joana (pt-PT)');
      final servidor = _Servidor(_ok);
      final tocador = _Tocador();
      final voz = AmigoVoz(motor: _motor(aparelho: aparelho, servidor: servidor, tocador: tocador));
      await voz.preparar();
      expect(voz.nomeVoz, 'Joana (pt-PT)');
      unawaited(voz.falar('Olá!'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(aparelho.ditas, ['Olá!']);
      expect(servidor.pedidos, isEmpty);
      expect(tocador.tocados, isEmpty);
      voz.dispose();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('sem pt-PT: pede o áudio à amigo-voz, toca-o e a boca mexe-se até ao fim do som',
        (tester) async {
      var agora = 0.0;
      final servidor = _Servidor(_ok);
      final tocador = _Tocador(duracaoMs: 4000);
      final voz = AmigoVoz(
        motor: _motor(servidor: servidor, tocador: tocador),
        relogio: () => agora,
      );
      await voz.preparar();
      expect(voz.nomeVoz, kAmigoVozServidorNome);
      expect(voz.somEstado, AmigoSomEstado.ligado);
      const frase = 'Olá, eu sou o Amigo.';
      expect(AmigoFala(frase).duracaoEstimada, lessThan(2500), reason: 'o áudio (4 s) é mais comprido');
      var acabou = false;
      unawaited(voz.falar(frase).then((_) => acabou = true));
      await _andar(tester, (x) => agora += x, 200);
      expect(servidor.pedidos, [frase]);
      expect(tocador.tocados, hasLength(1));
      expect(voz.legenda.value, frase);
      var aberta = 0.0;
      for (var i = 0; i < 50; i++) {
        await _andar(tester, (x) => agora += x, 50);
        aberta = [aberta, voz.bocaAgora()?.o ?? 0].reduce((a, b) => a > b ? a : b);
      }
      expect(aberta, greaterThan(0.1), reason: 'a boca abriu enquanto o áudio tocava');
      expect(acabou, isFalse, reason: 'aos 2,7 s o áudio de 4 s ainda toca');
      expect(voz.estado.value, AmigoVozEstado.aFalar);
      final f = voz.falaAtual!;
      expect(f.posicao(agora), lessThan(f.duracaoEstimada),
          reason: 'a boca vai pelo áudio (4 s), não pela estimativa: ainda não chegou ao fim');
      await _andar(tester, (x) => agora += x, 1600);
      expect(acabou, isTrue);
      expect(voz.bocaAgora(), isNull);
      expect(voz.ajusteVelocidade, 1, reason: 'com a duração real não se "aprende" velocidade errada');
      expect(tester.takeException(), isNull);
      voz.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(tocador.libertado, isTrue);
    });

    testWidgets('servidor diz "usa o aparelho" (desligado): legenda e boca em silêncio, sem erro, "Sem voz"',
        (tester) async {
      final servidor = _Servidor((_) => const AmigoAudioResposta.semVoz('desligado', definitivo: true));
      final tocador = _Tocador();
      final voz = AmigoVoz(motor: _motor(servidor: servidor, tocador: tocador));
      await voz.preparar();
      var acabou = false;
      unawaited(voz.falar('Olá a todos, eu sou o Amigo.').then((_) => acabou = true));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(voz.legenda.value, 'Olá a todos, eu sou o Amigo.');
      expect(voz.bocaAgora(), isNotNull, reason: 'a boca mexe-se ao ritmo da legenda');
      expect(voz.temVozPtPt, isFalse);
      expect(voz.somEstado, AmigoSomEstado.semVoz);
      expect(voz.precisaDeToque.value, isFalse, reason: 'não é um "Toca para ouvir"');
      await tester.pump(const Duration(seconds: 4));
      expect(acabou, isTrue, reason: 'acaba no tempo da legenda');
      unawaited(voz.falar('Outra frase.'));
      await tester.pump(const Duration(seconds: 3));
      expect(servidor.pedidos, hasLength(1), reason: 'desligado: não volta a pedir neste ecrã');
      expect(tocador.tocados, isEmpty);
      expect(tester.takeException(), isNull);
      voz.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('erro passageiro da Google: esta frase em silêncio, a seguinte volta a pedir',
        (tester) async {
      final servidor = _Servidor(
          (n) => n == 1 ? const AmigoAudioResposta.semVoz('erro_google') : AmigoAudioResposta.audio(_mp3()));
      final tocador = _Tocador(duracaoMs: 800);
      final voz = AmigoVoz(motor: _motor(servidor: servidor, tocador: tocador));
      await voz.preparar();
      var primeira = false;
      unawaited(voz.falar('Primeira.').then((_) => primeira = true));
      await tester.pump(const Duration(milliseconds: 150));
      expect(voz.temVozPtPt, isTrue, reason: 'continua a contar com o servidor');
      await tester.pump(const Duration(seconds: 3));
      expect(primeira, isTrue);
      unawaited(voz.falar('Segunda.'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(seconds: 1));
      expect(servidor.pedidos, ['Primeira.', 'Segunda.']);
      expect(tocador.tocados, hasLength(1));
      voz.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('voz do servidor desligada no painel: nem chama a Edge (só legenda, como antes)',
        (tester) async {
      final servidor = _Servidor(_ok);
      final voz = AmigoVoz(motor: _motor(servidor: servidor, tocador: _Tocador(), ligado: false));
      await voz.preparar();
      expect(voz.temVozPtPt, isFalse);
      unawaited(voz.falar('Olá.'));
      await tester.pump(const Duration(seconds: 3));
      expect(servidor.pedidos, isEmpty);
      voz.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Safari sem toque: áudio recusado → "Toca para ouvir"; o toque repete sem voltar ao servidor',
        (tester) async {
      final servidor = _Servidor(_ok);
      final tocador = _Tocador(duracaoMs: 600, recusarPrimeira: true);
      final voz = AmigoVoz(motor: _motor(servidor: servidor, tocador: tocador));
      await voz.preparar();
      unawaited(voz.falar('Olá, Ana!'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));
      expect(voz.precisaDeToque.value, isTrue);
      expect(voz.somEstado, AmigoSomEstado.precisaToque);
      unawaited(voz.repetirUltima());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tocador.tocados, hasLength(2));
      expect(servidor.pedidos, hasLength(1), reason: 'a frase já estava em memória');
      expect(voz.precisaDeToque.value, isFalse);
      await tester.pump(const Duration(seconds: 1));
      voz.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('aparelho que não toca áudio (NotSupported): legenda; à 2.ª frase deixa de gastar no servidor',
        (tester) async {
      final servidor = _Servidor((n) => AmigoAudioResposta.audio(_mp3()));
      final tocador = _Tocador(semAudio: true);
      final voz = AmigoVoz(motor: _motor(servidor: servidor, tocador: tocador));
      await voz.preparar();
      for (final f in ['Primeira frase.', 'Segunda frase.', 'Terceira frase.']) {
        var fim = false;
        unawaited(voz.falar(f).then((_) => fim = true));
        await tester.pump(const Duration(milliseconds: 150));
        expect(voz.legenda.value, f);
        expect(voz.precisaDeToque.value, isFalse);
        await tester.pump(const Duration(seconds: 4));
        expect(fim, isTrue, reason: 'acaba no tempo da legenda');
      }
      expect(servidor.pedidos, ['Primeira frase.', 'Segunda frase.']);
      expect(voz.somEstado, AmigoSomEstado.semVoz);
      expect(tester.takeException(), isNull);
      voz.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('ecrã do Amigo', () {
    Future<void> correr(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('iPhone sem voz pt-PT: a saudação sai pela voz do servidor e o botão diz "Som"',
        (tester) async {
      final servidor = _Servidor(_ok);
      final tocador = _Tocador(duracaoMs: 1500);
      await tester.pumpWidget(MaterialApp(
        home: AmigoScreen(
          cerebro: _Cerebro(),
          voz: AmigoVoz(motor: _motor(servidor: servidor, tocador: tocador)),
          ouvido: _Ouvido(),
        ),
      ));
      await correr(tester, 1200);
      expect(servidor.pedidos.first, startsWith('Boa noite, Ana!'));
      expect(tocador.tocados, hasLength(1));
      expect(find.text('Som'), findsOneWidget);
      expect(find.textContaining('do costume', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await correr(tester, 3000);
    });

    testWidgets('servidor sem voz (teto): fica a legenda e "Sem voz", sem erro à vista', (tester) async {
      final servidor = _Servidor((_) => const AmigoAudioResposta.semVoz('teto', definitivo: true));
      await tester.pumpWidget(MaterialApp(
        home: AmigoScreen(
          cerebro: _Cerebro(),
          voz: AmigoVoz(motor: _motor(servidor: servidor, tocador: _Tocador())),
          ouvido: _Ouvido(),
        ),
      ));
      await correr(tester, 1500);
      expect(find.text('Sem voz'), findsOneWidget);
      expect(find.textContaining('do costume', findRichText: true), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await correr(tester, 8000);
    });
  });
}

class _Cerebro extends AmigoCerebro {
  @override
  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) async =>
      AssistantReply.fromJson({'texto': 'Boa noite, Ana! Queres o do costume?', 'emocao': 'alegre'});

  @override
  Future<AssistantReply> enviar({
    required String? conversationId,
    required String mensagem,
    double? lat,
    double? lng,
    bool apartamento = false,
  }) async =>
      AssistantReply.texto('Ok.');

  @override
  Future<(String?, List<AssistantReply>)> conversaRecente() async => (null, const <AssistantReply>[]);

  @override
  Future<void> guardarConversa(String? id) async {}

  @override
  Future<void> evento(String tipo, {int? duracaoS}) async {}
}

class _Ouvido extends AmigoOuvido {
  @override
  Future<bool> iniciar({required void Function() aoParar}) async => true;
  @override
  Future<void> ouvir(void Function(String texto, bool fim) aoOuvir) async {}
  @override
  Future<void> parar() async {}
}
