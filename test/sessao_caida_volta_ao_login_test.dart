import 'dart:async';
import 'dart:convert';

import 'package:bora_app/auth/auth_store.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sessão caída tem de voltar à página de entrar (padrão Uber/Glovo).
///
/// Cicatriz (15/10/2026, 13:40–13:50 de Lisboa): o dono do Sabores de Casa
/// ficou no "Editar produto" de app.boraguarda.com com a sessão já caída. O
/// AuthStore ignorava o fim da sessão e mantinha o parceiro em memória; tudo
/// o que o ecrã pedia ia sem login e voltava vazio — "Não foi possível ler as
/// percentagens da plataforma". Ao entrar outra vez, funcionou à primeira.
///
/// O servidor aqui é falso, mas o SDK é o verdadeiro (gotrue 2.27.3): é ele
/// que decide quando emite o fim da sessão, como em produção.

enum _Renovar { recusada, semRede, aceite }

var _renovar = _Renovar.recusada;

const _json = {'content-type': 'application/json; charset=utf-8'};
const _emailParceiro = 'parceiro.teste.sessao@bora.app';
const _uidParceiro = '00000000-0000-4000-8000-000000001510';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uidParceiro, 'exp': exp, 'role': 'authenticated'})}'
      '.assinatura';
}

Map<String, Object?> _sessaoParceiro() => {
      'access_token': _jwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-de-teste',
      'user': {
        'id': _uidParceiro,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': _emailParceiro,
        'app_metadata': <String, Object?>{},
        'user_metadata': {
          'bora_role': 'partner',
          'bora_restaurant_name': 'Loja de Teste',
        },
        'created_at': '2026-10-15T00:00:00Z',
      },
    };

http.Response _erro(int status, String codigo, String msg) => http.Response(
      jsonEncode({'code': status, 'error_code': codigo, 'msg': msg}),
      status,
      headers: _json,
    );

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  final grant = req.url.queryParameters['grant_type'];
  if (caminho.endsWith('/auth/v1/token') && grant == 'password') {
    final corpo = jsonDecode(req.body) as Map<String, dynamic>;
    if (corpo['email'] == _emailParceiro) {
      return http.Response(jsonEncode(_sessaoParceiro()), 200,
          headers: _json);
    }
    // A conta de convidado não existe aqui — o AuthStore tenta-a no arranque.
    return _erro(400, 'invalid_credentials', 'Invalid login credentials');
  }
  if (caminho.endsWith('/auth/v1/token') && grant == 'refresh_token') {
    if (_renovar == _Renovar.semRede) {
      throw http.ClientException('sem rede');
    }
    if (_renovar == _Renovar.aceite) {
      return http.Response(jsonEncode(_sessaoParceiro()), 200,
          headers: _json);
    }
    return _erro(400, 'refresh_token_not_found',
        'Invalid Refresh Token: Refresh Token Not Found');
  }
  if (caminho.endsWith('/auth/v1/signup')) {
    return _erro(400, 'signup_disabled', 'Signups not allowed');
  }
  if (caminho.endsWith('/auth/v1/logout')) return http.Response('', 204);
  return http.Response('[]', 200, headers: _json);
}

/// O cliente do Supabase acaba as respostas fora do relógio falso do teste.
Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Faz de _RootNavigator com o papel "parceiro" escolhido: sem conta em
/// memória mostra a entrada (PartnerEntryScreen → PartnerLoginScreen).
Widget _app(AuthStore auth) => ChangeNotifierProvider<AuthStore>.value(
      value: auth,
      child: MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        home: Consumer<AuthStore>(
          builder: (_, a, __) => Scaffold(
            body: Text(a.currentPartner == null
                ? 'ENTRADA DO PARCEIRO'
                : 'PAINEL DO PARCEIRO'),
          ),
        ),
      ),
    );

/// Cria o AuthStore, entra com o parceiro de teste e abre "Editar produto"
/// por cima, como estava o dono da loja.
Future<AuthStore> _parceiroNoEditarProduto(WidgetTester tester) async {
  final auth = (await tester.runAsync(() async {
    final a = AuthStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return a;
  }))!;
  addTearDown(auth.dispose);
  await tester.pumpWidget(_app(auth));

  await tester.runAsync(() => Supabase.instance.client.auth
      .signInWithPassword(email: _emailParceiro, password: 'teste'));
  await _servidorResponde(tester);
  expect(auth.currentPartner?.email, _emailParceiro);
  expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);

  NotificationService.navigatorKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('Editar produto')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Editar produto'), findsOneWidget);
  return auth;
}

/// Deixa passar [ms] de tempo REAL (a tolerância de 2 s do AuthStore corre
/// fora do relógio falso do teste) e redesenha.
Future<void> _esperaReal(WidgetTester tester, int ms) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pumpAndSettle();
}

/// Deixa o aviso (8 s) sair do ecrã, para não sobrar relógio pendente.
Future<void> _avisoSai(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 9));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // O NotificationService (que o "Sair" chama) cria o leitor de som ao
    // nascer; nos testes não há som — nasce aqui, com as queixas do canal
    // de som engolidas, antes de qualquer teste.
    await runZonedGuarded(() async {
      NotificationService.instance;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (_, __) {});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
      'servidor recusa a sessão com o parceiro em memória → conta limpa, '
      'volta à entrada e avisa "A tua sessão terminou"', (tester) async {
    final auth = await _parceiroNoEditarProduto(tester);

    _renovar = _Renovar.recusada;
    await tester.runAsync(() async {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {}
    });
    await _servidorResponde(tester);
    await _esperaReal(tester, 2300);

    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(auth.currentPartner, isNull);
    expect(auth.isLogged, isFalse);
    expect(find.text('Editar produto'), findsNothing,
        reason: 'os ecrãs abertos por cima fecham-se');
    expect(find.text('ENTRADA DO PARCEIRO'), findsOneWidget);
    expect(find.text('A tua sessão terminou. Entra outra vez.'),
        findsOneWidget);
    // O que o "Editar produto" usa para não mostrar o erro das percentagens.
    expect(AuthStore.falhaPorSessao(StateError('o servidor não aceitou')),
        isTrue);

    await _avisoSai(tester);
  });

  testWidgets(
      'queda de rede ao renovar a sessão não tira ninguém da conta',
      (tester) async {
    final auth = await _parceiroNoEditarProduto(tester);

    _renovar = _Renovar.semRede;
    // O SDK tenta outra vez durante alguns segundos e desiste com erro de
    // rede — que chega como erro do stream, nunca como fim de sessão.
    await tester.runAsync(() async {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {}
    });
    await _servidorResponde(tester);
    await tester.pumpAndSettle();

    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    expect(auth.currentPartner?.email, _emailParceiro);
    expect(find.text('Editar produto'), findsOneWidget);
    expect(find.text('A tua sessão terminou. Entra outra vez.'), findsNothing);

    // Com sessão viva só conta erro de login vindo do servidor.
    expect(AuthStore.falhaPorSessao(StateError('x')), isFalse);
    expect(
        AuthStore.falhaPorSessao(
            const PostgrestException(message: 'JWT expired', code: 'PGRST303')),
        isTrue);
    expect(
        AuthStore.falhaPorSessao(
            const PostgrestException(message: 'duplicate key', code: '23505')),
        isFalse);

    // Arruma: sai como o "Sair" normal para o teste seguinte começar limpo.
    auth.logout(wipeBiometrics: false);
    await _servidorResponde(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('"Sair" normal não mostra o aviso de sessão terminada',
      (tester) async {
    final auth = await _parceiroNoEditarProduto(tester);

    auth.logout();
    await _servidorResponde(tester);
    await tester.pumpAndSettle();

    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(auth.currentPartner, isNull);
    expect(find.text('A tua sessão terminou. Entra outra vez.'), findsNothing);
  });

  testWidgets(
      'a sessão cai e volta em menos de 2 s (login noutro separador) → '
      'ninguém é expulso', (tester) async {
    final auth = await _parceiroNoEditarProduto(tester);

    _renovar = _Renovar.recusada;
    await tester.runAsync(() async {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {}
      // Logo a seguir a sessão volta (no browser chega pelo canal entre
      // separadores; aqui, um login novo da mesma conta).
      await Supabase.instance.client.auth
          .signInWithPassword(email: _emailParceiro, password: 'teste');
    });
    await _servidorResponde(tester);
    await _esperaReal(tester, 2300);

    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    expect(auth.currentPartner?.email, _emailParceiro);
    expect(find.text('Editar produto'), findsOneWidget);
    expect(find.text('A tua sessão terminou. Entra outra vez.'), findsNothing);

    auth.logout(wipeBiometrics: false);
    await _servidorResponde(tester);
    await tester.pumpAndSettle();
  });

  testWidgets(
      '401 com a sessão ainda renovável não expulsa; com a renovação recusada '
      'expulsa', (tester) async {
    final auth = await _parceiroNoEditarProduto(tester);
    const jwtExpirado =
        PostgrestException(message: 'JWT expired', code: 'PGRST303');

    // Relógio do aparelho atrasado: o servidor diz 401, mas renova bem.
    _renovar = _Renovar.aceite;
    final caiuAceite = await tester
        .runAsync(() => AuthStore.sessaoCaiu(jwtExpirado));
    await _servidorResponde(tester);
    expect(caiuAceite, isFalse);
    expect(auth.currentPartner?.email, _emailParceiro);

    // Sessão morta no servidor: a renovação é recusada → entrar outra vez.
    _renovar = _Renovar.recusada;
    final caiuRecusada = await tester
        .runAsync(() => AuthStore.sessaoCaiu(jwtExpirado));
    await _servidorResponde(tester);
    await _esperaReal(tester, 2300);
    expect(caiuRecusada, isTrue);
    expect(auth.currentPartner, isNull);
    expect(find.text('A tua sessão terminou. Entra outra vez.'),
        findsOneWidget);

    await _avisoSai(tester);
  });
}
