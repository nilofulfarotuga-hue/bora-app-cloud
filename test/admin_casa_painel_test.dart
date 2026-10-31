import 'package:bora_app/models/casa_models.dart' show CasaEstado;
import 'package:bora_app/screens/admin/admin_casa_acertos_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_catalogo_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_comum.dart';
import 'package:bora_app/screens/admin/admin_casa_definicoes_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_exportar_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_orcamentos_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_pedidos_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_profissionais_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_resumo_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [casa-manutencao · 31/10/2026] Painel admin da Casa (PT-BR), sem rede:
/// a função do servidor é injetada e só regista as chamadas.
///
///  1. Rótulos em PT-BR (estados, aprovação) — nunca o nome técnico.
///  2. Aviso "PROPOSTA — aguardando o autorizo do Danilo" quando
///     valores_autorizados=false; "Valores AUTORIZADOS" quando true.
///  3. O interruptor só liga com a confirmação forte (escrever LIGAR).
///  4. O registro do "autorizo" exige a palavra e a data.
///  5. Fase 2 só se aprova com o documento DGEG/IMPIC aprovado.
///  6. Cada ação pede confirmação antes de chamar o servidor.
///  7. Datas e semanas na hora de Lisboa.
///  8. O menu tem a entrada "Casa e manutenção" na secção 'limpeza'.
class _Rpc {
  _Rpc(this.respostas);
  final Map<String, dynamic> respostas;
  final chamadas = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, params));
    return respostas[fn];
  }

  List<Map<String, dynamic>> de(String fn) =>
      [for (final c in chamadas) if (c.$1 == fn) c.$2];
}

Widget _app(Widget filho) =>
    MaterialApp(home: Scaffold(body: filho));

void _ecraGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('rótulos PT-BR', () {
    test('os 12 estados do servidor são os mesmos do modelo, e todos têm texto',
        () {
      expect(kCasaEstados, CasaEstado.values.map((e) => e.db).toList());
      for (final e in kCasaEstados) {
        final t = casaEstadoPtBr(e);
        expect(t, isNot(e), reason: e);
        expect(t.contains('_'), isFalse, reason: e);
      }
      expect(casaEstadoPtBr('aguarda_pagamento'), 'Aguardando pagamento');
      expect(casaEstadoPtBr('procura'), 'Procurando profissional');
      expect(casaEstadoPtBr('em_curso'), 'Trabalho em andamento');
      expect(casaEstadoPtBr('aceite'), startsWith('Aceito'));
      expect(casaEstadoPtBr('disputa'), contains('Disputa'));
      expect(casaEstadoPtBr(null), '—');
    });

    test('aprovação, documentos e pagamentos em PT-BR', () {
      expect(kCasaAprovacoes.map(casaAprovacaoPtBr),
          ['Pendente', 'Aprovado', 'Suspenso', 'Recusado', 'Banido']);
      expect(casaDocumentoTipoPtBr('dgeg_eletricidade'), contains('DGEG'));
      expect(casaDocumentoTipoPtBr('impic'), contains('IMPIC'));
      expect(casaPagamentoPtBr('cash'), 'Dinheiro');
      expect(casaPagamentoStatusPtBr('held'), startsWith('Retido'));
      expect(casaDirecaoPtBr('handyman_to_bora'), 'Profissional paga à Bora');
    });

    test('erros do servidor viram texto para o Danilo', () {
      expect(casaErroPtBr(const CasaErroServidor('valores_por_autorizar')),
          contains('PROPOSTA'));
      expect(casaErroPtBr(Exception('casa_desligada')), contains('desligada'));
      expect(() => casaVerOk({'ok': false, 'error': 'sem_permissao'}),
          throwsA(isA<CasaErroServidor>()));
      expect(casaVerOk({'ok': true}), {'ok': true});
    });
  });

  group('dinheiro e datas (Lisboa)', () {
    test('euros com vírgula e leitura do preço escrito', () {
      expect(casaEuroAdmin(2500), '25,00 €');
      expect(casaEuroAdmin(null), '—');
      expect(casaCentimosDeTexto('25,50'), 2550);
      expect(casaCentimosDeTexto('30 €'), 3000);
      expect(casaCentimosDeTexto('0'), isNull);
      expect(casaCentimosDeTexto('abc'), isNull);
      expect(casaEuroCampo(3500), '35,00');
    });

    test('hora de Lisboa: 23:30 UTC de domingo no verão já é segunda', () {
      expect(casaDataHora('2026-08-30T23:30:00Z'), '31/08/2026 00:30');
      expect(casaSegundaLisboa(DateTime.utc(2026, 8, 30, 23, 30)),
          DateTime.utc(2026, 8, 31));
      // No inverno (depois de 25/10) 23:30 UTC de domingo ainda é domingo.
      expect(casaSegundaLisboa(DateTime.utc(2026, 11, 1, 23, 30)),
          DateTime.utc(2026, 10, 26));
      expect(casaRotuloSemana(DateTime.utc(2026, 10, 26)), '26/10 a 01/11');
      // Data simples (validade) não muda de dia.
      expect(casaData('2026-12-31'), '31/12/2026');
    });

    test('validade escrita: vazio, ISO, DD/MM/AAAA e inválida', () {
      expect(casaLerValidade(''), (ok: true, iso: null));
      expect(casaLerValidade('31/12/2027'), (ok: true, iso: '2027-12-31'));
      expect(casaLerValidade('2027-01-05'), (ok: true, iso: '2027-01-05'));
      expect(casaLerValidade('31/02/2027').ok, isFalse);
      expect(casaLerValidade('amanhã').ok, isFalse);
    });
  });

  group('regras das ações', () {
    test('ações da pessoa por estado; recusar/suspender/banir pedem motivo',
        () {
      expect(casaAcoesProfissional('pending'), containsAll(['aprovar', 'recusar']));
      expect(casaAcoesProfissional('approved'), ['suspender', 'banir']);
      expect(casaAcoesProfissional('banned'), ['reativar']);
      expect(casaAcaoPedeMotivo('recusar'), isTrue);
      expect(casaAcaoPedeMotivo('banir'), isTrue);
      expect(casaAcaoPedeMotivo('aprovar'), isFalse);
    });

    test('fase 2 só aprova com o documento exigido APROVADO', () {
      const fase1 = {'codigo': 'montagem', 'fase': 1};
      const fase2 = {
        'codigo': 'eletricidade',
        'fase': 2,
        'documento_exigido': 'dgeg_eletricidade',
      };
      expect(casaOficioPodeAprovar(fase1, const []), isTrue);
      expect(casaOficioPodeAprovar(fase2, const []), isFalse);
      expect(
          casaOficioPodeAprovar(fase2, const [
            {'tipo': 'dgeg_eletricidade', 'estado': 'pending', 'oficio': 'eletricidade'},
          ]),
          isFalse);
      expect(
          casaOficioPodeAprovar(fase2, const [
            {'tipo': 'dgeg_eletricidade', 'estado': 'approved', 'oficio': 'eletricidade'},
          ]),
          isTrue);
      expect(
          casaOficioPodeAprovar(fase2, const [
            {'tipo': 'impic', 'estado': 'approved', 'oficio': null},
          ]),
          isFalse);
    });

    test('ações do pedido por estado', () {
      expect(casaAcoesPedido('disputa'),
          containsAll(['resolver_disputa', 'reatribuir', 'cancelar', 'teste']));
      expect(casaAcoesPedido('confirmado'), isNot(contains('cancelar')));
      expect(casaAcoesPedido('cancelado'), {'teste'});
      expect(casaAcoesPedido('procura'), isNot(contains('forcar_conclusao')));
      expect(casaAcoesPedido('em_curso'), contains('forcar_conclusao'));
    });

    test('acerto: Bora paga, Bora recebe, ou nada', () {
      expect(casaAcertoAcao({'status': 'pending', 'direction': 'bora_to_handyman'}), 'paid');
      expect(casaAcertoAcao({'status': 'pending', 'direction': 'handyman_to_bora'}), 'received');
      expect(casaAcertoAcao({'status': 'paid', 'direction': 'bora_to_handyman'}), isNull);
      expect(casaAcertoAcao({'status': 'pending', 'direction': 'zero'}), isNull);
    });

    test('confirmação forte: só com o texto exigido', () {
      expect(CasaConfirmarDialog.podeConfirmar(escrito: 'ligar', exigido: 'LIGAR'), isTrue);
      expect(CasaConfirmarDialog.podeConfirmar(escrito: 'LIGA', exigido: 'LIGAR'), isFalse);
      expect(CasaConfirmarDialog.podeConfirmar(escrito: 'ok', obrigatorio: true), isFalse);
      expect(CasaConfirmarDialog.podeConfirmar(escrito: 'documento falso', obrigatorio: true), isTrue);
      expect(casaTemAutorizo('Eu AUTORIZO os preços'), isTrue);
      expect(casaTemAutorizo('pode avançar'), isFalse);
      expect(casaTextoAutorizacao(' autorizo tudo ', DateTime.utc(2026, 11, 2)),
          'autorizo tudo (dito pelo Danilo em 02/11/2026)');
    });
  });

  group('catálogo e configurações (puro)', () {
    test('perguntas em JSON: válidas e inválidas', () {
      final ok = casaLerPerguntas(
          '[{"id":"a","texto":"Que móvel?","tipo":"texto"},'
          '{"id":"b","texto":"Marca?","tipo":"escolha","opcoes":["IKEA","Outra"]}]');
      expect(ok.erro, isNull);
      expect(ok.lista, hasLength(2));
      expect(ok.lista![1]['opcoes'], ['IKEA', 'Outra']);
      expect(casaLerPerguntas('').lista, isEmpty);
      expect(casaLerPerguntas('{').erro, isNotNull);
      expect(casaLerPerguntas('{"id":"a"}').erro, contains('lista'));
      expect(casaLerPerguntas('[{"id":"a","texto":"x","tipo":"escolha"}]').erro,
          contains('opcoes'));
      expect(
          casaLerPerguntas(
                  '[{"id":"a","texto":"x"},{"id":"a","texto":"y"}]')
              .erro,
          contains('repetido'));
    });

    test('serviço: preço obrigatório fora do orçamento; quantidades', () {
      final base = {
        'oficio': 'montagem',
        'nome': 'Montar um móvel',
        'modo': 'fixo',
        'preco_cents': 2500,
        'min_quantidade': 1,
        'max_quantidade': 10,
        'duracao_min': 60,
      };
      expect(casaValidarServico(base), isNull);
      expect(casaValidarServico({...base, 'preco_cents': null}), contains('preço'));
      expect(casaValidarServico({...base, 'modo': 'orcamento'}), isNotNull);
      expect(
          casaValidarServico({...base, 'modo': 'orcamento', 'preco_cents': null}),
          isNull);
      expect(casaValidarServico({...base, 'max_quantidade': 0.5}), isNotNull);
      expect(casaMudaValores(base, {...base, 'nome': 'Outro nome'}), isFalse);
      expect(casaMudaValores(base, {...base, 'preco_cents': 3000}), isTrue);
      expect(casaMudaValores(null, base), isTrue);
    });

    test('definições: grupo, tipo do valor e testadores', () {
      expect(casaGrupoDefinicao('casa_enabled'), 'interruptor');
      expect(casaGrupoDefinicao('casa_bora_pct'), 'proposta');
      expect(casaGrupoDefinicao('casa_promo_meses'), 'proposta');
      expect(casaGrupoDefinicao('casa_testadores'), 'testadores');
      expect(casaGrupoDefinicao('casa_oferta_segundos'), 'tempos');
      expect(casaLerValorDefinicao(60, '90'), 90);
      expect(casaLerValorDefinicao(15.5, '12,5'), 12.5);
      expect(casaLerValorDefinicao(true, 'não'), isFalse);
      expect(casaLerValorDefinicao('a', ' b '), 'b');
      expect(casaLerValorDefinicao(const ['x'], '["y"]'), ['y']);
      expect(() => casaLerValorDefinicao(60, 'muito'),
          throwsA(isA<FormatException>()));
      expect(casaEhUuid('9b2f6c1e-1d2a-4c3b-8e9f-0a1b2c3d4e5f'), isTrue);
      expect(casaEhUuid('joao@x.pt'), isFalse);
    });

    test('CSV: todas as colunas, objetos em JSON, vazio para nulo', () {
      final csv = casaLinhasParaCsv([
        {'id': 'p1', 'total_cents': 2500, 'extras': null},
        {'id': 'p2', 'total_cents': 3000, 'respostas': {'a': 1}},
      ]);
      expect(csv.headers, ['id', 'total_cents', 'extras', 'respostas']);
      expect(csv.rows[0], ['p1', 2500, '', '']);
      expect(csv.rows[1], ['p2', 3000, '', '{"a":1}']);
    });

    test('orçamentos: contagens e tempo médio', () {
      final r = casaResumoOrcamentos([
        {'estado': 'aceite', 'ganhou': true, 'tempo_resposta_min': 30},
        {'estado': 'expirado', 'ganhou': false, 'tempo_resposta_min': null},
        {'estado': 'enviado', 'ganhou': false, 'tempo_resposta_min': 90},
      ]);
      expect(r.total, 3);
      expect(r.ganhos, 1);
      expect(r.expirados, 1);
      expect(r.abertos, 1);
      expect(r.mediaMin, 60);
      expect(casaMinutosPtBr(125), '2 h 05 min');
      expect(casaMinutosPtBr(45), '45 min');
    });
  });

  group('ecrãs (sem rede)', () {
    testWidgets('Resumo: PROPOSTA em destaque, zeros aparecem, contador abre a aba',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_resumo': {
          'enabled': false,
          'valores_autorizados': {'autorizado': false},
          'profissionais_pendentes': 2,
          'orcamentos_abertos': 0,
          'disputas': 0,
        },
      });
      int? aba;
      await tester.pumpWidget(_app(
          AdminCasaResumoTab(rpc: rpc.call, onIrPara: (i) => aba = i)));
      await tester.pumpAndSettle();
      expect(find.text(kCasaTextoProposta), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-valores-proposta')), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-resumo-desligada')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('casa-resumo-disputas'))).data,
          '0');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('casa-resumo-profissionais_pendentes')))
              .data,
          '2');
      await tester.tap(find.text('Orçamentos abertos'));
      expect(aba, 3);
    });

    testWidgets('Resumo: valores autorizados aparecem em verde', (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_resumo': {
          'enabled': true,
          'valores_autorizados': {
            'autorizado': true,
            'em': '2026-11-02T10:00:00Z',
            'texto': 'autorizo',
          },
        },
      });
      await tester.pumpWidget(_app(AdminCasaResumoTab(rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.text('Valores AUTORIZADOS'), findsOneWidget);
      expect(find.text(kCasaTextoProposta), findsNothing);
      expect(find.byKey(const ValueKey('casa-resumo-ligada')), findsOneWidget);
    });

    testWidgets('Configurações: ligar o interruptor pede LIGAR antes de chamar',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_definicoes': [
          {'key': 'casa_enabled', 'value': false, 'description': 'Casa ligada'},
          {'key': 'casa_bora_pct', 'value': 15, 'description': 'Comissão da Bora (%)'},
          {'key': 'casa_testadores', 'value': <String>[], 'description': 'Testadores'},
          {'key': 'casa_oferta_segundos', 'value': 60, 'description': 'Tempo da oferta (s)'},
        ],
        'admin_casa_resumo': {
          'enabled': false,
          'valores_autorizados': {'autorizado': false},
        },
        'admin_casa_interruptor': {'ok': true},
      });
      await tester.pumpWidget(_app(AdminCasaDefinicoesTab(rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.text('Casa DESLIGADA (só os testadores veem)'), findsOneWidget);
      expect(find.text('PROPOSTA'), findsOneWidget); // a linha da comissão
      expect(find.text('Comissão e promoção — PROPOSTA'), findsOneWidget);

      // 1.ª vez: abre a confirmação, o botão nasce desligado, "Voltar" não chama.
      await tester.tap(find.byKey(const ValueKey('casa-interruptor')));
      await tester.pumpAndSettle();
      expect(find.text('LIGAR a Casa para todos os clientes?'), findsOneWidget);
      FilledButton ok() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('casa-confirmar-ok')));
      expect(ok().onPressed, isNull);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_interruptor'), isEmpty);

      // 2.ª vez: escreve LIGAR e confirma.
      await tester.tap(find.byKey(const ValueKey('casa-interruptor')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('casa-confirmar-texto')), 'liga');
      await tester.pump();
      expect(ok().onPressed, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('casa-confirmar-texto')), 'ligar');
      await tester.pump();
      expect(ok().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_interruptor'), [
        {'p_ligado': true}
      ]);
    });

    testWidgets('Registrar autorização: exige "autorizo" e junta a data',
        (tester) async {
      String? resultado = 'nada';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  resultado = await showDialog<String>(
                    context: ctx,
                    builder: (_) =>
                        CasaAutorizarDialog(hoje: DateTime.utc(2026, 10, 31)),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      FilledButton ok() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('casa-autorizo-ok')));
      expect(ok().onPressed, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('casa-autorizo-texto')), 'pode avançar');
      await tester.pump();
      expect(ok().onPressed, isNull);
      expect(find.text('Falta a palavra "autorizo"'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('casa-autorizo-texto')),
          'Autorizo os preços da Casa');
      await tester.pump();
      expect(ok().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('casa-autorizo-ok')));
      await tester.pumpAndSettle();
      expect(resultado,
          'Autorizo os preços da Casa (dito pelo Danilo em 31/10/2026)');
    });

    testWidgets('Catálogo: aviso de preço sempre à vista e PROPOSTA',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_catalogo': {
          'valores_autorizados': {'autorizado': false},
          'oficios': [
            {'codigo': 'montagem', 'nome': 'Montagem de móveis', 'fase': 1, 'ativo': true, 'ordem': 10},
            {'codigo': 'eletricidade', 'nome': 'Eletricidade', 'fase': 2, 'documento_exigido': 'dgeg_eletricidade', 'ativo': false, 'ordem': 70},
          ],
          'servicos': [
            {'id': 's1', 'oficio': 'montagem', 'nome': 'Montar um móvel', 'modo': 'fixo', 'preco_cents': 2500, 'unidade': 'movel', 'min_quantidade': 1, 'max_quantidade': 10, 'duracao_min': 60, 'perguntas': [], 'ativo': true},
          ],
        },
        'admin_casa_guardar_oficio': {'ok': true},
      });
      await tester.pumpWidget(_app(AdminCasaCatalogoTab(rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('casa-catalogo-aviso-preco')), findsOneWidget);
      expect(find.textContaining(kCasaAvisoMudarPreco), findsOneWidget);
      expect(find.text(kCasaTextoProposta), findsOneWidget);
      expect(find.text('Montar um móvel'), findsOneWidget);
      expect(find.textContaining('25,00 €'), findsOneWidget);

      // Ligar o ofício da fase 2 pede confirmação e avisa do documento.
      await tester.tap(find.byKey(const ValueKey('casa-oficio-ativo-eletricidade')));
      await tester.pumpAndSettle();
      expect(find.textContaining('DGEG/IMPIC'), findsOneWidget);
      expect(rpc.de('admin_casa_guardar_oficio'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_guardar_oficio'), [
        {'p_codigo': 'eletricidade', 'p_ativo': true}
      ]);
    });

    testWidgets('Ficha do profissional: fase 2 travada e recusar pede motivo',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_profissional': {
          'perfil': {'id': 'p1', 'name': 'Rui Faz-Tudo', 'approval_status': 'pending'},
          'oficios': [
            {'codigo': 'montagem', 'nome': 'Montagem de móveis', 'fase': 1, 'estado': 'pending'},
            {'codigo': 'eletricidade', 'nome': 'Eletricidade', 'fase': 2, 'documento_exigido': 'dgeg_eletricidade', 'estado': 'pending'},
          ],
          'documentos': [
            {'id': 'd1', 'tipo': 'dgeg_eletricidade', 'oficio': 'eletricidade', 'estado': 'pending', 'storage_path': 'u1/dgeg_1.jpg'},
          ],
          'disponibilidade': [
            {'weekday': 1, 'start': '09:00', 'end': '18:00'},
          ],
          'pedidos': [],
          'atividade_status': 'em_analise',
          'conformidade_em_falta': ['iban'],
        },
        'admin_casa_decidir_profissional': {'ok': true},
      });
      await tester.pumpWidget(MaterialApp(
          home: AdminCasaProfissionalScreen(id: 'p1', rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.text('Rui Faz-Tudo'), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-oficio-fase2-eletricidade')),
          findsOneWidget);
      expect(find.textContaining('Fase 2: só se aprova'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('casa-oficio-aprovar-eletricidade')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('casa-oficio-aprovar-montagem')))
              .onPressed,
          isNotNull);
      expect(find.text('Segunda'), findsOneWidget);
      // O que falta da conformidade aparece a vermelho, com o rótulo legal.
      expect(find.text('Ainda falta'), findsOneWidget);
      expect(find.text('Comprovativo de atividade em análise'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('casa-prof-acao-recusar')));
      await tester.pumpAndSettle();
      FilledButton ok() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('casa-confirmar-ok')));
      expect(ok().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('casa-confirmar-texto')),
          'Documento ilegível');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_decidir_profissional'), [
        {'p_id': 'p1', 'p_acao': 'recusar', 'p_motivo': 'Documento ilegível'}
      ]);
    });

    testWidgets('Ficha do pedido: resolver disputa escolhe e confirma',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_pedido': {
          'id': 'x1',
          'estado': 'disputa',
          'servico_nome': 'Montar um móvel',
          'oficio': 'montagem',
          'modo': 'fixo',
          'total_cents': 2500,
          'morada': {'street': 'Rua A', 'city': 'Guarda', 'postal': '6300-000'},
          'cliente': {'nome': 'Ana'},
          'profissional': {'id': 'p1', 'name': 'Rui'},
          'eventos': [
            {'estado_de': 'concluido', 'estado_para': 'disputa', 'por_papel': 'client', 'created_at': '2026-10-31T10:00:00Z'},
          ],
        },
        'admin_casa_resolver_disputa': {'ok': true},
      });
      await tester.pumpWidget(
          MaterialApp(home: AdminCasaPedidoScreen(id: 'x1', rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Disputa'), findsWidgets);
      expect(find.text('Concluído (aguardando o cliente) → Disputa (cliente pediu para refazer)'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('casa-pedido-disputa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCasaResolucoes['refeito']!));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_resolver_disputa'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('casa-confirmar-texto')),
          'Voltou e refez a porta');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_resolver_disputa'), [
        {'p_pedido_id': 'x1', 'p_resolucao': 'refeito', 'p_nota': 'Voltou e refez a porta'}
      ]);
    });

    testWidgets('Acertos: última semana fechada em Lisboa e marcar pago confirma',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_acertos': [
          {
            'id': 'a1',
            'profissional_nome': 'Rui',
            'net_payout_cents': 4250,
            'direction': 'bora_to_handyman',
            'status': 'pending',
            'total_jobs': 3,
            'week_start_at': '2026-10-18T23:00:00Z',
            'week_end_at': '2026-10-25T23:59:59Z',
          },
        ],
        'admin_casa_acerto_marcar': {'ok': true},
      });
      await tester.pumpWidget(_app(AdminCasaAcertosTab(
          rpc: rpc.call, agora: DateTime.utc(2026, 10, 31, 12))));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_acertos').first, {'p_week_start': '2026-10-19'});
      expect(find.text('Semana 19/10 a 25/10'), findsOneWidget);
      expect(find.textContaining('19/10/2026 00:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('casa-acerto-marcar-a1')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text('42,50 €')),
          findsOneWidget);
      expect(rpc.de('admin_casa_acerto_marcar'), isEmpty);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Marcar pago')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_acerto_marcar'), [
        {
          'p_id': 'a1',
          'p_status': 'paid',
          'p_payment_method': 'transferencia',
          'p_reference': '',
        }
      ]);
    });

    testWidgets('Exportar: datas de Lisboa e CSV pelo serviço comum',
        (tester) async {
      final rpc = _Rpc({
        'admin_casa_exportar': [
          {'id': 'x1', 'total_cents': 2500},
        ],
      });
      String? nome;
      List<String>? cab;
      await tester.pumpWidget(_app(AdminCasaExportarTab(
        rpc: rpc.call,
        agora: DateTime.utc(2026, 10, 31, 12),
        gravar: ({required filename, required headers, required rows, subject}) async {
          nome = filename;
          cab = headers;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('casa-exportar-botao')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_exportar'), [
        {'p_tipo': 'pedidos', 'p_de': '2026-10-01', 'p_ate': '2026-10-31'}
      ]);
      expect(nome, 'bora_casa_pedidos_2026-10-01_2026-10-31.csv');
      expect(cab, ['id', 'total_cents']);
    });

    testWidgets('Orçamentos: resumo e quem ganhou', (tester) async {
      final rpc = _Rpc({
        'admin_casa_orcamentos': [
          {'id': 'o1', 'pedido_id': 'x1', 'servico_nome': 'Mudança', 'profissional_nome': 'Rui', 'preco_cents': 8000, 'estado': 'aceite', 'ganhou': true, 'tempo_resposta_min': 20},
          {'id': 'o2', 'pedido_id': 'x1', 'servico_nome': 'Mudança', 'profissional_nome': 'Zé', 'preco_cents': 9000, 'estado': 'recusado', 'ganhou': false, 'tempo_resposta_min': 40},
        ],
      });
      await tester.pumpWidget(_app(AdminCasaOrcamentosTab(rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('casa-orcamentos-resumo')), findsOneWidget);
      expect(find.textContaining('1 ganharam'), findsOneWidget);
      expect(find.textContaining('resposta média 30 min'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('Hub: 8 separadores e abre a ficha pedida', (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_resumo': {'enabled': false, 'valores_autorizados': {'autorizado': false}},
        'admin_casa_profissional': {
          'perfil': {'id': 'p9', 'name': 'Maria Jardim', 'approval_status': 'approved'},
        },
      });
      await tester.pumpWidget(
          MaterialApp(home: AdminCasaScreen(profissionalId: 'p9', rpc: rpc.call)));
      await tester.pumpAndSettle();
      expect(find.text('Profissional da Casa'), findsOneWidget);
      expect(find.text('Maria Jardim'), findsOneWidget);
      expect(rpc.de('admin_casa_profissional'), [
        {'p_id': 'p9'}
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(kCasaSeparadores, hasLength(8));
      for (final t in kCasaSeparadores) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });
  });

  group('menu do painel', () {
    test('a Casa vive na secção "limpeza" (id igual) e a busca encontra', () {
      final limpeza = adminMenuSections().firstWhere((s) => s.id == 'limpeza');
      expect(limpeza.title, contains('Casa'));
      final casa = limpeza.items.where((i) => i.id == 'limpeza_casa').toList();
      expect(casa, hasLength(1));
      expect(casa.single.title, 'Casa e manutenção');
      expect(casa.single.builder(), isA<AdminCasaScreen>());
      expect(
          adminMenuAllItems().where((i) => i.matches('faz-tudo')).map((i) => i.title),
          contains('Casa e manutenção'));
    });
  });
}
