import 'dart:io';

import 'package:bora_app/screens/admin/faturas_bora_semana.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, bloco E5 — nada se emite: o email ao
/// cliente passa a "Resumo do pedido — este documento não serve de fatura" e o
/// painel exporta a lista das faturas por emitir em CSV e PDF.
/// Dados de teste inventados (nada de clientes reais).
void main() {
  final linhas = <Map<String, dynamic>>[
    {
      'id': 'a',
      'order_id': 'abcdef1234567',
      'data': '2026-10-02',
      'valor': 1,
      'cliente_nome': 'Consumidor final',
      'descricao': 'Taxa de serviço e intermediação — plataforma Bora',
      'estado': 'por_lancar',
    },
    {
      'id': 'b',
      'order_id': 'zzz',
      'data': '2026-10-14',
      'valor': 0,
      'estado': 'sem_valor',
    },
    {
      'id': 'c',
      'order_id': '1234567890',
      'data': '2026-11-02',
      'valor': 2.46,
      'cliente_nif': '123456789',
      'cliente_nome': 'Cliente Teste',
      'descricao': 'Serviço da plataforma Bora',
      'estado': 'por_lancar',
    },
  ];

  group('PDF para o contabilista', () {
    test('as mesmas linhas do CSV, sem as que não têm valor', () {
      final pdf = FaturasBoraSemana.linhasPdf(linhas);
      expect(pdf, hasLength(2));
      expect(FaturasBoraSemana.cabecalhoPdf, hasLength(8));
      for (final r in pdf) {
        expect(r, hasLength(FaturasBoraSemana.cabecalhoPdf.length));
      }
      expect(pdf[0], ['02/10/2026', 'abcdef12', 'Consumidor final', '', '1,00', '1,00', '0,00', 'por lançar']);
      expect(pdf[1], ['02/11/2026', '12345678', 'Cliente Teste', '123456789', '2,46', '2,00', '0,46', 'por lançar']);
    });

    test('botão PDF ao lado do CSV, no "Fecho do mês"', () {
      final s = File('lib/screens/admin/admin_fecho_mensal_screen.dart')
          .readAsStringSync();
      expect(s, contains("key: const ValueKey('faturas_pdf')"));
      expect(s, contains('headers: FaturasBoraSemana.cabecalhoPdf'));
      expect(s, contains('Este documento não é fatura.'));
    });
  });

  group('email ao cliente (recibo-pedido-cliente)', () {
    final ts = File('supabase/functions/recibo-pedido-cliente/index.ts')
        .readAsStringSync();

    test('título "Resumo do pedido — este documento não serve de fatura"', () {
      expect(
          ts,
          contains("export const TITULO_RESUMO = 'Resumo do pedido — este "
              "documento não serve de fatura'"));
      expect(ts, contains(r'subject: `${TITULO_RESUMO}'));
      expect(ts, contains('Este documento não serve de fatura.'));
      expect(ts, isNot(contains('Recibo do teu pedido')));
      expect(ts, isNot(contains('Recibo emitido pela Bora')));
    });

    test('rodapé com a sociedade e o Livro de Reclamações', () {
      expect(ts, contains('Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233'));
      expect(ts, contains('sede Rua do Torreão 14, 6300-610 Guarda'));
      expect(ts, contains('www.livroreclamacoes.pt'));
    });
  });

  test('a conferência não leva NIFs (repositório público)', () {
    final md = File(
            'docs/propostas/fechar-tudo-2026-11-10/E5_faturas_conferencia.md')
        .readAsStringSync();
    expect(RegExp(r'(?<!\d)\d{9}(?!\d)').hasMatch(md), isFalse);
    expect(md, contains('152,85 €'));
    expect(md, contains('O que falta decidir com o Hugo'));
  });
}
