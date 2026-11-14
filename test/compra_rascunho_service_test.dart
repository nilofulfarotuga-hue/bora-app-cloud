// Compra guardada (14/11/2026, pedido b2b746d7 · Auchan): cada toque do
// estafeta fica gravado e volta igual ao reabrir a lista.

import 'dart:convert';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/services/compra_rascunho_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<CartItem> listaAuchan() => [
      CartItem(productId: 'p-pizza', name: 'Pizza 4 queijos', price: 3.45, quantity: 2),
      CartItem(productId: 'p-queijo', name: 'Queijo ralado', price: 1.15, quantity: 1),
      CartItem(productId: 'p-leite', name: 'Leite meio-gordo', price: 0.92, quantity: 6),
      // o mesmo produto duas vezes (opções diferentes)
      CartItem(productId: 'p-pizza', name: 'Pizza 4 queijos (sem cebola)', price: 3.45, quantity: 1),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CompraRascunhoService.limparParaTeste();
  });

  test('chaves estáveis: o mesmo produto duas vezes tem #0 e #1', () {
    expect(chavesDosItens(listaAuchan()),
        ['p-pizza#0', 'p-queijo#0', 'p-leite#0', 'p-pizza#1']);
  });

  test('marcar, trocar e repor: tudo volta igual ao reabrir', () {
    final ecra = listaAuchan();
    ecra[0].purchaseStatus = 'unavailable'; // pizzas trocadas
    ecra[1].purchaseStatus = 'unavailable'; // queijo em falta
    ecra[2].purchaseStatus = 'bought';
    ecra.add(CartItem(
      productId: 'extra_1731600000000',
      name: 'Pizza margarita',
      price: 2.99,
      quantity: 2,
      purchaseStatus: 'bought',
    ));
    final r = rascunhoDoEcra(
        orderId: 'b2b746d7', itens: ecra, seq: 10, sacos: 3, totalTalaoCents: 2345);

    // Ida e volta pelo JSON do telemóvel.
    final lido = RascunhoCompra.fromJson(r.toJson())!;
    final reaberto = aplicarRascunho(listaAuchan(), lido);

    expect(reaberto.map((i) => i.purchaseStatus).toList(),
        ['unavailable', 'unavailable', 'bought', 'pending', 'bought']);
    expect(reaberto.last.name, 'Pizza margarita');
    expect(reaberto.last.price, 2.99);
    expect(reaberto.last.quantity, 2);
    expect(lido.sacos, 3);
    expect(lido.totalTalaoCents, 2345);
    expect(lido.marcados, 4); // 3 linhas marcadas + 1 acrescentado
  });

  test('lê a linha do servidor (client_seq, bag_count, receipt_*)', () {
    final r = RascunhoCompra.fromJson({
      'order_id': 'x',
      'itens': {
        'p-queijo#0': {'s': 'unavailable', 'q': 1},
        'lixo#0': {'s': 'qualquer'}, // ignorado
      },
      'extras': [
        {'id': 'extra_1', 'nome': 'Fiambre', 'preco_cents': 199, 'qtd': 1, 's': 'bought'}
      ],
      'client_seq': 77,
      'bag_count': 2,
      'receipt_total_cents': 1500,
      'receipt_photo_path': 'receipts/x/1.jpg',
      'updated_at': '2026-11-14T16:30:00Z',
    }, pendente: false)!;
    expect(r.seq, 77);
    expect(r.sacos, 2);
    expect(r.totalTalaoCents, 1500);
    expect(r.fotoPath, 'receipts/x/1.jpg');
    expect(r.itens.keys, ['p-queijo#0']);
    expect(r.pendente, isFalse);
  });

  test('escolher: ganha o seq maior; empate fica o do servidor', () {
    RascunhoCompra v(int seq, bool pend) => RascunhoCompra(
        orderId: 'o', itens: const {}, extras: const [], seq: seq, pendente: pend);
    final local = v(20, true);
    final servidor = v(10, false);
    expect(RascunhoCompra.escolher(local, servidor), same(local));
    expect(RascunhoCompra.escolher(v(5, true), servidor), same(servidor));
    final empate = v(10, false);
    expect(RascunhoCompra.escolher(v(10, true), empate), same(empate));
    expect(RascunhoCompra.escolher(null, servidor), same(servidor));
  });

  test('sem rede: fica no telemóvel; com rede volta e manda o mais recente', () async {
    var online = false;
    final enviados = <int>[];
    CompraRascunhoService.enviarParaTeste = (p) async {
      if (!online) throw Exception('SocketException: sem rede');
      enviados.add(p['p_seq'] as int);
      return {'ok': true, 'applied': true};
    };

    final ecra = listaAuchan()..[1].purchaseStatus = 'unavailable';
    await CompraRascunhoService.guardar(rascunhoDoEcra(
        orderId: 'o1', itens: ecra, seq: CompraRascunhoService.proximoSeq()));
    // 3 tentativas falhadas (1 s + 3 s + 5 s de espera) → fica no telemóvel.
    await Future<void>.delayed(const Duration(seconds: 10));
    expect(CompraRascunhoService.estado('o1').value,
        EstadoGravacaoCompra.soNoTelemovel);
    expect(enviados, isEmpty);

    // A app "reinicia": a memória perde-se, o telemóvel guarda.
    CompraRascunhoService.limparParaTeste();
    CompraRascunhoService.enviarParaTeste = (p) async {
      if (!online) throw Exception('sem rede');
      enviados.add(p['p_seq'] as int);
      return {'ok': true, 'applied': true};
    };
    online = true;
    await CompraRascunhoService.reenviarPendentes();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(enviados.length, 1);
    expect(CompraRascunhoService.estado('o1').value,
        EstadoGravacaoCompra.guardado);
    // A cópia do telemóvel continua lá, agora marcada como confirmada.
    final prefs = await SharedPreferences.getInstance();
    final local = RascunhoCompra.fromJson(
        jsonDecode(prefs.getString('bora.compra_rascunho.v1.o1')!));
    expect(local!.pendente, isFalse);
    expect(local.itens['p-queijo#0']!.estado, 'unavailable');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('toque duplo / toques rápidos: o último é o que fica no servidor', () async {
    final enviados = <Map<String, dynamic>>[];
    CompraRascunhoService.enviarParaTeste = (p) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      enviados.add(p);
      return {'ok': true, 'applied': true};
    };
    final ecra = listaAuchan();
    for (final s in ['bought', 'pending', 'bought', 'unavailable']) {
      ecra[0].purchaseStatus = s;
      await CompraRascunhoService.guardar(rascunhoDoEcra(
          orderId: 'o2', itens: ecra, seq: CompraRascunhoService.proximoSeq()));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ultimo = enviados.last;
    expect((ultimo['p_itens'] as Map)['p-pizza#0'], {'s': 'unavailable', 'q': 2});
    // Os seq enviados sobem sempre (o servidor ignora um atrasado).
    final seqs = enviados.map((e) => e['p_seq'] as int).toList();
    expect(seqs, [...seqs]..sort());
    expect(CompraRascunhoService.estado('o2').value,
        EstadoGravacaoCompra.guardado);
  });

  test('pedido entregue/cancelado: o servidor diz ORDER_CLOSED e a cópia sai', () async {
    CompraRascunhoService.enviarParaTeste =
        (p) async => {'ok': false, 'error': 'ORDER_CLOSED'};
    await CompraRascunhoService.guardar(rascunhoDoEcra(
        orderId: 'o3', itens: listaAuchan(), seq: CompraRascunhoService.proximoSeq()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bora.compra_rascunho.v1.o3'), isNull);
    expect(CompraRascunhoService.emMemoria('o3'), isNull);
  });

  test('leitura lenta do servidor não apaga um toque mais novo', () async {
    CompraRascunhoService.enviarParaTeste =
        (p) async => {'ok': true, 'applied': true};
    CompraRascunhoService.lerParaTeste = (id) async => {
          'ok': true,
          'finalized': false,
          'rascunho': {
            'order_id': 'o5',
            'itens': {
              'p-pizza#0': {'s': 'pending', 'q': 2}
            },
            'client_seq': 5,
          },
        };
    final ecra = listaAuchan()..[0].purchaseStatus = 'bought';
    await CompraRascunhoService.guardar(rascunhoDoEcra(
        orderId: 'o5', itens: ecra, seq: CompraRascunhoService.proximoSeq()));
    final s = await CompraRascunhoService.carregarServidor('o5');
    expect(s, isNull, reason: 'o do servidor é mais velho: não entra');
    expect(CompraRascunhoService.emMemoria('o5')!.itens['p-pizza#0']!.estado,
        'bought');
    final prefs = await SharedPreferences.getInstance();
    final local = RascunhoCompra.fromJson(
        jsonDecode(prefs.getString('bora.compra_rascunho.v1.o5')!))!;
    expect(local.itens['p-pizza#0']!.estado, 'bought');
  });

  test('servidor com número maior: reenvia acima dele, sem "Guardado" falso',
      () async {
    final servidorSeq = DateTime.now().millisecondsSinceEpoch + 10000000;
    final enviados = <int>[];
    CompraRascunhoService.enviarParaTeste = (p) async {
      final seq = p['p_seq'] as int;
      enviados.add(seq);
      if (seq <= servidorSeq) {
        return {'ok': true, 'applied': false, 'stale': true, 'seq': servidorSeq};
      }
      return {'ok': true, 'applied': true, 'seq': seq};
    };
    await CompraRascunhoService.guardar(rascunhoDoEcra(
        orderId: 'o6',
        itens: listaAuchan()..[1].purchaseStatus = 'unavailable',
        seq: CompraRascunhoService.proximoSeq()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(enviados.length, 2);
    expect(enviados.last, greaterThan(servidorSeq));
    expect(CompraRascunhoService.estado('o6').value,
        EstadoGravacaoCompra.guardado);
  });

  test('compra aberta conta como em curso (o mapa não lhe tira o foco)', () {
    expect(CompraRascunhoService.temCompraEmCurso('o4'), isFalse);
    CompraRascunhoService.marcarCompraAberta('o4');
    expect(CompraRascunhoService.temCompraEmCurso('o4'), isTrue);
  });
}
