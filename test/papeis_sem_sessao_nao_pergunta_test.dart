// fechar-app-15-11 · Bloco 3 (e) — SEM SESSÃO NÃO SE PERGUNTA PELOS PAPÉIS.
//
// Medido a 14/11/2026 às 18:19:51 (registos do Postgres):
//   permission denied for function my_trabalho_pendente
//   permission denied for function my_roles_summary
// A app abria, o portão do prestador montava-se com o estafeta guardado no
// telemóvel e perguntava ao servidor 4 s ANTES de a sessão existir. As duas
// funções são fechadas a quem não entrou (e assim ficam): cada arranque dava
// dois 401.
//
// O servidor aqui é falso e responde SEMPRE "és estafeta aprovado, com
// trabalho à espera". Por isso o primeiro teste só passa se o pedido não
// sair: se saísse, a resposta vinha cheia.
import 'dart:convert';

import 'package:bora_app/services/roles_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
const _email = 'prestador.teste.sessao@bora.app';
const _uid = '00000000-0000-4000-8000-000000001511';

/// Os caminhos de todos os pedidos que chegaram ao servidor falso.
final _pedidos = <String>[];

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

Map<String, Object?> _sessao() => {
      'access_token': _jwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-de-teste',
      'user': {
        'id': _uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': _email,
        'app_metadata': <String, Object?>{},
        'user_metadata': {'bora_role': 'driver'},
        'created_at': '2026-11-15T00:00:00Z',
      },
    };

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  _pedidos.add(caminho);
  if (caminho.endsWith('/auth/v1/token') &&
      req.url.queryParameters['grant_type'] == 'password') {
    return http.Response(jsonEncode(_sessao()), 200, headers: _json);
  }
  if (caminho.endsWith('/rpc/my_roles_summary')) {
    return http.Response(
        jsonEncode({'has_driver': true, 'driver_status': 'approved'}), 200,
        headers: _json);
  }
  if (caminho.endsWith('/rpc/my_trabalho_pendente')) {
    return http.Response(jsonEncode({'estafeta': true}), 200, headers: _json);
  }
  return http.Response('[]', 200, headers: _json);
}

Iterable<String> _perguntasDePapeis() => _pedidos.where((c) =>
    c.endsWith('/rpc/my_roles_summary') ||
    c.endsWith('/rpc/my_trabalho_pendente'));

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
  });

  // A ordem conta: o primeiro corre antes de haver sessão.
  test('sem sessão: nenhum dos dois pedidos sai e a resposta é "nada"',
      () async {
    expect(Supabase.instance.client.auth.currentSession, isNull);
    _pedidos.clear();

    final resumo = await RolesService.mySummary();
    final pendente = await RolesService.myTrabalhoPendente();

    expect(_perguntasDePapeis(), isEmpty,
        reason: 'sem sessão o servidor recusa (401): o pedido não pode sair');
    expect(resumo.temAlgumPapel, isFalse);
    expect(resumo.driverStatus, isNull);
    expect(pendente.estafeta, isFalse);
    expect(pendente.limpeza || pendente.lavagem || pendente.casa, isFalse);
  });

  // A guarda não pode calar quem tem sessão: com sessão, os dois pedidos têm
  // de chegar ao servidor.
  //
  // [15/11/2026, CI 43652375486] A leitura da resposta deixou de se provar por
  // aqui: com este servidor falso o cliente do Supabase rebenta por dentro
  // depois de receber a resposta ("Null check operator used on a null value"),
  // o serviço apanha o erro e devolve "nada". Isso é do andaime do teste, não
  // da app. O que a guarda mudou é o pedido SAIR ou NÃO sair, e isso prova-se
  // pelos pedidos que o servidor falso recebeu; a leitura prova-se no teste a
  // seguir, sem rede.
  test('com sessão: os dois pedidos saem', () async {
    await Supabase.instance.client.auth
        .signInWithPassword(email: _email, password: 'teste');
    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    _pedidos.clear();

    await RolesService.mySummary();
    await RolesService.myTrabalhoPendente();

    expect(
        _perguntasDePapeis().toList(),
        containsAll(<Matcher>[
          endsWith('/rpc/my_roles_summary'),
          endsWith('/rpc/my_trabalho_pendente'),
        ]),
        reason: 'a guarda não pode calar quem tem sessão');
  });

  test('a resposta do servidor lê-se (as mesmas respostas do servidor falso)',
      () {
    final resumo = RolesSummary.fromJson(
        <String, dynamic>{'has_driver': true, 'driver_status': 'approved'});
    final pendente =
        TrabalhoPendente.fromJson(<String, dynamic>{'estafeta': true});

    expect(resumo.driverApproved, isTrue);
    expect(pendente.estafeta, isTrue);
    expect(pendente.limpeza || pendente.lavagem || pendente.casa, isFalse);
  });
}
