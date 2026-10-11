import 'package:bora_app/utils/ofertas_em_palavras.dart';
import 'package:bora_app/widgets/admin/admin_ofertas_do_pedido_section.dart';
import 'package:bora_app/widgets/admin/admin_reforco_section.dart';
import 'package:bora_app/widgets/chamada_reforco_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Missão "a chamada grita sempre" (10/10/2026): o painel mostra quem foi
/// chamado em cada pedido e a chamada de reforço; o estafeta tem o
/// interruptor de consentimento. Tudo tem de aguentar a migração
/// 20261010063000 ainda NÃO aplicada no servidor.
void main() {
  group('fase e desfecho em palavras', () {
    test('as cinco fases', () {
      expect(faseEmPalavras('online'), 'online');
      expect(faseEmPalavras('desligado'), 'desligado');
      expect(faseEmPalavras('online1'), '1ª rodada online');
      expect(faseEmPalavras('forcado'), 'chamada de reforço');
      expect(faseEmPalavras('online2'), 'rodada online final');
      expect(faseEmPalavras(null), '—');
      expect(faseEmPalavras('fase_nova'), 'fase nova');
    });

    test('os desfechos que o servidor escreve', () {
      expect(desfechoEmPalavras('aceite'), 'aceitou');
      expect(desfechoEmPalavras('recusou'), 'recusou');
      expect(desfechoEmPalavras('recusada'), 'recusou');
      expect(desfechoEmPalavras('expirou'), 'expirou sem resposta');
      expect(desfechoEmPalavras('sem_resposta'), 'não respondeu');
      expect(desfechoEmPalavras('pedido_cancelado'), 'pedido cancelado');
      expect(desfechoEmPalavras('pedido_mudou'), 'pedido mudou de estado');
      expect(desfechoEmPalavras('sem_motorista'), 'corrida ficou sem motorista');
      expect(desfechoEmPalavras('a decorrer'), 'em andamento');
      expect(desfechoEmPalavras(null), 'em andamento');
    });

    test('toque entregue ao FCM: sim/não (n de m aparelhos)', () {
      expect(toqueEntregueEmPalavras(1, 2), 'sim (1 de 2 aparelhos)');
      expect(toqueEntregueEmPalavras(0, 1), 'não (0 de 1 aparelho)');
      expect(toqueEntregueEmPalavras(1, null), 'sim');
      expect(toqueEntregueEmPalavras(null, 2), 'sem registro');
    });

    test('quanto tempo teve', () {
      expect(janelaEmPalavras(40), '40 s');
      expect(janelaEmPalavras(120), '2 min');
      expect(janelaEmPalavras(90), '1 min 30 s');
      expect(janelaEmPalavras(null), '—');
    });

    test('categoria', () {
      expect(categoriaEmPalavras('tvde'), 'TVDE (corrida)');
      expect(categoriaEmPalavras('favor'), 'Favor');
      expect(categoriaEmPalavras('entrega'), 'Entrega');
    });
  });

  group('servidor ainda sem a migração', () {
    test('função, tabela, coluna ou definição em falta contam como "ainda não ativo"', () {
      expect(
          servidorAindaSemIsto(const PostgrestException(
              message: 'Could not find the function public.admin_reforco_lista',
              code: 'PGRST202')),
          isTrue);
      expect(
          servidorAindaSemIsto(const PostgrestException(
              message: 'relation "public.chamada_reforco_consentimento" does not exist',
              code: '42P01')),
          isTrue);
      expect(
          servidorAindaSemIsto(const PostgrestException(
              message: 'unknown_setting: dispatch_forcado_ligado', code: '23503')),
          isTrue);
    });

    test('outros erros NÃO se escondem como "ainda não ativo"', () {
      expect(servidorAindaSemIsto(Exception('SocketException: sem rede')), isFalse);
      expect(
          servidorAindaSemIsto(
              const PostgrestException(message: 'admin_required', code: 'P0001')),
          isFalse);
      expect(servidorAindaSemIsto(null), isFalse);
    });

    test('chaves em falta e registro novo', () {
      expect(chavesEmFalta(kChavesReforcoTvde, ['tvde_forcado_ligado']),
          ['tvde_forcado_tentativas', 'tvde_forcado_prioridade']);
      expect(chavesEmFalta(['a'], ['a', 'b']), isEmpty);
      expect(registroNovoAtivo({'total': 3, 'aceites': 1}), isFalse);
      expect(registroNovoAtivo({'total': 3, 'reforco': 0, 'toque_falhou': 0}),
          isTrue);
    });
  });

  group('ordem da chamada de reforço', () {
    final itens = <Map<String, dynamic>>[
      {'user_id': 'b', 'nome': 'Bruno', 'consentiu': true, 'ordem': null},
      {'user_id': 'v', 'nome': 'Valdemir', 'consentiu': true, 'ordem': 1},
      {'user_id': 'n', 'nome': 'Ney', 'consentiu': false, 'ordem': 2},
      {'user_id': 'a', 'nome': 'Ana', 'consentiu': true, 'ordem': null},
    ];

    test('quem tem lugar primeiro, depois por nome; sem quem não consentiu', () {
      expect(ordemInicialConsentidos(itens), ['v', 'a', 'b']);
    });

    test('subir e descer', () {
      expect(moverNaLista(['v', 'a', 'b'], 2, -1), ['v', 'b', 'a']);
      expect(moverNaLista(['v', 'a', 'b'], 0, -1), ['v', 'a', 'b']);
      expect(moverNaLista(['v', 'a', 'b'], 2, 1), ['v', 'a', 'b']);
    });

    test('nova prioridade guarda o lugar de quem ainda não consentiu', () {
      expect(novaPrioridade(['a', 'v'], ['v', 'n']), ['a', 'v', 'n']);
      expect(novaPrioridade(const [], ['v']), ['v']);
      expect(listaDeIds(['x', null, 'y']), ['x', 'y']);
      expect(listaDeIds('nao-e-lista'), isEmpty);
    });

    test('hora HH:MM', () {
      expect(horaHhMm('8:00'), '08:00');
      expect(horaHhMm('23:00:00'), '23:00');
      expect(horaHhMm('25:00'), isNull);
      expect(horaHhMm(null), isNull);
    });
  });

  group('ecrãs', () {
    Widget app(Widget filho) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: filho)),
        );

    testWidgets('Quem foi chamado: servidor sem a RPC mostra o aviso, não erro',
        (tester) async {
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'abc',
        carregar: (_) async => throw const PostgrestException(
            message: 'Could not find the function public.admin_ofertas_do_pedido(p_ref)',
            code: 'PGRST202'),
      )));
      await tester.pumpAndSettle();
      expect(find.text(kAindaNaoAtivo), findsOneWidget);
      expect(find.textContaining('Erro'), findsNothing);
      expect(find.textContaining('Não deu para carregar'), findsNothing);
    });

    testWidgets('Quem foi chamado: cada linha em palavras, hora de Lisboa',
        (tester) async {
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'abc',
        carregar: (_) async => {
          'ok': true,
          'itens': [
            {
              'categoria': 'entrega',
              'nome': 'Valdemir',
              'fase': 'forcado',
              'estava_online': false,
              'tem_aparelho': true,
              'janela_s': 40,
              'oferecida_em': '2026-10-10T18:05:12Z',
              'desfecho': 'aceite',
              'push_aparelhos': 2,
              'push_enviados': 1,
            },
          ],
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('Quem foi chamado (1)'), findsOneWidget);
      expect(find.text('10/10 19:05:12 · Valdemir'), findsOneWidget);
      expect(find.textContaining('chamada de reforço'), findsOneWidget);
      expect(find.textContaining('estava online: não'), findsOneWidget);
      expect(find.textContaining('teve 40 s'), findsOneWidget);
      expect(find.text('Toque entregue ao FCM: sim (1 de 2 aparelhos)'),
          findsOneWidget);
      expect(find.text('aceitou'), findsOneWidget);
    });

    testWidgets('Reforço: sem definições nem lista no servidor → aviso e controles desligados',
        (tester) async {
      await tester.pumpWidget(app(AdminReforcoSection(
        listarDefinicoes: () async => [
          {'key': 'dispatch_offer_timeout_seconds', 'value': 40},
        ],
        listarPessoas: () async => throw const PostgrestException(
            message: 'Could not find the function public.admin_reforco_lista',
            code: 'PGRST202'),
        gravar: (_, __) async => fail('não pode gravar sem servidor'),
      )));
      await tester.pumpAndSettle();
      expect(find.text(kAindaNaoAtivo), findsNWidgets(2));
      final interruptores =
          tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      expect(interruptores, isNotEmpty);
      for (final s in interruptores) {
        expect(s.onChanged, isNull, reason: 'controle tem de estar desligado');
      }
    });

    testWidgets('Reforço: com servidor, lista verde/cinza e grava a ordem nos dois',
        (tester) async {
      final gravados = <String, Object>{};
      await tester.pumpWidget(app(AdminReforcoSection(
        listarDefinicoes: () async => [
          for (final k in [...kChavesReforcoEntregas, ...kChavesReforcoTvde])
            {
              'key': k,
              'value': k.endsWith('_prioridade')
                  ? ['v']
                  : k.endsWith('_ligado') || k.endsWith('_no_fim')
                      ? false
                      : k.contains('horario')
                          ? '08:00'
                          : 2,
            },
        ],
        listarPessoas: () async => {
          'ok': true,
          'itens': [
            {'user_id': 'v', 'nome': 'Valdemir', 'consentiu': true, 'ordem': 1, 'reforcos_hoje': 1},
            {'user_id': 'a', 'nome': 'Ana', 'consentiu': true, 'ordem': null, 'reforcos_hoje': 0},
            {'user_id': 'n', 'nome': 'Ney', 'consentiu': false, 'ordem': null, 'reforcos_hoje': 0},
          ],
        },
        gravar: (k, v) async => gravados[k] = v,
      )));
      await tester.pumpAndSettle();
      expect(find.text(kAindaNaoAtivo), findsNothing);
      expect(find.text('Valdemir'), findsOneWidget);
      expect(find.textContaining('não ligou o interruptor'), findsOneWidget);
      // Ana sobe para 1º e grava-se nas duas definições.
      await tester.ensureVisible(find.byTooltip('Subir').at(1));
      await tester.tap(find.byTooltip('Subir').at(1));
      await tester.pump();
      await tester.ensureVisible(find.text('Salvar ordem'));
      await tester.tap(find.text('Salvar ordem'));
      await tester.pumpAndSettle();
      expect(gravados['dispatch_forcado_prioridade'], ['a', 'v']);
      expect(gravados['tvde_forcado_prioridade'], ['a', 'v']);
    });

    testWidgets('Estafeta: sem tabela no servidor o interruptor não aparece',
        (tester) async {
      await tester.pumpWidget(app(ChamadaReforcoTile(
        userId: 'u1',
        ler: (_) async => throw const PostgrestException(
            message: 'relation does not exist', code: '42P01'),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('Estafeta: desligado por defeito e grava a própria linha',
        (tester) async {
      final gravados = <String, bool>{};
      await tester.pumpWidget(app(ChamadaReforcoTile(
        userId: 'u1',
        ler: (_) async => false,
        gravar: (uid, v) async => gravados[uid] = v,
      )));
      await tester.pumpAndSettle();
      final s = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(s.value, isFalse);
      expect(find.text('Aceito chamadas de reforço quando estou desligado'),
          findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(gravados, {'u1': true});
    });
  });
}
