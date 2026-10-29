// Agendar pedidos (item 5 do adendo 5, 29/10/2026): a função PURA que gera as
// janelas de 30 min a partir do horário da loja. Horário da Boom! Burger:
// ter–sáb 12:15–14:15 e 19:15–22:15 (a pausa 14:15–19:15 é o intervalo do
// horário 12:15–22:15), seg 19:15–22:15, dom fechado. Sem rede.
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:flutter_test/flutter_test.dart';

BusinessHours boom({List<Map<String, dynamic>>? especiais}) {
  Map<String, dynamic> terSab() => {
        'open': '12:15',
        'close': '22:15',
        'closed': false,
        'break_start': '14:15',
        'break_end': '19:15',
      };
  return BusinessHours.fromJson({
    'mon': {'open': '19:15', 'close': '22:15', 'closed': false},
    'tue': terSab(),
    'wed': terSab(),
    'thu': terSab(),
    'fri': terSab(),
    'sat': terSab(),
    'sun': {'open': '12:15', 'close': '22:15', 'closed': true},
    if (especiais != null) 'special_dates': especiais,
  });
}

/// Novembro de 2026 já está na hora de inverno: Lisboa == UTC.
DateTime utc(int dia, int h, [int m = 0]) => DateTime.utc(2026, 11, dia, h, m);

List<String> horas(List<JanelaAgendada> js) => js.map((j) => j.horas).toList();

void main() {
  tearDown(() => BoraLang.notifier.value = AppLang.pt);

  group('janelasDoDia — horário da Boom', () {
    test('terça: duas manhãs/noites, alinhadas às :00 e :30 e dentro de cada período', () {
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 11, 3),
        agora: utc(2, 10), // segunda 10:00
      );
      expect(horas(js), [
        '12:30–13:00', '13:00–13:30', '13:30–14:00', // 12:15–14:15
        '19:30–20:00', '20:00–20:30', '20:30–21:00', '21:00–21:30', '21:30–22:00', // 19:15–22:15
      ]);
    });

    test('nenhuma janela cai dentro da pausa (14:15–19:15) nem fora do horário', () {
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 11, 4), // quarta
        agora: utc(2, 10),
      );
      for (final j in js) {
        final ini = j.inicio.hour * 60 + j.inicio.minute;
        final fim = ini + 30;
        final manha = ini >= 12 * 60 + 15 && fim <= 14 * 60 + 15;
        final noite = ini >= 19 * 60 + 15 && fim <= 22 * 60 + 15;
        expect(manha || noite, isTrue, reason: 'janela ${j.horas} fora dos períodos abertos');
      }
      expect(js.where((j) => j.inicio.hour == 15 || j.inicio.hour == 16), isEmpty);
    });

    test('segunda: só a noite (19:15–22:15, sem pausa)', () {
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 11, 2),
        agora: utc(2, 9), // segunda 09:00
      );
      expect(horas(js), [
        '19:30–20:00', '20:00–20:30', '20:30–21:00', '21:00–21:30', '21:30–22:00',
      ]);
    });

    test('domingo: fechado, nada para agendar', () {
      expect(
        janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 8), agora: utc(3, 10)),
        isEmpty,
      );
    });

    test('dia especial fechado (feriado) tira o dia', () {
      final h = boom(especiais: [
        {'date': '2026-11-05', 'closed': true, 'open': '12:15', 'close': '22:15'},
      ]);
      expect(janelasDoDia(horas: h, dia: DateTime.utc(2026, 11, 5), agora: utc(2, 10)), isEmpty);
      expect(janelasDoDia(horas: h, dia: DateTime.utc(2026, 11, 6), agora: utc(2, 10)), isNotEmpty);
    });

    test('dia especial com horário diferente substitui o da semana', () {
      final h = boom(especiais: [
        {'date': '2026-11-04', 'closed': false, 'open': '20:00', 'close': '21:00'},
      ]);
      expect(horas(janelasDoDia(horas: h, dia: DateTime.utc(2026, 11, 4), agora: utc(2, 10))),
          ['20:00–20:30', '20:30–21:00']);
    });

    test('loja que fecha à meia-noite: a última janela acaba às 24:00', () {
      final h = BusinessHours.fromJson({
        for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
          d: {'open': '22:00', 'close': '00:00', 'closed': false},
      });
      final js = janelasDoDia(horas: h, dia: DateTime.utc(2026, 11, 3), agora: utc(2, 10));
      expect(horas(js), ['22:00–22:30', '22:30–23:00', '23:00–23:30', '23:30–24:00']);
    });
  });

  group('janelasDoDia — passado, antecedência e 7 dias', () {
    test('hoje: não oferece janelas antes de agora + 60 min', () {
      // Terça 13:00: o mínimo é 14:00; a manhã (a última janela começa às 13:30) fica toda de fora.
      final js = janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 3), agora: utc(3, 13));
      expect(horas(js).first, '19:30–20:00');
      expect(js.length, 5);
    });

    test('hoje à noite: só ficam as que começam a 60 min ou mais', () {
      // Terça 19:45 → mínimo 20:45 → só 21:00 e 21:30.
      final js = janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 3), agora: utc(3, 19, 45));
      expect(horas(js), ['21:00–21:30', '21:30–22:00']);
    });

    test('nunca devolve uma janela que começa antes de agora', () {
      final agora = utc(3, 12, 20);
      final js = janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 3), agora: agora);
      for (final j in js) {
        expect(j.instante.isBefore(agora), isFalse);
        expect(j.instante.difference(agora).inMinutes, greaterThanOrEqualTo(60));
      }
    });

    test('um dia que já passou não tem janelas', () {
      expect(janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 2), agora: utc(3, 10)), isEmpty);
    });

    test('além de 7 dias nada: dia 8 fora; no dia 7 só até à mesma hora do dia', () {
      // Terça 3 às 20:00 → o limite é terça 10 às 20:00.
      final agora = utc(3, 20);
      final dia8 = janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 11), agora: agora);
      expect(dia8, isEmpty);
      final dia7 = janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 10), agora: agora);
      expect(horas(dia7), ['12:30–13:00', '13:00–13:30', '13:30–14:00', '19:30–20:00', '20:00–20:30']);
      for (final j in dia7) {
        expect(j.instante.isAfter(agora.add(const Duration(days: 7))), isFalse);
      }
    });

    test('maxDias configurável (3 dias): quinta já não aparece a partir de segunda', () {
      final agora = utc(2, 10);
      expect(
        janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 6), agora: agora, maxDias: 3),
        isEmpty,
      );
      expect(
        janelasDoDia(horas: boom(), dia: DateTime.utc(2026, 11, 4), agora: agora, maxDias: 3),
        isNotEmpty,
      );
    });

    test('pausa temporária do parceiro: nada começa antes de pausaAte', () {
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 11, 3),
        agora: utc(2, 10),
        pausaAte: utc(3, 20, 10),
      );
      expect(horas(js), ['20:30–21:00', '21:00–21:30', '21:30–22:00']);
    });
  });

  group('diasComJanelas', () {
    test('a partir de segunda 10:00: seg a sáb têm janelas, domingo (fechado) e a segunda seguinte não', () {
      final dias = diasComJanelas(horas: boom(), agora: utc(2, 10));
      expect(dias.map((d) => d.day).toList(), [2, 3, 4, 5, 6, 7]);
      expect(dias.every((d) => d.weekday != DateTime.sunday), isTrue);
    });

    test('loja sem horário útil (tudo fechado) não tem dias', () {
      final h = BusinessHours.fromJson({
        for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
          d: {'open': '12:00', 'close': '22:00', 'closed': true},
      });
      expect(diasComJanelas(horas: h, agora: utc(2, 10)), isEmpty);
    });
  });

  group('instante e hora de verão', () {
    test('a janela das 12:30 de sábado 24/10 (verão, UTC+1) é as 11:30 UTC', () {
      // 25/10/2026 02:00 é a mudança de hora; sábado 24 ainda é verão.
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 10, 24),
        agora: DateTime.utc(2026, 10, 22, 10),
      );
      expect(js.first.horas, '12:30–13:00');
      expect(js.first.instante, DateTime.utc(2026, 10, 24, 11, 30));
    });

    test('a mesma janela de terça 27/10 (inverno, UTC+0) é as 12:30 UTC', () {
      final js = janelasDoDia(
        horas: boom(),
        dia: DateTime.utc(2026, 10, 27),
        agora: DateTime.utc(2026, 10, 26, 10),
      );
      expect(js.first.instante, DateTime.utc(2026, 10, 27, 12, 30));
    });
  });

  group('textos', () {
    final j = JanelaAgendada(
      inicio: DateTime.utc(2026, 11, 7, 19, 30),
      fim: DateTime.utc(2026, 11, 7, 20),
    );

    test('Agendado para sáb 07/11, 19:30–20:00 (PT)', () {
      expect(textoAgendadoPara(j), 'Agendado para sáb 07/11, 19:30–20:00');
    });

    test('a nota do parceiro é sempre em português', () {
      BoraLang.notifier.value = AppLang.en;
      expect(notaAgendadoParaParceiro(j), 'Pedido AGENDADO para sáb 07/11, 19:30–20:00');
    });

    test('em inglês o dia vem em inglês', () {
      BoraLang.notifier.value = AppLang.en;
      expect(diaComData(DateTime.utc(2026, 11, 7)), 'Sat 07/11');
    });

    test('rotuloDoDia: Hoje, Amanhã e o resto com data', () {
      final agora = utc(3, 10);
      expect(rotuloDoDia(DateTime.utc(2026, 11, 3), agora), 'Hoje');
      expect(rotuloDoDia(DateTime.utc(2026, 11, 4), agora), 'Amanhã');
      expect(rotuloDoDia(DateTime.utc(2026, 11, 7), agora), 'sáb 07/11');
    });

    test('faltaTexto', () {
      final agora = utc(3, 12);
      expect(faltaTexto(utc(3, 12, 45), agora), 'faltam 45 min');
      expect(faltaTexto(utc(3, 14, 10), agora), 'faltam 2 h 10 min');
      expect(faltaTexto(utc(3, 14), agora), 'faltam 2 h');
      expect(faltaTexto(utc(4, 15), agora), 'faltam 1 dia 3 h');
      expect(faltaTexto(utc(5, 12), agora), 'faltam 2 dias');
      expect(faltaTexto(agora, agora), 'é agora');
      expect(faltaTexto(utc(3, 11, 50), agora), 'passou há 10 min');
    });

    test('deviaAvisarParceiro: a 30 min ou menos, até 2 h depois', () {
      final agora = utc(3, 12);
      expect(deviaAvisarParceiro(utc(3, 12, 31), agora), isFalse);
      expect(deviaAvisarParceiro(utc(3, 12, 30), agora), isTrue);
      expect(deviaAvisarParceiro(utc(3, 12, 5), agora), isTrue);
      expect(deviaAvisarParceiro(utc(3, 10, 30), agora), isTrue);
      expect(deviaAvisarParceiro(utc(3, 9, 50), agora), isFalse);
    });
  });

  group('PedidoAgendado.fromJson', () {
    test('lê os campos do servidor e resume os itens', () {
      final p = PedidoAgendado.fromJson({
        'id': 'ord-abcd1234',
        'status': 'preparing',
        'scheduled_for': '2026-11-07T19:30:00+00:00',
        'price': 12.5,
        'customer_name': 'Ana',
        'payment_method': 'card',
        'payment_status': 'paid',
        'prep_time_minutes': 20,
        'items': [
          {'name': 'Hambúrguer', 'quantity': 2},
          {'name': 'Batatas'},
          {'quantity': 3},
        ],
      });
      expect(p.codigo, '1234');
      expect(p.aceite, isTrue);
      expect(p.quando, DateTime.utc(2026, 11, 7, 19, 30));
      expect(p.ate, DateTime.utc(2026, 11, 7, 20));
      expect(p.itens, '2× Hambúrguer, 1× Batatas');
      expect(p.totalEur, 12.5);
    });
  });
}
