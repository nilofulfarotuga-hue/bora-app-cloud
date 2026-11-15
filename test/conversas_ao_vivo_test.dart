// Conversas ao vivo (15/11/2026, missão app-15-11): o painel vê numa lista só
// as conversas dos 3 robôs (suporte da app, Amigo Bora, lojas no WhatsApp),
// abre a conversa, assume, devolve e responde como "Equipa Bora"; o cliente vê
// a resposta da equipa no Amigo. Sem rede: o serviço é falso e o Supabase
// nunca é inicializado. Servidor: docs/propostas/app-15-11/conversas_ao_vivo.PROPOSTA.sql
import 'dart:async';
import 'dart:io';

import 'package:bora_app/screens/admin/admin_conversas_ao_vivo_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/screens/client/assistant/assistant_chat_screen.dart';
import 'package:bora_app/services/admin_conversas_service.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _Falso extends AdminConversasService {
  _Falso({
    this.linhas = const [],
    this.msgs = const [],
    this.erro,
    this.respostaEnviar,
  });

  final List<ConversaAoVivo> linhas;
  final List<MensagemConversa> msgs;
  final Object? erro;
  final Completer<Map<String, dynamic>>? respostaEnviar;
  final List<String> chamadas = [];

  @override
  Future<List<ConversaAoVivo>> listar({
    int limite = 200,
    bool soEsperaEquipa = false,
    String? origem,
  }) async {
    chamadas.add('listar:${origem ?? 'todas'}:$soEsperaEquipa');
    if (erro != null) throw erro!;
    return linhas;
  }

  @override
  Future<List<MensagemConversa>> mensagens(String origem, String conversaId,
      {int limite = 300}) async {
    chamadas.add('mensagens:$origem:$conversaId');
    if (erro != null) throw erro!;
    return msgs;
  }

  @override
  Future<Map<String, dynamic>> assumir(String origem, String conversaId) async {
    chamadas.add('assumir:$origem:$conversaId');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> devolver(String origem, String conversaId) async {
    chamadas.add('devolver:$origem:$conversaId');
    return <String, dynamic>{'ok': true, 'mudou': true};
  }

  @override
  Future<Map<String, dynamic>> responder(
      String origem, String conversaId, String texto) {
    chamadas.add('responder:$origem:$conversaId:$texto');
    return respostaEnviar?.future ??
        Future.value(<String, dynamic>{'ok': true, 'mensagem_id': 'm9'});
  }

  @override
  VoidCallback ouvirMensagensNovas(void Function() aoMudar) {
    chamadas.add('tempo_real');
    return () => chamadas.add('desligou');
  }
}

ConversaAoVivo _conversa({
  String origem = 'amigo',
  String id = 'c1',
  String nome = 'Ana Silva',
  String autor = 'cliente',
  String estado = 'robo',
  int naoLidas = 0,
}) =>
    ConversaAoVivo(
      origem: origem,
      conversaId: id,
      clienteNome: nome,
      canal: 'App · Amigo Bora',
      ultimaMensagemEm: DateTime.utc(2026, 11, 15, 14, 5),
      ultimaMensagemResumo: 'Olá, onde está o meu pedido?',
      ultimoAutor: autor,
      estado: estado,
      naoLidas: naoLidas,
    );

final List<MensagemConversa> _msgs = [
  MensagemConversa(
      id: '1',
      autor: 'cliente',
      texto: 'Onde está o meu pedido?',
      criadoEm: DateTime.utc(2026, 11, 15, 14, 0)),
  MensagemConversa(
      id: '2',
      autor: 'ferramenta',
      texto: '{"ok":true}',
      ferramenta: 'agent_get_order_full',
      criadoEm: DateTime.utc(2026, 11, 15, 14, 1)),
  MensagemConversa(
      id: '3',
      autor: 'robo',
      texto: 'Está a caminho.',
      criadoEm: DateTime.utc(2026, 11, 15, 14, 1)),
  MensagemConversa(
      id: '4',
      autor: 'equipa',
      texto: 'Olá Ana, já confirmei com a loja.',
      criadoEm: DateTime.utc(2026, 11, 15, 14, 3)),
];

void _ecraGrande(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('modelos aguentam campos em falta', () {
    test('ConversaAoVivo vazia não rebenta', () {
      final c = ConversaAoVivo.fromJson(const {});
      expect(c.origem, '');
      expect(c.conversaId, '');
      expect(c.clienteUserId, isNull);
      expect(c.clienteNome, '');
      expect(c.ultimaMensagemEm, isNull);
      expect(c.ultimaMensagemResumo, '');
      expect(c.estado, '');
      expect(c.naoLidas, 0);
    });

    test('ConversaAoVivo com nulls, números em texto e datas', () {
      final c = ConversaAoVivo.fromJson({
        'origem': 'amigo',
        'conversa_id': 'abc',
        'cliente_user_id': null,
        'cliente_nome': null,
        'canal': null,
        'ultima_mensagem_em': '2026-11-15T14:05:00+00:00',
        'ultima_mensagem_resumo': null,
        'ultimo_autor': 'cliente',
        'estado': 'pediu_pessoa',
        'nao_lidas': '3',
      });
      expect(c.origem, 'amigo');
      expect(c.naoLidas, 3);
      expect(c.ultimaMensagemEm, DateTime.utc(2026, 11, 15, 14, 5));
      expect(c.clienteNome, '');
      expect(c.ultimaMensagemResumo, '');
      expect(ConversaAoVivo.fromJson({'nao_lidas': 2.0}).naoLidas, 2);
      expect(ConversaAoVivo.fromJson({'nao_lidas': 'x'}).naoLidas, 0);
      expect(ConversaAoVivo.fromJson({'ultima_mensagem_em': 'ontem'}).ultimaMensagemEm,
          isNull);
      expect(ConversaAoVivo.fromJson({'cliente_user_id': ''}).clienteUserId,
          isNull);
    });

    test('MensagemConversa vazia e com id numérico', () {
      final m = MensagemConversa.fromJson(const {});
      expect(m.id, '');
      expect(m.autor, '');
      expect(m.texto, '');
      expect(m.ferramenta, isNull);
      expect(m.criadoEm, isNull);
      expect(m.daFerramenta, isFalse);
      final f = MensagemConversa.fromJson({
        'id': 12,
        'autor': 'ferramenta',
        'ferramenta': 'search_help',
        'texto': null,
      });
      expect(f.id, '12');
      expect(f.daFerramenta, isTrue);
      expect(f.ferramenta, 'search_help');
      expect(f.texto, '');
    });

    test('linhas da RPC: null, mapa solto e lixo', () {
      expect(linhasDaRpc(null), isEmpty);
      expect(linhasDaRpc({'origem': 'amigo'}), isEmpty);
      expect(
          linhasDaRpc([
            1,
            'x',
            {'origem': 'amigo'}
          ]),
          hasLength(1));
    });

    test('a conversa fica da mais antiga (em cima) para a mais recente', () {
      final t1 = DateTime.utc(2026, 11, 15, 10, 1);
      // o servidor manda as mais recentes primeiro; 'a' e 'b' no mesmo instante
      final doServidor = [
        MensagemConversa(
            id: 'c', autor: 'equipa', texto: 'c', criadoEm: DateTime.utc(2026, 11, 15, 10, 3)),
        MensagemConversa(id: 'b', autor: 'robo', texto: 'b', criadoEm: t1),
        MensagemConversa(id: 'a', autor: 'cliente', texto: 'a', criadoEm: t1),
      ];
      expect(mensagensDaMaisAntiga(doServidor).map((m) => m.id), ['a', 'b', 'c']);
    });
  });

  group('função em falta no servidor (proposta por aplicar)', () {
    test('PGRST202 e "Could not find the function" contam', () {
      expect(
          funcaoEmFalta(PostgrestException(
              message:
                  'Could not find the function public.admin_conversas_ao_vivo(p_limite, p_origem, p_so_nao_lidas) in the schema cache',
              code: 'PGRST202')),
          isTrue);
      expect(funcaoEmFalta(PostgrestException(message: 'x', code: 'PGRST202')),
          isTrue);
      expect(
          funcaoEmFalta(PostgrestException(
              message: 'Could not find the function public.admin_conversa_mensagens')),
          isTrue);
      expect(funcaoEmFalta(Exception('PostgrestException(code: PGRST202)')), isTrue);
    });

    test('outros erros não contam', () {
      expect(
          funcaoEmFalta(
              PostgrestException(message: 'admin_required', code: '42501')),
          isFalse);
      expect(funcaoEmFalta(Exception('SocketException: Failed host lookup')),
          isFalse);
      expect(funcaoEmFalta(TimeoutException('lento')), isFalse);
    });

    test('o painel nunca mostra o erro cru', () {
      expect(
          textoDoErroConversa(
              PostgrestException(message: 'x', code: 'PGRST202'), 'outro'),
          kConversasFuncaoEmFalta);
      expect(textoDoErroConversa(Exception('boom 500'), 'Tente de novo.'),
          'Tente de novo.');
      expect(
          textoDoErroConversa(
              PostgrestException(message: 'texto_vazio'), 'outro'),
          'Escreva a mensagem antes de enviar.');
    });
  });

  group('links do aviso e do push', () {
    const sessao = '24c369e0-5bbe-4a4e-a576-265aeaab8876';
    const loja = '9b0f6a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';

    test('as 3 origens abrem a conversa certa', () {
      expect(conversaDoLink('/admin/conversas/suporte_app/$sessao'),
          (origem: 'suporte_app', conversaId: sessao));
      expect(conversaDoLink('/admin/conversas/amigo/$sessao?x=1'),
          (origem: 'amigo', conversaId: sessao));
      expect(conversaDoLink('/admin/conversas/whatsapp_loja/$loja:351912345678'),
          (origem: 'whatsapp_loja', conversaId: '$loja:351912345678'));
      expect(
          conversaDoLink(
              rotaConversaAoVivo('whatsapp_loja', '$loja:351912345678')),
          (origem: 'whatsapp_loja', conversaId: '$loja:351912345678'));
      expect(rotaConversaAoVivo('amigo', sessao), '/admin/conversas/amigo/$sessao');
    });

    test('o que não é uma conversa fica de fora', () {
      expect(conversaDoLink(kRotaConversasAoVivo), isNull);
      expect(conversaDoLink('/admin/conversas/'), isNull);
      expect(conversaDoLink('/admin/conversas/amigo/'), isNull);
      expect(conversaDoLink('/admin/conversas/amigo/nao-e-um-id'), isNull);
      expect(conversaDoLink('/admin/conversas/outra/$sessao'), isNull);
      expect(conversaDoLink('/admin/conversas/whatsapp_loja/$loja'), isNull);
      expect(conversaDoLink('/admin/conversas/whatsapp_loja/$loja:'), isNull);
      expect(conversaDoLink('/admin/conversas/amigo/%zz'), isNull);
      expect(conversaDoLink('/admin/support/sessions/$sessao'), isNull);
      expect(conversaDoLink(null), isNull);
    });
  });

  group('textos da lista', () {
    test('nome: nunca só um número', () {
      expect(nomeClienteParaMostrar('912345678'), 'Cliente sem nome (912345678)');
      expect(nomeClienteParaMostrar('+351 912 345 678 · Pizzaria Boom'),
          'Cliente sem nome (+351 912 345 678) · Pizzaria Boom');
      expect(nomeClienteParaMostrar('351912345678@c.us'),
          'Cliente sem nome (351912345678@c.us)');
      expect(nomeClienteParaMostrar(''), 'Cliente sem nome');
      expect(nomeClienteParaMostrar('Ana · Pizzaria Boom'), 'Ana · Pizzaria Boom');
      expect(nomeClienteParaMostrar('Cliente'), 'Cliente');
    });

    test('tempo relativo com a hora de Lisboa', () {
      final agora = DateTime.utc(2026, 7, 1, 12); // verão: Lisboa = UTC+1
      expect(quandoConversa(DateTime.utc(2026, 7, 1, 11, 59, 40), agora: agora),
          'agora · 01/07 12:59');
      expect(quandoConversa(DateTime.utc(2026, 7, 1, 11, 30), agora: agora),
          'há 30 min · 01/07 12:30');
      expect(quandoConversa(DateTime.utc(2026, 7, 1, 9), agora: agora),
          'há 3 h · 01/07 10:00');
      expect(quandoConversa(DateTime.utc(2026, 6, 29, 9), agora: agora),
          '29/06 10:00');
      expect(quandoConversa(null), '—');
    });

    test('quem falou por último e o estado em palavras', () {
      expect(prefixoAutorConversa('cliente'), 'Cliente: ');
      expect(prefixoAutorConversa('robo'), 'Robô: ');
      expect(prefixoAutorConversa('equipa'), 'Equipa: ');
      expect(prefixoAutorConversa('?'), '');
      expect(rotuloEstadoConversa('outro'), isNull);
      expect(rotuloOrigemConversa('whatsapp_loja'), 'Loja no WhatsApp');
    });
  });

  group('linha da lista (cada estado)', () {
    final agora = DateTime.utc(2026, 11, 15, 14, 10);

    Future<void> mostrar(WidgetTester t, ConversaAoVivo c) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListView(
                children: [ConversaAoVivoTile(conversa: c, agora: agora)]),
          ),
        ));

    for (final (estado, rotulo) in const [
      ('robo', 'Robô a responder'),
      ('equipa', 'Equipa assumiu'),
      ('pediu_pessoa', 'Pediu uma pessoa'),
      ('desligado', 'Robô desligado'),
    ]) {
      testWidgets('estado "$estado" → "$rotulo"', (t) async {
        await mostrar(t, _conversa(estado: estado));
        expect(find.text(rotulo), findsOneWidget);
        expect(find.text('Ana Silva'), findsOneWidget);
        expect(find.byKey(const ValueKey('conversa_nao_lidas')), findsNothing);
      });
    }

    testWidgets('resumo com quem falou, hora de Lisboa e não lidas', (t) async {
      await mostrar(t, _conversa(naoLidas: 3));
      expect(find.textContaining('Cliente: Olá, onde está o meu pedido?'),
          findsOneWidget);
      expect(find.textContaining('Amigo Bora · há 5 min · 15/11 14:05'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('conversa_nao_lidas')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('robô e equipa também dizem quem falou', (t) async {
      await mostrar(t, _conversa(autor: 'robo'));
      expect(find.textContaining('Robô: Olá'), findsOneWidget);
      await mostrar(t, _conversa(autor: 'equipa', origem: 'whatsapp_loja'));
      expect(find.textContaining('Equipa: Olá'), findsOneWidget);
      expect(find.textContaining('Loja no WhatsApp · '), findsOneWidget);
    });

    testWidgets('número sem nome nunca aparece sozinho', (t) async {
      await mostrar(t, _conversa(nome: '912345678'));
      expect(find.text('Cliente sem nome (912345678)'), findsOneWidget);
      expect(find.text('912345678'), findsNothing);
    });
  });

  group('ecrã da lista', () {
    testWidgets('mostra as conversas, filtra e abre a conversa', (t) async {
      _ecraGrande(t);
      final falso = _Falso(linhas: [_conversa(naoLidas: 2)], msgs: _msgs);
      await t.pumpWidget(MaterialApp(
          home: AdminConversasAoVivoScreen(servico: falso, aoVivo: false)));
      await t.pumpAndSettle();
      expect(find.text('Conversas ao vivo'), findsOneWidget);
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(falso.chamadas, contains('listar:todas:false'));
      expect(falso.chamadas, isNot(contains('tempo_real')));

      await t.tap(find.text('Lojas no WhatsApp'));
      await t.pumpAndSettle();
      expect(falso.chamadas, contains('listar:whatsapp_loja:false'));

      await t.tap(find.byKey(const ValueKey('filtro_so_espera')));
      await t.pumpAndSettle();
      expect(falso.chamadas, contains('listar:whatsapp_loja:true'));

      await t.tap(find.text('Ana Silva'));
      await t.pumpAndSettle();
      expect(falso.chamadas, contains('mensagens:amigo:c1'));
      expect(find.text('Olá Ana, já confirmei com a loja.'), findsOneWidget);
    });

    testWidgets('ao vivo: liga o tempo real e desliga ao sair', (t) async {
      final falso = _Falso(linhas: [_conversa()]);
      await t.pumpWidget(
          MaterialApp(home: AdminConversasAoVivoScreen(servico: falso)));
      await t.pump();
      expect(falso.chamadas, contains('tempo_real'));
      await t.pumpWidget(const SizedBox());
      expect(falso.chamadas, contains('desligou'));
    });

    testWidgets('sem a migração: frase calma, nunca o erro cru', (t) async {
      final falso = _Falso(
          erro: PostgrestException(
              message:
                  'Could not find the function public.admin_conversas_ao_vivo in the schema cache',
              code: 'PGRST202'));
      await t.pumpWidget(MaterialApp(
          home: AdminConversasAoVivoScreen(servico: falso, aoVivo: false)));
      await t.pumpAndSettle();
      expect(find.text(kConversasFuncaoEmFalta), findsOneWidget);
      expect(find.textContaining('PGRST202'), findsNothing);
      expect(find.textContaining('Could not find'), findsNothing);
    });

    testWidgets('outro erro: frase simples e "Tentar de novo"', (t) async {
      final falso = _Falso(erro: Exception('SocketException: 500'));
      await t.pumpWidget(MaterialApp(
          home: AdminConversasAoVivoScreen(servico: falso, aoVivo: false)));
      await t.pumpAndSettle();
      expect(find.text('Não consegui carregar as conversas agora.'),
          findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
    });
  });

  group('ecrã da conversa', () {
    testWidgets('balões, ferramentas recolhidas e nota do WhatsApp', (t) async {
      _ecraGrande(t);
      final falso = _Falso(msgs: _msgs);
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
          origem: 'whatsapp_loja',
          conversaId: '9b0f6a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b:351912345678',
          titulo: 'Ana · Pizzaria Boom',
          servico: falso,
          aoVivo: false,
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Ana · Pizzaria Boom'), findsOneWidget);
      expect(
          find.text(
              'A resposta sai pelo WhatsApp da loja (fila da VPS, até 30 min)'),
          findsOneWidget);
      expect(find.text('Assumir conversa'), findsOneWidget);
      expect(find.text('Devolver ao robô'), findsOneWidget);
      expect(find.text('Enviar como Equipa Bora'), findsOneWidget);
      expect(find.textContaining('Equipa Bora · '), findsOneWidget);
      // ferramentas recolhidas até se pedir
      expect(find.textContaining('agent_get_order_full'), findsNothing);
      expect(find.text('· o robô usou 1 ferramenta ·'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('conversa_ver_ferramentas')));
      await t.pumpAndSettle();
      expect(find.textContaining('agent_get_order_full'), findsOneWidget);
      // a mais recente em baixo
      final yCliente = t.getTopLeft(find.text('Onde está o meu pedido?')).dy;
      final yEquipa =
          t.getTopLeft(find.text('Olá Ana, já confirmei com a loja.')).dy;
      expect(yCliente, lessThan(yEquipa));
    });

    testWidgets('na app não há nota do WhatsApp', (t) async {
      _ecraGrande(t);
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
            origem: 'amigo', conversaId: 'c1', servico: _Falso(msgs: _msgs), aoVivo: false),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('conversa_nota_whatsapp')), findsNothing);
      expect(find.text('Amigo Bora'), findsWidgets);
    });

    testWidgets('enviar como Equipa Bora: um toque só, limpa no fim', (t) async {
      _ecraGrande(t);
      final resposta = Completer<Map<String, dynamic>>();
      final falso = _Falso(msgs: _msgs, respostaEnviar: resposta);
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
            origem: 'amigo', conversaId: 'c1', servico: falso, aoVivo: false),
      ));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const ValueKey('conversa_texto')), '  Já vimos o teu pedido.  ');
      await t.tap(find.byKey(const ValueKey('conversa_enviar')));
      await t.tap(find.byKey(const ValueKey('conversa_enviar')),
          warnIfMissed: false);
      await t.pump();
      expect(falso.chamadas.where((c) => c.startsWith('responder:')),
          hasLength(1));
      expect(falso.chamadas, contains('responder:amigo:c1:Já vimos o teu pedido.'));
      resposta.complete(<String, dynamic>{'ok': true, 'mensagem_id': 'm9'});
      await t.pumpAndSettle();
      final campo =
          t.widget<TextField>(find.byKey(const ValueKey('conversa_texto')));
      expect(campo.controller!.text, isEmpty);
    });

    testWidgets('erro ao enviar: aviso em palavras, o texto fica', (t) async {
      _ecraGrande(t);
      final resposta = Completer<Map<String, dynamic>>();
      final falso = _Falso(msgs: _msgs, respostaEnviar: resposta);
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
            origem: 'amigo', conversaId: 'c1', servico: falso, aoVivo: false),
      ));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('conversa_texto')), 'Olá');
      await t.tap(find.byKey(const ValueKey('conversa_enviar')));
      await t.pump();
      resposta.completeError(Exception('rede caiu'));
      await t.pumpAndSettle();
      expect(find.text('Não consegui enviar. Tente de novo.'), findsOneWidget);
      final campo =
          t.widget<TextField>(find.byKey(const ValueKey('conversa_texto')));
      expect(campo.controller!.text, 'Olá');
    });

    testWidgets('assumir e devolver chamam o servidor e avisam', (t) async {
      _ecraGrande(t);
      final falso = _Falso(msgs: _msgs);
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
          origem: 'suporte_app',
          conversaId: '24c369e0-5bbe-4a4e-a576-265aeaab8876',
          estado: 'pediu_pessoa',
          servico: falso,
          aoVivo: false,
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Pediu uma pessoa'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('conversa_assumir')));
      await t.pumpAndSettle();
      expect(falso.chamadas,
          contains('assumir:suporte_app:24c369e0-5bbe-4a4e-a576-265aeaab8876'));
      expect(find.text('Você assumiu a conversa: o robô fica calado.'),
          findsOneWidget);
      expect(find.text('Equipa assumiu'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('conversa_devolver')));
      await t.pumpAndSettle();
      expect(falso.chamadas,
          contains('devolver:suporte_app:24c369e0-5bbe-4a4e-a576-265aeaab8876'));
      expect(find.text('Robô a responder'), findsOneWidget);
    });

    testWidgets('sem a migração: a conversa diz com calma', (t) async {
      final falso = _Falso(
          erro: PostgrestException(
              message: 'Could not find the function public.admin_conversa_mensagens',
              code: 'PGRST202'));
      await t.pumpWidget(MaterialApp(
        home: AdminConversaAoVivoScreen(
            origem: 'amigo', conversaId: 'c1', servico: falso, aoVivo: false),
      ));
      await t.pumpAndSettle();
      expect(find.text(kConversasFuncaoEmFalta), findsOneWidget);
      expect(find.textContaining('PGRST202'), findsNothing);
    });
  });

  group('ligações no painel (fonte)', () {
    test('o menu tem a entrada em Clientes, logo a seguir às conversas do suporte',
        () {
      final clientes =
          adminMenuSections().firstWhere((s) => s.id == 'clientes');
      final ids = clientes.items.map((i) => i.id).toList();
      expect(ids, contains('clientes_conversas_ao_vivo'));
      expect(ids.indexOf('clientes_conversas_ao_vivo'),
          ids.indexOf('clientes_suporte_conversas') + 1);
      final item =
          clientes.items.firstWhere((i) => i.id == 'clientes_conversas_ao_vivo');
      expect(item.title, 'Conversas ao vivo (robôs)');
      expect(item.builder(), isA<AdminConversasAoVivoScreen>());
    });

    test('main.dart tem a rota da lista e os links das conversas', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main,
          contains("'/admin/conversas': (_) => const AdminConversasAoVivoScreen()"));
      expect(main, contains('conversaDoLink(name)'));
      expect(main, contains('AdminConversaAoVivoScreen('));
      // o link antigo do suporte continua a abrir o ecrã de sempre
      expect(main, contains('sessaoDoLink(name)'));
      expect(main, contains('AdminSuporteConversaScreen(sessionId: sessaoSuporte)'));
    });

    test('o painel escreve PT-BR direto (sem .tr)', () {
      final ecra = File('lib/screens/admin/admin_conversas_ao_vivo_screen.dart')
          .readAsStringSync();
      expect(RegExp(r"""['"]\s*\.tr\b""").hasMatch(ecra), isFalse);
    });
  });

  group('Amigo: a resposta da Equipa Bora no cliente', () {
    test('o histórico pede também o papel admin', () {
      expect(kPapeisHistoricoAssistente, ['user', 'assistant', 'admin']);
      final fonte = File('lib/services/assistant_service.dart').readAsStringSync();
      expect(fonte, contains(".inFilter('role', kPapeisHistoricoAssistente)"));
    });

    test('linha admin vira mensagem da Equipa Bora (sem cartões)', () {
      final m = AssistantHistoryMessage.fromRow({
        'id': 'a1',
        'role': 'admin',
        'content': 'Olá, sou da equipa.',
        'created_at': '2026-11-15T14:05:00Z',
      });
      expect(m.daEquipa, isTrue);
      expect(m.reply, isNull);
      expect(m.id, 'a1');
      expect(m.createdAt, DateTime.utc(2026, 11, 15, 14, 5));
      final r = AssistantHistoryMessage.fromRow(
          {'role': 'assistant', 'content': 'Olá', 'structured': null});
      expect(r.daEquipa, isFalse);
      expect(r.reply?.texto, 'Olá');
      expect(r.id, isNull);
    });

    test('a última da equipa só aparece se o cliente ainda não respondeu', () {
      AssistantHistoryMessage h(String role, String id) =>
          AssistantHistoryMessage.fromRow(
              {'id': id, 'role': role, 'content': 'texto $id'});
      expect(ultimaMensagemDaEquipa([h('user', '1'), h('admin', '2')])?.id, '2');
      expect(ultimaMensagemDaEquipa([h('admin', '1'), h('assistant', '2')])?.id,
          '1');
      expect(ultimaMensagemDaEquipa([h('admin', '1'), h('user', '2')]), isNull);
      expect(ultimaMensagemDaEquipa(const []), isNull);
    });

    test('resposta com modo equipa: sem ações nem cartões, sem erro', () {
      final r = AssistantReply.fromJson({
        'ok': true,
        'modo': 'equipa',
        'texto': 'A Equipa Bora está a acompanhar a tua conversa.',
        'conversation_id': 'c1',
      });
      expect(r.equipaAcompanha, isTrue);
      expect(r.temCartoes, isFalse);
      expect(r.acoes, isEmpty);
      expect(r.conversationId, 'c1');
      expect(AssistantReply.fromJson({'texto': 'olá'}).equipaAcompanha, isFalse);
    });

    test('rosto do Amigo sem Supabase (testes antigos): nada rebenta', () async {
      const cerebro = AmigoCerebro();
      expect(await cerebro.ultimaDaEquipa('c1'), isNull);
      expect(cerebro.ouvirEquipa('c1', (_) {}), isNull);
    });

    testWidgets('balão "Equipa Bora" e o aviso discreto', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            BalaoEquipaBora(texto: 'Já tratámos do teu pedido.'),
            NotaEquipaAcompanha(texto: ''),
          ]),
        ),
      ));
      expect(find.text('Equipa Bora'), findsOneWidget);
      expect(find.text('Já tratámos do teu pedido.'), findsOneWidget);
      expect(find.text('A Equipa Bora está a acompanhar esta conversa.'),
          findsOneWidget);
    });
  });
}
