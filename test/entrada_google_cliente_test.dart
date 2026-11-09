// Bloco E da missão pendencias-2026-11-09 — "Continuar com Google" para o
// CLIENTE (e "Continuar com a Apple" no iPhone).
//
// Prova, sem rede e sem conta nenhuma:
//  * os botões aparecem no login e no registo do cliente; não aparecem no
//    login do estafeta nem do parceiro;
//  * no iPhone a Apple aparece ao lado do Google (regra 4.8) — e sem a Apple
//    ligada no painel o Google também não aparece no iPhone;
//  * ao tocar chama o OAuth com o fornecedor, o redirectTo e o modo certos
//    (com um falso no lugar do Supabase);
//  * a ligação de volta (o que o supabase_flutter faz com
//    `pt.boraapp.bora://auth/callback#access_token=…`) abre a conta como
//    cliente, pelo mesmo fim do login por email, e volta ao carrinho;
//  * a etiqueta do método no painel admin.
import 'dart:convert';

import 'package:bora_app/auth/auth_store.dart';
import 'package:bora_app/screens/admin/admin_clients_screen.dart';
import 'package:bora_app/screens/client_login_screen.dart';
import 'package:bora_app/screens/driver_login_screen.dart';
import 'package:bora_app/screens/partner_login_screen.dart';
import 'package:bora_app/screens/register_client_screen.dart';
import 'package:bora_app/services/entrada_social_cliente.dart';
import 'package:bora_app/stores/session_store.dart';
import 'package:bora_app/utils/contact_validators.dart';
import 'package:bora_app/widgets/entrada_social_botoes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
final List<String> _pedidos = [];

/// Conta como o Supabase a devolve depois do Google (sem `bora_role`).
Map<String, dynamic> _contaGoogle({Map<String, dynamic> extra = const {}}) => {
      'id': '11111111-2222-3333-4444-555555555555',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'ana.google@exemplo.pt',
      'created_at': '2026-11-09T21:00:00Z',
      'app_metadata': {
        'provider': 'google',
        'providers': ['google'],
      },
      'user_metadata': {
        'full_name': 'Ana Google',
        'name': 'Ana Google',
        'email': 'ana.google@exemplo.pt',
        'email_verified': true,
        ...extra,
      },
    };

Map<String, dynamic> _metaGravada = {};

Future<http.Response> _servidor(http.Request req) async {
  _pedidos.add('${req.method} ${req.url.path}');
  final p = req.url.path;
  Object? corpo = [];
  if (p.endsWith('/auth/v1/user')) {
    if (req.method == 'PUT') {
      final dados = (jsonDecode(req.body) as Map)['data'];
      if (dados is Map) _metaGravada = {..._metaGravada, ...dados.cast()};
    }
    corpo = _contaGoogle(extra: _metaGravada);
  } else if (p.endsWith('/rest/v1/rpc/get_setting')) {
    corpo = null;
  } else if (p.endsWith('/rest/v1/rpc/add_client_role_to_me')) {
    corpo = true;
  }
  return http.Response(jsonEncode(corpo), 200, headers: _json, request: req);
}

/// O que o ecrã pediu ao "Supabase" (o falso).
final List<(OAuthProvider, String, LaunchMode)> _oauth = [];

Future<AuthStore> _authStore(WidgetTester t) async {
  final a = (await t.runAsync(() async {
    final a = AuthStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return a;
  }))!;
  addTearDown(a.dispose);
  return a;
}

Future<void> _assentar(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }
}

Future<SessionStore> _abrir(WidgetTester t, AuthStore auth, Widget ecra,
    {bool porCima = false}) async {
  t.view.physicalSize = const Size(390 * 3, 1600 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final session = SessionStore();
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthStore>.value(value: auth),
      ChangeNotifierProvider<SessionStore>.value(value: session),
    ],
    child: MaterialApp(
      home: porCima ? _Carrinho(ecra: ecra) : ecra,
    ),
  ));
  await _assentar(t);
  if (porCima) {
    await t.tap(find.text('abrir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await _assentar(t);
  }
  return session;
}

/// Faz de carrinho: abre o ecrã por cima e guarda o que ele devolveu.
class _Carrinho extends StatefulWidget {
  const _Carrinho({required this.ecra});
  final Widget ecra;
  static Object? devolveu = 'nada';

  @override
  State<_Carrinho> createState() => _CarrinhoState();
}

class _CarrinhoState extends State<_Carrinho> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            _Carrinho.devolveu = await Navigator.of(context)
                .push<bool>(MaterialPageRoute(builder: (_) => widget.ecra));
          },
          child: const Text('abrir'),
        ),
      );
}

Future<void> _tocar(WidgetTester t, Key chave) async {
  await t.ensureVisible(find.byKey(chave));
  await t.pump();
  await t.tap(find.byKey(chave));
  await t.pump();
  await _assentar(t);
}

final _google = find.text('Continuar com Google');
final _apple = find.text('Continuar com a Apple');

/// Um JWT de mentira (só o `exp` interessa ao SDK).
String _jwt() {
  String b64(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': '11111111-2222-3333-4444-555555555555', 'exp': exp, 'role': 'authenticated'})}.assinatura';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      // Igual à app (main.dart): fluxo implícito.
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient(_servidor),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _pedidos.clear();
    _oauth.clear();
    _metaGravada = {};
    _Carrinho.devolveu = 'nada';
    EntradaSocialCliente.interruptoresParaTeste =
        () async => (google: true, apple: false);
    EntradaSocialCliente.iniciarParaTeste =
        (f, {required redirectTo, required modo}) async {
      _oauth.add((f, redirectTo, modo));
      return true;
    };
  });

  tearDown(() {
    EntradaSocialCliente.interruptoresParaTeste = null;
    EntradaSocialCliente.iniciarParaTeste = null;
    EntradaSocialCliente.ultimosInterruptores = (google: true, apple: false);
  });

  group('regras (sem ecrã)', () {
    test('volta à app por pt.boraapp.bora://auth/callback; na web à origem',
        () {
      expect(redirectDaEntradaSocial(web: false),
          'pt.boraapp.bora://auth/callback');
      expect(
          redirectDaEntradaSocial(
              web: true,
              base: Uri.parse('https://app.boraguarda.com/#/registo-cliente')),
          'https://app.boraguarda.com');
      expect(
          redirectDaEntradaSocial(
              web: true, base: Uri.parse('https://bora-app-web.pages.dev/')),
          'https://bora-app-web.pages.dev');
    });

    test('Android e web: só o Google; iPhone: Google só com a Apple ao lado',
        () {
      for (final web in [false, true]) {
        expect(
            botoesDeEntradaVisiveis(
                web: web,
                plataforma: TargetPlatform.android,
                googleLigado: true,
                appleLigado: true),
            (google: true, apple: false));
      }
      expect(
          botoesDeEntradaVisiveis(
              web: false,
              plataforma: TargetPlatform.iOS,
              googleLigado: true,
              appleLigado: false),
          (google: false, apple: false),
          reason: 'regra 4.8: sem Apple não há Google no iPhone');
      expect(
          botoesDeEntradaVisiveis(
              web: false,
              plataforma: TargetPlatform.iOS,
              googleLigado: true,
              appleLigado: true),
          (google: true, apple: true));
      // Safari do iPhone na web conta como web: só Google.
      expect(
          botoesDeEntradaVisiveis(
              web: true,
              plataforma: TargetPlatform.iOS,
              googleLigado: true,
              appleLigado: false),
          (google: true, apple: false));
      expect(
          botoesDeEntradaVisiveis(
              web: false,
              plataforma: TargetPlatform.android,
              googleLigado: false,
              appleLigado: false),
          (google: false, apple: false),
          reason: 'interruptor do painel desliga');
    });

    test('modo da página: Safari dentro da app no iPhone, navegador no Android',
        () {
      expect(modoDaPaginaDeEntrada(web: false, plataforma: TargetPlatform.iOS),
          LaunchMode.inAppBrowserView);
      expect(
          modoDaPaginaDeEntrada(web: false, plataforma: TargetPlatform.android),
          LaunchMode.externalApplication);
      expect(modoDaPaginaDeEntrada(web: true, plataforma: TargetPlatform.iOS),
          LaunchMode.platformDefault);
    });

    test('conta Google/Apple reconhece-se pelo app_metadata', () {
      expect(EntradaSocialCliente.contaSocial(User.fromJson(_contaGoogle())!),
          isTrue);
      final soEmail = {
        ..._contaGoogle(),
        'app_metadata': {
          'provider': 'email',
          'providers': ['email'],
        },
      };
      expect(EntradaSocialCliente.contaSocial(User.fromJson(soEmail)!), isFalse);
      final ligada = {
        ..._contaGoogle(),
        'app_metadata': {
          'provider': 'email',
          'providers': ['email', 'apple'],
        },
      };
      expect(EntradaSocialCliente.contaSocial(User.fromJson(ligada)!), isTrue);
    });

    test('o URL que o SDK abre leva provider=google e o redirect_to da app',
        () async {
      final res = await Supabase.instance.client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: oauthRedirectApp,
      );
      final u = Uri.parse(res.url);
      expect(u.path, '/auth/v1/authorize');
      expect(u.queryParameters['provider'], 'google');
      expect(u.queryParameters['redirect_to'], 'pt.boraapp.bora://auth/callback');
    });

    test('a marca "entrada de cliente em curso" serve uma vez só', () async {
      await EntradaSocialCliente.iniciar(OAuthProvider.google);
      expect(await EntradaSocialCliente.consumirPendente(), isTrue);
      expect(await EntradaSocialCliente.consumirPendente(), isFalse);
    });
  });

  group('ecrãs do cliente', () {
    testWidgets('login do cliente: Google aparece, sem Apple; ao tocar → '
        'OAuth google para pt.boraapp.bora://auth/callback', (t) async {
      final auth = await _authStore(t);
      await _abrir(t, auth, const ClientLoginScreen());

      expect(_google, findsOneWidget);
      expect(_apple, findsNothing);

      await _tocar(t, const Key('entrar_google'));
      expect(_oauth, hasLength(1));
      expect(_oauth.single.$1, OAuthProvider.google);
      expect(_oauth.single.$2, 'pt.boraapp.bora://auth/callback');
      expect(_oauth.single.$3, LaunchMode.externalApplication);
    });

    testWidgets('registo do cliente: Google aparece e chama o OAuth', (t) async {
      final auth = await _authStore(t);
      await _abrir(t, auth, const RegisterClientScreen());

      expect(_google, findsOneWidget);
      expect(_apple, findsNothing);
      expect(find.text('ou regista-te por email'), findsOneWidget);

      await _tocar(t, const Key('entrar_google'));
      expect(_oauth.map((c) => (c.$1, c.$2)).toList(),
          [(OAuthProvider.google, 'pt.boraapp.bora://auth/callback')]);
    });

    testWidgets('painel desliga o Google → o botão some', (t) async {
      EntradaSocialCliente.interruptoresParaTeste =
          () async => (google: false, apple: false);
      final auth = await _authStore(t);
      await _abrir(t, auth, const ClientLoginScreen());
      expect(_google, findsNothing);
      expect(find.byType(BotaoEntradaGoogle), findsNothing);
    });

    testWidgets('iPhone com a Apple ligada: Apple e Google no login e no '
        'registo; a Apple abre pela folha Safari', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      EntradaSocialCliente.interruptoresParaTeste =
          () async => (google: true, apple: true);
      final auth = await _authStore(t);

      await _abrir(t, auth, const ClientLoginScreen());
      expect(_apple, findsOneWidget);
      expect(_google, findsOneWidget);
      await _tocar(t, const Key('entrar_apple'));
      expect(_oauth.single.$1, OAuthProvider.apple);
      expect(_oauth.single.$2, 'pt.boraapp.bora://auth/callback');
      expect(_oauth.single.$3, LaunchMode.inAppBrowserView);

      await _abrir(t, auth, const RegisterClientScreen());
      expect(_apple, findsOneWidget);
      expect(_google, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iPhone sem a Apple ligada: nem Apple nem Google (regra 4.8)',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final auth = await _authStore(t);
      await _abrir(t, auth, const ClientLoginScreen());
      expect(_apple, findsNothing);
      expect(_google, findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('estafeta e parceiro ficam como estão', () {
    testWidgets('login do estafeta: sem Google nem Apple', (t) async {
      EntradaSocialCliente.interruptoresParaTeste =
          () async => (google: true, apple: true);
      final auth = await _authStore(t);
      await _abrir(t, auth, const DriverLoginScreen());
      expect(find.byType(EntradaSocialBotoes), findsNothing);
      expect(_google, findsNothing);
      expect(_apple, findsNothing);
    });

    testWidgets('login do parceiro: sem Google nem Apple', (t) async {
      EntradaSocialCliente.interruptoresParaTeste =
          () async => (google: true, apple: true);
      final auth = await _authStore(t);
      await _abrir(t, auth, const PartnerLoginScreen());
      expect(find.byType(EntradaSocialBotoes), findsNothing);
      expect(_google, findsNothing);
      expect(_apple, findsNothing);
    });
  });

  group('painel admin', () {
    test('lê a resposta da RPC e ignora linhas estranhas', () {
      final m = metodosLoginPorCliente([
        {'user_id': 'a', 'metodos': ['email', 'google'], 'ultimo_metodo': 'google'},
        {'user_id': 'b', 'metodos': ['apple'], 'ultimo_metodo': null},
        {'user_id': '', 'metodos': ['email']},
        {'user_id': 'c', 'metodos': []},
        'lixo',
      ]);
      expect(m.keys, ['a', 'b']);
      expect(m['a']!.metodos, ['email', 'google']);
      expect(m['a']!.ultimo, 'google');
      expect(metodosLoginPorCliente(null), isEmpty);
    });

    testWidgets('etiqueta "Email + Google" com o último acesso no tooltip',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EtiquetaMetodoLogin(
            metodos: MetodosLoginCliente(
                metodos: ['email', 'google'], ultimo: 'google'),
          ),
        ),
      ));
      expect(find.text('Email + Google'), findsOneWidget);
      final tip = t.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, 'Entra por: Email + Google · último acesso por Google');
    });
  });

  // Fica em último: deixa uma sessão Google aberta no SDK partilhado.
  group('a volta do Google abre a conta de cliente', () {
    testWidgets(
        'carrinho → "Entrar ou criar conta" → Google → ligação de volta '
        '→ cliente aberto, papel garantido, nome do Google, volta ao carrinho',
        (t) async {
      final auth = await _authStore(t);
      final session = await _abrir(
          t, auth, const ClientLoginScreen(voltarAoChamador: true),
          porCima: true);
      expect(find.text('Entrar ou criar conta'), findsOneWidget);

      await _tocar(t, const Key('entrar_google'));
      expect(_oauth.single.$1, OAuthProvider.google);
      expect(auth.currentClient, isNull);

      // O que o supabase_flutter faz quando o Android/iPhone abre a ligação.
      await t.runAsync(() async {
        await Supabase.instance.client.auth.getSessionFromUrl(Uri.parse(
            'pt.boraapp.bora://auth/callback#access_token=${_jwt()}'
            '&expires_in=3600&refresh_token=r1&token_type=bearer'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _assentar(t);
      await t.pump(const Duration(milliseconds: 600));
      await _assentar(t);

      final c = auth.currentClient;
      expect(c, isNotNull, reason: 'a conta de cliente tem de abrir');
      expect(c!.email, 'ana.google@exemplo.pt');
      expect(c.name, 'Ana Google', reason: 'o nome vem do Google');
      expect(c.phone, isEmpty);
      expect(contactoDoClienteCompleto(nome: c.name, telemovel: c.phone),
          isFalse,
          reason: 'sem telemóvel → a app pede-o (CompleteProfileScreen)');
      expect(auth.currentDriver, isNull);
      expect(session.role, UserRole.client);
      expect(_pedidos, contains('POST /rest/v1/rpc/add_client_role_to_me'));
      expect(_metaGravada['bora_role'], 'client',
          reason: 'conta nova fica com o modo cliente, como no registo');
      expect(_metaGravada['bora_name'], 'Ana Google');
      expect(_Carrinho.devolveu, isTrue, reason: 'volta ao MESMO carrinho');
      expect(find.byType(ClientLoginScreen), findsNothing);
    });
  });
}
