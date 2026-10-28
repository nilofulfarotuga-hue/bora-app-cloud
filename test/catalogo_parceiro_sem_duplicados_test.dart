// CATÁLOGO DO PARCEIRO NÃO PODE APARECER A DOBRAR.
//
// Achado a 27/10/2026 (missão boom-burger): o painel da Boom! Burger dizia
// "112 Total / 112 Disponíveis" com 56 produtos na base, e o menu do cliente
// usa o mesmo mapa. Causa: o construtor do RestaurantStore liga um ouvinte de
// sessão que, com a lista de lojas ainda vazia, corre
// loadRestaurantsFromSupabase().then(loadProductsFromSupabase) AO MESMO TEMPO
// que o _init(). No loadProductsFromSupabase o mapa era limpo ANTES do await
// dos grupos de opções e depois cada corrida acrescentava os seus 56 → 112.
//
// Este teste faz exatamente isso contra um servidor de brincar: 56 produtos,
// a resposta dos grupos de opções retida até as duas cargas lá chegarem.
import 'dart:async';
import 'dart:convert';

import 'package:bora_app/stores/restaurant_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _loja = 'loja-teste-duplicados';
final _soltarGrupos = Completer<void>();
var _pedidosGrupos = 0;

http.Response _json(http.Request req, Object corpo) => http.Response(
      jsonEncode(corpo),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async {
        switch (req.url.path) {
          case '/rest/v1/restaurants':
            return _json(req, [
              {
                'id': _loja,
                'name': 'Loja de teste',
                'is_partner': true,
                'category': 'restaurant',
                'approval_status': 'approved',
                'is_active_admin': true,
              }
            ]);
          case '/rest/v1/products':
            return _json(req, [
              for (var i = 1; i <= 56; i++)
                {
                  'id': 'produto-$i',
                  'restaurant_id': _loja,
                  'name': 'Produto $i',
                  'price': 10 + i / 100,
                  'is_available': true,
                  'category': 'Hambúrgueres',
                }
            ]);
          case '/rest/v1/product_option_groups':
            _pedidosGrupos++;
            await _soltarGrupos.future;
            return _json(req, const []);
          default:
            return _json(req, const []);
        }
      }),
    );
  });

  test('duas cargas ao mesmo tempo deixam 56 produtos, não 112', () async {
    final store = RestaurantStore(); // o _init() arranca sozinho
    // O mesmo que o ouvinte de sessão faz quando a sessão chega com a lista vazia.
    final segunda = store
        .loadRestaurantsFromSupabase()
        .then((_) => store.loadProductsFromSupabase());

    // Espera que as cargas cheguem aos grupos de opções (no máximo 2 s).
    for (var i = 0; i < 40 && _pedidosGrupos < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _soltarGrupos.complete();
    await segunda;
    await pumpEventQueue();

    final produtos = store.partnerProductsForRestaurant(_loja);
    expect(produtos.length, 56, reason: 'o catálogo apareceu a dobrar');
    expect(produtos.map((p) => p.id).toSet().length, 56);
    expect(store.storeLoadedCount(_loja), 56);
  });
}
