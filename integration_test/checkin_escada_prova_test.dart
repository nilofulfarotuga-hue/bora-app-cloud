// PROVA VISUAL da escada de prémios do check-in (adendo 9, 29/10/2026).
// Sem login e sem escrever no banco: monta o cartão do check-in e o ecrã
// "Os meus prémios" com respostas de exemplo iguais às do servidor
// (`client_checkin_premios`, `client_checkin_escada_levantar/_continuar`) e pára
// em cada passo para o PC tirar a captura por adb.
//
// Cada paragem anuncia-se no log: "[prova] PRONTO <nome>". O guião do PC
// (`.claude/.ai/provas/checkin-escada-2026-10-29/capturar.ps1`) espera pela
// linha e fotografa.
//
// Corre-se como app normal (sem flutter drive):
//   flutter build apk --debug --target=integration_test/checkin_escada_prova_test.dart
//   powershell -File .claude/.ai/provas/checkin-escada-2026-10-29/capturar.ps1
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bora_app/screens/client/checkin_premios_screen.dart';
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/services/checkin_service.dart';
import 'package:bora_app/widgets/home/checkin_diario_card.dart';

const _segundosPorCaptura = 4;
const _recompensas = [5, 5, 10, 10, 15, 15, 40];

const _textoEscada =
    'Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.';

const _salgados = {'chave': 'salgados', 'dia': 10, 'titulo': '2 salgados da Keli', 'descricao': ''};
const _acai = {'chave': 'acai', 'dia': 15, 'titulo': 'um açaí do Goola', 'descricao': ''};
const _mes = {
  'chave': 'mes', 'dia': 30, 'titulo': '2 horas de limpeza ou uma lavagem exterior do carro', 'descricao': '',
};

/// Tokens do dia: o ciclo de 7 continua igual (o dia 10 da sequência é o Dia 3 dos tokens).
CheckinEstado _tokens({required int diaSequencia, required bool feito}) {
  final hoje = ((diaSequencia - 1) % 7) + 1;
  final amanha = (hoje % 7) + 1;
  return CheckinEstado(
    enabled: true,
    eligible: true,
    reason: null,
    alreadyDone: feito,
    streakDay: hoje,
    tokensToday: _recompensas[hoje - 1],
    nextDay: feito ? amanha : hoje,
    nextReward: _recompensas[(feito ? amanha : hoje) - 1],
    rewards: _recompensas,
  );
}

Map<String, dynamic> _guardado(Map<String, Object> marco, String guardadoEm) => {
      ...marco,
      'tipo': 'produto',
      'guardado_em': guardadoEm,
      'garantido_ate': '2026-11-28T10:00:00+00:00',
    };

Map<String, dynamic> _escada({
  Map<String, dynamic>? guardado,
  String? decisao,
  Map<String, Object>? proximo,
  int faltam = 0,
}) =>
    {
      'ativa': true,
      'texto': _textoEscada,
      'guardado': guardado,
      'decisao': decisao,
      'pendente_decisao': guardado != null && decisao == 'pendente' && proximo != null,
      'pode_continuar': guardado != null && proximo != null,
      'proximo_maior': proximo == null ? null : {...proximo, 'faltam': faltam},
      'ultimo_dia': 30,
      'levantados': 0,
      'reinicio_data': null,
      'ultimo_vale_id': null,
    };

/// O JSON de `client_checkin_premios()` para o dia [dias] da sequência.
Map<String, dynamic> _estadoJson({
  required int dias,
  required bool hojeFeito,
  required Map<String, dynamic> escada,
  List<String> novos = const [],
  List<Map<String, dynamic>> vales = const [],
}) =>
    {
      'ok': true,
      'marcos_ativos': true,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': dias,
      'ciclo_inicio': '2026-10-15',
      'hoje_feito': hojeFeito,
      'escada': escada,
      'texto': 'Faz o check-in todos os dias. Aos 10 dias seguidos chegas aos 2 salgados da Keli, aos 15 a um açaí do Goola e aos 30 a 2 horas de limpeza ou uma lavagem exterior do carro.',
      'marcos': [
        for (final m in const [
          ['semana', 7, 'tokens', 'os tokens do Dia 7'],
          ['salgados', 10, 'produto', '2 salgados da Keli'],
          ['acai', 15, 'produto', 'um açaí do Goola'],
          ['mes', 30, 'servico', '2 horas de limpeza ou uma lavagem exterior do carro'],
        ])
          {
            'chave': m[0], 'dia': m[1], 'tipo': m[2], 'titulo': m[3], 'descricao': '',
            'tokens': m[2] == 'tokens' ? 40 : null,
            'atingido': dias >= (m[1] as int),
            'faltam': dias >= (m[1] as int) ? 0 : (m[1] as int) - dias,
          },
      ],
      'proximo': null,
      'vales': vales,
      'novos': novos,
    };

Map<String, dynamic> _valeAcai() => {
      'id': 'vale-prova-acai', 'marco': 15, 'chave': 'acai', 'tipo': 'produto', 'estado': 'por_usar',
      'titulo': 'um açaí do Goola', 'loja_id': 'goola-acai-guarda', 'loja_nome': 'Goola',
      'produto_id': 'premio-checkin-acai', 'opcoes': <String>[], 'valido_ate': '2026-11-28T10:00:00Z',
    };

Future<void> _parar(WidgetTester t, String nome) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  debugPrint('[prova] PRONTO $nome');
  for (var i = 0; i < _segundosPorCaptura * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
}

Future<void> _assentar(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }
}

Widget _pagina(Widget filho) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(title: const Text('Início · dados de exemplo')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: filho,
        ),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prova visual da escada de prémios do check-in', (t) async {
    SharedPreferences.setMockInitialValues({});
    var festas = 0;
    Future<void> festa() async {
      festas++;
      // No flutter-tester do PC não há o plugin do som: lá conta-se só a festa.
      if (Platform.environment['FLUTTER_TEST'] == 'true') return;
      try {
        await festaDoDegrau();
      } catch (e) {
        debugPrint('[prova] som/vibração: $e');
      }
    }

    Widget cartao({
      required CheckinEstado tokens,
      required Future<CheckinPremiosEstado?> Function() premios,
      Future<CheckinEscadaResultado> Function()? levantar,
      Future<CheckinEscadaResultado> Function()? continuar,
    }) =>
        _pagina(CheckinDiarioCard(
          key: UniqueKey(),
          carregar: () async => tokens,
          carregarPremios: premios,
          marcarVistos: (_) async {},
          abrirPremios: (_) async {},
          levantarEscada: levantar ?? () async => const CheckinEscadaResultado(ok: false, reason: 'sem_premio'),
          continuarEscada: continuar ?? () async => const CheckinEscadaResultado(ok: false, reason: 'sem_premio'),
          festaEscada: festa,
        ));

    // 1. Dia 12 por fazer, salgados guardados (escolheu continuar no dia 10): faixa 8 a 14.
    final dia12 = CheckinPremiosEstado.fromJson(_estadoJson(
      dias: 11,
      hojeFeito: false,
      escada: _escada(
          guardado: _guardado(_salgados, '2026-10-24T10:00:00+00:00'),
          decisao: 'continuar',
          proximo: _acai,
          faltam: 4),
    ));
    await t.pumpWidget(cartao(tokens: _tokens(diaSequencia: 12, feito: false), premios: () async => dia12));
    await _assentar(t);
    await _parar(t, '01_cartao_fechado_dia12');

    // 2. A seta abre o mês dentro do próprio cartão.
    await t.tap(find.byKey(const Key('btn_checkin_mes')));
    await _assentar(t);
    await _parar(t, '02_cartao_mes_aberto');
    await t.tap(find.byKey(const Key('btn_checkin_mes')));
    await _assentar(t);

    // 3. Dia 10 feito agora: festa e a escolha Levantar / Continuar.
    var estado = CheckinPremiosEstado.fromJson(_estadoJson(
      dias: 10,
      hojeFeito: true,
      escada: _escada(
          guardado: _guardado(_salgados, '2026-10-29T10:00:00+00:00'),
          decisao: 'pendente',
          proximo: _acai,
          faltam: 5),
    ));
    var continuou = 0;
    await t.pumpWidget(cartao(
      tokens: _tokens(diaSequencia: 10, feito: true),
      premios: () async => estado,
      continuar: () async {
        continuou++;
        final depois = _estadoJson(
          dias: 10,
          hojeFeito: true,
          escada: _escada(
              guardado: _guardado(_salgados, '2026-10-29T10:00:00+00:00'),
              decisao: 'continuar',
              proximo: _acai,
              faltam: 5),
        );
        estado = CheckinPremiosEstado.fromJson(depois);
        return CheckinEscadaResultado.fromJson({'ok': true, 'estado': depois});
      },
    ));
    await _assentar(t);
    await _parar(t, '03_festa_dia10_escolha');

    // 4. Continuar: fica guardado, a escolha some.
    await t.tap(find.byKey(const Key('btn_escada_continuar')));
    await _assentar(t);
    await _parar(t, '04_continuar_fica_guardado');

    // 5. Dia 15: os salgados são TROCADOS pelo açaí (um só guardado) e nova escolha.
    estado = CheckinPremiosEstado.fromJson(_estadoJson(
      dias: 15,
      hojeFeito: true,
      escada: _escada(
          guardado: _guardado(_acai, '2026-11-03T10:00:00+00:00'),
          decisao: 'pendente',
          proximo: _mes,
          faltam: 15),
    ));
    var levantou = 0;
    await t.pumpWidget(cartao(
      tokens: _tokens(diaSequencia: 15, feito: true),
      premios: () async => estado,
      levantar: () async {
        levantou++;
        final depois = _estadoJson(
          dias: 0,
          hojeFeito: true,
          escada: _escada(proximo: _salgados, faltam: 10),
        );
        estado = CheckinPremiosEstado.fromJson(_estadoJson(
          dias: 0,
          hojeFeito: true,
          escada: _escada(proximo: _salgados, faltam: 10),
          vales: [_valeAcai()],
          novos: const ['vale-prova-acai'],
        ));
        return CheckinEscadaResultado.fromJson({'ok': true, 'vale': _valeAcai(), 'estado': depois});
      },
    ));
    await _assentar(t);
    await _parar(t, '05_dia15_troca_por_acai');

    // 6. Levantar: vale criado e a sequência volta ao dia 1.
    await t.tap(find.byKey(const Key('btn_escada_levantar')));
    await _assentar(t);
    await _parar(t, '06_levantou_recomeca_dia1');

    // 7. "Os meus prémios": a regra da escada, o guardado e os degraus.
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CheckinPremiosScreen(
        carregar: () async => CheckinPremiosEstado.fromJson(_estadoJson(
          dias: 12,
          hojeFeito: true,
          escada: _escada(
              guardado: _guardado(_salgados, '2026-10-24T10:00:00+00:00'),
              decisao: 'continuar',
              proximo: _acai,
              faltam: 3),
        )),
        levantarEscada: () async => const CheckinEscadaResultado(ok: false, reason: 'sem_premio'),
      ),
    ));
    await _assentar(t);
    await _parar(t, '07_os_meus_premios_escada');

    debugPrint('[prova] RESUMO festas=$festas continuou=$continuou levantou=$levantou');
    expect(continuou, 1);
    expect(levantou, 1);
    expect(festas, 2, reason: 'uma festa no dia 10 e outra no dia 15');
    debugPrint('[prova] FIM');
  });
}
