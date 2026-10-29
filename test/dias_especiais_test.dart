import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIAS ESPECIAIS (27/10/2026, missão boom-burger-2026-10-27, adendo 3).
///
/// O servidor (`is_partner_open`) já trocava o horário do dia pelo de
/// `business_hours.special_dates` (feriados, dias fechados, horário curto);
/// a app ignorava-os e podia dizer "Aberto" num dia em que a loja está
/// fechada. Agora a app usa o dia especial da data de Lisboa, como o servidor.
///
/// Calendário de 2026: 24/12 quinta, 25/12 sexta, 26/12 sábado, 31/12 quinta.

const _dia = {
  'open': '12:00',
  'close': '22:30',
  'closed': false,
  'break_start': '14:30',
  'break_end': '19:00',
};

Map<String, dynamic> _horario({bool comEspeciais = true}) => {
      'mon': {'open': '19:00', 'close': '22:30', 'closed': false},
      'tue': _dia,
      'wed': _dia,
      'thu': _dia,
      'fri': _dia,
      'sat': _dia,
      'sun': {'open': '12:00', 'close': '22:30', 'closed': true},
      if (comEspeciais)
        'special_dates': [
          {'date': '2026-12-24', 'open': '12:00', 'close': '16:00', 'closed': false},
          {'date': '2026-12-25', 'closed': true},
        ],
    };

RestaurantModel _loja(Map<String, dynamic> horario) => RestaurantModel(
      id: 'loja-teste',
      name: 'Loja Teste',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      businessHours: BusinessHours.fromJson(horario),
    );

DateTime _lx(int mes, int dia, int hora, [int minuto = 0]) =>
    instanteDeLisboa(DateTime(2026, mes, dia, hora, minuto));

void main() {
  group('os dias especiais vão e voltam da base', () {
    test('lê special_dates e o toJson devolve-os iguais', () {
      final h = BusinessHours.fromJson(_horario());
      expect(h.specialDates.keys, containsAll(['2026-12-24', '2026-12-25']));
      expect(h.specialDates['2026-12-25']!.closed, isTrue);
      expect(BusinessHours.fromJson(h.toJson()), h);
    });

    test('sem dias especiais o toJson não manda special_dates', () {
      final h = BusinessHours.fromJson(_horario(comEspeciais: false));
      expect(h.toJson().containsKey('special_dates'), isFalse);
    });

    test('mudar um dia da semana não perde os dias especiais', () {
      final h = BusinessHours.fromJson(_horario())
          .copyWithDay(DateTime.monday, const DayHours(closed: true));
      expect(h.specialDates.length, 2);
    });
  });

  group('a app respeita o dia especial como o servidor', () {
    final loja = _loja(_horario());

    test('Natal fechado: sexta 25/12 às 13:00 está fechada', () {
      final i = _lx(12, 25, 13);
      expect(loja.isOpenNow(i), isFalse);
      expect(loja.statusLabel(i), 'Fechada hoje — abre amanhã às 12h00');
      expect(loja.avisoLojaFechadaEm(i),
          'Loja Teste está fechada hoje. Abre amanhã às 12h00.');
    });

    test('véspera com horário curto substitui o da quinta (sem pausa)', () {
      // Numa quinta normal às 15:00 estaria em pausa; a 24/12 abre até às 16:00.
      expect(loja.isOpenNow(_lx(12, 24, 13)), isTrue);
      expect(loja.isOpenNow(_lx(12, 24, 15)), isTrue);
      expect(loja.isOpenNow(_lx(12, 24, 17)), isFalse);
    });

    test('a próxima abertura salta o dia especial fechado', () {
      // 24/12 às 17:00: o 25/12 está fechado, abre sábado 26/12 às 12:00.
      expect(loja.statusLabel(_lx(12, 24, 17)), 'Fechada, abre sábado às 12h00');
    });

    test('noutra quinta sem dia especial a pausa continua a contar', () {
      expect(loja.isOpenNow(_lx(12, 31, 15)), isFalse);
      expect(loja.isOpenNow(_lx(12, 31, 13)), isTrue);
    });
  });
}
