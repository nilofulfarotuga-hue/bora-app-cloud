import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:bora_app/widgets/pausa_do_dia_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PAUSA DO DIA (27/10/2026, missão boom-burger-2026-10-27, passo F2).
///
/// A Boom! Burger abre de terça a sábado das 12:00 às 22:30 com pausa das
/// 14:30 às 19:00; segunda das 19:00 às 22:30; domingo fechada. Dentro da
/// pausa a loja está FECHADA, igual ao `is_partner_open` do servidor, e o
/// texto diz a próxima abertura com o dia, como o `opens_dia` dele.
///
/// Os instantes são fixos e passam pela hora de Lisboa ([instanteDeLisboa]):
/// o resultado não pode depender do fuso da máquina (PC em Lisboa, CI em UTC).

/// O `business_hours` da Boom tal como está em produção (SELECT de 27/10).
const Map<String, dynamic> _boomJson = {
  'fri': {
    'open': '12:00',
    'close': '22:30',
    'closed': false,
    'break_end': '19:00',
    'break_start': '14:30',
  },
  'mon': {'open': '19:00', 'close': '22:30', 'closed': false},
  'sat': {
    'open': '12:00',
    'close': '22:30',
    'closed': false,
    'break_end': '19:00',
    'break_start': '14:30',
  },
  'sun': {'open': '12:00', 'close': '22:30', 'closed': true},
  'thu': {
    'open': '12:00',
    'close': '22:30',
    'closed': false,
    'break_end': '19:00',
    'break_start': '14:30',
  },
  'tue': {
    'open': '12:00',
    'close': '22:30',
    'closed': false,
    'break_end': '19:00',
    'break_start': '14:30',
  },
  'wed': {
    'open': '12:00',
    'close': '22:30',
    'closed': false,
    'break_end': '19:00',
    'break_start': '14:30',
  },
};

RestaurantModel _boom() => RestaurantModel(
      id: 'boom-burger-guarda',
      name: 'Boom! Burger',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      businessHours: BusinessHours.fromJson(_boomJson),
    );

/// Instante em que o relógio de Lisboa marca este dia e hora de 2026.
DateTime _lx(int mes, int dia, int hora, [int minuto = 0]) =>
    instanteDeLisboa(DateTime(2026, mes, dia, hora, minuto));

void main() {
  group('o horário vai e volta da base sem perder a pausa', () {
    test('lê break_start/break_end do business_hours de produção', () {
      final h = BusinessHours.fromJson(_boomJson);
      expect(h.tue.breakStart, '14:30');
      expect(h.tue.breakEnd, '19:00');
      expect(h.tue.temPausa, isTrue);
      expect(h.mon.temPausa, isFalse);
      expect(h.sun.closed, isTrue);
    });

    test('toJson com pausa: fromJson(toJson) == original', () {
      const dia = DayHours(
        open: '12:00',
        close: '22:30',
        breakStart: '14:30',
        breakEnd: '19:00',
      );
      expect(dia.toJson()['break_start'], '14:30');
      expect(dia.toJson()['break_end'], '19:00');
      expect(DayHours.fromJson(dia.toJson()), dia);

      final semana = BusinessHours.fromJson(_boomJson);
      expect(BusinessHours.fromJson(semana.toJson()), semana);
    });

    test('toJson sem pausa manda break_start e break_end a null', () {
      // A guarda do servidor (trg_business_hours_guarda_pausa) mantém a
      // pausa antiga quando as chaves NÃO vêm: têm de ir, a null.
      final json = const DayHours(open: '19:00', close: '22:30').toJson();
      expect(json.containsKey('break_start'), isTrue);
      expect(json.containsKey('break_end'), isTrue);
      expect(json['break_start'], isNull);
      expect(json['break_end'], isNull);

      final segunda = BusinessHours.fromJson(_boomJson).toJson()['mon']
          as Map<String, dynamic>;
      expect(segunda.containsKey('break_start'), isTrue);
      expect(segunda['break_start'], isNull);
      expect(segunda.containsKey('break_end'), isTrue);
      expect(segunda['break_end'], isNull);
    });

    test('tirar a pausa manda as duas chaves a null', () {
      final terca = BusinessHours.fromJson(_boomJson).tue;
      final sem = terca.copyWith(semPausa: true);
      expect(sem.temPausa, isFalse);
      expect(sem.toJson(), {
        'open': '12:00',
        'close': '22:30',
        'closed': false,
        'break_start': null,
        'break_end': null,
      });
      // O resto do dia não mexe.
      expect(sem.copyWith(breakStart: '14:30', breakEnd: '19:00'), terca);
    });
  });

  group('isOpenNow respeita a pausa (hora de Lisboa)', () {
    test('terça 16:00 fechada; 13:00 e 19:30 aberta', () {
      final boom = _boom();
      expect(boom.isOpenNow(_lx(10, 27, 16)), isFalse);
      expect(boom.isOpenNow(_lx(10, 27, 13)), isTrue);
      expect(boom.isOpenNow(_lx(10, 27, 19, 30)), isTrue);
    });

    test('as pontas da pausa: 14:30 já fecha, 19:00 já abre', () {
      final boom = _boom();
      expect(boom.isOpenNow(_lx(10, 27, 14, 29)), isTrue);
      expect(boom.isOpenNow(_lx(10, 27, 14, 30)), isFalse);
      expect(boom.isOpenNow(_lx(10, 27, 18, 59)), isFalse);
      expect(boom.isOpenNow(_lx(10, 27, 19)), isTrue);
    });

    test('no verão a pausa é pela hora de Lisboa, não pela UTC', () {
      final boom = _boom();
      // Terça 20/10 (verão): 13:30 UTC = 14:30 em Lisboa → em pausa.
      final instante = DateTime.utc(2026, 10, 20, 13, 30);
      expect(boom.isOpenNow(instante), isFalse);
      // 11:30 UTC = 12:30 em Lisboa → aberta.
      expect(boom.isOpenNow(DateTime.utc(2026, 10, 20, 11, 30)), isTrue);
    });

    test('dia sem pausa funciona como antes (segunda 19:00–22:30)', () {
      final boom = _boom();
      expect(boom.isOpenNow(_lx(10, 26, 16)), isFalse);
      expect(boom.isOpenNow(_lx(10, 26, 20)), isTrue);
      expect(boom.isOpenNow(_lx(10, 26, 22, 30)), isFalse);
    });

    test('domingo fechada o dia todo', () {
      expect(_boom().isOpenNow(_lx(11, 1, 13)), isFalse);
    });
  });

  group('o texto diz a próxima abertura, como o opens_dia do servidor', () {
    test('terça 16:00 (pausa): abre às 19h00', () {
      final boom = _boom();
      expect(boom.statusLabel(_lx(10, 27, 16)), 'Fechada, abre às 19h00');
      expect(boom.avisoLojaFechadaEm(_lx(10, 27, 16)),
          'Boom! Burger está fechada agora. Abre às 19h00.');
    });

    test('domingo: fechada hoje, abre amanhã (segunda) às 19h00', () {
      final boom = _boom();
      expect(boom.statusLabel(_lx(11, 1, 13)),
          'Fechada hoje — abre amanhã às 19h00');
      expect(boom.avisoLojaFechadaEm(_lx(11, 1, 13)),
          'Boom! Burger está fechada hoje. Abre amanhã às 19h00.');
    });

    test('sábado depois do fecho: salta o domingo, abre segunda às 19h00', () {
      final boom = _boom();
      expect(boom.statusLabel(_lx(10, 31, 23)),
          'Fechada, abre segunda às 19h00');
      expect(boom.avisoLojaFechadaEm(_lx(10, 31, 23)),
          'Boom! Burger está fechada agora. Abre segunda às 19h00.');
    });

    test('terça depois do fecho: abre amanhã às 12h00', () {
      expect(_boom().statusLabel(_lx(10, 27, 23)),
          'Fechada, abre amanhã às 12h00');
    });

    test('segunda de manhã: abre às 19h00 (mais tarde no mesmo dia)', () {
      expect(_boom().statusLabel(_lx(10, 26, 10)), 'Fechada, abre às 19h00');
    });

    test('aberta diz Aberto', () {
      expect(_boom().statusLabel(_lx(10, 27, 13)), 'Aberto');
      expect(_boom().statusLabel(_lx(10, 27, 19, 30)), 'Aberto');
    });

    test('proximaAbertura dá o dia e a hora certos', () {
      final boom = _boom();
      final pausa = boom.proximaAbertura(_lx(10, 27, 16))!;
      expect([pausa.emDias, pausa.weekday, pausa.hora],
          [0, DateTime.tuesday, '19:00']);
      final domingo = boom.proximaAbertura(_lx(11, 1, 13))!;
      expect([domingo.emDias, domingo.weekday, domingo.hora],
          [1, DateTime.monday, '19:00']);
    });

    test('loja sem nenhum dia aberto não inventa abertura', () {
      const fechado = DayHours(closed: true);
      const loja = RestaurantModel(
        id: 'x',
        name: 'Loja',
        phone: '',
        address: '',
        email: '',
        photoUrl: '',
        cuisineType: '',
        isPartner: true,
        category: BusinessCategory.restaurant,
        businessHours: BusinessHours(
          mon: fechado,
          tue: fechado,
          wed: fechado,
          thu: fechado,
          fri: fechado,
          sat: fechado,
          sun: fechado,
        ),
      );
      expect(loja.statusLabel(_lx(10, 27, 13)), 'Fechada hoje');
      expect(loja.avisoLojaFechadaEm(_lx(10, 27, 13)),
          'Loja está fechada hoje. Volta noutro dia para fazer o pedido.');
    });
  });

  group('validação da pausa (parceiro PT-PT, admin PT-BR)', () {
    const dia = DayHours(open: '12:00', close: '22:30');

    test('pausa dentro do horário e início < fim passa', () {
      expect(dia.copyWith(breakStart: '14:30', breakEnd: '19:00').erroPausa(),
          isNull);
      expect(dia.erroPausa(), isNull); // sem pausa
    });

    test('fim antes do início é recusado', () {
      final mal = dia.copyWith(breakStart: '19:00', breakEnd: '14:30');
      expect(mal.erroPausa(), 'O fim da pausa tem de ser depois do início.');
      expect(mal.erroPausa(ptBr: true),
          'O fim da pausa precisa ser depois do início.');
      expect(dia.copyWith(breakStart: '15:00', breakEnd: '15:00').erroPausa(),
          isNotNull);
    });

    test('pausa fora do horário é recusada', () {
      final cedo = dia.copyWith(breakStart: '11:00', breakEnd: '13:00');
      expect(cedo.erroPausa(), 'A pausa tem de ficar dentro do horário aberto.');
      expect(cedo.erroPausa(ptBr: true),
          'A pausa precisa ficar dentro do horário de funcionamento.');
      expect(dia.copyWith(breakStart: '21:00', breakEnd: '23:00').erroPausa(),
          isNotNull);
    });

    test('dia fechado não se queixa da pausa', () {
      expect(
          dia
              .copyWith(closed: true, breakStart: '19:00', breakEnd: '14:30')
              .erroPausa(),
          isNull);
    });
  });

  group('editor da pausa (o mesmo no parceiro e no admin)', () {
    Future<void> montar(WidgetTester t, DayHours dia,
        {bool ptBr = false, void Function(DayHours)? aoMudar}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PausaDoDiaEditor(
            day: dia,
            ptBr: ptBr,
            onChanged: (v) => aoMudar?.call(v),
          ),
        ),
      ));
    }

    testWidgets('com pausa mostra as horas e tira-a com as chaves a null',
        (t) async {
      DayHours? novo;
      await montar(
        t,
        const DayHours(
            open: '12:00', close: '22:30', breakStart: '14:30', breakEnd: '19:00'),
        aoMudar: (v) => novo = v,
      );
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
      await t.tap(find.byTooltip('Tirar pausa'));
      expect(novo, isNotNull);
      expect(novo!.temPausa, isFalse);
      expect(novo!.toJson()['break_start'], isNull);
      expect(novo!.toJson().containsKey('break_end'), isTrue);
    });

    testWidgets('sem pausa: "Adicionar pausa" põe uma dentro do horário',
        (t) async {
      DayHours? novo;
      // Segunda da Boom (19:00–22:30): o 13:00–14:00 não cabe.
      await montar(t, const DayHours(open: '19:00', close: '22:30'),
          aoMudar: (v) => novo = v);
      await t.tap(find.text('Adicionar pausa'));
      expect(novo!.temPausa, isTrue);
      expect(novo!.erroPausa(), isNull);
      expect([novo!.breakStart, novo!.breakEnd], ['20:00', '21:00']);
    });

    testWidgets('pausa errada mostra o erro (PT-BR no admin)', (t) async {
      await montar(
        t,
        const DayHours(
            open: '12:00', close: '22:30', breakStart: '19:00', breakEnd: '14:30'),
        ptBr: true,
      );
      expect(find.text('O fim da pausa precisa ser depois do início.'),
          findsOneWidget);
      expect(find.byTooltip('Remover pausa'), findsOneWidget);
    });
  });
}
