/// Editar perfil do cliente (missão editar-perfil-2026-11-11).
///
/// Caso real: uma cliente perguntou como mudar o nome e o botão não existia.
/// Estes testes provam o ecrã com o AuthStore verdadeiro e um servidor falso:
/// o "Guardar" só liga com mudanças, grava pela RPC `client_update_my_profile`
/// com o telemóvel sem +351, o nome novo aparece logo no "Olá, X!", e com a
/// rede em baixo aparece uma mensagem clara sem perder o que se escreveu.
library;

import 'dart:async';
import 'dart:convert';

import 'package:bora_app/auth/auth_store.dart';
import 'package:bora_app/screens/edit_profile_screen.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:bora_app/utils/contact_validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _email = 'cliente.teste.perfil@bora.app';
const _uid = '00000000-0000-4000-8000-000000001111';

enum _Rpc { grava, semRede }

var _rpc = _Rpc.grava;
final _pedidosRpc = <Map<String, dynamic>>[];

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'exp': exp, 'role': 'authenticated'})}'
      '.assinatura';
}

Map<String, Object?> _user() => {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': _email,
      'app_metadata': <String, Object?>{},
      'user_metadata': {
        'bora_role': 'client',
        'bora_name': 'Ana Antiga',
        'bora_phone': '912345678',
      },
      'created_at': '2026-11-11T00:00:00Z',
    };

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  if (caminho.endsWith('/auth/v1/token') &&
      req.url.queryParameters['grant_type'] == 'password') {
    return http.Response(
        jsonEncode({
          'access_token': _jwt(),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-de-teste',
          'user': _user(),
        }),
        200,
        headers: _json, request: req);
  }
  if (caminho.endsWith('/rest/v1/rpc/client_update_my_profile')) {
    if (_rpc == _Rpc.semRede) throw http.ClientException('sem rede');
    final corpo = jsonDecode(req.body) as Map<String, dynamic>;
    _pedidosRpc.add(corpo);
    return http.Response(
        jsonEncode({
          'ok': true,
          'alterado': true,
          'name': corpo['p_name'],
          'phone': corpo['p_phone'] ?? '912345678',
          'campos': ['name'],
        }),
        200,
        headers: _json, request: req);
  }
  if (caminho.endsWith('/auth/v1/user')) {
    return http.Response(jsonEncode(_user()), 200,
        headers: _json, request: req);
  }
  if (caminho.endsWith('/rest/v1/users')) {
    // A linha de public.users igual ao metadata: o acerto não muda nada.
    return http.Response(
        jsonEncode({'name': 'Ana Antiga', 'phone': '912345678'}), 200,
        headers: _json, request: req);
  }
  return http.Response('[]', 200, headers: _json, request: req);
}

Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Faz de ecrã Início: mostra o "Olá, X!" a partir do AuthStore, como a app.
Widget _app(AuthStore auth) => ChangeNotifierProvider<AuthStore>.value(
      value: auth,
      child: MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        home: Consumer<AuthStore>(
          builder: (context, a, __) => Scaffold(
            body: Column(children: [
              Text('Olá, ${(a.displayName ?? '').split(' ').first}!'),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                        builder: (_) => const EditProfileScreen())),
                child: const Text('abrir'),
              ),
            ]),
          ),
        ),
      ),
    );

Future<AuthStore> _clienteNoEditarPerfil(WidgetTester tester) async {
  final auth = (await tester.runAsync(() async {
    final a = AuthStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return a;
  }))!;
  addTearDown(auth.dispose);
  await tester.pumpWidget(_app(auth));
  await tester.runAsync(() => Supabase.instance.client.auth
      .signInWithPassword(email: _email, password: 'teste'));
  await _servidorResponde(tester);
  expect(auth.currentClient?.name, 'Ana Antiga');
  expect(find.text('Olá, Ana!'), findsOneWidget);

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(find.byType(EditProfileScreen), findsOneWidget);
  return auth;
}

bool _guardarLigado(WidgetTester tester) {
  final botao = find.descendant(
    of: find.byKey(const Key('editar_perfil_guardar')),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  return tester.widget<ButtonStyleButton>(botao.first).onPressed != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('regra do nome (igual à do servidor)', () {
    test('2 a 60 caracteres, com letras, sem espaços a mais', () {
      expect(limparNome('  Ana   Paula  '), 'Ana Paula');
      expect(validarNomePerfil('Ana'), isNull);
      expect(validarNomePerfil('Zé'), isNull);
      expect(validarNomePerfil('A'), isNotNull);
      expect(validarNomePerfil('12'), isNotNull);
      expect(validarNomePerfil('   '), isNotNull);
      expect(validarNomePerfil('a' * 60), isNull);
      expect(validarNomePerfil('a' * 61), isNotNull);
    });
  });

  group('ecrã Editar perfil', () {
    setUpAll(() async {
      await runZonedGuarded(() async {
        NotificationService.instance;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }, (_, __) {});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Supabase.initialize(
        url: 'http://127.0.0.1:1',
        publishableKey: 'teste',
        debug: false,
        authOptions:
            const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient(_servidor),
      );
    });

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      _rpc = _Rpc.grava;
      _pedidosRpc.clear();
    });

    testWidgets(
        'Guardar desligado sem mudanças; grava nome e telemóvel sem +351 e '
        'o "Olá, X!" muda logo', (tester) async {
      final auth = await _clienteNoEditarPerfil(tester);

      expect(find.text('O email é o teu acesso e não se altera.'),
          findsOneWidget);
      expect(find.text(_email), findsOneWidget);
      expect(_guardarLigado(tester), isFalse,
          reason: 'sem mudanças o Guardar fica desligado');

      // O mesmo número escrito de outra forma não é uma mudança.
      await tester.enterText(
          find.byKey(const Key('editar_perfil_telemovel')), '+351 912 345 678');
      await tester.pump();
      expect(_guardarLigado(tester), isFalse);

      await tester.enterText(
          find.byKey(const Key('editar_perfil_nome')), '  Paula   Ferreira ');
      await tester.enterText(
          find.byKey(const Key('editar_perfil_telemovel')), '+351 931 112 222');
      await tester.pump();
      expect(_guardarLigado(tester), isTrue);

      await tester.tap(find.byKey(const Key('editar_perfil_guardar')));
      await _servidorResponde(tester);
      await tester.pumpAndSettle();

      expect(_pedidosRpc, hasLength(1));
      expect(_pedidosRpc.single['p_name'], 'Paula Ferreira');
      expect(_pedidosRpc.single['p_phone'], '931112222');
      expect(find.byType(EditProfileScreen), findsNothing,
          reason: 'gravou e voltou ao ecrã de onde veio');
      expect(auth.currentClient?.name, 'Paula Ferreira');
      expect(auth.currentClient?.phone, '931112222');
      expect(find.text('Olá, Paula!'), findsOneWidget);
    });

    testWidgets('nome inválido: mostra o erro e não chama o servidor',
        (tester) async {
      await _clienteNoEditarPerfil(tester);
      await tester.enterText(find.byKey(const Key('editar_perfil_nome')), 'A');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editar_perfil_guardar')));
      await tester.pumpAndSettle();
      expect(find.text('O nome tem de ter entre 2 e 60 caracteres.'),
          findsOneWidget);
      expect(_pedidosRpc, isEmpty);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets(
        'rede em baixo: mensagem clara, o que se escreveu fica e o estado '
        'não muda', (tester) async {
      final auth = await _clienteNoEditarPerfil(tester);
      _rpc = _Rpc.semRede;
      await tester.enterText(
          find.byKey(const Key('editar_perfil_nome')), 'Paula Ferreira');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editar_perfil_guardar')));
      await _servidorResponde(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editar_perfil_erro')), findsOneWidget);
      expect(
          find.text(
              'Não foi possível guardar. Verifica a ligação e tenta de novo.'),
          findsOneWidget);
      expect(find.text('Paula Ferreira'), findsOneWidget,
          reason: 'o texto escrito não se perde');
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(auth.currentClient?.name, 'Ana Antiga',
          reason: 'sem confirmação do servidor nada muda');
      expect(_guardarLigado(tester), isTrue,
          reason: 'pode tentar de novo');
    });
  });
}
