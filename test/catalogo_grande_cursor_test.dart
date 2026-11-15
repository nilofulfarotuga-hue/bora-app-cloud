// Missão fechar-app-15-11, Bloco 3c — abrir um mercado grande deixou de pedir
// a loja inteira por offset (o Continente tem 19 808 produtos: 20 páginas, a
// última a saltar 19 000 linhas; a 14/11 18:02 o servidor respondeu erro 500).
// Cada página pede agora "o que vem depois da última linha recebida".
//
// A consulta em si só se prova contra o servidor (feito por SELECT a 14/11:
// depois da linha 1000 ficam 18 808 e a primeira é a 1001; depois da 8000, já
// sem sort_order, ficam 11 808 e a primeira é a 8001). Aqui prova-se o texto
// do filtro e, pela fonte, que o offset saiu mesmo do carregamento da loja.
import 'dart:io';

import 'package:bora_app/stores/restaurant_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A regra do cursor escrita em Dart simples, para conferir o filtro contra
/// uma lista pequena ordenada como o servidor ordena.
bool _vemDepois(Map<String, dynamic> linha, int? sort, String id) {
  final s = linha['sort_order'] as int?;
  final i = linha['id'] as String;
  if (sort == null) return s == null && i.compareTo(id) > 0;
  return (s != null && s > sort) ||
      (s != null && s == sort && i.compareTo(id) > 0) ||
      s == null;
}

void main() {
  test('filtro do cursor: maior sort_order, ou igual com id maior, ou vazio',
      () {
    expect(
      RestaurantStore.filtroDepoisDoCursor(120, 'cnt-2000022'),
      'sort_order.gt.120,'
      'and(sort_order.eq.120,id.gt."cnt-2000022"),'
      'sort_order.is.null',
    );
  });

  test('o id vai entre aspas e com as aspas e barras protegidas', () {
    final f = RestaurantStore.filtroDepoisDoCursor(5, r'a,b)"c\d');
    expect(f, contains(r'id.gt."a,b)\"c\\d"'));
    // A vírgula e o parêntese do id ficam DENTRO das aspas: não partem o filtro.
    expect(f.endsWith(',sort_order.is.null'), isTrue);
  });

  test('a regra do cursor percorre a lista toda, sem repetir nem saltar', () {
    // Ordem do servidor: sort_order crescente (vazios no fim), depois id.
    final linhas = <Map<String, dynamic>>[
      {'sort_order': 1, 'id': 'b'},
      {'sort_order': 2, 'id': 'a'},
      {'sort_order': 2, 'id': 'c'}, // empate no sort_order: decide o id
      {'sort_order': 7, 'id': 'a2'},
      {'sort_order': null, 'id': 'a1'},
      {'sort_order': null, 'id': 'm'},
      {'sort_order': null, 'id': 'z'},
    ];
    const pagina = 2;
    final recebidas = <String>[];
    int? sort;
    String? id;
    var voltas = 0;
    while (true) {
      final resto = id == null
          ? linhas
          : linhas.where((l) => _vemDepois(l, sort, id!)).toList();
      final pag = resto.take(pagina).toList();
      for (final l in pag) {
        recebidas.add('${l['sort_order']}/${l['id']}');
      }
      if (pag.isNotEmpty) {
        sort = pag.last['sort_order'] as int?;
        id = pag.last['id'] as String;
      }
      if (pag.length < pagina || ++voltas > 20) break;
    }
    expect(recebidas, ['1/b', '2/a', '2/c', '7/a2', 'null/a1', 'null/m', 'null/z']);
  });

  test('pela fonte: o carregamento da loja já não usa offset', () {
    final fonte = File('lib/stores/restaurant_store.dart')
        .readAsStringSync()
        .replaceAll(String.fromCharCode(13), '');
    final ini = fonte.indexOf('Future<void> loadFullStoreProducts(');
    final fim = fonte.indexOf('static const String _productProjection');
    expect(ini, greaterThan(0));
    expect(fim, greaterThan(ini));
    final corpo = fonte.substring(ini, fim);
    expect(corpo.contains('.range('), isFalse,
        reason: 'range(offset, …) é a paginação antiga');
    expect(corpo.contains('.limit(_storePageSize)'), isTrue);
    expect(corpo.contains('filtroDepoisDoCursor('), isTrue);
    expect(corpo.contains(".isFilter('sort_order', null).gt('id', c.id)"),
        isTrue,
        reason: 'na zona sem sort_order o cursor é só o id');
    // A ordem pedida ao servidor continua a mesma de sempre.
    expect(
        corpo.contains(
            ".order('sort_order', ascending: true, nullsFirst: false)"),
        isTrue);
    expect(corpo.contains(".order('id', ascending: true)"), isTrue);
  });
}
