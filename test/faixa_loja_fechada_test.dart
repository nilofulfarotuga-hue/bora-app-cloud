import 'dart:io';

import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/widgets/bora/loja_fechada.dart';
import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 4] Loja fechada nunca mostra "5-20 min".
///
/// Cicatriz (26/10, 06:55, REA): o Burger King (11:00–23:00) aparecia com
/// "5-20 min" fora de horas. Regra do Danilo de 27/08: entra-se e vê-se tudo,
/// com a faixa "Fechado · abre às 11:00"; o travão é só ao pôr no carrinho.
RestaurantModel _loja({
  String id = 'bk',
  BusinessHours? horario,
  BusinessCategory categoria = BusinessCategory.restaurant,
  bool emBreve = false,
  DateTime? pausaAte,
}) =>
    RestaurantModel(
      id: id,
      name: 'Loja $id',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: false,
      category: categoria,
      businessHours: horario ?? _onzeAsVinteETres,
      comingSoon: emBreve,
      pausaAte: pausaAte,
    );

const _d = DayHours(open: '11:00', close: '23:00');
const _onzeAsVinteETres =
    BusinessHours(mon: _d, tue: _d, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d);

// Segunda-feira 26/10/2026: depois da mudança de hora, Lisboa = UTC.
final _segunda0655 = DateTime.utc(2026, 10, 26, 6, 55);
final _segunda2330 = DateTime.utc(2026, 10, 26, 23, 30);
final _segunda1300 = DateTime.utc(2026, 10, 26, 13, 0);

void main() {
  test('antes de abrir: "Fechado · abre às 11:00"', () {
    final bk = _loja();
    expect(bk.fechadaParaClienteEm(_segunda0655), isTrue);
    expect(bk.faixaFechadaEm(_segunda0655), 'Fechado · abre às 11:00');
  });

  test('depois de fechar: abre amanhã', () {
    expect(_loja().faixaFechadaEm(_segunda2330), 'Fechado · abre amanhã às 11:00');
  });

  test('dias fechados: diz o dia em que abre', () {
    const fechado = DayHours(open: '11:00', close: '23:00', closed: true);
    final loja = _loja(
      horario: const BusinessHours(
          mon: fechado, tue: fechado, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d),
    );
    expect(loja.faixaFechadaEm(_segunda1300), 'Fechado · abre quarta às 11:00');
  });

  test('loja de um dia só por semana: diz a próxima semana', () {
    const fechado = DayHours(closed: true);
    final loja = _loja(
      horario: const BusinessHours(
          mon: _d, tue: fechado, wed: fechado, thu: fechado, fri: fechado,
          sat: fechado, sun: fechado),
    );
    expect(loja.faixaFechadaEm(_segunda2330), 'Fechado · abre segunda às 11:00');
  });

  test('aberta não tem faixa; Festas e "Em breve" ficam com as faixas delas', () {
    expect(_loja().fechadaParaClienteEm(_segunda1300), isFalse);
    expect(_loja(categoria: BusinessCategory.festas).fechadaParaClienteEm(_segunda0655), isFalse);
    expect(_loja(emBreve: true).fechadaParaClienteEm(_segunda0655), isFalse);
  });

  test('pausa do parceiro conta como fechada, com a hora a que volta', () {
    final loja = _loja(pausaAte: DateTime.utc(2026, 10, 26, 15, 30));
    expect(loja.fechadaParaClienteEm(_segunda1300), isTrue);
    expect(loja.faixaFechadaEm(_segunda1300), 'Fechado · volta às 15:30');
  });

  // 28/10 (missao-geral): a app decide como o servidor (`is_partner_open`),
  // que olha só ao horário do PRÓPRIO dia, também na madrugada. Se a app
  // dissesse "aberto" e o servidor "fechado", o pedido caía no fim com
  // STORE_CLOSED. Contar a madrugada pela véspera fica reportado como
  // proposta para o servidor primeiro.
  test('madrugada segue o servidor: conta o horário do próprio dia', () {
    const noite = DayHours(open: '20:00', close: '02:00');
    const fechado = DayHours(closed: true);
    final kebab = _loja(
      horario: const BusinessHours(
          mon: fechado, tue: fechado, wed: fechado, thu: fechado, fri: fechado,
          sat: noite, sun: fechado),
    );
    // Domingo 25/10/2026 01:00 em Lisboa (já em hora de inverno = UTC):
    // domingo fecha, logo fechado — como o servidor.
    expect(kebab.isOpenNow(DateTime.utc(2026, 10, 25, 1, 0)), isFalse);
    expect(kebab.isOpenNow(DateTime.utc(2026, 10, 25, 2, 30)), isFalse);
    // Sábado 01:30 em Lisboa (00:30 UTC, ainda hora de verão): o sábado
    // é 20:00–02:00, logo aberto — como o servidor.
    expect(kebab.isOpenNow(DateTime.utc(2026, 10, 24, 0, 30)), isTrue);
    expect(kebab.isOpenNow(DateTime.utc(2026, 10, 24, 21, 0)), isTrue);
  });

  test('o travão diz "Abre amanhã às" depois de fechar e o dia num dia fechado', () {
    expect(_loja().avisoLojaFechadaEm(_segunda2330), 'Loja bk está fechada agora. Abre amanhã às 11h00.');
    const fechado = DayHours(closed: true);
    final loja = _loja(
      horario: const BusinessHours(
          mon: fechado, tue: fechado, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d),
    );
    expect(loja.avisoLojaFechadaEm(_segunda1300), 'Loja bk está fechada hoje. Abre quarta às 11h00.');
  });

  test('lojas abertas parecidas: mesma secção, abertas, sem a própria', () {
    final bk = _loja();
    final aberta = _loja(id: 'mc', horario: const BusinessHours(
        mon: DayHours(open: '06:00', close: '23:59'),
        tue: _d, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d));
    final mercado = _loja(
        id: 'pd',
        categoria: BusinessCategory.supermarket,
        horario: const BusinessHours(
            mon: DayHours(open: '06:00', close: '23:59'),
            tue: _d, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d));
    final r = lojasAbertasParecidas([bk, aberta, mercado], bk, agora: _segunda0655);
    expect(r.map((e) => e.id), ['mc']);
  });

  test('os três sítios do tempo trocam-no pela faixa quando fechada', () {
    String ler(String p) => File(p).readAsStringSync();
    expect(ler('lib/screens/restaurants_screen.dart').contains('business.fechadaParaCliente'), isTrue);
    expect(ler('lib/screens/restaurant_menu_screen.dart').contains('model!.faixaFechada'), isTrue);
    expect(ler('lib/widgets/market/market_store_tab.dart').contains('restaurant.faixaFechada'), isTrue);
    expect(ler('lib/widgets/bora/coming_soon.dart').contains("'Ver lojas abertas parecidas'.tr"), isTrue);
  });
}
