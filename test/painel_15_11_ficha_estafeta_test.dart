// painel-15-11 (auditoria S3 da ficha do entregador no painel): os dois ids do
// entregador (user_id e drivers.id), as 10 chaves do admin_update_driver, o
// link de senha para a conta de login, os erros do "Forçar logout", o
// "Remover" que confere os pedidos em andamento antes e os textos em PT-BR.
//
// Sem rede: funções puras do serviço + leitura do código-fonte.
import 'dart:io';

import 'package:bora_app/services/admin/admin_driver_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tela = 'lib/screens/admin/admin_driver_detail_screen.dart';
const _servico = 'lib/services/admin/admin_driver_service.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

/// Trecho do código de [inicio] até ao [fim] seguinte.
String _trecho(String fonte, String inicio, String fim) {
  final i = fonte.indexOf(inicio);
  expect(i, isNonNegative, reason: 'não achei "$inicio"');
  final f = fonte.indexOf(fim, i + inicio.length);
  expect(f, isNonNegative, reason: 'não achei "$fim" depois de "$inicio"');
  return fonte.substring(i, f);
}

/// O texto que o admin lê: literais com espaço, fora das linhas de comentário.
List<String> _textos(String fonte) {
  final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'|" r'"((?:[^"\\\n]|\\.)*)"');
  final textos = <String>[];
  for (final linha in fonte.split('\n')) {
    if (linha.trimLeft().startsWith('//')) continue;
    for (final m in literal.allMatches(linha)) {
      final t = m.group(1) ?? m.group(2) ?? '';
      if (t.contains(' ')) textos.add(t);
    }
  }
  return textos;
}

const _ficha = <String, dynamic>{
  'id': '11111111-1111-1111-1111-111111111111',
  'user_id': '22222222-2222-2222-2222-222222222222',
};

void main() {
  final tela = _ler(_tela);
  final servico = _ler(_servico);

  group('os dois ids do entregador (user_id e drivers.id)', () {
    test('idsDoEntregador traz os dois, sem repetir nem vazios', () {
      expect(AdminDriverService.idsDoEntregador(_ficha),
          [_ficha['user_id'], _ficha['id']]);
      expect(AdminDriverService.idsDoEntregador({'id': 'x', 'user_id': 'x'}),
          ['x']);
      expect(AdminDriverService.idsDoEntregador({'id': 'x', 'user_id': null}),
          ['x']);
      expect(AdminDriverService.idsDoEntregador({'id': 'x', 'user_id': ' '}),
          ['x']);
    });

    test('conta de login = user_id; ficha antiga sem user_id usa drivers.id',
        () {
      expect(AdminDriverService.authIdDoEntregador(_ficha), _ficha['user_id']);
      expect(
          AdminDriverService.authIdDoEntregador({'id': 'x', 'user_id': null}),
          'x');
    });

    test('o histórico procura os dois ids nas duas colunas', () {
      expect(AdminDriverService.filtroHistoricoDoEntregador(['u1', 'd1']),
          'entity_id.in.(u1,d1),entity_id_text.in.(u1,d1)');
    });

    test('saldo: mostra a linha da conta de login e não soma nada', () {
      final doUser = <String, dynamic>{'driver_id': 'u1', 'balance': 5};
      final daFicha = <String, dynamic>{'driver_id': 'd1', 'balance': 3};
      expect(AdminDriverService.saldoDoEntregador([daFicha, doUser], 'u1'),
          same(doUser));
      expect(AdminDriverService.saldoDoEntregador([daFicha], 'u1'),
          same(daFicha));
      expect(AdminDriverService.saldoDoEntregador(const [], 'u1'), isNull);
    });

    test('Pedidos, Transações e saldo filtram pelos dois ids', () {
      expect(
          RegExp(r"\.inFilter\('assigned_driver_id', widget\.driverIds\)")
              .allMatches(tela)
              .length,
          2,
          reason: '"Últimos 50" e o período');
      expect(tela, contains(".inFilter('driver_id', widget.driverIds)"),
          reason: 'transações');
      expect(tela, contains(".inFilter('driver_id', ids)"),
          reason: 'saldo do cabeçalho');
      expect(tela, isNot(contains(".eq('assigned_driver_id'")));
      expect(tela, isNot(contains(".eq('driver_id'")));
      expect(tela, contains('_OrdersTab(driverIds: ids)'));
      expect(tela,
          contains('_TransactionsTab(driverIds: ids, balance: _balance)'));
      expect(tela, contains('_AuditTab(driverIds: ids)'));
    });

    test('o período dos Pedidos continua igual (entrega ou, sem ela, pedido)',
        () {
      expect(
          tela,
          contains(
              r"'and(delivered_at.gte.$deIso,delivered_at.lt.$ateIso),'"));
      expect(
          tela,
          contains(r"'and(delivered_at.is.null,created_at.gte.$deIso,"
              r"created_at.lt.$ateIso)'"));
      expect(tela, contains('entregaNoPeriodo(at, periodo, agora)'));
      expect(tela, contains('.limit(500)'));
      expect(tela, contains("key: const Key('admin_estafeta_total_periodo')"));
    });

    test('Histórico e "Última ação" leem as entradas dos dois ids', () {
      expect(
          RegExp(r'\.or\(AdminDriverService\.filtroHistoricoDoEntregador\(')
              .allMatches(tela)
              .length,
          2);
      expect(tela, isNot(contains(".eq('entity_id', widget.driverId)")));
    });
  });

  group('Editar dados', () {
    test('vão sempre as 10 chaves do admin_update_driver, mesmo a null', () {
      final p = AdminDriverService.paramsAtualizarEntregador(
          driverId: 'd1', reason: 'corrigir o nome', name: 'Ana');
      expect(p.keys.toSet(), {
        'p_driver_id',
        'p_reason',
        'p_name',
        'p_phone',
        'p_vehicle_type',
        'p_license_plate',
        'p_iban',
        'p_nif',
        'p_vehicle_color',
        'p_vehicle_make_model',
      });
      expect(p, hasLength(10));
      expect(p['p_name'], 'Ana');
      expect(p['p_vehicle_color'], isNull);
      expect(p['p_vehicle_make_model'], isNull);
    });

    test('o serviço usa as 10 chaves (já não corta a cor e o modelo)', () {
      final metodo = _trecho(
          servico,
          'Future<Map<String, dynamic>> updateDriver(',
          'Future<Map<String, dynamic>> softDeleteDriver(');
      expect(metodo, contains('paramsAtualizarEntregador('));
      expect(servico,
          isNot(contains("if (vehicleColor != null) 'p_vehicle_color'")));
      expect(servico, isNot(contains('if (vehicleMakeModel != null)')));
    });

    test('a ficha carrega cor e marca/modelo; o TVDE aparece no veículo', () {
      expect(tela, contains("'vehicle_color, vehicle_make_model'"));
      expect(tela, contains("value: 'carro_passageiros'"));
    });
  });

  test('o link de senha vai para a conta de login (user_id ?? id)', () {
    final t = _trecho(tela, "label: 'Enviar link de redefinição de senha'",
        "label: 'Remover (fica arquivado)'");
    expect(t, contains('userId: AdminDriverService.authIdDoEntregador(driver)'));
    expect(t, isNot(contains("userId: driver['id']")));
    expect(tela, isNot(contains('drivers.id É o auth.users.id')));
  });

  group('Forçar logout: erro do servidor não é falha de rede', () {
    test('401 e 403 = sem permissão de admin', () {
      for (final status in [401, 403]) {
        final e = AdminDriverService.erroAoForcarLogout(FunctionException(
            status: status, details: const {'error': 'admin_required'}));
        expect(e.code, 'admin_required', reason: '$status');
        expect(e.message, startsWith('Sem permissão de admin'));
        expect(e.message, isNot(contains('conexão')));
      }
    });

    test('404 = função não instalada no servidor (ou entregador não achado)',
        () {
      final semFuncao = AdminDriverService.erroAoForcarLogout(
          const FunctionException(status: 404, details: {
        'code': 'NOT_FOUND',
        'message': 'Requested function was not found',
      }));
      expect(semFuncao.code, 'function_not_installed');
      expect(semFuncao.message, contains('não está instalada no servidor'));

      final semEntregador = AdminDriverService.erroAoForcarLogout(
          const FunctionException(
              status: 404, details: {'error': 'driver_not_found'}));
      expect(semEntregador.code, 'driver_not_found');
      expect(semEntregador.message, contains('Entregador não encontrado'));
    });

    test('outros erros do servidor = frase traduzida, nunca "sem conexão"', () {
      final e = AdminDriverService.erroAoForcarLogout(const FunctionException(
          status: 500, details: {'error': 'update_failed'}));
      expect(e.code, 'update_failed');
      expect(e.message, contains('Erro do servidor ao forçar logout'));

      final semCodigo = AdminDriverService.erroAoForcarLogout(
          const FunctionException(status: 502, details: 'Bad Gateway'));
      expect(semCodigo.code, 'http_502');
      expect(semCodigo.message, contains('HTTP 502'));
      expect(semCodigo.message, isNot(contains('conexão')));
    });

    test('só falta de rede de verdade diz "sem conexão"', () {
      final semRede = AdminDriverService.erroAoForcarLogout(
          const FunctionException(
              status: 0, details: 'ClientException: Failed to fetch'));
      expect(semRede.code, 'network');
      expect(semRede.message, startsWith('Sem conexão'));

      expect(
          AdminDriverService.erroAoForcarLogout(
                  Exception('ClientException: XMLHttpRequest error.'))
              .code,
          'network');

      final estranho =
          AdminDriverService.erroAoForcarLogout(StateError('resposta estranha'));
      expect(estranho.code, 'unexpected');
      expect(estranho.message, isNot(contains('conexão')));

      expect(
          AdminDriverService.pareceSemRede(
              const PostgrestException(message: 'Failed to fetch')),
          isFalse,
          reason: 'resposta do servidor nunca é falta de rede');
    });

    test('"Falha de rede" saiu do serviço', () {
      expect(servico, isNot(contains('Falha de rede')));
    });

    test('depois de forçar, a mensagem diz o que acontece hoje', () {
      final t = _trecho(tela, 'Future<void> _runForceLogout(',
          'Future<void> _runSoftDelete(');
      expect(t, contains('A sessão no celular dele pode continuar aberta até ele'));
      expect(t, isNot(contains('Sessões revogadas')));
      expect(t, contains('_erroParaAdmin(e)'));
    });
  });

  group('Remover confere os pedidos em andamento antes', () {
    test('lê pedidos_em_curso da resposta da admin_driver_presence', () {
      expect(
          AdminDriverService.pedidosEmCursoDaPresenca([
            {'pedidos_em_curso': 2},
          ]),
          2);
      expect(
          AdminDriverService.pedidosEmCursoDaPresenca({'pedidos_em_curso': 0}),
          0);
      expect(AdminDriverService.pedidosEmCursoDaPresenca(const []), isNull);
      expect(AdminDriverService.pedidosEmCursoDaPresenca(null), isNull);
    });

    test('trava com a frase pedida; sem pedidos, segue', () {
      expect(AdminDriverService.bloqueioParaRemover(0), isNull);
      expect(
          AdminDriverService.bloqueioParaRemover(2),
          'Este entregador tem 2 pedido(s) em andamento. Passe esses pedidos '
          'para outro entregador antes de remover.');
    });

    test('a ficha confere antes de chamar o servidor', () {
      final t = _trecho(tela, 'Future<void> _runSoftDelete(',
          'Future<bool> _temPedidoEmAndamento(');
      const confere = '_temPedidoEmAndamento(svc, driver, toast)';
      final remove = t.indexOf('svc.softDeleteDriver(');
      expect(t.indexOf(confere), isNonNegative);
      expect(remove, greaterThan(t.indexOf(confere)));
      expect(t.lastIndexOf(confere), lessThan(remove),
          reason: 'confere de novo logo antes de remover');

      final ajuda =
          _trecho(tela, 'Future<bool> _temPedidoEmAndamento(', '\n  }\n');
      expect(ajuda, contains('svc.pedidosEmCurso('));
      expect(ajuda, contains('AdminDriverService.authIdDoEntregador(driver)'));
      expect(ajuda, contains('AdminDriverService.bloqueioParaRemover('));

      final rpc = _trecho(servico, 'Future<int> pedidosEmCurso(', '\n  }\n');
      expect(rpc, contains("'admin_driver_presence'"));
      expect(rpc, contains("'p_driver': driverAuthId"));
    });

    test('a confirmação avisa que o dinheiro ainda não é conferido', () {
      expect(tela,
          contains('o painel ainda não consegue conferir se há dinheiro'));
    });
  });

  group('textos do painel em PT-BR', () {
    test('separadores, ações e botões com o texto novo', () {
      for (final novo in [
        "Tab(text: 'Transações')",
        "Tab(text: 'Histórico')",
        "Text('Ações'",
        "label: 'Reativar'",
        "Text('Reativar entregador?')",
        "'Última ação: ",
        "label: 'Remover (fica arquivado)'",
        "Prefira 'Suspender com motivo': ele guarda o registro ",
        'Movimentos de saldo do entregador: ganhos, acertos e ajustes.',
      ]) {
        expect(tela, contains(novo), reason: novo);
      }
    });

    test('sem os textos antigos em PT-PT ou em inglês', () {
      for (final antigo in [
        "'Acções'",
        "'Transacções'",
        "Tab(text: 'Audit')",
        "'Reactivar'",
        'Reactivar entregador?',
        'Última acção',
        'soft delete',
        'Sem transacções',
        'Saldo cash actual',
        "'Activo'",
        'Sem entradas de audit',
      ]) {
        expect(tela, isNot(contains(antigo)), reason: antigo);
      }
    });

    test('nenhum texto visível com palavra de Portugal', () {
      const ptPt = <String>[
        'acção',
        'Acção',
        'acções',
        'Acções',
        'transacç',
        'Transacç',
        // 'activa'/'activo' e não 'activ': o inglês 'active' das mensagens do
        // servidor (expressões regulares) não é texto para o admin.
        'activa',
        'activo',
        'Activa',
        'Activo',
        'actividade',
        'Inactiv',
        'inactiv',
        'actual',
        'Actual',
        'Tens de',
        'Tenta ',
        'Refresca',
        'Escolhe ',
        'escreve ',
        'exacto',
        'registo',
        'Morada',
        'telemóvel',
        'ecrã',
        'utilizador',
        'Matrícula',
        'Motociclo',
        'libertad',
        'Vais ',
        ' lhe ',
        'Faz login',
        'estafeta',
      ];
      final achados = <String>[];
      for (final (nome, fonte) in [('tela', tela), ('serviço', servico)]) {
        for (final t in _textos(fonte)) {
          for (final p in ptPt) {
            if (t.contains(p)) achados.add('$nome: "$p" em: $t');
          }
        }
      }
      expect(achados, isEmpty, reason: achados.join('\n'));
    });
  });
}
