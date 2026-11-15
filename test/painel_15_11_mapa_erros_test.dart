// painel-15-11 (H3): erros do painel em PT-BR, mapa ao vivo (auditoria S1),
// busca global (S5) e as telas Encomendas por telefone, Stripe — duas contas
// e Cancelamentos. Sem rede: funções puras e leitura das fontes.
//
// Os dados do mapa imitam o que se viu em produção a 15/11/2026: o mesmo
// entregador em duas linhas de `driver_locations` (uma com `drivers.id`,
// outra com `user_id`), as duas com GPS recente; `admin_live_drivers()`
// devolve as duas, com `driver_id` diferentes e o mesmo nome e telefone.
import 'dart:io';

import 'package:bora_app/screens/admin/_admin_rpc_errors.dart';
import 'package:bora_app/screens/admin/admin_cancellations_screen.dart';
import 'package:bora_app/screens/admin/admin_global_search_screen.dart';
import 'package:bora_app/screens/admin/admin_live_orders_map_screen.dart';
import 'package:bora_app/screens/admin/admin_stripe_contas_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, PostgrestException;

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

/// Corpo de um método (da assinatura até ao fecho com dois espaços).
String _metodo(String fonte, String assinatura) {
  final i = fonte.indexOf(assinatura);
  expect(i, greaterThanOrEqualTo(0), reason: 'falta "$assinatura"');
  final fim = fonte.indexOf('\n  }\n', i);
  return fonte.substring(i, fim < 0 ? fonte.length : fim);
}

void main() {
  group('humanizeAdminRpcError em PT-BR', () {
    String h(Object e) => humanizeAdminRpcError(e);
    PostgrestException pg(String message, [String? code]) =>
        PostgrestException(message: message, code: code);

    test('as marcas antigas, agora em PT-BR', () {
      expect(h(pg('admin_required')), 'Sem permissão de admin para esta ação.');
      // A guarda `_admin_op_guard` manda a marca com o código 42501: a marca
      // ganha ao código.
      expect(
          h(pg('admin_required: app_metadata.role=NULL (need admin)', '42501')),
          'Sem permissão de admin para esta ação.');
      expect(h(pg('so_admin', '42501')),
          'Sem permissão de admin para esta ação.');
      expect(h(pg('forbidden_admin_only', '42501')),
          'Sem permissão de admin para esta ação.');
      expect(h(pg('driver_not_found')),
          'Entregador não encontrado. Atualize a lista.');
      expect(h(pg('missing_docs: selfie, carta')),
          'Faltam documentos: selfie, carta');
      expect(h(pg('justification_required')),
          'Preencha a justificativa (mínimo 3 caracteres).');
      expect(h(pg('reason_required')),
          'Preencha o motivo (mínimo 3 caracteres).');
    });

    test('nenhuma frase do helper em PT-PT', () {
      final saidas = [
        for (final marca in [
          'admin_required',
          'so_admin',
          'driver_not_found',
          'driver_already_approved',
          'driver_already_rejected',
          'missing_docs: selfie',
          'justification_required',
          'reason_required',
          'not_admin',
          'conformidade_incompleta: faltam nif',
          'xpto',
        ])
          h(pg(marca)),
        h(pg('x', 'PGRST202')),
        h(pg('x', 'PGRST203')),
        h(pg('x', '42501')),
        h(const FunctionException(status: 401)),
        h(const FunctionException(status: 404)),
        h(const FunctionException(status: 500)),
        h(const FunctionException(status: 0)),
        h(Exception('SocketException: x')),
      ];
      const ptPt = [
        'acção', 'Refresca', 'Tens de', 'ecrã', 'utilizador', 'em falta',
        'justificação', 'equipa ', 'ligação', 'Tenta ',
      ];
      for (final s in saidas) {
        for (final p in ptPt) {
          expect(s, isNot(contains(p)), reason: '"$s" tem "$p"');
        }
      }
    });

    test('os casos especiais continuam iguais', () {
      expect(h(pg('not_admin')),
          'Sem permissão de administrador (a sessão não é de admin).');
      expect(h(pg('conformidade_incompleta: faltam iban')),
          'Ativação bloqueada: faltam dados legais (IBAN).');
      expect(h(pg('atividade_por_aprovar')), kErroAtividadePorAprovar);
    });

    test('função por instalar, repetida ou sem permissão no servidor', () {
      expect(
          h(pg('Could not find the function public.admin_x(p_a) in the '
              'schema cache', 'PGRST202')),
          'Esta parte ainda não foi instalada no servidor.');
      expect(h(pg('Could not find the function public.admin_y without parameters')),
          'Esta parte ainda não foi instalada no servidor.');
      expect(h(pg('Could not choose the best candidate function', 'PGRST203')),
          'O servidor tem duas versões desta função; a equipe técnica '
          'precisa corrigir.');
      expect(h(pg('permission denied for table stripe_webhook_events', '42501')),
          'O servidor não deixa o painel ler isto (falta permissão de admin).');
      expect(h(pg('permission denied for function admin_x')),
          'O servidor não deixa o painel ler isto (falta permissão de admin).');
      expect(h(pg('xpto', 'P0001')), 'Erro do servidor: xpto');
    });

    test('Edge Functions (FunctionException)', () {
      expect(h(const FunctionException(status: 401)), 'Sem permissão de admin.');
      expect(h(const FunctionException(status: 403, details: {'error': 'not_admin'})),
          'Sem permissão de admin.');
      expect(h(const FunctionException(status: 404)),
          'Esta função do servidor não está instalada.');
      expect(
          h(const FunctionException(status: 404, details: {
            'code': 'NOT_FOUND',
            'message': 'Requested function was not found',
          })),
          'Esta função do servidor não está instalada.');
      // Uma função que responde 404 com o seu próprio erro mostra esse erro
      // (ex.: admin-force-driver-logout → driver_not_found).
      expect(h(const FunctionException(status: 404, details: {'error': 'driver_not_found'})),
          'Erro do servidor: driver_not_found');
      expect(
          h(const FunctionException(
              status: 502,
              details: {'error': 'reprocess_failed', 'details': 'stripe fora'})),
          'Erro do servidor: reprocess_failed (stripe fora)');
      expect(h(const FunctionException(status: 500, details: 'boom')),
          'Erro do servidor: boom');
      expect(h(const FunctionException(status: 500)),
          'Erro do servidor (código 500).');
      // Sem resposta nenhuma (o pacote usa o código 0): é a rede.
      expect(
          h(const FunctionException(
              status: 0, details: 'ClientException: XMLHttpRequest error.')),
          'Sem conexão com a internet. Tente de novo.');
    });

    test('sem rede, sem dart:io no código do painel', () {
      const semRede = 'Sem conexão com a internet. Tente de novo.';
      expect(h(const SocketException('Failed host lookup: x.supabase.co')),
          semRede);
      expect(h(Exception('ClientException: XMLHttpRequest error., uri=https://x')),
          semRede);
      expect(h(Exception('Failed host lookup: x')), semRede);
      expect(h(Exception('x')), startsWith('Erro inesperado'));
      expect(_ler('lib/screens/admin/_admin_rpc_errors.dart'),
          isNot(contains("import 'dart:io'")));
    });
  });

  group('mapa ao vivo (S1)', () {
    final agora = DateTime.utc(2026, 11, 15, 12);
    String ha(Duration d) => agora.subtract(d).toIso8601String();

    test('mesmo telefone com driver_id diferentes conta uma vez (a linha mais nova)', () {
      final linhas = <Map<String, dynamic>>[
        {
          'driver_id': 'id-da-tabela-drivers',
          'driver_name': 'Ana',
          'driver_phone': '+351912000111',
          'latitude': 40.53,
          'longitude': -7.26,
          'last_updated': ha(const Duration(seconds: 15)),
        },
        {
          'driver_id': 'id-do-user',
          'driver_name': 'Ana',
          'driver_phone': '+351912000111',
          'latitude': 40.54,
          'longitude': -7.27,
          // formato do Postgres (microssegundos e +00:00)
          'last_updated': '2026-11-15T11:59:59.123456+00:00',
        },
      ];
      final ligados = entregadoresLigadosNoMapa(linhas, agora: agora);
      expect(ligados, hasLength(1));
      expect(ligados.single['driver_id'], 'id-do-user');
      expect(ligados.single['latitude'], 40.54);
      // A ordem das linhas não muda o resultado.
      final aoContrario =
          entregadoresLigadosNoMapa(linhas.reversed, agora: agora);
      expect(aoContrario.single['driver_id'], 'id-do-user');
    });

    test('chave: telefone, senão nome, senão id', () {
      expect(
          chaveEntregadorNoMapa(
              {'driver_id': 'a', 'driver_name': 'Ana', 'driver_phone': '+351 912 000 111'}),
          chaveEntregadorNoMapa(
              {'driver_id': 'b', 'driver_name': 'Ana', 'driver_phone': '+351912000111'}));
      expect(chaveEntregadorNoMapa({'driver_id': 'a', 'driver_name': 'Ana', 'driver_phone': ''}),
          chaveEntregadorNoMapa({'driver_id': 'b', 'driver_name': 'Ana'}));
      expect(chaveEntregadorNoMapa({'driver_id': 'a'}),
          isNot(chaveEntregadorNoMapa({'driver_id': 'b'})));
      // Pessoas diferentes não se juntam.
      final quatro = entregadoresLigadosNoMapa(<Map<String, dynamic>>[
        {'driver_id': 'a', 'driver_phone': '+351911', 'last_updated': ha(Duration.zero)},
        {'driver_id': 'b', 'driver_phone': '+351922', 'last_updated': ha(Duration.zero)},
        {'driver_id': 'c', 'last_updated': ha(Duration.zero)},
        {'driver_id': 'd', 'last_updated': ha(Duration.zero)},
      ], agora: agora);
      expect(quatro, hasLength(4));
    });

    test('só conta como ligado com GPS de 5 minutos ou menos', () {
      List<Map<String, dynamic>> uma(Object? lastUpdated) => [
            {'driver_id': 'x', 'driver_phone': '+351933', 'last_updated': lastUpdated},
          ];
      int n(Object? lu) => entregadoresLigadosNoMapa(uma(lu), agora: agora).length;
      expect(n(ha(const Duration(minutes: 4, seconds: 59))), 1);
      expect(n(ha(const Duration(minutes: 5))), 1);
      expect(n(ha(const Duration(minutes: 5, seconds: 1))), 0);
      expect(n(null), 0, reason: 'sem hora não prova que está ligado');
      expect(n('ontem'), 0);
      // Relógio do computador do admin atrasado: hora no "futuro" conta.
      expect(n(agora.add(const Duration(seconds: 30)).toIso8601String()), 1);
      expect(kMapaJanelaLigado, const Duration(minutes: 5));
    });

    test('pedidos: pronto na loja espera entregador; ativos por lista explícita', () {
      final c = contarPedidosNoMapa(<Map<String, dynamic>>[
        {'status': 'created'},
        {'status': 'preparing'},
        {'status': 'readyForPickup'},
        {'status': 'callingDriver'},
        {'status': 'driverAccepted'},
        {'status': 'pickedUp'},
        {'status': 'onTheWay'},
        {'status': 'delivered'},
        {'status': 'xpto'},
        {'status': null},
      ]);
      expect(c.esperando, 4);
      expect(c.emEntrega, 3);
    });

    test('legenda, nome do contador, frase do topo, vazio e erro em PT-BR', () {
      expect(
          kLegendaMapaAoVivo,
          'Laranja = esperando entregador · Verde = em entrega · '
          'Roxo = casa do cliente · Azul = entregador ligado (GPS nos últimos '
          '5 min)');
      final fonte = _ler('lib/screens/admin/admin_live_orders_map_screen.dart');
      expect(fonte, contains("_stat('Entregadores ligados', ligados.length"));
      expect(fonte, contains('Nenhum pedido em andamento agora.'));
      expect(fonte, contains('Aqui você vê no mapa os pedidos em andamento'));
      expect(fonte, contains('_error = humanizeAdminRpcError(e)'));
      expect(fonte, isNot(contains(r"Text('Erro: $_error'")));
      // O comentário dizia "cinza" para a casa do cliente; o pino é roxo.
      expect(fonte, isNot(contains('cinza')));
      expect(fonte, contains('BitmapDescriptor.hueViolet'));
      // Os pinos azuis saem da lista já sem repetidos.
      expect(fonte, contains('for (final d in ligados)'));
      expect(fonte, contains('entregadoresLigadosNoMapa(_drivers, agora: DateTime.now())'));
    });
  });

  group('busca global (S5)', () {
    test('filtro de entregadores: nome ou telefone, entre aspas', () {
      expect(filtroBuscaEntregadores('Ana Silva'),
          'name.ilike."%Ana Silva%",phone.ilike."%AnaSilva%"');
      expect(filtroBuscaEntregadores(' 912 345 678 '),
          'name.ilike."%912 345 678%",phone.ilike."%912345678%"');
      // Vírgula e parênteses partiam o filtro `or` sem as aspas.
      expect(filtroBuscaEntregadores('Silva, Ana (Guarda)'),
          'name.ilike."%Silva, Ana (Guarda)%",phone.ilike."%Silva,Ana(Guarda)%"');
      expect(filtroBuscaEntregadores('a"b'),
          r'name.ilike."%a\"b%",phone.ilike."%a\"b%"');
    });

    test('linhas de drivers: uma vez por id, com o estado online', () {
      final r = entregadoresDaBusca(<Map<String, dynamic>>[
        {'id': 'd1', 'name': 'Ana', 'phone': '+351912', 'vehicle_type': 'moto', 'is_online': true},
        {'id': 'd1', 'name': 'Ana', 'phone': '+351912', 'vehicle_type': 'moto', 'is_online': true},
        {'id': 'd2', 'name': 'Rui', 'phone': null, 'vehicle_type': 'carro', 'is_online': false},
        {'id': null, 'name': 'Sem id'},
      ]);
      expect(r, hasLength(2));
      expect(r[0], {
        'driver_id': 'd1',
        'driver_name': 'Ana',
        'driver_phone': '+351912',
        'vehicle_type': 'moto',
        'is_online': true,
      });
      expect(r[1]['driver_id'], 'd2');
      expect(r[1]['is_online'], false);
    });

    test('a busca de entregadores lê a tabela drivers (fonte)', () {
      final fonte = _ler('lib/screens/admin/admin_global_search_screen.dart');
      final drivers = _metodo(fonte, 'Future<_Secao> _searchDrivers(String q)');
      expect(drivers, contains(".from('drivers')"));
      expect(drivers, contains(".select('id, name, phone, vehicle_type, is_online')"));
      expect(drivers, contains('.or(filtroBuscaEntregadores(q))'));
      expect(drivers, contains('.limit(10)'));
      expect(drivers, contains('entregadoresDaBusca('));
      expect(drivers, contains('erro: humanizeAdminRpcError(e)'));
      // admin_live_drivers só tem quem mandou GPS nos últimos 5 minutos.
      expect(fonte, isNot(contains("rpc('admin_live_drivers')")));
      // O detalhe abre como antes, com drivers.id em `driver_id`.
      expect(fonte, contains('AdminDriverDetailScreen(driverId: id)'));
      expect(fonte, contains("d['is_online'] == true"));
    });

    test('pedidos: a mesma consulta, mas o erro aparece em PT-BR (fonte)', () {
      final fonte = _ler('lib/screens/admin/admin_global_search_screen.dart');
      final pedidos = _metodo(fonte, 'Future<_Secao> _searchOrders(String q)');
      expect(pedidos,
          contains(r".or('customer_name.ilike.$like,vendor_name.ilike.$like,id.ilike.$q%')"));
      expect(pedidos, isNot(contains('catch (_)')));
      expect(pedidos, contains('erro: humanizeAdminRpcError(e)'));
      expect(fonte, contains(r"'Pedidos: ${orders.erro}'"));
      expect(fonte, contains('for (final aviso in _avisos) _aviso(aviso)'));
    });

    test('dica da lupa desta tela', () {
      expect(kTooltipBuscaGlobal, 'Buscar pessoas e pedidos');
      final fonte = _ler('lib/screens/admin/admin_global_search_screen.dart');
      expect(fonte, contains('message: kTooltipBuscaGlobal'));
    });
  });

  group('Encomendas por telefone, Stripe e Cancelamentos', () {
    test('Encomendas por telefone: sem erro cru na tela (fonte)', () {
      final fonte = _ler('lib/screens/admin/admin_encomendas_telefone_screen.dart');
      expect(fonte, isNot(contains(r"Text('Erro: $e')")));
      expect(fonte, isNot(contains(r"'Erro: $t'")));
      expect(fonte, isNot(contains(r"_erro = '$e'")));
      expect(fonte, isNot(contains(r"'Erro ao salvar: $e'")));
      expect('humanizeAdminRpcError('.allMatches(fonte).length,
          greaterThanOrEqualTo(4));
      // O aviso próprio do botão "Chamar entregador já" continua.
      expect(fonte, contains('O botão ainda não está ligado no servidor'));
    });

    test('Stripe: eventos do webhook sem permissão dizem isso, não "falta coluna"', () {
      expect(
          kAvisoEventosWebhookSemPermissao,
          'O painel ainda não tem permissão para ler os eventos do webhook '
          '(proposta enviada ao servidor).');
      expect(
          mensagemErroEventosWebhook(const PostgrestException(
              message: 'permission denied for table stripe_webhook_events',
              code: '42501')),
          kAvisoEventosWebhookSemPermissao);
      expect(mensagemErroEventosWebhook(Exception('permission denied for table x')),
          kAvisoEventosWebhookSemPermissao);
      expect(mensagemErroEventosWebhook(Exception('x')),
          startsWith('Não deu para ler os eventos do webhook: Erro inesperado'));
      final fonte = _ler('lib/screens/admin/admin_stripe_contas_screen.dart');
      expect(fonte, isNot(contains('Coluna da conta ainda não existe')));
      expect(fonte, contains('_erroEventos = mensagemErroEventosWebhook(e)'));
      // O interruptor e as chaves não mudaram.
      expect(fonte, contains("_sb.functions.invoke('admin-payments', body: {'action': 'contas'})"));
      expect(fonte, contains("rpc('admin_update_setting'"));
    });

    test('Cancelamentos: diz o que mostra e os erros vêm em PT-BR', () {
      expect(
          kAvisoAlcanceCancelamentos,
          'Aqui aparecem só os cancelamentos pedidos pelo cliente com taxa ou '
          'reembolso; a lista de todos os pedidos cancelados está em Pedidos '
          '(filtro Cancelado).');
      final fonte = _ler('lib/screens/admin/admin_cancellations_screen.dart');
      expect(fonte, contains('kAvisoAlcanceCancelamentos,'));
      expect(fonte, contains('_error = humanizeAdminRpcError(e)'));
      expect(fonte, isNot(contains(r"Text('Erro: $e')")));
      // A consulta não mudou.
      expect(fonte, contains("rpc('admin_list_cancellations'"));
      expect(fonte, isNot(contains('estafeta')));
    });
  });
}
