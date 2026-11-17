// Impressão e personalizados (missão a3-guarda-16-11, parte 2): regras puras do modelo.
import 'package:bora_app/models/pedido_impressao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intervalo de páginas', () {
    test('vazio = todas', () => expect(paginasDoIntervalo('', 4), [1, 2, 3, 4]));
    test('misto com vírgulas e traços', () => expect(paginasDoIntervalo('1-3, 5', 6), [1, 2, 3, 5]));
    test('repetidas contam uma vez', () => expect(paginasDoIntervalo('2, 2, 1-2', 3), [1, 2]));
    test('fora do documento = inválido', () => expect(paginasDoIntervalo('1-9', 3), isNull));
    test('ao contrário = inválido', () => expect(paginasDoIntervalo('3-1', 3), isNull));
    test('texto = inválido', () => expect(paginasDoIntervalo('abc', 3), isNull));
  });

  test('euros em PT', () {
    expect(euros(975), '9,75 €');
    expect(euros(null), '—');
  });

  test('pedido lido da base, com resumo', () {
    final p = PedidoImpressao.fromMap({
      'id': 'x',
      'created_at': '2026-11-17T10:00:00Z',
      'restaurant_id': 'a3-guarda',
      'user_id': 'u',
      'tipo': 'impressao',
      'estado': 'aceite',
      'ficheiros': [
        {'path': 'u/a.pdf', 'nome': 'a.pdf', 'paginas': 12, 'tipo': 'pdf'}
      ],
      'tamanho': 'A4',
      'cor': true,
      'frente_verso': true,
      'papel': 'normal',
      'copias': 1,
      'paginas': 12,
      'acabamento': 'agrafar',
      'modo': 'entrega',
      'total_cents': 975,
      'is_demo': true,
    });
    expect(p.estado, ImpressaoEstado.aceite);
    expect(p.entrega, isTrue);
    expect(p.ficheiros.single.paginas, 12);
    expect(p.resumo, '12 pág. · A4 · cores · frente e verso · agrafado · 1 cópia');
    expect(impressaoEstadoTexto(p.estado), 'Em preparação');
  });
}
