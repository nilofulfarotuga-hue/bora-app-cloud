// Cancelamento tardio TVDE (17/10/2026): a app do cliente mostra o valor que
// o SERVIDOR vai cobrar (`tvde_cancel_quote`) e, depois de cancelar, o que
// foi mesmo cobrado (`cancel_fee_cents` devolvido por `tvde_cancel_ride`).
//
// Antes a app contava a janela grátis desde o PEDIDO e calculava o valor
// sozinha — podia prometer um valor e cobrar outro. Estes testes prendem:
//  (i)  a leitura da cotação e a escolha texto/botão para cada regra, mais
//       terminal, erro e campos em falta;
//  (ii) o `cancelRide` devolve a taxa real (store com cliente falso).
import 'package:bora_app/models/tvde_cancel_quote.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/tvde/tvde_rides_history_screen.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _cotacao(String regra,
        {int fee = 0,
        int fare = 700,
        String? como,
        int grace = 180,
        int desde = 0,
        int restam = 0,
        bool motorista = true}) =>
    {
      'ok': true,
      'terminal': false,
      'regra': regra,
      'fee_cents': fee,
      'fare_cents': fare,
      'como_cobra': como,
      'grace_seconds': grace,
      'seconds_since_accept': desde,
      'seconds_left_free': restam,
      'had_driver': motorista,
      'accepted_at': '2026-10-17T13:00:00+00:00',
    };

/// Store com o cliente Supabase trocado por respostas fixas.
class _StoreFalsa extends TvdeStore {
  _StoreFalsa(this.respostas);
  final Map<String, Object? Function(Map<String, dynamic>)> respostas;
  final List<(String, Map<String, dynamic>)> chamadas = [];

  @override
  Future<dynamic> rpcCancelamento(
      String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, params));
    final r = respostas[fn];
    if (r == null) throw StateError('RPC inesperada: $fn');
    return r(params);
  }
}

void main() {
  group('(i) leitura da cotação', () {
    test('cada regra lê-se com todos os campos', () {
      for (final regra in kRegrasDeCancelamento) {
        final q = TvdeCancelQuote.fromJson(_cotacao(regra,
            fee: 700, como: 'carteira', desde: 200, restam: 0))!;
        expect(q.ok, isTrue);
        expect(q.terminal, isFalse);
        expect(q.regra, regra);
        expect(q.feeCents, 700);
        expect(q.fareCents, 700);
        expect(q.comoCobra, 'carteira');
        expect(q.graceSeconds, 180);
        expect(q.secondsSinceAccept, 200);
        expect(q.hadDriver, isTrue);
        expect(q.acceptedAt, DateTime.utc(2026, 10, 17, 13));
      }
    });

    test('terminal: só status e fee_cents; sem_motorista não é "já terminou"',
        () {
      final cancelada = TvdeCancelQuote.fromJson({
        'ok': true,
        'terminal': true,
        'status': 'cancelada_cliente',
        'fee_cents': 700,
      })!;
      expect(cancelada.jaTerminou, isTrue);
      expect(textoJaTerminou(cancelada), 'A corrida já estava cancelada.');
      final finalizada = TvdeCancelQuote.fromJson(
          {'ok': true, 'terminal': true, 'status': 'finalizada'})!;
      expect(textoJaTerminou(finalizada), 'A corrida já tinha terminado.');
      final semMotorista = TvdeCancelQuote.fromJson(
          {'ok': true, 'terminal': true, 'status': 'sem_motorista'})!;
      expect(semMotorista.jaTerminou, isFalse,
          reason: 'sem motorista o cancelamento normal segue, sem custo');
      expect(semMotorista.taxaAMostrar, 0);
    });

    test('erros e lixo dão null (o ecrã mostra o aviso neutro)', () {
      for (final erro in ['ride_not_found', 'not_authorized', 'quote_failed']) {
        expect(TvdeCancelQuote.fromJson({'ok': false, 'error': erro}), isNull);
      }
      expect(TvdeCancelQuote.fromJson(null), isNull);
      expect(TvdeCancelQuote.fromJson('ok'), isNull);
      expect(TvdeCancelQuote.fromJson(const []), isNull);
      expect(TvdeCancelQuote.fromJson({'terminal': false}), isNull,
          reason: 'sem ok:true não é cotação');
      expect(TvdeCancelQuote.fromJson({'ok': true, 'regra': 'regra_nova'}),
          isNull,
          reason: 'regra que a app não conhece → aviso neutro');
      expect(TvdeCancelQuote.fromJson({'ok': true, 'terminal': true}), isNull,
          reason: 'terminal sem estado não diz nada');
    });

    test('campos em falta ou com tipos trocados ficam a zero', () {
      final q = TvdeCancelQuote.fromJson({
        'ok': true,
        'regra': 'corrida_inteira',
        'fee_cents': '850',
        'seconds_since_accept': 241.6,
        'accepted_at': 'não é data',
      })!;
      expect(q.feeCents, 850);
      expect(q.fareCents, 0);
      expect(q.secondsSinceAccept, 241);
      expect(q.graceSeconds, 0);
      expect(q.hadDriver, isFalse);
      expect(q.acceptedAt, isNull);
      expect(q.comoCobra, isNull);
      // Uma lista com a linha também se aceita (forma de algumas RPCs).
      expect(TvdeCancelQuote.fromJson([_cotacao('sem_custo')])!.regra,
          'sem_custo');
    });
  });

  group('(i) texto e botão para cada regra', () {
    test('sem_custo: sem motorista / com motorista', () {
      final semMot = textoDoCancelamento(
          TvdeCancelQuote.fromJson(_cotacao('sem_custo', motorista: false)),
          minutosDaJanela: 3);
      expect(semMot.principal,
          'Ainda nenhum motorista aceitou. Cancelas sem custo.');
      expect(semMot.confirmar, 'Sim, cancelar');
      expect(semMot.taxaCents, 0);
      expect(semMot.caixaCusto, isNull);
      final comMot = textoDoCancelamento(
          TvdeCancelQuote.fromJson(_cotacao('sem_custo')),
          minutosDaJanela: 3);
      expect(comMot.principal, 'Cancelamento sem custo.');
      expect(comMot.confirmar, 'Sim, cancelar');
    });

    test('dentro_da_graca: contador mm:ss desde o aceitar + aviso do depois',
        () {
      final q = TvdeCancelQuote.fromJson(
          _cotacao('dentro_da_graca', desde: 105, restam: 75, fare: 820))!;
      final t = textoDoCancelamento(q, minutosDaJanela: 3);
      expect(t.contador, isTrue);
      expect(t.principal,
          'Cancelamento grátis durante mais 01:15 (conta desde que o motorista aceitou).');
      expect(t.detalhe,
          'Passado esse tempo, cancelar passa a ter custo (até 8,20 €, o valor da corrida).');
      expect(t.confirmar, 'Sim, cancelar');
      expect(t.taxaCents, 0);
      // O contador vivo manda sobre o número do servidor.
      expect(
          textoDoCancelamento(q, minutosDaJanela: 3, segundosRestantes: 9)
              .principal,
          contains('mais 00:09 '));
      // Sem tarifa conhecida não se promete um "até".
      final semTarifa = textoDoCancelamento(
          TvdeCancelQuote.fromJson(
              _cotacao('dentro_da_graca', restam: 30, fare: 0)),
          minutosDaJanela: 3);
      expect(semTarifa.detalhe, isNull);
    });

    test('corrida_inteira: caixa vermelha + como se cobra (online e carteira)',
        () {
      final online = textoDoCancelamento(
          TvdeCancelQuote.fromJson(_cotacao('corrida_inteira',
              fee: 1250, fare: 1250, como: 'pagamento_retido', desde: 400)),
          minutosDaJanela: 3);
      expect(online.caixaCusto, 'Custo de cancelamento: 12,50 €');
      expect(online.principal,
          'O motorista já aceitou há mais de 3 min. Cancelar agora custa o valor total da corrida.');
      expect(online.detalhe,
          'Esta corrida já está paga: o valor pago fica retido.');
      expect(online.confirmar, 'Cancelar e pagar 12,50 €');
      expect(online.taxaCents, 1250);
      final carteira = textoDoCancelamento(
          TvdeCancelQuote.fromJson(_cotacao('corrida_inteira',
              fee: 600, fare: 600, como: 'carteira', grace: 300)),
          minutosDaJanela: 3);
      expect(carteira.principal, contains('há mais de 5 min'),
          reason: 'os minutos vêm da cotação, não da app');
      expect(carteira.detalhe,
          'O valor é debitado da tua carteira Bora (se não tiveres saldo, fica como dívida).');
      expect(carteira.confirmar, 'Cancelar e pagar 6,00 €');
    });

    test('taxa_fixa: uma frase com a taxa', () {
      final t = textoDoCancelamento(
          TvdeCancelQuote.fromJson(_cotacao('taxa_fixa', fee: 250)),
          minutosDaJanela: 3);
      expect(t.principal, 'Cancelar agora tem uma taxa de 2,50 €.');
      expect(t.caixaCusto, isNull);
      expect(t.confirmar, 'Cancelar e pagar 2,50 €');
      expect(t.taxaCents, 250);
    });

    test('terminal sem_motorista no diálogo = nenhum motorista aceitou', () {
      final t = textoDoCancelamento(
          TvdeCancelQuote.fromJson(
              {'ok': true, 'terminal': true, 'status': 'sem_motorista'}),
          minutosDaJanela: 3);
      expect(t.principal,
          'Ainda nenhum motorista aceitou. Cancelas sem custo.');
      expect(t.confirmar, 'Sim, cancelar');
      expect(t.taxaCents, 0);
    });

    test('cotação falhada: aviso neutro, sem números de dinheiro', () {
      final t = textoDoCancelamento(null, minutosDaJanela: 3);
      expect(t.semCotacao, isTrue);
      expect(t.taxaCents, -1);
      expect(t.principal,
          'Não foi possível confirmar agora o custo do cancelamento. Se o motorista já aceitou há mais de 3 min, cancelar custa o valor da corrida. Queres cancelar na mesma?');
      expect(t.principal.contains('€'), isFalse);
      expect(t.confirmar, 'Cancelar na mesma');
    });

    test('depois de cancelar diz o que foi cobrado', () {
      expect(textoDepoisDeCancelar(820), 'Corrida cancelada. Foram cobrados 8,20 €.');
      expect(textoDepoisDeCancelar(0), 'Corrida cancelada. Sem custo.');
    });
  });

  group('(ii) a store fala com o servidor', () {
    test('cancelRide devolve a taxa REAL cobrada pelo servidor', () async {
      final store = _StoreFalsa({
        'tvde_cancel_ride': (p) => {
              'id': p['p_ride_id'],
              'status': 'cancelada_cliente',
              'cancel_fee_cents': 820,
            },
      });
      final cobrada = await store.cancelRide('r1');
      expect(cobrada, 820);
      expect(store.chamadas.single.$1, 'tvde_cancel_ride');
      expect(store.chamadas.single.$2,
          {'p_ride_id': 'r1', 'p_actor': 'cliente', 'p_reason': null});
      expect(store.busy, isFalse);
    });

    test('taxa ilegível ou em falta → 0; lista com a linha também serve',
        () async {
      expect(
          await _StoreFalsa({'tvde_cancel_ride': (_) => {'id': 'r1'}})
              .cancelRide('r1'),
          0);
      expect(
          await _StoreFalsa({
            'tvde_cancel_ride': (_) => [
                  {'id': 'r1', 'cancel_fee_cents': 250}
                ]
          }).cancelRide('r1'),
          250);
      expect(taxaCobradaDoCancelamento('lixo'), 0);
      expect(taxaCobradaDoCancelamento({'cancel_fee_cents': -5}), 0);
    });

    test('erro do servidor ao cancelar continua a subir (o ecrã trata)',
        () async {
      final store = _StoreFalsa({
        'tvde_cancel_ride': (_) => throw Exception('ride_already_terminal'),
      });
      await expectLater(store.cancelRide('r1'), throwsException);
      expect(store.busy, isFalse);
    });

    test('cancelQuote: lê a cotação; ok:false ou erro → null, nunca lança',
        () async {
      final boa = _StoreFalsa(
          {'tvde_cancel_quote': (_) => _cotacao('corrida_inteira', fee: 700)});
      final q = await boa.cancelQuote('r1');
      expect(q?.regra, 'corrida_inteira');
      expect(boa.chamadas.single.$2, {'p_ride_id': 'r1'});
      expect(
          await _StoreFalsa({
            'tvde_cancel_quote': (_) => {'ok': false, 'error': 'not_authorized'}
          }).cancelQuote('r1'),
          isNull);
      expect(
          await _StoreFalsa(
                  {'tvde_cancel_quote': (_) => throw Exception('sem rede')})
              .cancelQuote('r1'),
          isNull);
    });
  });

  group('histórico: corrida cancelada mostra a taxa cobrada', () {
    TvdeRide corrida(String status, {int? taxa}) => TvdeRide.fromMap({
          'id': 'r1',
          'client_id': 'c1',
          'status': status,
          'est_fare_cents': 700,
          if (taxa != null) 'cancel_fee_cents': taxa,
        });

    test('cancelada com taxa, cancelada sem taxa, finalizada', () {
      expect(corrida('cancelada_cliente', taxa: 700).cancelFeeCents, 700);
      expect(valorNoHistorico(corrida('cancelada_cliente', taxa: 700),
              packageCents: 800),
          '€7.00');
      expect(
          valorNoHistorico(corrida('cancelada_cliente', taxa: 0),
              packageCents: 800),
          'Sem custo');
      expect(
          valorNoHistorico(corrida('cancelada_motorista'), packageCents: 800),
          'Sem custo',
          reason: 'sem o campo no mapa a taxa é 0, não a tarifa');
      expect(valorNoHistorico(corrida('finalizada'), packageCents: 800),
          '€7.00',
          reason: 'as não-canceladas continuam a mostrar a tarifa');
    });
  });
}
