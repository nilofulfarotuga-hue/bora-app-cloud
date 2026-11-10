// Bloco G da missão fechar-tudo-2026-11-10 — check-in a fundo.
// Regras (R2 desbloqueio, R3 reinício só da escada, R4 sugestão, R5 perdão 1/mês
// só com compra, R6 aviso aos 80%, R8 parar depois de 3 falhas) e os ecrãs novos
// (caminho dos 30 dias, barra do próximo prémio, festa do degrau, avisos do
// perdão, botão do lembrete). O servidor decide; a prova SQL das mesmas regras
// está em docs/propostas/fechar-tudo-2026-11-10/G_prova_pglite.mjs.
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/services/checkin_service.dart';
import 'package:bora_app/utils/checkin_regras.dart';
import 'package:bora_app/widgets/checkin/checkin_barra_proximo.dart';
import 'package:bora_app/widgets/checkin/checkin_caminho.dart';
import 'package:bora_app/widgets/checkin/checkin_festa_premio.dart';
import 'package:bora_app/widgets/home/checkin_diario_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _marcosJson = <Map<String, dynamic>>[
  {'chave': 'semana', 'dia': 7, 'tipo': 'tokens', 'titulo': 'os tokens do Dia 7', 'tokens': 40},
  {
    'chave': 'leonidas_barra', 'dia': 8, 'tipo': 'produto', 'titulo': 'uma barra de chocolate Leonidas',
    'valor_cents': 280, 'foto_url': 'https://exemplo.invalid/barra.jpg', 'loja_nome': 'Leonidas', 'loja_id': 'leonidas-guarda',
  },
  {
    'chave': 'salgados', 'dia': 14, 'tipo': 'produto', 'titulo': '2 salgados da Keli', 'valor_cents': 630,
    'foto_url': 'https://exemplo.invalid/salgados.jpg', 'loja_nome': 'Sabores do Brasil', 'loja_id': 'sabores-brasil-guarda',
  },
  {
    'chave': 'acai', 'dia': 19, 'tipo': 'produto', 'titulo': 'um açaí do Goola', 'valor_cents': 922,
    'foto_url': 'https://exemplo.invalid/acai.jpg', 'loja_nome': 'Goola Açaí', 'loja_id': 'goola-acai-guarda',
  },
  {
    'chave': 'boom_mes', 'dia': 28, 'tipo': 'produto', 'titulo': 'o hambúrguer do mês da Boom', 'valor_cents': 1610,
    'loja_nome': 'Boom! Burger', 'loja_id': 'boom-burger-guarda',
  },
  {'chave': 'mes', 'dia': 30, 'tipo': 'servico', 'titulo': '2 horas de limpeza ou uma lavagem exterior do carro'},
];

Map<String, dynamic> _estadoJson({
  int dias = 16,
  bool hojeFeito = false,
  List<int> perdoados = const [],
  bool pendente = false,
  String? avisoDia,
  bool precisaPedido = false,
  Map<String, dynamic>? escada,
  Map<String, dynamic>? sugestao,
}) =>
    {
      'ok': true,
      'marcos_ativos': true,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': dias,
      'hoje_feito': hojeFeito,
      'tokens_por_dia': [5, 5, 10, 10, 15, 15, 40],
      'marcos': _marcosJson,
      'precisa_pedido': precisaPedido,
      'sugestao': sugestao,
      'perdao': {
        'ativo': true,
        'por_mes': 1,
        'usados_mes': perdoados.length,
        'disponivel': perdoados.isEmpty,
        'pendente': pendente,
        'aviso_dia': avisoDia,
        'dias': perdoados,
      },
      'lembrete': {'ligado': true, 'hora': 9},
      'escada': escada ?? {'ativa': true, 'texto': ''},
      'texto': '',
      'vales': const [],
      'novos': const [],
    };

CheckinMarco _m(String chave) =>
    CheckinMarco.fromJson(_marcosJson.firstWhere((m) => m['chave'] == chave).cast<String, dynamic>());

const _semana = CheckinEstado(
  enabled: true,
  eligible: true,
  reason: null,
  alreadyDone: false,
  streakDay: 3,
  tokensToday: 10,
  nextDay: 3,
  nextReward: 10,
  rewards: [5, 5, 10, 10, 15, 15, 40],
);

void main() {
  group('R2 — todo o prémio espera 1 pedido pago', () {
    test('vale à espera do pedido: "Falta 1 pedido para desbloquear"', () {
      final v = CheckinVale.fromJson({'id': 'e1', 'marco': 8, 'chave': 'leonidas_barra', 'tipo': 'produto',
          'estado': 'a_espera_pedido', 'titulo': 'barra'});
      expect(faltaPedido(v), isTrue);
      expect(v.usavel, isFalse, reason: 'não se usa no carrinho');
      expect(v.ativo, isTrue, reason: 'fica guardado em "Por usar"');
      expect(textoEstadoVale(v), 'Falta 1 pedido para desbloquear o prémio');
      final desbloqueado = CheckinVale.fromJson({'id': 'e1', 'tipo': 'produto', 'estado': 'por_usar'});
      expect(faltaPedido(desbloqueado), isFalse, reason: 'depois de comprar, desbloqueia');
      expect(desbloqueado.usavel, isTrue);
    });

    test('o estado diz quando falta o pedido', () {
      expect(CheckinPremiosEstado.fromJson(_estadoJson(precisaPedido: true)).precisaPedido, isTrue);
      expect(CheckinPremiosEstado.fromJson(_estadoJson()).precisaPedido, isFalse);
      expect(CheckinPremiosEstado.fromJson(const {'ok': true}).precisaPedido, isFalse,
          reason: 'servidor antigo: nada muda');
    });
  });

  group('R3 — "Quero este" recomeça só a escada', () {
    test('a escada volta ao dia 1; a semana de tokens continua', () {
      final r = depoisDeQueroEste(diaSemanaHoje: 3, recomecaSemana: false);
      expect(r.diaEscadaAmanha, 1);
      expect(r.diaSemanaAmanha, 4, reason: 'os tokens seguem o seu ciclo de 7 dias');
      expect(depoisDeQueroEste(diaSemanaHoje: 7, recomecaSemana: false).diaSemanaAmanha, 1);
    });

    test('com o interruptor do painel, a semana também recomeça', () {
      expect(depoisDeQueroEste(diaSemanaHoje: 5, recomecaSemana: true).diaSemanaAmanha, 1);
    });

    test('a resposta do servidor muda a escada e mantém os tokens de cada dia', () {
      final antes = CheckinPremiosEstado.fromJson(_estadoJson(dias: 14, hojeFeito: true));
      final depois = antes.juntar(CheckinPremiosEstado.fromJson(
          _estadoJson(dias: 0, hojeFeito: false)..remove('tokens_por_dia')));
      expect(depois.diaMarco, 0);
      expect(depois.diaDeHoje, 1, reason: 'amanhã a escada é o dia 1');
      expect(depois.tokensPorDia, [5, 5, 10, 10, 15, 15, 40]);
    });
  });

  group('R4 — a melhor sugestão (uma só)', () {
    final marcos = [for (final m in _marcosJson) CheckinMarco.fromJson(m.cast<String, dynamic>())];

    test('o mais valioso a que já chegou', () {
      expect(melhorSugestao(marcos, 19)?.chave, 'acai');
      expect(melhorSugestao(marcos, 14)?.chave, 'salgados');
      expect(melhorSugestao(marcos, 7), isNull, reason: 'os tokens do Dia 7 não são prémio');
    });

    test('entre iguais, a loja onde mais pediu; depois o dia mais alto', () {
      final iguais = [
        CheckinMarco.fromJson({'chave': 'a', 'dia': 10, 'tipo': 'produto', 'titulo': 'A', 'valor_cents': 500, 'loja_id': 'x'}),
        CheckinMarco.fromJson({'chave': 'b', 'dia': 12, 'tipo': 'produto', 'titulo': 'B', 'valor_cents': 500, 'loja_id': 'y'}),
      ];
      expect(melhorSugestao(iguais, 12, pedidosPorLoja: {'x': 3, 'y': 1})?.chave, 'a');
      expect(melhorSugestao(iguais, 12, pedidosPorLoja: {'x': 0, 'y': 2})?.chave, 'b');
      expect(melhorSugestao(iguais, 12)?.chave, 'b', reason: 'sem pedidos: o do dia mais alto');
    });

    test('o serviço do dia 30 (sem valor no painel) conta como o maior', () {
      expect(melhorSugestao(marcos, 30)?.chave, 'mes');
      expect(valorParaComparar(null), greaterThan(valorParaComparar(1610)));
    });

    test('a sugestão do servidor chega ao modelo com foto e valor', () {
      final e = CheckinPremiosEstado.fromJson(_estadoJson(sugestao: _marcosJson[3]));
      expect(e.sugestao?.chave, 'acai');
      expect(e.sugestao?.valorCents, 922);
      expect(e.sugestao?.fotoUrl, 'https://exemplo.invalid/acai.jpg');
    });
  });

  group('R5 — perdão: 1 dia por mês, só com compra', () {
    test('só com pedido pago, só 1 por mês, só 1 dia falhado', () {
      bool pode({bool ativo = true, bool compra = true, int usados = 0, int porMes = 1, int falhados = 1}) =>
          perdaoPodeAplicar(ativo: ativo, temPedidoPago: compra, usadosNoMes: usados, porMes: porMes, diasFalhados: falhados);
      expect(pode(), isTrue);
      expect(pode(compra: false), isFalse, reason: 'sem compra não há perdão');
      expect(pode(usados: 1), isFalse, reason: 'só 1 por mês');
      expect(pode(usados: 1, porMes: 2), isTrue);
      expect(pode(falhados: 2), isFalse, reason: 'perdoa um dia, não dois');
      expect(pode(ativo: false), isFalse, reason: 'interruptor do painel');
    });

    test('o dia perdoado fica com gelo; os outros feitos com chama', () {
      expect(estadoDoDia(dia: 9, feitoAte: 12, hoje: 13, perdoados: [9]), EstadoDiaCaminho.perdoado);
      expect(estadoDoDia(dia: 10, feitoAte: 12, hoje: 13, perdoados: [9]), EstadoDiaCaminho.feito);
      expect(estadoDoDia(dia: 13, feitoAte: 12, hoje: 13), EstadoDiaCaminho.hoje);
      expect(estadoDoDia(dia: 14, feitoAte: 12, hoje: 13), EstadoDiaCaminho.futuro);
    });

    test('o modelo lê o perdão (pendente, aviso por ver e dias com gelo)', () {
      final e = CheckinPremiosEstado.fromJson(
          _estadoJson(perdoados: [9], pendente: false, avisoDia: '2026-11-09'));
      expect(e.perdao!.dias, [9]);
      expect(e.perdao!.temAviso, isTrue);
      expect(e.perdao!.disponivel, isFalse, reason: 'já usou o deste mês');
    });
  });

  group('R6 — teto de custo do mês, aviso aos 80%', () {
    test('abaixo de 80% está bem; a 80% avisa; no teto esgota', () {
      expect(nivelTecto(custoCents: 7900, tectoCents: 10000, avisoPct: 80).nivel, NivelTecto.ok);
      final a = nivelTecto(custoCents: 8000, tectoCents: 10000, avisoPct: 80);
      expect(a.nivel, NivelTecto.aviso);
      expect(a.pct, 80);
      expect(nivelTecto(custoCents: 10000, tectoCents: 10000, avisoPct: 80).nivel, NivelTecto.esgotado);
      expect(nivelTecto(custoCents: 500, tectoCents: 0, avisoPct: 80).nivel, NivelTecto.semTecto);
      expect(nivelTecto(custoCents: 9000, tectoCents: 10000, avisoPct: 80, ativo: false).nivel, NivelTecto.semTecto);
    });
  });

  group('R8 — lembrete: 1 por dia, pára depois de 3 falhas', () {
    final hoje = DateTime(2026, 11, 10, 9);
    bool recebe(DateTime? ult, {int max = 3, bool desligado = false, bool jaRecebeu = false}) => deveReceberLembrete(
        ultimoCheckin: ult, hoje: hoje, maxFalhas: max, desligado: desligado, jaRecebeuHoje: jaRecebeu);

    test('fez ontem ou falhou 1-2 dias: recebe; falhou 3: pára', () {
      expect(recebe(DateTime(2026, 11, 9)), isTrue);
      expect(recebe(DateTime(2026, 11, 8)), isTrue);
      expect(recebe(DateTime(2026, 11, 7)), isTrue, reason: 'falhou 2 dias');
      expect(recebe(DateTime(2026, 11, 6)), isFalse, reason: 'falhou 3 dias seguidos');
    });

    test('já fez hoje, desligou, já recebeu hoje ou nunca fez: não recebe', () {
      expect(recebe(DateTime(2026, 11, 10)), isFalse);
      expect(recebe(DateTime(2026, 11, 9), desligado: true), isFalse);
      expect(recebe(DateTime(2026, 11, 9), jaRecebeu: true), isFalse, reason: 'no máximo 1 por dia');
      expect(recebe(null), isFalse);
    });

    test('com 1 falha máxima é a regra de 18/10 (só a quem fez ontem)', () {
      expect(recebe(DateTime(2026, 11, 9), max: 1), isTrue);
      expect(recebe(DateTime(2026, 11, 8), max: 1), isFalse);
    });

    test('o modelo lê o lembrete (ligado e hora habitual)', () {
      final e = CheckinPremiosEstado.fromJson(_estadoJson());
      expect(e.lembrete!.ligado, isTrue);
      expect(e.lembrete!.hora, 9);
    });
  });

  group('barra do próximo prémio', () {
    test('no dia 16 faltam 3 dias para o açaí (dia 19)', () {
      final p = proximoPremio(CheckinPremiosEstado.fromJson(_estadoJson(dias: 16)))!;
      expect(p.marco.chave, 'acai');
      expect(p.faltam, 3);
      expect(p.progresso, closeTo(2 / 5, 0.001), reason: 'do dia 14 (salgados) ao 19');
    });

    test('sem sequência, o primeiro prémio; depois do último, nada', () {
      expect(proximoPremio(CheckinPremiosEstado.fromJson(_estadoJson(dias: 0)))!.marco.chave, 'leonidas_barra');
      expect(proximoPremio(CheckinPremiosEstado.fromJson(_estadoJson(dias: 30))), isNull);
    });

    testWidgets('mostra a foto, "Faltam 3 dias para um açaí do Goola" e o valor', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CheckinBarraProximo(marco: _m('acai'), faltam: 3, progresso: 0.4),
        ),
      ));
      await t.pump();
      expect(find.text('Faltam 3 dias para um açaí do Goola'), findsOneWidget);
      expect(find.text('Vale 9,22 € · Goola Açaí'), findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(find.byKey(const Key('checkin_barra_progresso'))).value, 0.4);
      expect(find.byType(Image), findsOneWidget, reason: 'a foto real do prémio');
    });

    testWidgets('sem pedido pago, avisa que falta 1 pedido', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: CheckinBarraProximo(marco: _m('acai'), faltam: 1, progresso: 0.8, precisaPedido: true)),
      ));
      await t.pump();
      expect(find.text('Falta 1 dia para um açaí do Goola'), findsOneWidget);
      expect(find.text('Falta 1 pedido para desbloquear o prémio'), findsOneWidget);
    });
  });

  group('caminho dos 30 dias', () {
    testWidgets('chama nos feitos, gelo no perdoado, hoje a brilhar, foto e valor nos prémios', (t) async {
      final e = CheckinPremiosEstado.fromJson(_estadoJson(dias: 12, perdoados: [9]));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 300, child: CheckinCaminho(dias: diasDoCaminho(e, feitoAte: 12, hoje: 13))),
          ),
        ),
      ));
      await t.pump();
      Finder no(int d) => find.byKey(Key('checkin_caminho_dia_$d'));
      for (var d = 1; d <= 30; d++) {
        expect(no(d), findsOneWidget);
      }
      expect(find.byKey(const Key('checkin_caminho_dia_31')), findsNothing);
      expect(find.descendant(of: no(10), matching: find.byIcon(Icons.local_fire_department_rounded)), findsOneWidget);
      expect(find.descendant(of: no(9), matching: find.byIcon(Icons.ac_unit_rounded)), findsOneWidget);
      final hoje = t.widget<Container>(no(13)).decoration! as BoxDecoration;
      expect(hoje.boxShadow, isNotEmpty, reason: 'hoje a brilhar');
      expect(find.descendant(of: no(14), matching: find.byType(Image)), findsOneWidget, reason: 'foto dos salgados');
      expect(find.text('6,30 €'), findsOneWidget, reason: 'valor dos salgados à vista');
      expect(find.text('16,10 €'), findsOneWidget);
      expect(find.byKey(const Key('checkin_caminho_marco_7')), findsOneWidget);
      expect(find.byKey(const Key('checkin_caminho_marco_30')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('festa do degrau (R3)', () {
    final guardado = CheckinDegrau.fromJson({
      'chave': 'salgados', 'dia': 14, 'titulo': '2 salgados da Keli', 'tipo': 'produto', 'valor_cents': 630,
      'foto_url': 'https://exemplo.invalid/salgados.jpg', 'loja_nome': 'Sabores do Brasil',
    })!;
    final proximo = CheckinDegrau.fromJson({
      'chave': 'acai', 'dia': 19, 'titulo': 'um açaí do Goola', 'tipo': 'produto', 'faltam': 5,
      'foto_url': 'https://exemplo.invalid/acai.jpg',
    })!;

    testWidgets('o prémio em grande e os dois botões', (t) async {
      var quero = 0;
      var continuar = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CheckinFestaPremio(
              guardado: guardado,
              proximo: proximo,
              onQueroEste: () => quero++,
              onContinuar: () => continuar++,
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.byKey(const Key('checkin_festa_foto')), findsOneWidget);
      expect(find.text('Sabores do Brasil · vale 6,30 €'), findsOneWidget);
      expect(find.text('Quero este'), findsOneWidget);
      expect(find.text('Continuar para o próximo'), findsOneWidget);
      expect(find.text('um açaí do Goola daqui a 5 dias'), findsOneWidget);
      expect(find.byKey(const Key('checkin_falta_pedido')), findsNothing);
      await t.tap(find.byKey(const Key('btn_escada_levantar')));
      await t.tap(find.byKey(const Key('btn_escada_continuar')));
      expect((quero, continuar), (1, 1));
    });

    testWidgets('sem pedido pago: "Falta 1 pedido para desbloquear"; a decidir, os botões travam', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CheckinFestaPremio(guardado: guardado, onQueroEste: () {}, aDecidir: true, precisaPedido: true),
          ),
        ),
      ));
      await t.pump();
      expect(find.byKey(const Key('checkin_falta_pedido')), findsOneWidget);
      expect(find.byKey(const Key('btn_escada_continuar')), findsNothing, reason: 'sem próximo');
      expect(t.widget<FilledButton>(find.byKey(const Key('btn_escada_levantar'))).onPressed, isNull);
    });
  });

  group('cartão da home', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget cartao(CheckinPremiosEstado e, {Future<void> Function()? perdaoVisto, Future<bool> Function(bool)? lembrete}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CheckinDiarioCard(
                carregar: () async => _semana,
                carregarPremios: () async => e,
                marcarVistos: (_) async {},
                abrirPremios: (_) async {},
                festaEscada: () async {},
                marcarPerdaoVisto: perdaoVisto ?? () async {},
                definirLembrete: lembrete ?? (_) async => true,
              ),
            ),
          ),
        );

    testWidgets('barra do próximo prémio debaixo da semana', (t) async {
      await t.pumpWidget(cartao(CheckinPremiosEstado.fromJson(_estadoJson(dias: 16))));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_barra_proximo')), findsOneWidget);
      expect(find.text('Faltam 3 dias para um açaí do Goola'), findsOneWidget);
    });

    testWidgets('R5: "Usámos o teu perdão deste mês" aparece uma vez e marca como visto', (t) async {
      var vistos = 0;
      await t.pumpWidget(cartao(
        CheckinPremiosEstado.fromJson(_estadoJson(perdoados: [15], avisoDia: '2026-11-09')),
        perdaoVisto: () async => vistos++,
      ));
      await t.pump();
      await t.pump();
      expect(find.text('Usámos o teu perdão deste mês: a tua sequência continua.'), findsOneWidget);
      await t.tap(find.byKey(const Key('btn_perdao_ok')));
      await t.pump();
      expect(find.byKey(const Key('checkin_perdao_aviso')), findsNothing);
      expect(vistos, 1);
    });

    testWidgets('R5: falhou ontem com perdão disponível — avisa antes do check-in', (t) async {
      await t.pumpWidget(cartao(CheckinPremiosEstado.fromJson(_estadoJson(pendente: true))));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_perdao_pendente')), findsOneWidget);
    });

    testWidgets('R8: o lembrete desliga-se no mês aberto', (t) async {
      final pedidos = <bool>[];
      await t.pumpWidget(cartao(
        CheckinPremiosEstado.fromJson(_estadoJson()),
        lembrete: (v) async {
          pedidos.add(v);
          return true;
        },
      ));
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const Key('btn_checkin_mes')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('checkin_lembrete_switch')), 200);
      expect(find.text('Um aviso por dia, por volta das 9h, só enquanto vens fazer o check-in.'), findsOneWidget);
      await t.tap(find.byKey(const Key('checkin_lembrete_switch')));
      await t.pumpAndSettle();
      expect(pedidos, [false]);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('checkin_lembrete_switch'))).value, isFalse);
    });

    testWidgets('R2: na festa do degrau, sem pedido pago, "Falta 1 pedido para desbloquear"', (t) async {
      await t.pumpWidget(cartao(CheckinPremiosEstado.fromJson(_estadoJson(
        dias: 14,
        hojeFeito: true,
        precisaPedido: true,
        escada: {
          'ativa': true,
          'texto': '',
          'guardado': {
            'chave': 'salgados', 'dia': 14, 'titulo': '2 salgados da Keli', 'tipo': 'produto', 'valor_cents': 630,
            'guardado_em': '2026-11-10T10:00:00+00:00', 'garantido_ate': '2026-12-10T10:00:00+00:00',
          },
          'decisao': 'pendente',
          'pendente_decisao': true,
          'pode_continuar': true,
          'proximo_maior': {'chave': 'acai', 'dia': 19, 'titulo': 'um açaí do Goola', 'faltam': 5},
        },
      ))));
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_escada_escolha')), findsOneWidget);
      expect(find.byKey(const Key('checkin_falta_pedido')), findsOneWidget);
      await t.pumpAndSettle();
    });
  });
}
