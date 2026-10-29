import 'dart:convert';

import 'package:bora_app/widgets/terms_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Missão boom-burger-2026-10-27, F4 — TermsGate com o público 'parceiro'.
///
/// O servidor é falso (MockClient), o SDK do Supabase é o verdadeiro, com um
/// parceiro com sessão aberta. Prova:
///  1. sem versão pendente (`legal_terms_pending` devolve `null`, como o SQL
///     faz para quem já aceitou) o painel aparece e não há ecrã de termos;
///  2. com a versão 2026-10-28 pendente aparece o texto e o botão "Aceito";
///     tocar grava com `legal_terms_accept('parceiro', '2026-10-28', ...)` e o
///     painel fica à vista;
///  3. erro do servidor ao perguntar → falha aberta (o painel aparece).
///
/// missao-geral-2026-10-28, F3 — os termos são só das lojas de comida e
/// mercado APROVADAS. O portão lê primeiro as lojas do dono (`restaurants`):
///  4. dono de serviços (sem loja), loja de beleza aprovada e loja por aprovar
///     → nem pergunta pela versão, painel à vista mesmo havendo uma pendente;
///  5. erro a ler as lojas → falha aberta, sem termos;
///  6. [termosDoParceiroAplicam] linha a linha (categoria, extra, estado).

const _json = {'content-type': 'application/json; charset=utf-8'};
const _uid = '00000000-0000-4000-8000-000000002810';

/// O que o servidor responde a `legal_terms_pending`: null, uma versão, ou
/// um erro 500.
Object? _pendente;
bool _pendenteFalha = false;
final List<Map<String, dynamic>> _chamadas = [];

/// Loja de comida aprovada (o caso de quem TEM de aceitar).
const _restauranteAprovado = {
  'category': 'restaurant',
  'extra_categories': <String>[],
  'is_partner': true,
  'approval_status': 'approved',
};

/// O que o servidor responde à leitura das lojas do dono (`restaurants`).
List<Map<String, Object?>> _lojas = [_restauranteAprovado];
bool _lojasFalha = false;
final List<Uri> _consultasLojas = [];

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _sessao() {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': _uid, 'exp': exp, 'role': 'authenticated'})}.assinatura',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-de-teste',
    'user': {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'parceiro.termos@bora.app',
      'app_metadata': <String, Object?>{},
      'user_metadata': {'bora_role': 'partner'},
      'created_at': '2026-10-27T00:00:00Z',
    },
  };
}

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  if (caminho.endsWith('/auth/v1/token')) {
    return http.Response(jsonEncode(_sessao()), 200, headers: _json, request: req);
  }
  if (caminho.endsWith('/rest/v1/restaurants')) {
    _consultasLojas.add(req.url);
    if (_lojasFalha) {
      return http.Response(
          jsonEncode({'message': 'boom', 'code': 'XX000'}), 500,
          headers: _json, request: req);
    }
    return http.Response(jsonEncode(_lojas), 200, headers: _json, request: req);
  }
  if (caminho.endsWith('/rest/v1/rpc/legal_terms_pending')) {
    _chamadas.add({'rpc': 'legal_terms_pending', ...jsonDecode(req.body)});
    if (_pendenteFalha) {
      return http.Response(
          jsonEncode({'message': 'boom', 'code': 'XX000'}), 500,
          headers: _json, request: req);
    }
    return http.Response(jsonEncode(_pendente), 200, headers: _json, request: req);
  }
  if (caminho.endsWith('/rest/v1/rpc/legal_terms_accept')) {
    final corpo = jsonDecode(req.body) as Map<String, dynamic>;
    _chamadas.add({'rpc': 'legal_terms_accept', ...corpo});
    return http.Response(
        jsonEncode({'ok': true, 'version': corpo['p_version']}), 200,
        headers: _json, request: req);
  }
  return http.Response('[]', 200, headers: _json, request: req);
}

/// O cliente do Supabase acaba as respostas fora do relógio falso do teste.
Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Widget _app() => const MaterialApp(
      home: TermsGate(
        audience: 'parceiro',
        child: Scaffold(body: Text('PAINEL DO PARCEIRO')),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
    await Supabase.instance.client.auth
        .signInWithPassword(email: 'parceiro.termos@bora.app', password: 'x');
  });

  setUp(() {
    _pendente = null;
    _pendenteFalha = false;
    _chamadas.clear();
    _lojas = [_restauranteAprovado];
    _lojasFalha = false;
    _consultasLojas.clear();
  });

  testWidgets('sem versão pendente (null) → painel à vista, sem termos',
      (tester) async {
    expect(Supabase.instance.client.auth.currentUser?.id, _uid);
    final logs = await _comLogs(() async {
      await tester.pumpWidget(_app());
      await _servidorResponde(tester);
    });

    expect(_chamadas, [
      {'rpc': 'legal_terms_pending', 'p_audience': 'parceiro'},
    ]);
    // A resposta foi lida a sério (null), não engolida pela falha aberta.
    expect(logs.where((l) => l.contains('[TermsGate]')), isEmpty);
    expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);
    expect(find.text('Aceito'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('versão 2026-10-28 pendente → termos por cima; "Aceito" grava '
      'e tira os termos', (tester) async {
    _pendente = {
      'version': '2026-10-28',
      'audience': 'parceiro',
      'title': 'Termos e Condições do Parceiro — versão de 28/10/2026',
      'body': 'Estes são os termos entre a Bora e as lojas parceiras.',
    };
    final logs = await _comLogs(() async {
      await tester.pumpWidget(_app());
      await _servidorResponde(tester);

      expect(find.text('Termos e Condições do Parceiro — versão de 28/10/2026'),
          findsOneWidget);
      expect(find.text('Estes são os termos entre a Bora e as lojas parceiras.'),
          findsOneWidget);
      expect(find.text('Aceito'), findsOneWidget);

      await tester.tap(find.text('Aceito'));
      await _servidorResponde(tester);
    });

    expect(logs.where((l) => l.contains('[TermsGate]')), isEmpty);
    final aceite =
        _chamadas.where((c) => c['rpc'] == 'legal_terms_accept').toList();
    expect(aceite, hasLength(1));
    expect(aceite.single['p_audience'], 'parceiro');
    expect(aceite.single['p_version'], '2026-10-28');
    expect(aceite.single['p_platform'], isNotNull);
    expect(find.text('Aceito'), findsNothing);
    expect(find.text('Termos e Condições do Parceiro — versão de 28/10/2026'),
        findsNothing);
    expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);
  });

  testWidgets('erro do servidor ao perguntar → falha aberta', (tester) async {
    _pendenteFalha = true;
    final logs = await _comLogs(() async {
      await tester.pumpWidget(_app());
      await _servidorResponde(tester);
    });
    expect(_chamadas.single['rpc'], 'legal_terms_pending');
    expect(logs.where((l) => l.contains('[TermsGate] legal_terms_pending')),
        hasLength(1));
    expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);
    expect(find.text('Aceito'), findsNothing);
  });

  group('F3 — só lojas de comida e mercado aprovadas', () {
    const versao = {
      'version': '2026-10-28',
      'audience': 'parceiro',
      'title': 'Termos e Condições do Parceiro — versão de 28/10/2026',
      'body': 'Estes são os termos entre a Bora e as lojas parceiras.',
    };

    testWidgets('lê as lojas do próprio dono (user_id ou user_)',
        (tester) async {
      _pendente = versao;
      await tester.pumpWidget(_app());
      await _servidorResponde(tester);
      expect(_consultasLojas, hasLength(1));
      final q = Uri.decodeQueryComponent(_consultasLojas.single.query);
      expect(q, contains('user_id.eq.$_uid'));
      expect(q, contains('user_.eq.$_uid'));
      expect(find.text('Aceito'), findsOneWidget);
    });

    for (final caso in <String, List<Map<String, Object?>>>{
      'parceiro de serviços (sem loja)': [],
      'loja de beleza aprovada': [
        {'category': 'beauty', 'extra_categories': <String>[], 'is_partner': true, 'approval_status': 'approved'},
      ],
      'restaurante por aprovar': [
        {'category': 'restaurant', 'extra_categories': <String>[], 'is_partner': true, 'approval_status': 'pending'},
      ],
    }.entries) {
      testWidgets('${caso.key} → não pergunta pela versão, painel à vista',
          (tester) async {
        _pendente = versao;
        _lojas = caso.value;
        await tester.pumpWidget(_app());
        await _servidorResponde(tester);
        expect(_consultasLojas, hasLength(1));
        expect(_chamadas, isEmpty);
        expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);
        expect(find.text('Aceito'), findsNothing);
      });
    }

    testWidgets('erro a ler as lojas → falha aberta, sem termos',
        (tester) async {
      _pendente = versao;
      _lojasFalha = true;
      final logs = await _comLogs(() async {
        await tester.pumpWidget(_app());
        await _servidorResponde(tester);
      });
      expect(logs.where((l) => l.contains('[TermsGate] lojas do parceiro')),
          hasLength(1));
      expect(_chamadas, isEmpty);
      expect(find.text('PAINEL DO PARCEIRO'), findsOneWidget);
      expect(find.text('Aceito'), findsNothing);
    });

    test('termosDoParceiroAplicam, caso a caso', () {
      Map<String, Object?> loja(String cat,
              {List<String> extra = const [],
              bool parceira = true,
              String estado = 'approved'}) =>
          {
            'category': cat,
            'extra_categories': extra,
            'is_partner': parceira,
            'approval_status': estado,
          };
      for (final c in ['restaurant', 'sobremesa', 'festas', 'supermarket']) {
        expect(termosDoParceiroAplicam([loja(c)]), isTrue, reason: c);
      }
      for (final c in ['beauty', 'pharmacy', 'store', '']) {
        expect(termosDoParceiroAplicam([loja(c)]), isFalse, reason: c);
      }
      expect(termosDoParceiroAplicam([loja('beauty', extra: ['restaurant'])]),
          isTrue);
      expect(termosDoParceiroAplicam([loja('restaurant', estado: 'pending')]),
          isFalse);
      expect(termosDoParceiroAplicam([loja('restaurant', estado: 'rejected')]),
          isFalse);
      expect(termosDoParceiroAplicam([loja('restaurant', parceira: false)]),
          isFalse);
      expect(termosDoParceiroAplicam(const []), isFalse);
      expect(
          termosDoParceiroAplicam(
              [loja('beauty'), loja('supermarket', estado: 'pending'), loja('festas')]),
          isTrue);
      // Sem extra_categories (null) não parte.
      expect(
          termosDoParceiroAplicam([
            {'category': 'restaurant', 'extra_categories': null, 'is_partner': true, 'approval_status': 'approved'}
          ]),
          isTrue);
    });
  });
}

/// Corre [corpo] a guardar o que passar pelo debugPrint (o TermsGate escreve
/// lá quando a pergunta falha) e repõe o debugPrint no fim.
Future<List<String>> _comLogs(Future<void> Function() corpo) async {
  final logs = <String>[];
  final antes = debugPrint;
  debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  try {
    await corpo();
  } finally {
    debugPrint = antes;
  }
  return logs;
}
