import 'dart:io';

import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:flutter_test/flutter_test.dart';

/// LOJA ABERTA/FECHADA PELA HORA DE LISBOA (06/10/2026, decisão tomada pela
/// Claude.ai com a autoridade do Danilo).
///
/// A Bora só opera em Portugal. Aberta/fechada decide-se pela hora de Lisboa
/// (Europe/Lisbon, com hora de verão) — a mesma que o servidor usa em
/// `is_partner_open` e no travão `STORE_CLOSED` —, nunca pelo relógio do
/// telemóvel: o emulador do CI anda em UTC, um turista traz o fuso de casa e
/// há relógios mal acertados. Antes, a app e o servidor divergiam uma hora e o
/// cliente enchia o carrinho para depois ser recusado no fim (ou o contrário).
///
/// Todos os instantes aqui são UTC fixos: o resultado não pode depender do
/// fuso da máquina que corre o teste (PC em Lisboa, CI em UTC).
RestaurantModel _loja(BusinessHours horario) => RestaurantModel(
      id: 'loja-hora',
      name: 'Loja Teste',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      businessHours: horario,
    );

BusinessHours _todosOsDias(DayHours d) =>
    BusinessHours(mon: d, tue: d, wed: d, thu: d, fri: d, sat: d, sun: d);

const _noveAsVinteDuas = DayHours(open: '09:00', close: '22:00');

String _hh(int h) => h.toString().padLeft(2, '0');

void main() {
  group('o instante decide, não o fuso do telemóvel', () {
    test('verão: 21:30 em UTC já são 22:30 em Lisboa — fechada', () {
      final loja = _loja(_todosOsDias(_noveAsVinteDuas));
      final instante = DateTime.utc(2026, 10, 6, 21, 30);
      expect(loja.isOpenNow(instante), isFalse);
      expect(loja.statusLabel(instante), 'Fechada, abre às 09h00');
    });

    test('verão: 08:30 em UTC já são 09:30 em Lisboa — aberta', () {
      final loja = _loja(_todosOsDias(_noveAsVinteDuas));
      final instante = DateTime.utc(2026, 10, 6, 8, 30);
      expect(loja.isOpenNow(instante), isTrue);
      expect(loja.statusLabel(instante), 'Aberto');
    });

    test('inverno: Lisboa é UTC — 21:30 UTC ainda está aberta', () {
      final loja = _loja(_todosOsDias(_noveAsVinteDuas));
      final instante = DateTime.utc(2026, 1, 15, 21, 30);
      expect(loja.isOpenNow(instante), isTrue);
      expect(loja.statusLabel(instante), 'Aberto');
    });

    test('mudança da hora (25/10/2026, 01:00 UTC) acompanha Lisboa', () {
      final loja =
          _loja(_todosOsDias(const DayHours(open: '01:30', close: '23:00')));
      // 00:59 UTC ainda é verão: 01:59 em Lisboa → aberta.
      expect(loja.isOpenNow(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      // 01:10 UTC já é inverno: 01:10 em Lisboa → ainda não abriu.
      expect(loja.isOpenNow(DateTime.utc(2026, 10, 25, 1, 10)), isFalse);
    });
  });

  group('o dia da semana também é o de Lisboa', () {
    test('domingo 23:30 UTC já é segunda 00:30 em Lisboa', () {
      const segunda = DayHours(open: '00:00', close: '23:59');
      final loja = _loja(const BusinessHours(
        mon: segunda,
        tue: segunda,
        wed: segunda,
        thu: segunda,
        fri: segunda,
        sat: segunda,
        sun: DayHours(closed: true),
      ));
      final instante = DateTime.utc(2026, 10, 4, 23, 30);
      expect(instante.weekday, DateTime.sunday); // em UTC ainda é domingo
      expect(loja.isOpenNow(instante), isTrue);
      expect(loja.statusLabel(instante), 'Aberto');
    });

    test('o aviso do carrinho fala do dia de Lisboa', () {
      const domingo = DayHours(open: '10:00', close: '20:00');
      final loja = _loja(const BusinessHours(
        mon: DayHours(closed: true),
        sun: domingo,
      ));
      // Domingo 23:30 UTC = segunda 00:30 em Lisboa, e à segunda não abre.
      final instante = DateTime.utc(2026, 10, 4, 23, 30);
      expect(loja.statusLabel(instante), 'Fechada hoje');
      expect(loja.avisoLojaFechadaEm(instante),
          'Loja Teste está fechada hoje. Volta noutro dia para fazer o pedido.');
    });

    test('o aviso diz a hora de abrir do dia de Lisboa', () {
      final loja = _loja(const BusinessHours(
        mon: DayHours(open: '08:00', close: '20:00'),
        sun: DayHours(open: '12:00', close: '20:00'),
      ));
      // Domingo 23:30 UTC = segunda 00:30 em Lisboa → abre às 08h00 (segunda),
      // não às 12h00 (domingo, o dia do telemóvel em UTC).
      final instante = DateTime.utc(2026, 10, 4, 23, 30);
      expect(loja.avisoLojaFechadaEm(instante),
          'Loja Teste está fechada agora. Abre às 08h00.');
    });
  });

  group('outro fuso: o mesmo instante dá a mesma resposta', () {
    test('São Paulo, Tóquio, UTC e Lisboa no mesmo instante', () {
      final loja = _loja(_todosOsDias(_noveAsVinteDuas));
      // Telemóvel em São Paulo (UTC-3) a marcar 18:30 de 06/10…
      final saoPaulo =
          DateTime.utc(2026, 10, 6, 18, 30).add(const Duration(hours: 3));
      // …e um em Tóquio (UTC+9) a marcar 06:30 de 07/10: é o mesmo instante,
      // 21:30 UTC, que em Lisboa são 22:30 — a loja já fechou.
      final toquio =
          DateTime.utc(2026, 10, 7, 6, 30).subtract(const Duration(hours: 9));
      final lisboa = instanteDeLisboa(DateTime(2026, 10, 6, 22, 30));
      expect(saoPaulo, toquio);
      expect(saoPaulo, lisboa);
      for (final i in [saoPaulo, toquio, lisboa, saoPaulo.toLocal()]) {
        expect(loja.isOpenNow(i), isFalse, reason: '$i');
        expect(loja.statusLabel(i), 'Fechada, abre às 09h00', reason: '$i');
      }
    });
  });

  group('sem instante dado, usa o agora deste aparelho em hora de Lisboa', () {
    test('aberta só na hora de Lisboa de agora', () {
      final l = horaLisboa(DateTime.now());
      // Janela de duas horas que começa na hora de Lisboa de agora.
      final loja = _loja(_todosOsDias(DayHours(
        open: '${_hh(l.hour)}:00',
        close: '${_hh((l.hour + 2) % 24)}:00',
      )));
      expect(loja.isOpenNow(), isTrue);
      expect(loja.statusLabel(), 'Aberto');
    });

    test('fechada na hora do aparelho quando esta não é a de Lisboa', () {
      final agora = DateTime.now();
      final l = horaLisboa(agora);
      // Neste PC (Lisboa) as duas horas coincidem e não há nada a provar;
      // no CI (UTC) ou noutro fuso, a hora do aparelho não pode abrir a loja.
      if (agora.hour == l.hour) return;
      final loja = _loja(_todosOsDias(DayHours(
        open: '${_hh(agora.hour)}:00',
        close: '${_hh((agora.hour + 1) % 24)}:00',
      )));
      expect(loja.isOpenNow(), isFalse);
    });
  });

  group('paredeLisboa não depende do fuso do telemóvel', () {
    test('vem marcado UTC, com o dia e a hora de Lisboa', () {
      // Um relógio LOCAL cairia no buraco da mudança de hora do fuso do
      // aparelho (ex.: Chile, Austrália) e saltava uma hora.
      final l = paredeLisboa(DateTime.utc(2026, 10, 4, 23, 30));
      expect(l.isUtc, isTrue);
      expect([l.weekday, l.hour, l.minute], [DateTime.monday, 0, 30]);
      final i = paredeLisboa(DateTime.utc(2026, 1, 15, 21, 30));
      expect([i.isUtc, i.hour, i.minute], [true, 21, 30]);
    });
  });

  group('festas: a data vai ao servidor pelo relógio de Lisboa', () {
    test('09h de amanhã em Lisboa nunca vira "hoje" (telemóvel UTC+11)', () {
      // Em Sydney (UTC+11) um `.toUtc()` mandava 22:00 UTC da véspera — que
      // em Lisboa ainda é hoje — e o festas_set_schedule recusava.
      expect(instanteDeLisboa(DateTime(2026, 10, 7, 9)),
          DateTime.utc(2026, 10, 7, 8));
    });

    for (final ficheiro in [
      'lib/screens/payment_method_screen.dart',
      'lib/stores/cart_store.dart',
    ]) {
      test('$ficheiro envia por instanteDeLisboa', () {
        final src = File(ficheiro).readAsStringSync();
        expect(src, contains("'p_scheduled_for': instanteDeLisboa(quandoFesta)"));
        expect(src, isNot(contains('quandoFesta.toUtc()')));
      });
    }
  });

  group('instanteDeLisboa é o inverso de horaLisboa', () {
    test('verão: 20:00 em Lisboa = 19:00 UTC', () {
      expect(instanteDeLisboa(DateTime(2026, 10, 6, 20)),
          DateTime.utc(2026, 10, 6, 19));
    });

    test('inverno: 20:00 em Lisboa = 20:00 UTC', () {
      expect(instanteDeLisboa(DateTime(2026, 1, 15, 20)),
          DateTime.utc(2026, 1, 15, 20));
    });

    test('meia-noite de Lisboa no verão é 23:00 UTC da véspera', () {
      expect(instanteDeLisboa(DateTime(2026, 10, 7)),
          DateTime.utc(2026, 10, 6, 23));
    });

    test('ida e volta dá o mesmo relógio, ao longo do ano', () {
      for (var mes = 1; mes <= 12; mes++) {
        for (final hora in [0, 7, 12, 19, 23]) {
          final parede = DateTime(2026, mes, 10, hora, 15);
          final volta = horaLisboa(instanteDeLisboa(parede));
          expect(
            [volta.year, volta.month, volta.day, volta.hour, volta.minute],
            [2026, mes, 10, hora, 15],
            reason: 'mes=$mes hora=$hora',
          );
        }
      }
    });
  });
}
