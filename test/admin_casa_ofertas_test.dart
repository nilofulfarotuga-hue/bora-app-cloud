import 'dart:io';

import 'package:bora_app/screens/admin/admin_casa_comum.dart';
import 'package:bora_app/screens/admin/admin_casa_ofertas_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [app-fechar B1 · 01/11/2026] Painel admin da Casa (PT-BR), sem rede:
///
///  1. C16 — `admin_casa_ofertas` deixou de ser casca sem fio: aba "Ofertas"
///     com o registro da rotação de todos os pedidos (resumo, filtros, toque
///     abre o pedido).
///  2. Os textos do painel da Casa estão em PT-BR (nada de "Guardar",
///     "ladrilho", "Morada", "ecrã", "telemóvel", "registo", "utilizador"…).
///  3. Todos os códigos de erro das funções admin_casa_* têm frase PT-BR.
class _Rpc {
  _Rpc(this.respostas);
  final Map<String, dynamic> respostas;
  final chamadas = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, params));
    return respostas[fn];
  }

  List<Map<String, dynamic>> de(String fn) => [
        for (final c in chamadas)
          if (c.$1 == fn) c.$2
      ];
}

void _ecraGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

final _ofertas = <Map<String, dynamic>>[
  {
    'id': 'o1',
    'pedido_id': 'x1',
    'profissional_id': 'p1',
    'profissional_nome': 'Rui',
    'tipo': 'oferta',
    'enviada_em': '2026-11-01T10:00:00Z',
    'expira_em': '2026-11-01T10:05:00Z',
    'tinha_aparelho': true,
    'resposta': 'aceite',
    'respondida_em': '2026-11-01T10:01:00Z',
    'ronda': 1,
  },
  {
    'id': 'o2',
    'pedido_id': 'x2',
    'profissional_id': 'p2',
    'profissional_nome': 'Zé',
    'tipo': 'oferta',
    'enviada_em': '2026-11-01T09:00:00Z',
    'expira_em': '2026-11-01T09:05:00Z',
    'tinha_aparelho': false,
    'resposta': 'expirada',
    'ronda': 2,
  },
  {
    'id': 'o3',
    'pedido_id': 'x3',
    'profissional_id': 'p1',
    'profissional_nome': 'Rui',
    'tipo': 'convite_orcamento',
    'enviada_em': '2026-11-01T11:00:00Z',
    'expira_em': '2026-11-02T11:00:00Z',
    'tinha_aparelho': true,
    'resposta': null,
    'ronda': 1,
  },
];

void main() {
  group('Ofertas (C16): contas e filtros', () {
    test('resumo conta o que veio do servidor', () {
      final r = casaResumoOfertas(_ofertas);
      expect(r.total, 3);
      expect(r.aceitas, 1);
      expect(r.recusadas, 0);
      expect(r.expiradas, 1);
      expect(r.semAparelho, 1);
      expect(r.aguardando, 1);
      expect(casaResumoOfertas(const []).total, 0);
    });

    test('filtro "aguardando" = resposta nula; null = todas', () {
      expect(_ofertas.where((o) => casaOfertaNoFiltro(o, null)), hasLength(3));
      expect(
          _ofertas
              .where((o) => casaOfertaNoFiltro(o, kCasaOfertaAguardando))
              .map((o) => o['id']),
          ['o3']);
      expect(
          _ofertas
              .where((o) => casaOfertaNoFiltro(o, 'expirada'))
              .map((o) => o['id']),
          ['o2']);
    });

    test('cada filtro tem rótulo PT-BR (nunca o código cru)', () {
      for (final f in kCasaOfertaRespostas) {
        final t = casaOfertaFiltroPtBr(f);
        expect(t, isNot(f), reason: f);
        expect(t.contains('_'), isFalse, reason: f);
      }
      expect(casaOfertaFiltroPtBr('sem_aparelho'), 'Sem aparelho registrado');
    });
  });

  group('Ofertas (C16): a aba', () {
    testWidgets('chama admin_casa_ofertas, resume, filtra e abre o pedido',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_ofertas': _ofertas,
        'admin_casa_pedido': {
          'id': 'x2',
          'estado': 'expirado',
          'servico_nome': 'Montar um móvel',
          'oficio': 'montagem',
          'modo': 'fixo',
          'total_cents': 2500,
          'morada': {'street': 'Rua A', 'city': 'Guarda', 'postal': '6300-000'},
          'cliente': {'nome': 'Ana'},
          'eventos': <dynamic>[],
          'ofertas': [_ofertas[1]],
        },
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AdminCasaOfertasTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_ofertas'), [
        {'p_pedido_id': null}
      ]);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('casa-ofertas-resumo')))
              .data,
          '3 ofertas · 1 aceitas · 0 recusadas · 1 expiraram · '
          '1 sem aparelho · 1 aguardando');
      expect(find.byKey(const ValueKey('casa-oferta-o1')), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-oferta-o3')), findsOneWidget);
      expect(find.textContaining('Convite para orçar'), findsOneWidget);
      expect(find.byIcon(Icons.phonelink_erase), findsOneWidget);

      // Filtro "Deixou expirar": só a o2, sem ir outra vez ao servidor.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Deixou expirar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('casa-oferta-o2')), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-oferta-o1')), findsNothing);
      expect(rpc.de('admin_casa_ofertas'), hasLength(1));

      // Toque abre a ficha do pedido.
      await tester.tap(find.byKey(const ValueKey('casa-oferta-o2')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_pedido'), [
        {'p_id': 'x2'}
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lista vazia diz isso; erro mostra "Tentar de novo"',
        (tester) async {
      final vazio = _Rpc({'admin_casa_ofertas': <dynamic>[]});
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AdminCasaOfertasTab(rpc: vazio.call))));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma oferta neste filtro.'), findsOneWidget);

      final recusa = _Rpc({
        'admin_casa_ofertas': {'ok': false, 'error': 'sem_permissao'},
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AdminCasaOfertasTab(
                  key: const ValueKey('outra'), rpc: recusa.call))));
      await tester.pumpAndSettle();
      expect(find.text('Sem permissão para esta ação.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('o hub tem a aba "Ofertas" no fim (índices antigos iguais)',
        (tester) async {
      _ecraGrande(tester);
      expect(kCasaSeparadores.last, 'Ofertas');
      expect(kCasaSeparadores.indexOf('Configurações'), 5,
          reason: 'o Resumo salta para a aba 5 (Configurações)');
      final rpc = _Rpc({
        'admin_casa_resumo': {
          'enabled': false,
          'valores_autorizados': {'autorizado': false},
        },
        'admin_casa_ofertas': _ofertas,
      });
      await tester.pumpWidget(MaterialApp(
          home: AdminCasaScreen(
              separadorInicial: kCasaSeparadores.indexOf('Ofertas'),
              rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_ofertas'), isNotEmpty);
      expect(find.byKey(const ValueKey('casa-ofertas-resumo')), findsOneWidget);
    });
  });

  group('PT-BR no painel da Casa', () {
    // Só o texto que o Danilo lê (literais com espaço); chaves JSON e nomes de
    // funções não contam.
    final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
    const ptPt = <String, String>{
      'Guardar': 'Salvar',
      'guardad': 'salvo/salva',
      'ladrilho': 'atalho/card',
      'Morada': 'Endereço',
      ' morada': ' endereço',
      'ecrã': 'tela',
      'telemóvel': 'celular/telefone',
      'registo': 'registro',
      'utilizador': 'usuário',
      'contactar': 'entrar em contato',
      'ficheiro': 'arquivo',
      'equipa': 'equipe',
      'Definições': 'Configurações',
    };

    test('nenhum texto em PT-PT nos ficheiros admin_casa_*', () {
      final ficheiros = Directory('lib/screens/admin')
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('admin_casa_'))
          .toList();
      expect(ficheiros.length, greaterThanOrEqualTo(10));
      final achados = <String>[];
      for (final f in ficheiros) {
        final linhas = f.readAsLinesSync();
        for (var i = 0; i < linhas.length; i++) {
          final l = linhas[i].trimLeft();
          if (l.startsWith('//')) continue;
          for (final m in literal.allMatches(l)) {
            final texto = m.group(1)!;
            if (!texto.contains(' ')) continue;
            for (final e in ptPt.entries) {
              if (texto.contains(e.key)) {
                achados.add('${f.uri.pathSegments.last}:${i + 1} '
                    '"${e.key}" → ${e.value}: $texto');
              }
            }
          }
        }
      }
      expect(achados, isEmpty, reason: achados.join('\n'));
    });

    test('todos os códigos das admin_casa_* têm frase PT-BR', () {
      // Lidos do servidor (RAISE EXCEPTION das admin_casa_*) a 01/11/2026,
      // mais os dos gatilhos que a aprovação dispara.
      const codigos = [
        'acao_invalida',
        'chave_invalida',
        'documento_em_falta',
        'estado_invalido',
        'nao_e_profissional',
        'oficio_invalido',
        'profissional_ocupado',
        'profissional_sem_oficio',
        'tem_trabalhos_ativos',
        'texto_sem_autorizo',
        'usar_interruptor',
        'validade_passada',
        'valor_invalido',
        'valores_por_autorizar',
        'sem_permissao',
        'motivo_obrigatorio',
        'atividade_por_aprovar',
        'conformidade_incompleta',
      ];
      for (final c in codigos) {
        final t = casaErroPtBr(CasaErroServidor(c));
        expect(t, isNot(startsWith('O servidor recusou')), reason: c);
        expect(t.contains('_'), isFalse, reason: c);
      }
      expect(casaErroPtBr(const CasaErroServidor('oficio_invalido')),
          'Esse ofício não existe (ou está desativado) na Casa.');
    });
  });
}
