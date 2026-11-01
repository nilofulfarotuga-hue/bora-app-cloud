// B4 (missão app-fechar-2026-11-01) — ESTAFETA NÃO APROVADO NÃO FICA ONLINE.
//
// Cicatriz (revisão de 01/11, achado O1): o botão Online mudava para verde no
// telemóvel ANTES de o servidor responder, e a gravação engolia o erro. Com o
// gatilho `trg_online_so_aprovado` a recusar, o estafeta via "Online", o
// batimento e o serviço de fundo arrancavam, e nunca recebia nada.
//
// Sem rede: a pergunta ao servidor (`PortaOnline.perguntar`) e a gravação
// (`gravarOnline`) são falsas. O SDK do Supabase arranca com um servidor de
// mentira que responde `[]` a tudo (só para o pedido de "pedidos pendentes"
// que corre depois de ficar online).
import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/driver_model.dart';
import 'package:bora_app/models/online_resultado.dart';
import 'package:bora_app/services/heartbeat_service.dart';
import 'package:bora_app/services/porta_online_service.dart';
import 'package:bora_app/services/tvde_conformidade_service.dart'
    show mensagemErroConformidade;
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/utils/mensagem_online_recusado.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '00000000-0000-4000-8000-0000000b4b40';

const _fraseNaoAprovada = 'A tua conta ainda não está aprovada. Quando for '
    'aprovada recebes um aviso e podes ficar online.';

/// O que o servidor devolve a `prestador_pode_ficar_online()` para uma conta
/// pendente (cópia da função em produção, 01/11/2026).
const Map<String, Object?> _respostaPendente = {
  'ok': false,
  'codigo': 'CONTA_NAO_APROVADA',
  'mensagem': _fraseNaoAprovada,
  'faltas': ['carta de condução'],
};

/// Estafeta de teste já em memória (sem ir ao servidor).
DriverStore _loja({required GravarOnline gravar}) {
  final s = DriverStore(gravarOnline: gravar, ligarAoServidor: false);
  s.configurePrimaryDriver(
    name: 'Estafeta de teste',
    phone: '910000001',
    vehicleType: VehicleType.motorcycle,
    driverId: _uid,
  );
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final perguntarOriginal = PortaOnline.perguntar;
  final verificarContaOriginal = HeartbeatService.verificarConta;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async => http.Response('[]', 200,
          headers: const {'content-type': 'application/json'}, request: req)),
    );
  });

  setUp(PortaOnline.esquecer);
  tearDown(() {
    PortaOnline.perguntar = perguntarOriginal;
    HeartbeatService.verificarConta = verificarContaOriginal;
    PortaOnline.esquecer();
  });

  group('servidor recusa → o botão NÃO fica verde', () {
    test('conta por aprovar: isOnline fica false, nada se grava, frase certa',
        () async {
      PortaOnline.perguntar = () async => _respostaPendente;
      var gravacoes = 0;
      final loja = _loja(gravar: (_, __) async {
        gravacoes++;
        return {'is_online': true};
      });
      final vistos = <bool>[];
      loja.addListener(() => vistos.add(loja.currentDriver!.isOnline));

      final r = await loja.alternarOnline(_uid, true);

      expect(r.ok, isFalse);
      expect(r.codigo, CodigoOnline.contaNaoAprovada);
      expect(r.mensagem, _fraseNaoAprovada);
      expect(r.recusaDaConta, isTrue);
      expect(loja.currentDriver!.isOnline, isFalse);
      expect(gravacoes, 0, reason: 'recusado na pergunta: não se grava nada');
      expect(vistos, isNot(contains(true)),
          reason: 'o ecrã nunca pode ter visto o botão verde');
    });

    test('a pergunta passa mas o GATILHO recusa ao gravar → volta a offline',
        () async {
      PortaOnline.perguntar = () async => {'ok': true, 'codigo': 'OK'};
      final loja = _loja(
        gravar: (_, __) async => throw const PostgrestException(
          message: 'CONTA_NAO_APROVADA: A tua conta ainda não está aprovada. '
              'Quando for aprovada recebes um aviso e podes ficar online.',
          code: 'P0001',
        ),
      );
      final r = await loja.alternarOnline(_uid, true);
      expect(r.ok, isFalse);
      expect(r.codigo, CodigoOnline.contaNaoAprovada);
      expect(r.mensagem, _fraseNaoAprovada);
      expect(loja.currentDriver!.isOnline, isFalse);
    });

    test('o servidor grava mas a linha fica offline → não confirma', () async {
      PortaOnline.perguntar = () async => {'ok': true};
      final loja = _loja(gravar: (_, __) async => {'is_online': false});
      final r = await loja.alternarOnline(_uid, true);
      expect(r.ok, isFalse);
      expect(r.codigo, CodigoOnline.naoConfirmado);
      expect(r.mensagem, isNotEmpty);
      expect(loja.currentDriver!.isOnline, isFalse);
    });

    test('0 linhas gravadas (sem ficha de estafeta) → SEM_CONTA', () async {
      PortaOnline.perguntar = () async => {'ok': true};
      final loja = _loja(gravar: (_, __) async => null);
      final r = await loja.alternarOnline(_uid, true);
      expect(r.codigo, CodigoOnline.semConta);
      expect(loja.currentDriver!.isOnline, isFalse);
    });

    test('sem ligação ao gravar → não fica online às escuras', () async {
      PortaOnline.perguntar = () async => {'ok': true};
      final loja = _loja(
          gravar: (_, __) async => throw const SocketException('sem rede'));
      final r = await loja.alternarOnline(_uid, true);
      expect(r.codigo, CodigoOnline.semLigacao);
      expect(loja.currentDriver!.isOnline, isFalse);
    });

    test(
        'a assinatura antiga (OrderStore) já não pinta o botão antes do '
        'servidor', () async {
      PortaOnline.perguntar = () async => _respostaPendente;
      final loja = _loja(gravar: (_, __) async => {'is_online': true});
      expect(loja.toggleAvailability(_uid, true), isFalse);
      expect(loja.currentDriver!.isOnline, isFalse);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(loja.currentDriver!.isOnline, isFalse);
    });
  });

  group('servidor aceita → fica online só depois de confirmar', () {
    test('aprovado: grava, confirma e liga', () async {
      PortaOnline.perguntar = () async => {'ok': true, 'codigo': 'OK'};
      final pedidos = <String>[];
      final loja = _loja(gravar: (id, online) async {
        pedidos.add('$id=$online');
        return {'is_online': online};
      });
      final r = await loja.alternarOnline(_uid, true);
      expect(r.ok, isTrue);
      expect(pedidos, ['$_uid=true'],
          reason: 'grava por user_id (identidade-estafeta)');
      expect(loja.currentDriver!.isOnline, isTrue);
    });

    test('sem resposta à pergunta (rede) → falha aberta: o gatilho decide',
        () async {
      PortaOnline.perguntar = () async => throw TimeoutException('lento');
      var gravacoes = 0;
      final loja = _loja(gravar: (_, online) async {
        gravacoes++;
        return {'is_online': online};
      });
      final r = await loja.alternarOnline(_uid, true);
      expect(gravacoes, 1);
      expect(r.ok, isTrue);
      expect(loja.currentDriver!.isOnline, isTrue);
    });

    test('dois toques seguidos: o segundo não pergunta outra vez', () async {
      final resposta = Completer<Object?>();
      var perguntas = 0;
      PortaOnline.perguntar = () {
        perguntas++;
        return resposta.future;
      };
      final loja = _loja(gravar: (_, online) async => {'is_online': online});
      final primeiro = loja.alternarOnline(_uid, true);
      final segundo = await loja.alternarOnline(_uid, true);
      expect(segundo.codigo, CodigoOnline.emCurso);
      resposta.complete({'ok': true});
      expect((await primeiro).ok, isTrue);
      expect(perguntas, 1);
    });

    test('offline continua imediato (sem esperar pelo servidor)', () async {
      PortaOnline.perguntar = () async => {'ok': true};
      final loja = _loja(gravar: (_, online) async => {'is_online': online});
      await loja.alternarOnline(_uid, true);
      expect(loja.currentDriver!.isOnline, isTrue);
      final r = loja.alternarOnline(_uid, false);
      expect(loja.currentDriver!.isOnline, isFalse,
          reason: 'muda no mesmo instante, antes de qualquer resposta');
      expect((await r).ok, isTrue);
    });
  });

  group('O3 — o batimento não arranca para conta por aprovar', () {
    test('recusado: não bate, não liga relógio', () async {
      HeartbeatService.verificarConta =
          () async => OnlineResultado.recusado(CodigoOnline.contaNaoAprovada);
      final hb = HeartbeatService();
      await hb.start();
      expect(hb.isRunning, isFalse);
      expect(HeartbeatService.relogioAtivo, isFalse);
      expect(HeartbeatService.instanciasAtivas, 0);
    });

    test('parado enquanto esperava a resposta: não liga depois', () async {
      final resposta = Completer<OnlineResultado>();
      HeartbeatService.verificarConta = () => resposta.future;
      final hb = HeartbeatService();
      final arranque = hb.start();
      await HeartbeatService.pararTodos();
      resposta.complete(const OnlineResultado.ok());
      await arranque;
      expect(hb.isRunning, isFalse);
      expect(HeartbeatService.relogioAtivo, isFalse);
    });
  });

  group('PortaOnline guarda a resposta para o batimento', () {
    test('forcar:false aproveita a resposta recente; esquecer limpa', () async {
      var perguntas = 0;
      PortaOnline.perguntar = () async {
        perguntas++;
        return _respostaPendente;
      };
      final a = await PortaOnline.verificar();
      final b = await PortaOnline.verificar(forcar: false);
      expect(perguntas, 1);
      expect(a.codigo, CodigoOnline.contaNaoAprovada);
      expect(b.codigo, CodigoOnline.contaNaoAprovada);
      PortaOnline.esquecer();
      await PortaOnline.verificar(forcar: false);
      expect(perguntas, 2);
    });

    test('sem resposta não fica guardada (falha aberta não é "aprovado")',
        () async {
      PortaOnline.perguntar = () async => throw TimeoutException('lento');
      final r = await PortaOnline.verificar();
      expect(r.ok, isTrue);
      expect(r.semRespostaDoServidor, isTrue);
      expect(PortaOnline.ultimaResposta, isNull);
    });
  });

  group('mapeamento de TODOS os códigos (frase única, PT-PT)', () {
    test('frases fixas', () {
      expect(mensagemOnlineRecusado('CONTA_NAO_APROVADA'), _fraseNaoAprovada);
      expect(mensagemOnlineRecusado('CONTA_RECUSADA'),
          'A tua candidatura não foi aprovada. Fala com o suporte da Bora.');
      expect(mensagemOnlineRecusado('CONTA_BLOQUEADA'),
          'A tua conta está bloqueada. Fala com o suporte da Bora.');
      // As fixas ganham à do servidor (texto igual nos dois ecrãs).
      expect(
          mensagemOnlineRecusado('CONTA_BLOQUEADA', mensagemServidor: 'outra'),
          'A tua conta está bloqueada. Fala com o suporte da Bora.');
    });

    test('TVDE_BLOQUEADO usa a mensagem do servidor', () {
      expect(
        mensagemOnlineRecusado('TVDE_BLOQUEADO',
            mensagemServidor: 'Não podes ficar online: seguro caducado'),
        'Não podes ficar online: seguro caducado',
      );
      expect(mensagemOnlineRecusado('TVDE_BLOQUEADO'), isNotEmpty);
    });

    test('os outros: a do servidor, ou uma frase genérica', () {
      expect(
          mensagemOnlineRecusado('CONTA_APAGADA',
              mensagemServidor: 'Esta conta já não está ativa.'),
          'Esta conta já não está ativa.');
      expect(
          mensagemOnlineRecusado('SEM_CONTA',
              mensagemServidor: 'Não encontrámos a tua conta de prestador.'),
          'Não encontrámos a tua conta de prestador.');
      expect(mensagemOnlineRecusado('QUALQUER_COISA'),
          'Não foi possível ficar online. Tenta outra vez.');
      expect(mensagemOnlineRecusado(null),
          'Não foi possível ficar online. Tenta outra vez.');
      expect(mensagemOnlineRecusado('SEM_LIGACAO'), contains('ligação'));
    });

    test('resposta da RPC → resultado (todos os códigos do servidor)', () {
      for (final c in [
        'SEM_CONTA',
        'CONTA_APAGADA',
        'CONTA_BLOQUEADA',
        'CONTA_RECUSADA',
        'CONTA_NAO_APROVADA',
        'TVDE_BLOQUEADO',
      ]) {
        final r = OnlineResultado.daResposta(
            {'ok': false, 'codigo': c, 'mensagem': 'texto do servidor'});
        expect(r.ok, isFalse, reason: c);
        expect(r.codigo, c);
        expect(r.mensagem, isNotEmpty, reason: c);
        expect(r.recusaDaConta, c != 'TVDE_BLOQUEADO', reason: c);
      }
      final ok = OnlineResultado.daResposta(
          {'ok': true, 'codigo': 'OK', 'mensagem': null});
      expect(ok.ok, isTrue);
      expect(ok.semRespostaDoServidor, isFalse);
      final tvde = OnlineResultado.daResposta({
        'ok': false,
        'codigo': 'TVDE_BLOQUEADO',
        'mensagem': 'Não podes ficar online: Seguro',
        'motivos': [
          {'codigo': 'SEGURO', 'rotulo': 'Seguro'},
        ],
      });
      expect(tvde.motivos, ['Seguro']);
      expect(tvde.mensagem, 'Não podes ficar online: Seguro');
    });

    test('erro do gatilho → código e frase', () {
      for (final c in [
        'CONTA_NAO_APROVADA',
        'CONTA_RECUSADA',
        'CONTA_BLOQUEADA',
        'CONTA_APAGADA',
      ]) {
        final r = OnlineResultado.doErro('$c: texto do servidor');
        expect(r.codigo, c);
        expect(r.ok, isFalse);
      }
      expect(OnlineResultado.doErro('outra coisa').codigo,
          CodigoOnline.naoConfirmado);
      expect(
        mensagemDoServidorNoErro(
            'PostgrestException(message: CONTA_APAGADA: Esta conta já não '
                'está ativa., code: P0001, details: null, hint: null)',
            'CONTA_APAGADA'),
        'Esta conta já não está ativa.',
      );
    });

    test('TVDE (mensagemErroConformidade) traduz os códigos da conta', () {
      expect(
          mensagemErroConformidade(
              Exception('CONTA_NAO_APROVADA: A tua conta ainda não …')),
          _fraseNaoAprovada);
      expect(mensagemErroConformidade(Exception('CONTA_RECUSADA: x')),
          'A tua candidatura não foi aprovada. Fala com o suporte da Bora.');
      expect(mensagemErroConformidade(Exception('CONTA_BLOQUEADA: x')),
          'A tua conta está bloqueada. Fala com o suporte da Bora.');
      // O que já traduzia continua igual.
      expect(mensagemErroConformidade(Exception('TVDE_BLOQUEADO: Seguro')),
          'Não podes ficar online: Seguro');
    });
  });

  group('O4 — com a conta pendente o interruptor Online não existe', () {
    test('a regra única', () {
      expect(mostraInterruptorOnline(DriverStatus.pending), isFalse);
      expect(mostraInterruptorOnline(DriverStatus.rejected), isFalse);
      expect(mostraInterruptorOnline(DriverStatus.approved), isTrue);
    });

    String ler(String p) =>
        File(p).readAsStringSync().replaceAll(String.fromCharCode(13), '');

    test(
        'ecrã das entregas: o portão vem antes do driver_online_toggle e o '
        'ecrã de espera não tem interruptor', () {
      final s = ler('lib/screens/driver_home_screen.dart');
      final build = s.indexOf('Widget build(BuildContext context)');
      final portao = s.indexOf('if (!mostraInterruptorOnline(driverStatus))');
      final interruptor = s.indexOf("Key('driver_online_toggle')");
      expect(build, greaterThan(0));
      expect(portao, greaterThan(build));
      expect(interruptor, greaterThan(portao));
      final espera = s.indexOf('Widget _buildPendingScreen(');
      expect(espera, greaterThan(0));
      final fimEspera = s.indexOf('\n  Widget ', espera + 10);
      final corpo = s.substring(espera, fimEspera < 0 ? s.length : fimEspera);
      expect(corpo.contains('Switch('), isFalse);
      expect(corpo.contains('driver_online_toggle'), isFalse);
      expect(corpo.contains('_handleOnlineToggle'), isFalse);
    });

    test('ecrã TVDE usa a mesma regra', () {
      final s = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      expect(s.contains('if (!mostraInterruptorOnline(status))'), isTrue);
    });

    test(
        'os dois ecrãs mostram a frase única e não arrancam batimento '
        'quando recusado', () {
      final home = ler('lib/screens/driver_home_screen.dart');
      final ligar =
          home.substring(home.indexOf('Future<bool> _ficarOnlineNoServidor'));
      expect(ligar.contains('alternarOnline'), isTrue);
      expect(home.contains('mensagemOnlineRecusado'), isTrue);
      final tvde = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      final toggle = tvde.substring(
          tvde.indexOf('final r = await driverStore.alternarOnline'));
      final recusa = toggle.indexOf('if (!r.ok)');
      final batimento = toggle.indexOf('_heartbeat.start()');
      expect(recusa, greaterThanOrEqualTo(0));
      expect(batimento, greaterThan(recusa),
          reason: 'o batimento só arranca depois de passar a recusa');
    });
  });
}
