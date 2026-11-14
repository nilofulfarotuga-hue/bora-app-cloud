// Missão farmacias-loja-2026-11-14 — partes puras do painel da farmácia:
// condições (comissão), ligação do WhatsApp do cliente e a hora marcada ("chega às").
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/farmacia_chegada.dart';
import 'package:bora_app/widgets/partner/farmacia_painel.dart';

void main() {
  group('textoCondicoesFarmacia', () {
    final agora = DateTime.utc(2026, 11, 14, 12);

    test('sem data de início: conta a partir da abertura ao público', () {
      expect(
        textoCondicoesFarmacia(pct: 0.10, inicio: null, meses: 3, agora: agora),
        '3 meses sem comissão a contar do dia em que a loja abrir ao público. '
        'Depois, 10 % sobre as vendas. Pagamento semanal.',
      );
    });

    test('data no futuro: "até DD/MM" em hora de Lisboa', () {
      expect(
        textoCondicoesFarmacia(
            pct: 0.10, inicio: DateTime.utc(2027, 2, 14, 10), meses: 3, agora: agora),
        '3 meses sem comissão até 14/02. Depois, 10 % sobre as vendas. Pagamento semanal.',
      );
    });

    test('data já passou: comissão em vigor', () {
      expect(
        textoCondicoesFarmacia(
            pct: 0.10, inicio: DateTime.utc(2026, 11, 1, 10), meses: 3, agora: agora),
        'Comissão de 10 % sobre as vendas desde 01/11. Pagamento semanal.',
      );
    });

    test('sem percentagem: sem comissão', () {
      expect(textoCondicoesFarmacia(pct: null, inicio: null, agora: agora),
          'Sem comissão sobre as vendas. Pagamento semanal.');
    });

    test('percentagem com casa decimal', () {
      expect(
        textoCondicoesFarmacia(pct: 0.125, inicio: null, meses: 1, agora: agora),
        '1 mês sem comissão a contar do dia em que a loja abrir ao público. '
        'Depois, 12,5 % sobre as vendas. Pagamento semanal.',
      );
    });
  });

  group('linkWhatsAppDoCliente', () {
    test('telemóvel português com e sem indicativo', () {
      expect(linkWhatsAppDoCliente('912345678').toString(), 'https://wa.me/351912345678');
      expect(linkWhatsAppDoCliente('+351 912 345 678').toString(),
          'https://wa.me/351912345678');
      expect(linkWhatsAppDoCliente('00351912345678').toString(),
          'https://wa.me/351912345678');
    });

    test('número estrangeiro só com indicativo', () {
      expect(linkWhatsAppDoCliente('+55 11 91234-5678').toString(),
          'https://wa.me/5511912345678');
      expect(linkWhatsAppDoCliente('0034612345678').toString(), 'https://wa.me/34612345678');
    });

    test('sem número utilizável não há botão', () {
      expect(linkWhatsAppDoCliente(null), isNull);
      expect(linkWhatsAppDoCliente(''), isNull);
      expect(linkWhatsAppDoCliente('271000000'), isNull); // fixo sem indicativo
      expect(linkWhatsAppDoCliente('abc'), isNull);
    });
  });

  group('FarmaciaChegada', () {
    test('estados lidos da base', () {
      expect(EstadoChegada.fromDb('pendente'), EstadoChegada.pendente);
      expect(EstadoChegada.fromDb('esperar'), EstadoChegada.esperar);
      expect(EstadoChegada.fromDb('tirar'), EstadoChegada.tirar);
      expect(EstadoChegada.fromDb('cancelar'), EstadoChegada.cancelar);
      expect(EstadoChegada.fromDb('anulado'), EstadoChegada.anulado);
      expect(EstadoChegada.fromDb(null), EstadoChegada.pendente);
      for (final e in EstadoChegada.values) {
        expect(EstadoChegada.fromDb(e.db), e);
      }
      expect(EstadoChegada.pendente.viva, isTrue);
      expect(EstadoChegada.esperar.viva, isTrue);
      expect(EstadoChegada.tirar.viva, isFalse);
      expect(EscolhaChegada.cancelar.db, 'cancelar');
    });

    test('linha da base e a mais recente', () {
      final a = FarmaciaChegada.fromMap({
        'id': 'a',
        'order_id': 'o1',
        'restaurant_id': 'farmacia-se-guarda',
        'linha_idx': 1,
        'product_id': 'p1',
        'produto_nome': ' Ben-u-ron ',
        'chega_as': '2026-11-14T15:00:00+00:00',
        'estado': 'pendente',
        'criado_em': '2026-11-14T12:00:00+00:00',
      });
      final b = FarmaciaChegada.fromMap({
        'id': 'b',
        'order_id': 'o1',
        'restaurant_id': 'farmacia-se-guarda',
        'linha_idx': null,
        'produto_nome': '',
        'chega_as': '2026-11-14T16:00:00+00:00',
        'estado': 'anulado',
        'criado_em': '2026-11-14T11:00:00+00:00',
      });
      expect(a.eUmProduto, isTrue);
      expect(a.produtoNome, 'Ben-u-ron');
      expect(hhmmFarmacia(a.chegaAs), '15:00');
      expect(b.eUmProduto, isFalse);
      expect(b.produtoNome, isNull);
      expect(FarmaciaChegada.maisRecente([b, a])?.id, 'a');
      expect(FarmaciaChegada.maisRecente(const []), isNull);
    });
  });
}
