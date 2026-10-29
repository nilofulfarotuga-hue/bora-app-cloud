import 'package:bora_app/screens/admin/faturas_bora_semana.dart';
import 'package:flutter_test/flutter_test.dart';

/// missao-geral-2026-10-28, H2/N4 — faturas da Bora no "Fecho do mês":
/// semana de segunda a domingo, base e IVA 23% por data, e o CSV.
/// Dados de teste inventados (nada de clientes reais).
void main() {
  const f = FaturasBoraSemana.baseEIva;

  group('base e IVA', () {
    test('outubro e antes: base = valor, IVA 0 (isenção)', () {
      expect(f(250, DateTime(2026, 10, 31)), (base: 250, iva: 0));
      expect(f(362, DateTime(2026, 10, 1)), (base: 362, iva: 0));
      expect(f(1000, DateTime(2026, 9, 15)), (base: 1000, iva: 0));
    });

    test('de 01/11/2026: base = valor ÷ 1,23 ao cêntimo, IVA = valor − base',
        () {
      expect(f(250, DateTime(2026, 11, 1)), (base: 203, iva: 47));
      expect(f(100, DateTime(2026, 11, 2)), (base: 81, iva: 19));
      expect(f(362, DateTime(2026, 12, 1)), (base: 294, iva: 68));
      expect(f(1000, DateTime(2027, 1, 1)), (base: 813, iva: 187));
      expect(f(123, DateTime(2026, 11, 3)), (base: 100, iva: 23));
      expect(f(0, DateTime(2026, 11, 3)), (base: 0, iva: 0));
    });

    test('base + IVA dá sempre o valor, em 1 a 10 000 cêntimos', () {
      for (var v = 1; v <= 10000; v++) {
        final r = f(v, DateTime(2026, 11, 10));
        expect(r.base + r.iva, v);
        // A base é a mais próxima de valor ÷ 1,23.
        expect((r.base - v / 1.23).abs() <= 0.5, isTrue, reason: '$v');
      }
    });

    test('cêntimos e euros com vírgula', () {
      expect(FaturasBoraSemana.cents(2.5), 250);
      expect(FaturasBoraSemana.cents('3.62'), 362);
      expect(FaturasBoraSemana.cents(null), 0);
      expect(FaturasBoraSemana.eur(203), '2,03');
      expect(FaturasBoraSemana.eur(5), '0,05');
      expect(FaturasBoraSemana.eur(-250), '-2,50');
    });
  });

  group('semana de segunda a domingo', () {
    test('segunda-feira e domingo', () {
      expect(FaturasBoraSemana.segundaFeira(DateTime(2026, 11, 1)),
          DateTime(2026, 10, 26));
      expect(FaturasBoraSemana.segundaFeira(DateTime(2026, 10, 26)),
          DateTime(2026, 10, 26));
      expect(FaturasBoraSemana.segundaFeira(DateTime(2026, 10, 25, 23, 30)),
          DateTime(2026, 10, 19));
      expect(FaturasBoraSemana.domingo(DateTime(2026, 10, 26)),
          DateTime(2026, 11, 1));
    });

    test('semanas que tocam outubro e novembro de 2026', () {
      expect(FaturasBoraSemana.semanasDoMes(2026, 10), [
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
      ]);
      expect(FaturasBoraSemana.semanasDoMes(2026, 11).first,
          DateTime(2026, 10, 26));
      expect(FaturasBoraSemana.semanasDoMes(2026, 11).last,
          DateTime(2026, 11, 30));
      expect(FaturasBoraSemana.semanasDoMes(2026, 11), hasLength(6));
    });

    test('rótulo e meses por onde passa', () {
      expect(FaturasBoraSemana.rotuloSemana(DateTime(2026, 10, 26)),
          '26/10 a 01/11');
      expect(FaturasBoraSemana.mesesDaSemana(DateTime(2026, 10, 26)),
          [(2026, 10), (2026, 11)]);
      expect(FaturasBoraSemana.mesesDaSemana(DateTime(2026, 10, 5)),
          [(2026, 10)]);
      expect(FaturasBoraSemana.mesesDaSemana(DateTime(2026, 12, 28)),
          [(2026, 12), (2027, 1)]);
    });

    test('daSemana fica com segunda..domingo, sem repetidas, por data', () {
      final linhas = [
        {'id': 'a', 'data': '2026-11-02', 'valor': 1},
        {'id': 'b', 'data': '2026-11-01', 'valor': 1},
        {'id': 'c', 'data': '2026-10-25', 'valor': 1},
        {'id': 'd', 'data': '2026-10-26', 'valor': 1},
        {'id': 'd', 'data': '2026-10-26', 'valor': 1},
        {'id': 'e', 'data': null, 'valor': 1},
      ];
      final s = FaturasBoraSemana.daSemana(linhas, DateTime(2026, 10, 26));
      expect(s.map((l) => l['id']), ['d', 'b']);
    });
  });

  group('CSV', () {
    final linhas = <Map<String, dynamic>>[
      {
        'id': '1',
        'order_id': 'pedido-teste-0001',
        'data': '2026-10-30',
        'valor': 3.62,
        'cliente_nif': '123456789',
        'cliente_nome': 'Cliente Teste; Lda',
        'iva': 'IVA — regime de isenção (art. 53.º CIVA), M10',
        'descricao': 'Taxa de serviço e intermediação — plataforma Bora',
        'estado': 'por_lancar',
      },
      {
        'id': '2',
        'order_id': 'pedido-teste-0002',
        'data': '2026-11-01',
        'valor': 2.5,
        'cliente_nif': null,
        'cliente_nome': 'Consumidor final',
        'iva': 'IVA 23% incluído — regime normal',
        'descricao': 'Taxa de cancelamento — plataforma Bora',
        'estado': 'lancada',
      },
      {
        'id': '3',
        'order_id': 'pedido-teste-0003',
        'data': '2026-11-01',
        'valor': 0,
        'cliente_nif': null,
        'cliente_nome': 'Consumidor final',
        'iva': null,
        'descricao': 'Serviço da plataforma Bora',
        'estado': 'sem_valor',
      },
      {
        'id': '4',
        'order_id': 'p5',
        'data': '2026-11-03',
        'valor': '1.00',
        'cliente_nif': '',
        'cliente_nome': '',
        'iva': null,
        'descricao': 'Serviço da plataforma Bora',
        'estado': 'por_lancar',
      },
    ];

    test('linhas: data, pedido curto, cliente, NIF, valor, base, IVA, regime',
        () {
      final r = FaturasBoraSemana.linhasCsv(linhas);
      expect(r, hasLength(3), reason: 'a sem_valor fica de fora');
      expect(r[0], [
        '30/10/2026',
        'pedido-t',
        'Cliente Teste; Lda',
        '123456789',
        '3,62',
        '3,62',
        '0,00',
        'IVA — regime de isenção (art. 53.º CIVA), M10',
        'Taxa de serviço e intermediação — plataforma Bora',
        'por lançar',
      ]);
      expect(r[1].sublist(0, 8), [
        '01/11/2026',
        'pedido-t',
        'Consumidor final',
        '',
        '2,50',
        '2,03',
        '0,47',
        'IVA 23% incluído — regime normal',
      ]);
      expect(r[1][9], 'lançada');
      // Sem nome nem regime do servidor: "Consumidor final" e o regime da data.
      expect(r[2].sublist(0, 8), [
        '03/11/2026',
        'p5',
        'Consumidor final',
        '',
        '1,00',
        '0,81',
        '0,19',
        FaturasBoraSemana.regimeNormal,
      ]);
    });

    test('texto: cabeçalho, ";" e aspas no campo que as pede', () {
      final t = FaturasBoraSemana.csv(linhas).split('\n');
      expect(t.first,
          'Data;Pedido;Cliente;NIF;Valor (EUR);Base (EUR);IVA 23% (EUR);Regime;Descrição;Estado');
      expect(t, hasLength(4));
      expect(t[1], startsWith('30/10/2026;pedido-t;"Cliente Teste; Lda";123456789;3,62;3,62;0,00;'));
    });

    test('mês sem faturas: só o cabeçalho', () {
      expect(FaturasBoraSemana.csv(const []).split('\n'), hasLength(1));
    });
  });

  group('nota do IVA vem do servidor', () {
    const frase =
        'IVA: até outubro de 2026, isenção do art. 53.º do CIVA (M10); a partir de novembro de 2026, regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.';
    test('chave nota_iva quando existe', () {
      expect(FaturasBoraSemana.notaIva({'nota_iva': frase, 'texto': 'x'}),
          frase);
    });
    test('senão, a frase "IVA: ..." do texto', () {
      expect(
          FaturasBoraSemana.notaIva(
              {'texto': 'Receita própria da Bora em outubro de 2026: 1 €. $frase'}),
          frase);
    });
    test('sem nada: null', () {
      expect(FaturasBoraSemana.notaIva({'texto': 'sem nota'}), isNull);
      expect(FaturasBoraSemana.notaIva(const {}), isNull);
    });
  });
}
