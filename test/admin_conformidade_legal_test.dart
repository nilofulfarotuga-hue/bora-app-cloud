import 'dart:io';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/screens/admin/_admin_rpc_errors.dart';
import 'package:bora_app/screens/admin/admin_conformidade_legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// D4 (ronda-fecho-2026-09-22) — painel admin "Conformidade legal" (PT-BR).
///
/// O que estes testes fecham:
///  1. O ecrã desenha os 5 itens legais com o chip certo (ok verde, parcial
///     laranja, falta vermelho), a tabela de prestadores (aprovados
///     incompletos a vermelho) e a lista de incompletos com os chips do que
///     falta — a 360×800 e a 1024×768, sem overflow.
///  2. O botão "Abrir" só aparece quando a rota existe mesmo em `main.dart`.
///  3. O filtro por tipo reduz a lista de incompletos.
///  4. "Exportar CSV DAC7" chama `exportar(ano escolhido)` e entrega
///     `dac7_<ano>_bora.csv` com o cabeçalho pedido, euros com vírgula
///     (12168 → 121,68) e `campos_em_falta` unidos por '|'; sem linhas, avisa
///     e não guarda ficheiro nenhum.
///  5. `not_admin` chega humanizado e "Tentar de novo" volta a carregar.
///  6. O helper de erros traduz `not_admin` e `conformidade_incompleta`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('helper de erros (_admin_rpc_errors)', () {
    test('not_admin fica humanizado', () {
      expect(
        humanizeAdminRpcError(const PostgrestException(message: 'not_admin')),
        'Sem permissão de administrador (a sessão não é de admin).',
      );
    });

    test('conformidade_incompleta traduz a lista de campos', () {
      expect(
        humanizeAdminRpcError(const PostgrestException(
            message: 'conformidade_incompleta: faltam nif, morada, iban, '
                'data_nascimento, autocertificacao, nome')),
        'Ativação bloqueada: faltam dados legais (NIF, Morada, IBAN, '
        'Data de nascimento, Autocertificação DSA, Nome legal).',
      );
      expect(
        humanizeAdminRpcError(const PostgrestException(
            message: 'conformidade_incompleta: faltam iban')),
        'Ativação bloqueada: faltam dados legais (IBAN).',
      );
      // Sem lista legível não inventa campos.
      expect(
        humanizeConformidadeIncompleta('conformidade_incompleta'),
        'Ativação bloqueada: faltam dados legais.',
      );
    });

    test('os casos antigos continuam iguais', () {
      expect(
        humanizeAdminRpcError(
            const PostgrestException(message: 'admin_required')),
        'Sem permissões de admin para esta acção.',
      );
      expect(
          humanizeAdminRpcError(Exception('x')), startsWith('Erro inesperado'));
    });

    test('rótulos dos campos legais em PT-BR', () {
      expect(rotuloCampoLegal('nif'), 'NIF');
      expect(rotuloCampoLegal('morada'), 'Morada');
      expect(rotuloCampoLegal('iban'), 'IBAN');
      expect(rotuloCampoLegal('data_nascimento'), 'Data de nascimento');
      expect(rotuloCampoLegal('autocertificacao'), 'Autocertificação DSA');
      expect(rotuloCampoLegal('nome'), 'Nome legal');
      expect(rotuloCampoLegal('outro_campo'), 'outro_campo');
    });
  });

  group('CSV DAC7 (funções puras)', () {
    test('cêntimos → euros com vírgula, sem vírgula flutuante', () {
      expect(centsParaEuros(12168), '121,68');
      expect(centsParaEuros(5), '0,05');
      expect(centsParaEuros(-250), '-2,50');
      expect(centsParaEuros(null), '0,00');
      expect(centsParaEuros('300'), '3,00');
      expect(centsParaEuros(12168.0), '121,68');
    });

    test('cabeçalho pedido, ";" e aspas escapados, campos unidos por "|"', () {
      final csv = construirCsvDac7([_linhaNey()]);
      final linhas = csv.split('\n');
      expect(
          linhas.first,
          'ano;tipo;id;nome;nome_comercial;nif;morada;data_nascimento;iban;'
          'pais;autocertificado_em;trimestre_1_eur;trimestre_2_eur;'
          'trimestre_3_eur;trimestre_4_eur;total_eur;comissoes_bora_eur;'
          'transacoes;campos_em_falta');
      expect(
        linhas[1],
        '2026;driver;u1;Ney Silva;Ney;;"Rua A; ""casa"" 1";;;PT;;'
        '0,00;50,00;71,68;0,00;121,68;0,00;31;'
        'iban|data_nascimento|autocertificacao',
      );
    });

    test('nome do ficheiro e rotas conhecidas', () {
      expect(nomeFicheiroDac7(2026), 'dac7_2026_bora.csv');
      expect(rotaAdminExiste('/admin/users'), isTrue);
      expect(rotaAdminExiste('/admin/configuracoes'), isTrue,
          reason: 'registada em main.dart a 23/09 — com botão Abrir');
      expect(rotaAdminExiste('/admin/conformidade'), isFalse,
          reason: 'é este ecrã: não se abre a si próprio');
      expect(rotaAdminExiste(null), isFalse);
    });
  });

  group('ecrã Conformidade legal', () {
    for (final tamanho in const [Size(360, 800), Size(1024, 768)]) {
      testWidgets(
          'a ${tamanho.width.toInt()}×${tamanho.height.toInt()}: itens, '
          'tabela e incompletos, sem overflow', (tester) async {
        final f = _Fakes();
        await _pump(tester, f, tamanho: tamanho);
        expect(find.text('Conformidade legal'), findsOneWidget);
        expect(find.textContaining('Gerado em '), findsOneWidget);
        expect(find.textContaining('Ativação obrigatória: ligada'),
            findsOneWidget);

        // Os 5 itens com o chip certo — e "Abrir" só onde a rota existe.
        const esperado = {
          'd3_ativacao': ('OK', AppColors.success, true),
          'd3_prestadores': ('Parcial', AppColors.accent, false),
          'd3_recibo_vendedor': ('Parcial', AppColors.accent, true),
          'd3_opt_in': ('Falta', AppColors.error, true),
          'd4_dac7': ('OK', AppColors.success, false),
        };
        for (final e in esperado.entries) {
          final item = find.byKey(ValueKey('conformidade-item-${e.key}'));
          await _ver(tester, item);
          final (rotulo, cor, temAbrir) = e.value;
          final chip = find.descendant(of: item, matching: find.text(rotulo));
          expect(chip, findsOneWidget, reason: 'item ${e.key}');
          expect(tester.widget<Text>(chip).style?.color, cor,
              reason: 'cor do chip de ${e.key}');
          expect(
            find.descendant(of: item, matching: find.text('Abrir')),
            temAbrir ? findsOneWidget : findsNothing,
            reason: 'botão Abrir em ${e.key}',
          );
        }

        // Tabela de prestadores: uma linha por tipo, aprovados incompletos
        // a vermelho quando > 0; tipo ausente no resumo aparece a zeros.
        await _ver(tester, find.byKey(const Key('tabela-prestadores')));
        for (final rotulo in const [
          'Estafetas/Motoristas',
          'Parceiros',
          'Faxineiros',
          'Lavadores',
          'Prestadores de serviços',
        ]) {
          expect(find.text(rotulo), findsOneWidget, reason: rotulo);
        }
        final aprIncDriver =
            tester.widget<Text>(find.byKey(const ValueKey('apr-inc-driver')));
        expect(aprIncDriver.data, '5');
        expect(aprIncDriver.style?.color, AppColors.error);
        final aprIncWasher =
            tester.widget<Text>(find.byKey(const ValueKey('apr-inc-washer')));
        expect(aprIncWasher.data, '0');
        expect(aprIncWasher.style?.color, isNot(AppColors.error));
        expect(find.byKey(const ValueKey('apr-inc-provider')), findsOneWidget);

        // Incompletos: 5 linhas, nome, telefone, aprovação e chips do que falta.
        await _ver(tester, find.byKey(const Key('seccao-incompletos')));
        expect(find.textContaining('Incompletos (5)'), findsOneWidget);
        expect(_linhasIncompletos(), 5);
        final ney = find.byKey(const ValueKey('incompleto-driver-d1'));
        expect(find.descendant(of: ney, matching: find.text('Ney Silva')),
            findsOneWidget);
        expect(
            find.descendant(
                of: ney, matching: find.textContaining('910000001')),
            findsOneWidget);
        expect(find.descendant(of: ney, matching: find.text('Aprovado')),
            findsOneWidget);
        for (final chip in const [
          'NIF',
          'Morada',
          'IBAN',
          'Data de nascimento',
          'Autocertificação DSA',
        ]) {
          expect(find.descendant(of: ney, matching: find.text(chip)),
              findsOneWidget,
              reason: 'chip $chip');
        }
        final semNome = find.byKey(const ValueKey('incompleto-driver-d3'));
        expect(find.descendant(of: semNome, matching: find.text('(sem nome)')),
            findsOneWidget);
        expect(find.descendant(of: semNome, matching: find.text('Nome legal')),
            findsOneWidget);
        expect(find.descendant(of: semNome, matching: find.text('Recusado')),
            findsOneWidget);
        final maria = find.byKey(const ValueKey('incompleto-cleaner-c1'));
        expect(
            find.descendant(
                of: maria, matching: find.textContaining('sem telefone')),
            findsOneWidget);
        expect(find.descendant(of: maria, matching: find.text('Pendente')),
            findsOneWidget);

        // Marketing e lojas.
        await _ver(tester, find.byKey(const Key('cartao-marketing')));
        expect(_kpi(tester, 'kpi-clientes').data, '125');
        expect(_kpi(tester, 'kpi-com-opt-in').data, '0');
        expect(_kpi(tester, 'kpi-ultimo-opt-in').data, 'nunca');
        await _ver(tester, find.byKey(const Key('cartao-lojas')));
        expect(_kpi(tester, 'kpi-aprovadas').data, '6');
        final semNif = _kpi(tester, 'kpi-sem-nif');
        expect(semNif.data, '5');
        expect(semNif.style?.color, AppColors.error);
        final semMorada = _kpi(tester, 'kpi-sem-morada');
        expect(semMorada.data, '0');
        expect(semMorada.style?.color, isNot(AppColors.error));

        // DAC7: ano atual e 2 anteriores, botão com o ano.
        await _ver(tester, find.byKey(const Key('cartao-dac7')));
        for (final a in const [2024, 2025, 2026]) {
          expect(find.byKey(ValueKey('ano-$a')), findsOneWidget);
        }
        expect(find.text('Exportar CSV DAC7 (2026)'), findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'overflow ou erro de layout');
        expect(f.carregadas, 1);
      });
    }

    testWidgets('"Abrir" leva à rota nomeada', (tester) async {
      final f = _Fakes();
      await _pump(tester, f);
      final item = find.byKey(const ValueKey('conformidade-item-d3_opt_in'));
      await _ver(tester, item);
      await tester.tap(find.descendant(of: item, matching: find.text('Abrir')));
      await tester.pumpAndSettle();
      expect(find.text('destino: clientes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('o filtro por tipo reduz a lista de incompletos',
        (tester) async {
      final f = _Fakes();
      await _pump(tester, f);
      await _ver(tester, find.byKey(const Key('seccao-incompletos')));
      expect(_linhasIncompletos(), 5);

      await tester.tap(find.text('Parceiros (1)'));
      await tester.pumpAndSettle();
      expect(_linhasIncompletos(), 1);
      expect(find.text('Goola Açaí'), findsOneWidget);
      expect(find.text('Ney Silva'), findsNothing);

      await tester.tap(find.text('Lavadores (0)'));
      await tester.pumpAndSettle();
      expect(_linhasIncompletos(), 0);
      expect(find.text('Nenhum incompleto neste tipo.'), findsOneWidget);

      await tester.tap(find.text('Estafetas/Motoristas (3)'));
      await tester.pumpAndSettle();
      expect(_linhasIncompletos(), 3);

      await tester.tap(find.text('Todos (5)'));
      await tester.pumpAndSettle();
      expect(_linhasIncompletos(), 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Exportar CSV DAC7 chama exportar(ano) e guarda o ficheiro',
        (tester) async {
      final f = _Fakes();
      await _pump(tester, f);
      final botao = find.byKey(const Key('botao-exportar-dac7'));
      await _ver(tester, botao);

      await tester.tap(botao);
      await tester.pumpAndSettle();
      expect(f.anosExportados, [2026]);
      expect(f.guardadas, 1);
      expect(f.nomeGuardado, 'dac7_2026_bora.csv');
      final linhas = f.csvGuardado!.split('\n');
      expect(
          linhas.first,
          'ano;tipo;id;nome;nome_comercial;nif;morada;data_nascimento;iban;'
          'pais;autocertificado_em;trimestre_1_eur;trimestre_2_eur;'
          'trimestre_3_eur;trimestre_4_eur;total_eur;comissoes_bora_eur;'
          'transacoes;campos_em_falta');
      expect(linhas[1], contains(';121,68;'));
      expect(linhas[1], endsWith(';iban|data_nascimento|autocertificacao'));
      expect(linhas[1], contains('"Rua A; ""casa"" 1"'));
      expect(linhas[2], contains(';-2,50;30,05;12;'));
      expect(linhas, hasLength(3));
      expect(find.text('Exportadas 2 linhas'), findsOneWidget);
      expect(find.textContaining('Última exportação: 2 linhas de 2026'),
          findsOneWidget);
      expect(find.textContaining('DAC7 (DL 26/2023)'), findsOneWidget);

      // Ano sem linhas: chama exportar(2025), avisa e não guarda nada.
      await tester.tap(find.byKey(const ValueKey('ano-2025')));
      await tester.pumpAndSettle();
      expect(find.text('Exportar CSV DAC7 (2025)'), findsOneWidget);
      await _ver(tester, botao);
      await tester.tap(botao);
      await tester.pumpAndSettle();
      expect(f.anosExportados, [2026, 2025]);
      expect(f.guardadas, 1, reason: 'sem linhas não há ficheiro');
      expect(find.text('Sem linhas para 2025'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'not_admin ao carregar mostra a mensagem humanizada e '
        '"Tentar de novo" volta a carregar', (tester) async {
      final f =
          _Fakes(erroPrimeiro: const PostgrestException(message: 'not_admin'));
      await _pump(tester, f);
      expect(find.text('Não foi possível carregar.'), findsOneWidget);
      expect(
        find.text('Sem permissão de administrador (a sessão não é de admin).'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('conformidade-item-d3_ativacao')),
          findsNothing);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(f.carregadas, 2);
      expect(find.byKey(const ValueKey('conformidade-item-d3_ativacao')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// ─── apoio ──────────────────────────────────────────────────────────────────

class _Fakes {
  _Fakes({this.erroPrimeiro});

  final Object? erroPrimeiro;
  int carregadas = 0;
  final anosExportados = <int>[];
  int guardadas = 0;
  String? nomeGuardado;
  String? csvGuardado;

  Future<Map<String, dynamic>> carregar() async {
    carregadas++;
    if (carregadas == 1 && erroPrimeiro != null) throw erroPrimeiro!;
    return _dadosFalsos();
  }

  Future<Map<String, dynamic>> exportar(int ano) async {
    anosExportados.add(ano);
    return {
      'ano': ano,
      'gerado_em': '2026-09-23T10:20:00+00:00',
      'nota': 'DAC7 (DL 26/2023): contraprestação paga por trimestre, '
          'comissões retidas e n.º de operações por vendedor.',
      'linhas': ano == 2026 ? [_linhaNey(), _linhaGoola()] : <Object>[],
    };
  }

  Future<void> guardarCsv(String nome, String csv) async {
    guardadas++;
    nomeGuardado = nome;
    csvGuardado = csv;
  }
}

Future<void> _pump(WidgetTester tester, _Fakes f,
    {Size tamanho = const Size(360, 800)}) async {
  // Inter real, como no painel: o Ahem dos testes tem glifos quadrados e
  // não representa a largura verdadeira do texto.
  final bytes = File('assets/fonts/Inter-VariableFont.ttf').readAsBytesSync();
  final loader = FontLoader('Inter')
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();

  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Inter'),
    routes: {
      '/admin/users': (_) => const Scaffold(body: Text('destino: clientes')),
    },
    home: AdminConformidadeLegalScreen(
      carregar: f.carregar,
      exportar: f.exportar,
      guardarCsv: f.guardarCsv,
      anoAtual: 2026,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Rola a lista principal até o alvo estar construído e visível.
Future<void> _ver(WidgetTester tester, Finder alvo) async {
  await tester.scrollUntilVisible(
    alvo,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('conformidade-lista')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

int _linhasIncompletos() => find
    .byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('incompleto-'))
    .evaluate()
    .length;

Text _kpi(WidgetTester tester, String chave) => tester.widget<Text>(find
    .descendant(of: find.byKey(Key(chave)), matching: find.byType(Text))
    .first);

Map<String, dynamic> _linhaNey() => {
      'ano': 2026,
      'tipo': 'driver',
      'id': 'u1',
      'nome': 'Ney Silva',
      'nome_comercial': 'Ney',
      'nif': null,
      'morada': 'Rua A; "casa" 1',
      'data_nascimento': null,
      'iban': null,
      'pais': 'PT',
      'autocertificado_em': null,
      'trimestre_1_cents': 0,
      'trimestre_2_cents': 5000,
      'trimestre_3_cents': 7168,
      'trimestre_4_cents': 0,
      'total_cents': 12168,
      'comissoes_bora_cents': 0,
      'transacoes': 31,
      'campos_em_falta': ['iban', 'data_nascimento', 'autocertificacao'],
    };

Map<String, dynamic> _linhaGoola() => {
      'ano': 2026,
      'tipo': 'partner',
      'id': 'r1',
      'nome': 'Goola Lda',
      'nome_comercial': 'Goola Açaí',
      'nif': '123456789',
      'morada': 'Av. B 2, Guarda',
      'data_nascimento': null,
      'iban': 'PT50000201231234567890154',
      'pais': 'PT',
      'autocertificado_em': '2026-09-01T10:00:00+00:00',
      'trimestre_1_cents': 1000,
      'trimestre_2_cents': -1250,
      'trimestre_3_cents': 0,
      'trimestre_4_cents': 0,
      'total_cents': -250,
      'comissoes_bora_cents': 3005,
      'transacoes': 12,
      'campos_em_falta': <String>[],
    };

Map<String, dynamic> _dadosFalsos() => {
      'gerado_em': '2026-09-23T10:15:00+00:00',
      'ativacao_obrigatoria': true,
      'itens': [
        {
          'codigo': 'd3_ativacao',
          'titulo': 'Ativação bloqueada sem dados legais (DSA art. 30 + DAC7)',
          'estado': 'ok',
          'detalhe': 'Gatilho ligado: nome, NIF, morada, IBAN, data de '
              'nascimento e autocertificação são exigidos antes de aprovar.',
          // Registada em main.dart a 23/09 → botão "Abrir".
          'rota': '/admin/configuracoes',
        },
        {
          'codigo': 'd3_prestadores',
          'titulo': 'Prestadores com dados completos',
          'estado': 'parcial',
          'detalhe': 'Ver a lista de incompletos abaixo; os aprovados '
              'incompletos precisam de completar na app.',
          'rota': null,
        },
        {
          'codigo': 'd3_recibo_vendedor',
          'titulo': 'Nome, NIF e morada do vendedor no recibo do cliente',
          'estado': 'parcial',
          'detalhe': '6 lojas parceiras aprovadas: 5 sem NIF, 0 sem morada.',
          'rota': '/admin/parceiros',
        },
        {
          'codigo': 'd3_opt_in',
          'titulo': 'Opt-in separado para marketing',
          'estado': 'falta',
          'detalhe': '125 clientes, 0 com opt-in. Push comercial só vai a '
              'estes.',
          // Existe em main.dart → botão "Abrir".
          'rota': '/admin/users',
        },
        {
          'codigo': 'd4_dac7',
          'titulo': 'Exportação DAC7 anual (CSV)',
          'estado': 'ok',
          'detalhe': 'Uma linha por vendedor com totais por trimestre; '
              'entregar à AT até 31 de janeiro do ano seguinte.',
          // É este ecrã: não se abre a si próprio.
          'rota': '/admin/conformidade',
        },
      ],
      'prestadores': {
        'resumo': {
          'driver': {
            'total': 8,
            'aprovados': 5,
            'completos': 0,
            'incompletos': 8,
            'aprovados_incompletos': 5,
          },
          'partner': {
            'total': 6,
            'aprovados': 6,
            'completos': 5,
            'incompletos': 1,
            'aprovados_incompletos': 1,
          },
          'cleaner': {
            'total': 2,
            'aprovados': 1,
            'completos': 1,
            'incompletos': 1,
            'aprovados_incompletos': 0,
          },
          'washer': {
            'total': 0,
            'aprovados': 0,
            'completos': 0,
            'incompletos': 0,
            'aprovados_incompletos': 0,
          },
          // 'provider' de propósito ausente: o servidor não devolve tipos
          // sem linhas; o ecrã mostra a linha a zeros na mesma.
        },
        'incompletos': [
          {
            'tipo': 'driver',
            'id': 'd1',
            'user_id': 'u1',
            'nome': 'Ney Silva',
            'phone': '910000001',
            'approval_status': 'approved',
            'falta': [
              'nif',
              'morada',
              'iban',
              'data_nascimento',
              'autocertificacao',
            ],
          },
          {
            'tipo': 'driver',
            'id': 'd2',
            'user_id': 'u2',
            'nome': 'Valdemir Costa',
            'phone': '910000002',
            'approval_status': 'pending',
            'falta': ['iban'],
          },
          {
            'tipo': 'driver',
            'id': 'd3',
            'user_id': 'u3',
            'nome': '',
            'phone': '910000003',
            'approval_status': 'rejected',
            'falta': ['nome', 'nif'],
          },
          {
            'tipo': 'partner',
            'id': 'r1',
            'user_id': 'u4',
            'nome': 'Goola Açaí',
            'phone': '271000000',
            'approval_status': 'approved',
            'falta': ['nif'],
          },
          {
            'tipo': 'cleaner',
            'id': 'c1',
            'user_id': 'u5',
            'nome': 'Maria Faxina',
            'phone': null,
            'approval_status': 'pending',
            'falta': ['autocertificacao'],
          },
        ],
      },
      'marketing': {'clientes': 125, 'com_opt_in': 0, 'ultimo_opt_in': null},
      'lojas': {'aprovadas': 6, 'sem_nif': 5, 'sem_morada': 0},
    };
