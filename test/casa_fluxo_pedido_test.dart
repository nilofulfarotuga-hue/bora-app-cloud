// CASA — o fluxo inteiro de um pedido, sem rede (missão app-fechar
// 01/11/2026, bloco B1).
//
// Um "servidor" falso faz de casa_* (as mesmas regras do contrato: estados por
// ordem, foto de depois para concluir, oferta que expira, Casa só a dinheiro).
// O CasaStore (cliente) e o HandymanStore (profissional) falam com ele pelos
// construtores de teste `comServidor` — o código das ações é o verdadeiro.
//
// pedir → aceitar → a caminho → chegou → iniciar → concluir → confirmar
// (= pagar, porque a Casa hoje só aceita dinheiro em mão). Cartão, MB Way e
// carteira não existem na Casa: o servidor recusa e a app diz porquê.
import 'dart:io';
import 'dart:typed_data';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/screens/client/casa/casa_pedido_screen.dart';
import 'package:bora_app/screens/client/casa/casa_regras.dart';
import 'package:bora_app/screens/client/casa/casa_widgets.dart';
import 'package:bora_app/screens/handyman/casa_profissional_ui.dart';
import 'package:bora_app/services/oferta_trabalho_aviso.dart';
import 'package:bora_app/stores/casa_store.dart';
import 'package:bora_app/stores/handyman_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _config = CasaConfig.fromJson({
  'visivel': true,
  'enabled': true,
  'max_cash_cents': 4000,
  'pagamento_cartao': false,
  'max_fotos': 5,
  'min_lead_hours': 2,
  'quote_max_pros': 3,
  'oficios': [
    {
      'codigo': 'montagem',
      'nome': 'Montagem de móveis',
      'fase': 1,
      'ativo': true
    },
  ],
  'servicos': [
    {
      'id': 's1',
      'oficio': 'montagem',
      'nome': 'Montar um móvel',
      'modo': 'fixo',
      'preco_cents': 2500,
      'unidade': 'movel',
      'min_quantidade': 1,
      'max_quantidade': 10,
    },
  ],
});

CasaServico get _montarMovel => _config.servicos.single;

/// Cabeçalho PNG: o tipo vê-se pelos bytes (não precisa de descodificar).
final Uint8List _png = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 1, 2, 3]);

PostgrestException _recusa(String codigo) =>
    PostgrestException(message: codigo, code: 'P0001');

/// O servidor falso: as regras de casa_03 (cliente) e casa_04 (profissional)
/// que interessam ao fluxo. Guarda o que lhe pediram.
class _ServidorCasa {
  static const proId = 'pro-1';
  static const uidCliente = 'u-cli';
  static const uidPro = 'u-pro';

  final chamadas = <(String, Map<String, dynamic>)>[];
  final pedidos = <String, Map<String, dynamic>>{};
  final fotos = <Map<String, dynamic>>[];
  String? ofertaPara;
  DateTime? ofertaExpira;
  int _n = 0;

  List<String> get nomes => [for (final c in chamadas) c.$1];
  Map<String, dynamic> ultima(String fn) =>
      chamadas.lastWhere((c) => c.$1 == fn).$2;

  Map<String, dynamic> _json(String id) {
    final p = pedidos[id];
    if (p == null) throw _recusa('sem_permissao');
    final estado = p['estado'] as String;
    return {
      ...p,
      'fotos': [
        for (final f in fotos)
          if (f['pedido_id'] == id) f,
      ],
      // Dinheiro: contacto abre com o trabalho aceite (decisão 4).
      'pode_contactar': const {
        'aceite',
        'a_caminho',
        'chegou',
        'em_curso',
        'concluido',
      }.contains(estado),
      if (p['profissional_id'] != null)
        'profissional': {'id': proId, 'name': 'Rui Faz-Tudo'},
    };
  }

  /// Põe um pedido já num estado (para os testes de ecrã).
  String semear(String estado, {bool comFotoDepois = false}) {
    final id = 'ped-${++_n}';
    pedidos[id] = {
      'id': id,
      'servico_id': 's1',
      'servico_nome': 'Montar um móvel',
      'oficio': 'montagem',
      'oficio_nome': 'Montagem de móveis',
      'modo': 'fixo',
      'quantidade': 1,
      'estado': estado,
      'payment_method': 'cash',
      'payment_status': 'unpaid',
      'preco_cents': 2500,
      'total_cents': 2500,
      'ganho_cents': 2125,
      'scheduled_at': '2026-11-03T10:00:00Z',
      'created_at': '2026-11-01T09:00:00Z',
      'morada': {'street': 'Rua do Comércio 5', 'city': 'Guarda'},
      if (estado != 'procura') 'profissional_id': proId,
    };
    if (comFotoDepois) {
      fotos.add({
        'id': 'f-$id',
        'pedido_id': id,
        'tipo': 'depois',
        'storage_path': '$uidPro/$id/depois_1.png',
      });
    }
    return id;
  }

  Future<dynamic> doCliente(String fn, Map<String, dynamic> a) async {
    chamadas.add((fn, a));
    final pid = '${a['p_pedido_id']}';
    switch (fn) {
      case 'casa_criar_pedido':
        final metodo = a['p_payment_method'];
        // casa_03:78–79 — a Casa só aceita dinheiro nesta fase.
        if (metodo == 'card' || metodo == 'mbway') {
          throw _recusa('pagamento_cartao_indisponivel');
        }
        if (metodo != 'cash') throw _recusa('metodo_invalido');
        final total = 2500 * (a['p_quantidade'] as num).round();
        if (total > 4000) throw _recusa('dinheiro_acima_do_limite');
        final novo = semear('procura');
        pedidos[novo]!['total_cents'] = total;
        pedidos[novo]!['preco_cents'] = total;
        ofertaPara = novo;
        ofertaExpira = DateTime.now().add(const Duration(minutes: 5));
        return _json(novo);
      case 'casa_meus_pedidos':
        return [for (final k in pedidos.keys) _json(k)];
      case 'casa_pedido':
        return _json(pid);
      case 'casa_adicionar_foto':
        if (!'${a['p_storage_path']}'.startsWith('$uidCliente/$pid/')) {
          throw _recusa('caminho_invalido');
        }
        fotos.add({
          'id': 'f${fotos.length}',
          'pedido_id': pid,
          'tipo': a['p_tipo'],
          'storage_path': a['p_storage_path'],
        });
        return {'id': 'f${fotos.length}'};
      case 'casa_confirmar_conclusao':
        if (pedidos[pid]?['estado'] != 'concluido') {
          throw _recusa('estado_invalido');
        }
        pedidos[pid]!['estado'] = 'confirmado';
        pedidos[pid]!['confirmed_at'] =
            DateTime.now().toUtc().toIso8601String();
        return _json(pid);
      case 'casa_avaliar':
        if (pedidos[pid]?['estado'] != 'confirmado') {
          throw _recusa('estado_invalido');
        }
        pedidos[pid]!['rating_cliente'] = a['p_nota'];
        return {'ok': true};
    }
    throw _recusa('funcao_que_o_falso_nao_conhece_$fn');
  }

  Future<dynamic> doProfissional(String fn, Map<String, dynamic> a) async {
    chamadas.add((fn, a));
    final pid = '${a['p_pedido_id']}';
    switch (fn) {
      case 'casa_meu_perfil':
        return {
          'perfil': {
            'id': proId,
            'name': 'Rui Faz-Tudo',
            'approval_status': 'approved'
          },
          'oficios': [
            {
              'codigo': 'montagem',
              'nome': 'Montagem de móveis',
              'estado': 'approved',
              'ligado': true
            },
          ],
          'disponibilidade': [
            {'weekday': 2, 'start': '08:00', 'end': '20:00'},
          ],
          'comissao_pct': 15,
          'valores_autorizados': true,
        };
      case 'casa_minhas_ofertas':
        final oferta = ofertaPara;
        if (oferta == null || pedidos[oferta]?['estado'] != 'procura') {
          return const [];
        }
        return [
          {
            'pedido_id': oferta,
            'tipo': 'oferta',
            'oficio': 'montagem',
            'oficio_nome': 'Montagem de móveis',
            'servico_nome': 'Montar um móvel',
            'modo': 'fixo',
            'localidade': 'Guarda',
            'distancia_km': 2.1,
            'scheduled_at': pedidos[oferta]!['scheduled_at'],
            'duracao_min': 60,
            'ganho_cents': 2125,
            'total_cents': pedidos[oferta]!['total_cents'],
            'expira_em': ofertaExpira!.toUtc().toIso8601String(),
          },
        ];
      case 'casa_meus_trabalhos':
        return [
          for (final e in pedidos.entries)
            if (e.value['profissional_id'] == proId) _json(e.key),
        ];
      case 'casa_pedido':
        return _json(pid);
      case 'casa_aceitar_oferta':
        if (ofertaPara != pid) throw _recusa('sem_permissao');
        if (!DateTime.now().isBefore(ofertaExpira!)) {
          throw _recusa('oferta_expirada');
        }
        pedidos[pid]!['estado'] = 'aceite';
        pedidos[pid]!['profissional_id'] = proId;
        ofertaPara = null;
        return {'ok': true};
      case 'casa_avancar':
        const seguinte = {
          'aceite': 'a_caminho',
          'a_caminho': 'chegou',
          'chegou': 'em_curso',
          'em_curso': 'concluido',
        };
        final atual = pedidos[pid]?['estado'];
        if (seguinte[atual] != a['p_para']) throw _recusa('estado_invalido');
        if (a['p_para'] == 'concluido' &&
            !fotos.any((f) => f['pedido_id'] == pid && f['tipo'] == 'depois')) {
          throw _recusa('foto_depois_em_falta');
        }
        pedidos[pid]!['estado'] = a['p_para'];
        return _json(pid);
      case 'casa_adicionar_foto':
        if (!'${a['p_storage_path']}'.startsWith('$uidPro/$pid/')) {
          throw _recusa('caminho_invalido');
        }
        fotos.add({
          'id': 'f${fotos.length}',
          'pedido_id': pid,
          'tipo': a['p_tipo'],
          'storage_path': a['p_storage_path'],
        });
        return {'id': 'f${fotos.length}'};
    }
    throw _recusa('funcao_que_o_falso_nao_conhece_$fn');
  }
}

Future<void> _montarEcra(
    WidgetTester tester, CasaStore store, Widget ecra) async {
  await tester.binding.setSurfaceSize(const Size(800, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider<CasaStore>.value(
    value: store,
    child: MaterialApp(home: ecra),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    esquecerOfertasTrabalhoTratadas();
  });

  group('o fluxo inteiro a dinheiro (cliente + profissional)', () {
    test(
        'pedir → aceitar → a caminho → chegou → iniciar → concluir → confirmar/pagar',
        () async {
      final srv = _ServidorCasa();
      final cliente = CasaStore.comServidor(
          rpc: srv.doCliente, config: _config, uid: _ServidorCasa.uidCliente);
      final pro = HandymanStore.comServidor(
          rpc: srv.doProfissional, uid: _ServidorCasa.uidPro);
      addTearDown(pro.dispose);
      addTearDown(cliente.dispose);

      // 1. PEDIR (a dinheiro, 1 móvel = 25 €, dentro do limite de 40 €).
      final pedido = await cliente.criarPedido(
        servico: _montarMovel,
        quantidade: 1,
        descricao: 'Montar uma cómoda',
        respostas: const {},
        rua: 'Rua do Comércio 5',
        cidade: 'Guarda',
        codigoPostal: '6300-000',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        metodoPagamento: 'cash',
      );
      expect(pedido.estado, CasaEstado.procura);
      expect(srv.ultima('casa_criar_pedido')['p_payment_method'], 'cash');
      expect(cliente.aberto?.id, pedido.id);

      // A foto do problema sobe com a extensão real (C14).
      final caminho =
          await cliente.adicionarFoto(pedido.id, _png, extensao: 'png');
      expect(caminho,
          startsWith('${_ServidorCasa.uidCliente}/${pedido.id}/problema_'));
      expect(caminho, endsWith('.png'));

      // 2. O PROFISSIONAL vê a oferta (e a sondagem acelera: C5).
      await pro.loadProfile();
      expect(pro.isApproved, isTrue);
      expect(pro.ofertasVivas().map((o) => o.pedidoId), [pedido.id]);
      expect(pro.intervaloSondagem, const Duration(seconds: 10));

      // 3. ACEITAR.
      expect(await pro.accept(pedido.id), isTrue, reason: pro.lastError);
      expect(pro.trabalhoAtivo?.id, pedido.id);
      expect(pro.trabalhoAtivo?.estado, CasaEstado.aceite);
      expect(pro.ofertasVivas(), isEmpty);
      expect(pro.intervaloSondagem, const Duration(seconds: 30),
          reason: 'sem ofertas por responder volta aos 30 s');
      await cliente.refreshTracked();
      expect(cliente.aberto?.estado, CasaEstado.aceite);
      expect(cliente.aberto?.profissional?.nome, 'Rui Faz-Tudo');

      // 4. A CAMINHO → CHEGOU → INICIAR (o cliente acompanha cada passo).
      for (final (para, estado) in const [
        ('a_caminho', CasaEstado.aCaminho),
        ('chegou', CasaEstado.chegou),
        ('em_curso', CasaEstado.emCurso),
      ]) {
        expect(casaProximoPasso(pro.trabalhoAtivo!.estado)?.para, para);
        expect(await pro.avancar(pedido.id, para), isTrue,
            reason: pro.lastError);
        expect(pro.trabalhoPorId(pedido.id)?.estado, estado);
        await cliente.refreshTracked();
        expect(cliente.aberto?.estado, estado);
      }

      // 5. CONCLUIR: sem foto de depois nem chega ao servidor.
      final antes = srv.nomes.where((n) => n == 'casa_avancar').length;
      expect(await pro.avancar(pedido.id, 'concluido'), isFalse);
      expect(pro.lastError, contains('foto'));
      expect(srv.nomes.where((n) => n == 'casa_avancar').length, antes);

      // Foto de depois (PNG → caminho .png, C14) e concluir.
      expect(await pro.adicionarFoto(pedido.id, 'depois', XFile.fromData(_png)),
          isTrue,
          reason: pro.lastError);
      final fotoDepois = srv.fotos.lastWhere((f) => f['tipo'] == 'depois');
      expect(fotoDepois['storage_path'], endsWith('.png'));
      expect(await pro.avancar(pedido.id, 'concluido'), isTrue,
          reason: pro.lastError);
      expect(pro.trabalhoAtivo, isNull,
          reason: 'concluído já não manda no ecrã');

      // 6. CONFIRMAR = PAGAR (dinheiro em mão: pago quando confirmado).
      await cliente.refreshTracked();
      expect(cliente.aberto?.estado, CasaEstado.concluido);
      expect(casaPedidoPago(cliente.aberto!), isFalse);
      final confirmado = await cliente.confirmarConclusao(pedido.id);
      expect(confirmado.estado, CasaEstado.confirmado);
      expect(casaPedidoPago(confirmado), isTrue);
      expect(confirmado.paymentMethod, 'cash');
      await cliente.avaliar(pedido.id, 5);
      expect(srv.pedidos[pedido.id]!['rating_cliente'], 5);
    });

    test('oferta que expirou: aceitar falha com a frase certa (C9)', () async {
      final srv = _ServidorCasa();
      final cliente = CasaStore.comServidor(
          rpc: srv.doCliente, config: _config, uid: _ServidorCasa.uidCliente);
      final pro = HandymanStore.comServidor(
          rpc: srv.doProfissional, uid: _ServidorCasa.uidPro);
      addTearDown(pro.dispose);
      addTearDown(cliente.dispose);

      final pedido = await cliente.criarPedido(
        servico: _montarMovel,
        quantidade: 1,
        descricao: '',
        respostas: const {},
        rua: 'Rua do Comércio 5',
        cidade: 'Guarda',
        codigoPostal: '',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        metodoPagamento: 'cash',
      );
      await pro.loadProfile();
      // O tempo da oferta acaba no servidor.
      srv.ofertaExpira = DateTime.now().subtract(const Duration(seconds: 1));
      expect(await pro.accept(pedido.id), isFalse);
      expect(pro.lastError, 'Esta oferta já expirou. Fica atento às próximas.');
      expect(pro.ultimaFalhaFoiDeRede, isFalse);
    });

    test('passo fora de ordem: o servidor recusa e a app explica', () async {
      final srv = _ServidorCasa();
      final pro = HandymanStore.comServidor(
          rpc: srv.doProfissional, uid: _ServidorCasa.uidPro);
      addTearDown(pro.dispose);
      final id = srv.semear('aceite');
      await pro.loadProfile();
      expect(await pro.avancar(id, 'em_curso'), isFalse);
      expect(
          pro.lastError, 'Este trabalho já mudou de estado. Atualiza a lista.');
      expect(await pro.avancar(id, 'pago'), isFalse,
          reason: 'passo que não existe nem sai da app');
    });
  });

  group('pagamento: a Casa hoje só aceita dinheiro', () {
    Future<String> tentar(String metodo, {double quantidade = 1}) async {
      final srv = _ServidorCasa();
      final cliente = CasaStore.comServidor(
          rpc: srv.doCliente, config: _config, uid: _ServidorCasa.uidCliente);
      addTearDown(cliente.dispose);
      try {
        await cliente.criarPedido(
          servico: _montarMovel,
          quantidade: quantidade,
          descricao: '',
          respostas: const {},
          rua: 'Rua do Comércio 5',
          cidade: 'Guarda',
          codigoPostal: '',
          scheduledAt: DateTime.now().add(const Duration(days: 1)),
          metodoPagamento: metodo,
        );
        return 'criado';
      } catch (e) {
        expect(srv.pedidos, isEmpty, reason: 'recusado não cria pedido');
        return casaMensagemDeErro(e, maxCashCents: _config.maxCashCents);
      }
    }

    test('dinheiro: cria', () async {
      expect(await tentar('cash'), 'criado');
    });

    test('cartão e MB Way: recusados com a mensagem certa', () async {
      const frase =
          'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.';
      expect(await tentar('card'), frase);
      expect(await tentar('mbway'), frase);
    });

    test('carteira: não é método da Casa (nem aparece na lista)', () async {
      expect(await tentar('wallet'), 'Escolhe como queres pagar.');
      final codigos = casaMetodosPagamento(totalCents: 2500, config: _config)
          .map((m) => m.codigo)
          .toList();
      expect(codigos, ['cash', 'card', 'mbway']);
    });

    test('dinheiro acima do limite: diz o limite', () async {
      expect(await tentar('cash', quantidade: 2),
          'Em dinheiro só até 40,00 €. Acima disso, só cartão ou MB Way.');
    });

    test('porque é que cada método está cinzento', () {
      expect(casaPorqueIndisponivel('card', totalCents: 2500, config: _config),
          'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.');
      expect(casaPorqueIndisponivel('mbway', totalCents: 2500, config: _config),
          'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.');
      expect(casaPorqueIndisponivel('cash', totalCents: 5000, config: _config),
          casaExplicacaoDinheiro(_config));
      expect(casaPorqueIndisponivel('card', totalCents: 5000, config: _config),
          casaExplicacaoDinheiro(_config),
          reason: 'acima do limite nem o dinheiro serve: diz o limite');
    });
  });

  group('ecrãs do cliente com o servidor falso', () {
    testWidgets('tocar em "Cartão — brevemente" explica (botão nunca mudo)',
        (tester) async {
      final escolhidos = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CasaEscolhaPagamento(
            totalCents: 2500,
            config: _config,
            metodo: 'cash',
            onEscolher: escolhidos.add,
          ),
        ),
      ));
      expect(find.text('Dinheiro (no local)'), findsOneWidget);
      expect(find.text('Cartão — brevemente'), findsOneWidget);
      expect(find.text('MB Way — brevemente'), findsOneWidget);
      expect(find.textContaining('Carteira'), findsNothing);
      expect(find.byKey(const Key('casa_pagamento_porque')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('casa_pagamento_card')));
      await tester.pump();
      expect(escolhidos, isEmpty, reason: 'cartão não se escolhe');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('casa_pagamento_porque')))
              .data,
          'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.');

      await tester.tap(find.byKey(const ValueKey('casa_pagamento_mbway')));
      await tester.pump();
      expect(escolhidos, isEmpty);
      expect(find.byKey(const Key('casa_pagamento_porque')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('casa_pagamento_cash')));
      await tester.pump();
      expect(escolhidos, ['cash']);
      expect(find.byKey(const Key('casa_pagamento_porque')), findsNothing);
    });

    testWidgets('acima de 40 €: tocar no dinheiro diz o limite uma só vez',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CasaEscolhaPagamento(
            totalCents: 5000,
            config: _config,
            metodo: null,
            onEscolher: (_) {},
          ),
        ),
      ));
      final limite = casaExplicacaoDinheiro(_config);
      expect(find.text(limite), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('casa_pagamento_cash')));
      await tester.pump();
      expect(find.text(limite), findsOneWidget, reason: 'sem repetir a frase');
      expect(find.byKey(const Key('casa_pagamento_porque')), findsOneWidget);
    });

    testWidgets('acompanhamento: a caminho → concluído → confirmar → avaliar',
        (tester) async {
      final srv = _ServidorCasa();
      final id = srv.semear('a_caminho');
      final store = CasaStore.comServidor(
          rpc: srv.doCliente, config: _config, uid: _ServidorCasa.uidCliente);
      await store.carregarMeusPedidos();
      final inicial = store.meusPedidos.single;

      await _montarEcra(tester, store, CasaPedidoScreen(pedido: inicial));
      expect(find.text('Profissional a caminho'), findsWidgets);
      expect(find.text('Confirmar que está tudo bem'), findsNothing);
      expect(find.text('Rui Faz-Tudo'), findsOneWidget);

      // O profissional chega, trabalha e conclui com foto (servidor).
      srv.pedidos[id]!['estado'] = 'concluido';
      srv.fotos.add({
        'id': 'fd',
        'pedido_id': id,
        'tipo': 'depois',
        'storage_path': '${_ServidorCasa.uidPro}/$id/depois_1.png',
      });
      await store.refreshTracked();
      await tester.pump();
      expect(find.text('Confirmar que está tudo bem'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);

      // Confirmar = pagar em mão; logo a seguir pede a avaliação.
      await tester.tap(find.text('Confirmar que está tudo bem'));
      await tester.pumpAndSettle();
      expect(srv.nomes, contains('casa_confirmar_conclusao'));
      expect(srv.pedidos[id]!['estado'], 'confirmado');
      expect(find.text('Como correu o trabalho?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Enviar'));
      await tester.pumpAndSettle();
      expect(srv.ultima('casa_avaliar')['p_nota'], 5);
      expect(srv.pedidos[id]!['rating_cliente'], 5);
      expect(find.text('Confirmar que está tudo bem'), findsNothing);
      expect(tester.takeException(), isNull);
      // Deixa acabar os avisos (SnackBar) antes de desmontar.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets(
        'aceitar orçamento acima do limite: o botão explica em vez de ficar mudo',
        (tester) async {
      final srv = _ServidorCasa();
      final id = srv.semear('orcamentos');
      srv.pedidos[id]!.addAll({
        'modo': 'orcamento',
        'preco_cents': 0,
        'total_cents': 0,
        'orcamentos': [
          {
            'id': 'o1',
            'preco_cents': 9000,
            'inclui': 'Tudo',
            'estado': 'enviado',
            'expira_em': DateTime.now()
                .add(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            'profissional': {'id': 'pro-1', 'name': 'Rui Faz-Tudo'},
          },
        ],
      });
      srv.pedidos[id]!.remove('profissional_id');
      final store = CasaStore.comServidor(
          rpc: srv.doCliente, config: _config, uid: _ServidorCasa.uidCliente);
      await store.carregarMeusPedidos();

      await _montarEcra(
          tester, store, CasaPedidoScreen(pedido: store.meusPedidos.single));
      await tester.tap(find.text('Aceitar este orçamento'));
      await tester.pumpAndSettle();
      expect(find.text('Aceitar o orçamento de 90,00 €'), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('casa_aceitar_orcamento_confirmar')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('casa_aceitar_orcamento_aviso')))
              .data,
          casaExplicacaoDinheiro(_config));
      expect(srv.nomes, isNot(contains('casa_aceitar_orcamento')),
          reason: 'nada vai ao servidor sem método possível');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  });

  group('sondagem das ofertas (C5)', () {
    test('10 s com ofertas por responder, 30 s sem nenhuma', () {
      expect(casaIntervaloSondagem(0), const Duration(seconds: 30));
      expect(casaIntervaloSondagem(1), const Duration(seconds: 10));
      expect(casaIntervaloSondagem(3), const Duration(seconds: 10));
    });

    test('o store muda de ritmo sozinho e pára ao sair', () async {
      final srv = _ServidorCasa();
      final pro = HandymanStore.comServidor(
          rpc: srv.doProfissional, uid: _ServidorCasa.uidPro);
      addTearDown(pro.dispose);
      expect(pro.intervaloSondagem, isNull, reason: 'antes do perfil, parado');
      await pro.loadProfile();
      expect(pro.intervaloSondagem, const Duration(seconds: 30));

      final id = srv.semear('procura');
      srv.ofertaPara = id;
      srv.ofertaExpira = DateTime.now().add(const Duration(minutes: 5));
      await pro.loadOffers();
      expect(pro.intervaloSondagem, const Duration(seconds: 10));

      srv.ofertaPara = null;
      await pro.loadOffers();
      expect(pro.intervaloSondagem, const Duration(seconds: 30));

      pro.reset();
      expect(pro.intervaloSondagem, isNull);
    });

    test('o tempo real continua ligado (só se junta a sondagem)', () {
      final src = File('lib/stores/handyman_store.dart').readAsStringSync();
      expect(src, contains("_sb.channel('casa_profissional_"));
      expect(src, contains('casaIntervaloSondagem(ofertasParaAviso().length)'));
    });
  });

  group('sem horários não há trabalhos (C10)', () {
    testWidgets('o aviso diz o que fazer e o botão abre os horários',
        (tester) async {
      var abriu = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CasaAvisoSemHorarios(onDefinir: () => abriu++)),
      ));
      expect(
          find.text(
              'Sem horários não recebes trabalhos. Define os teus horários.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('casa_definir_horarios')));
      expect(abriu, 1);
    });

    test('o store sabe quando não há horários', () {
      final semHorarios = HandymanStore()
        ..debugDefinir(
            perfil: CasaPerfil.fromJson(const {
          'perfil': {'id': 'p', 'approval_status': 'pending'},
        }));
      expect(semHorarios.slots, isEmpty);
      final comHorarios = HandymanStore()
        ..debugDefinir(
            perfil: CasaPerfil.fromJson(const {
          'perfil': {'id': 'p', 'approval_status': 'approved'},
          'disponibilidade': [
            {'weekday': 1, 'start': '09:00', 'end': '18:00'},
          ],
        }));
      expect(comHorarios.slots, hasLength(1));
    });

    test('o aviso está no ecrã pendente e no aprovado', () {
      final src = File('lib/screens/handyman/handyman_home_screen.dart')
          .readAsStringSync();
      expect(src, contains('semHorarios: store.slots.isEmpty'));
      expect(
          RegExp(r'if \(semHorarios\)\s+CasaAvisoSemHorarios\(').hasMatch(src),
          isTrue,
          reason: 'ecrã pendente');
      expect(
          RegExp(r'if \(store\.slots\.isEmpty\)\s+CasaAvisoSemHorarios\(')
              .hasMatch(src),
          isTrue,
          reason: 'ecrã aprovado');
    });
  });
}
