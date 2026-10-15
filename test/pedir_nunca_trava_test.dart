// Missão tvde-pedir-nunca-trava-2026-10-14.
//
// Cicatriz: a cliente Stela (Android) escreveu a morada no ecrã do Bora
// Motorista, não tocou em nenhuma sugestão, e o botão de pedir ficou cinzento
// sem dizer porquê — `tvde_calculate_fare` nunca foi chamado. Já a 15/09 e
// 17/09 tinha "sem_resultados" a escrever "Av. Cidade de Safed n8 a 1d".
//
// Estes testes provam, sem rede: texto escrito conta; a pesquisa tolera nº de
// porta e abreviaturas; o atalho "Casa" preenche com coordenadas; o GPS negado
// deixa uma mensagem; e a morada inversa lenta não prende o ecrã.
import 'dart:async';

import 'package:bora_app/screens/client/tvde/tvde_pedir_estado.dart';
import 'package:bora_app/services/atalhos_morada_service.dart';
import 'package:bora_app/services/location_service.dart';
import 'package:bora_app/services/morada_tolerante.dart';
import 'package:bora_app/services/place_autocomplete_service.dart';
import 'package:bora_app/widgets/address_autocomplete_field.dart';
import 'package:bora_app/widgets/atalhos_morada.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart' as ll;

const _guarda = ll.LatLng(40.5399001, -7.2580);

/// Serviço falso: responde só às pesquisas e moradas que o teste conhece —
/// como o Google faz com a morada da Stela (texto todo vazio).
class _ServicoFalso extends PlaceAutocompleteService {
  _ServicoFalso({
    this.sugestoes = const {},
    this.moradas = const {},
    this.locais = const {},
  });

  /// place_id → coordenadas (o que o Place Details devolveria).
  final Map<String, ll.LatLng> locais;

  /// texto pesquisado → sugestões.
  final Map<String, List<PlacePrediction>> sugestoes;

  /// texto geocodificado → resultado.
  final Map<String, MoradaGeocodificada> moradas;

  final List<String> pesquisas = [];
  final List<String> geocodes = [];

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async {
    pesquisas.add(input);
    return sugestoes[input] ?? const [];
  }

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async =>
      locais[placeId];

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async =>
      moradas[address]?.coords;

  @override
  Future<MoradaGeocodificada?> geocodeComMorada(String address) async {
    geocodes.add(address);
    return moradas[address];
  }

  @override
  void resetSession() {}

  @override
  void dispose() {}
}

Future<void> _esperar(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump();
}

void main() {
  // ── Bloco B — pesquisa tolerante ──────────────────────────────────────────
  group('variantesDeMorada', () {
    test('a morada da Stela chega à avenida sem o nº de porta', () {
      final v = variantesDeMorada('Av. Cidade de Safed n8 a 1d, Guarda');
      expect(v.first, 'Av. Cidade de Safed n8 a 1d, Guarda');
      expect(v, contains('Avenida Cidade de Safed n8 a 1d, Guarda'));
      expect(v.last, 'Avenida Cidade de Safed, Guarda');
    });

    test('"nº 12", "R." e andar entre vírgulas saem; código postal fica', () {
      expect(variantesDeMorada('R. Direita nº 12, 2º Esq, 6300-559 Guarda').last,
          'Rua Direita, 6300-559 Guarda');
    });

    test('números que são nome de rua ficam ("5 de Outubro")', () {
      expect(variantesDeMorada('Rua 5 de Outubro 12, Guarda').last,
          'Rua 5 de Outubro, Guarda');
    });

    test('palavras começadas por "n" não são número ("Nossa Senhora")', () {
      expect(variantesDeMorada('Rua Nossa Senhora de Fátima 3').last,
          'Rua Nossa Senhora de Fátima');
    });

    test('texto sem nada a simplificar dá uma só tentativa', () {
      expect(variantesDeMorada('Rua Direita, Guarda'), ['Rua Direita, Guarda']);
      expect(variantesDeMorada('   '), isEmpty);
    });
  });

  group('escolherMelhorNaGuarda', () {
    test('a cidade inteira não serve de recolha', () {
      expect(
        escolherMelhorNaGuarda(const [
          CandidatoGeocode(
              coords: ll.LatLng(40.537, -7.265),
              morada: 'Guarda, Portugal',
              tipos: ['locality', 'political']),
        ]),
        isNull,
      );
    });

    test('prefere o resultado na Guarda ao homónimo noutra cidade', () {
      final m = escolherMelhorNaGuarda(const [
        CandidatoGeocode(
            coords: ll.LatLng(40.66, -7.91),
            morada: 'Rua Direita, Viseu',
            tipos: ['route']),
        CandidatoGeocode(
            coords: ll.LatLng(40.538, -7.267),
            morada: 'Rua Direita, 6300 Guarda',
            tipos: ['route']),
      ]);
      expect(m?.morada, 'Rua Direita, 6300 Guarda');
    });

    test('escreveu "Guarda" e só há a rua em Lisboa → não aceita Lisboa', () {
      const lisboa = [
        CandidatoGeocode(
            coords: ll.LatLng(38.71, -9.14),
            morada: 'Av. Rainha Dona Amélia 14, Lisboa',
            tipos: ['street_address']),
      ];
      expect(escolherMelhorNaGuarda(lisboa, exigirGuarda: true), isNull);
      // Sem "Guarda" no texto (ex.: ir ao aeroporto do Porto) aceita.
      expect(escolherMelhorNaGuarda(lisboa)?.morada,
          'Av. Rainha Dona Amélia 14, Lisboa');
      expect(textoPedeGuarda('Av. Rainha D. Amélia 14, Guarda'), isTrue);
    });

    test('resultado à toa perto da Guarda ("Rua, Portugal") não passa', () {
      // Prova web 15/10: o Google devolveu isto para uma rua inventada.
      const aToa = [
        CandidatoGeocode(
            coords: ll.LatLng(40.55, -7.22),
            morada: 'Rua, Portugal',
            tipos: ['route']),
      ];
      expect(
          escolherMelhorNaGuarda(aToa,
              exigirGuarda: true,
              textoPesquisado: 'Rua Inventada Xyzqw 999, Guarda'),
          isNull);
      // A morada da Stela partilha "Safed" com o resultado → passa (sem acentos
      // e sem as palavras genéricas "Avenida", "Cidade", "Guarda").
      expect(
          partilhaPalavra('Av. Cidade de Safed n8 a 1d, Guarda',
              'Av. Cidade de Safed, Guarda, Portugal'),
          isTrue);
      expect(
          partilhaPalavra('Av. Rainha D. Amelia 14, Guarda',
              'Av. Rainha Dona Amélia 14, 6300-749 Guarda, Portugal'),
          isTrue);
      expect(partilhaPalavra('Rua Inventada Xyzqw 999, Guarda', 'Rua, Portugal'),
          isFalse);
    });
  });

  // ── Bloco A — morada escrita conta ───────────────────────────────────────
  group('AddressAutocompleteField: texto escrito sem tocar na sugestão', () {
    testWidgets('sair do campo aceita a morada escrita, com coordenadas',
        (tester) async {
      String? morada;
      ll.LatLng? coords;
      final servico = _ServicoFalso(moradas: {
        'Rua da Torre 5, Guarda': const MoradaGeocodificada(_guarda,
            morada: 'R. da Torre 5, 6300-123 Guarda'),
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AddressAutocompleteField(
              controller: TextEditingController(),
              serviceOverride: servico,
              onSelected: (a, c) {
                morada = a;
                coords = c;
              },
            ),
            const TextField(key: Key('outro')),
          ]),
        ),
      ));

      await tester.enterText(
          find.byType(TextField).first, 'Rua da Torre 5, Guarda');
      await _esperar(tester);
      // Sai do campo SEM tocar em nenhuma sugestão (o overlay de sugestões
      // fica por cima do campo de baixo, por isso tira-se o foco direto).
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump();

      expect(morada, 'Rua da Torre 5, Guarda');
      expect(coords, _guarda);
      // A morada encontrada aparece por baixo para o cliente confirmar.
      expect(find.text('No mapa: R. da Torre 5, 6300-123 Guarda'),
          findsOneWidget);
    });

    testWidgets('"concluído" no teclado também aceita', (tester) async {
      ll.LatLng? coords;
      final servico = _ServicoFalso(moradas: {
        'Largo da Sé, Guarda': const MoradaGeocodificada(_guarda),
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            controller: TextEditingController(),
            serviceOverride: servico,
            onSelected: (_, c) => coords = c,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'Largo da Sé, Guarda');
      await _esperar(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _esperar(tester);

      expect(coords, _guarda);
      expect(find.text('Morada encontrada no mapa.'), findsOneWidget);
    });

    testWidgets(
        '"Av. Cidade de Safed n8 a 1d, Guarda" encontra a avenida (sugestão e confirmação)',
        (tester) async {
      final key = GlobalKey<AddressAutocompleteFieldState>();
      ll.LatLng? coords;
      // O Google só conhece a forma tolerante — como na vida real da Stela.
      final servico = _ServicoFalso(
        sugestoes: {
          'Avenida Cidade de Safed, Guarda': const [
            PlacePrediction(
              placeId: 'safed',
              description: 'Avenida Cidade de Safed, Guarda',
              primaryText: 'Avenida Cidade de Safed',
              secondaryText: 'Guarda',
            ),
          ],
        },
        moradas: {
          'Avenida Cidade de Safed, Guarda': const MoradaGeocodificada(
              _guarda,
              morada: 'Av. Cidade de Safed, 6300-537 Guarda'),
        },
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            key: key,
            controller: TextEditingController(),
            serviceOverride: servico,
            confirmarAoSair: false,
            onSelected: (_, c) => coords = c,
          ),
        ),
      ));

      await tester.enterText(
          find.byType(TextField), 'Av. Cidade de Safed n8 a 1d, Guarda');
      await _esperar(tester);

      // A lista já não vem vazia: mostra a avenida.
      expect(find.text('Avenida Cidade de Safed'), findsOneWidget);
      expect(find.text('Não encontrei essa morada.'), findsNothing);

      // E o botão de pedir (que chama a confirmação) fica com coordenadas.
      expect(key.currentState!.temTextoPorConfirmar, isTrue);
      late bool ok;
      await tester.runAsync(() async {
        ok = await key.currentState!.confirmarTextoEscrito();
      });
      await tester.pump();
      expect(ok, isTrue);
      expect(coords, _guarda);
      expect(servico.geocodes, contains('Avenida Cidade de Safed, Guarda'));
      expect(key.currentState!.temTextoPorConfirmar, isFalse);
    });

    testWidgets('sem coordenadas: diz no campo e NÃO aceita em silêncio',
        (tester) async {
      var chamadas = 0;
      final key = GlobalKey<AddressAutocompleteFieldState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            key: key,
            controller: TextEditingController(),
            serviceOverride: _ServicoFalso(),
            onSelected: (_, __) => chamadas++,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'qwerty asdfgh');
      await _esperar(tester);
      late bool ok;
      await tester.runAsync(() async {
        ok = await key.currentState!.confirmarTextoEscrito();
      });
      await tester.pump();

      expect(ok, isFalse);
      expect(chamadas, 0);
      expect(find.textContaining('Não encontrei esta morada no mapa'),
          findsOneWidget);
    });

    testWidgets(
        '"…, Guarda" com sugestões só de Lisboa: não aceita a sugestão de Lisboa',
        (tester) async {
      var chamadas = 0;
      final key = GlobalKey<AddressAutocompleteFieldState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            key: key,
            controller: TextEditingController(),
            confirmarAoSair: false,
            serviceOverride: _ServicoFalso(sugestoes: {
              'Av. Rainha D. Amélia 14, Guarda': const [
                PlacePrediction(
                  placeId: 'lx',
                  description: 'Av. Rainha Dona Amélia 14, Lisboa, Portugal',
                  primaryText: 'Av. Rainha Dona Amélia 14',
                  secondaryText: 'Lisboa, Portugal',
                ),
              ],
            }, locais: const {
              'lx': ll.LatLng(38.71, -9.14),
            }),
            onSelected: (_, __) => chamadas++,
          ),
        ),
      ));
      await tester.enterText(
          find.byType(TextField), 'Av. Rainha D. Amélia 14, Guarda');
      await _esperar(tester);
      late bool ok;
      await tester.runAsync(() async {
        ok = await key.currentState!.confirmarTextoEscrito();
      });
      await tester.pump();
      expect(ok, isFalse);
      expect(chamadas, 0);
      expect(find.textContaining('Não encontrei esta morada no mapa'),
          findsOneWidget);
    });

    testWidgets('texto posto pelo ecrã (GPS, morada guardada) não é "por confirmar"',
        (tester) async {
      final ctrl = TextEditingController();
      final key = GlobalKey<AddressAutocompleteFieldState>();
      var chamadas = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            key: key,
            controller: ctrl,
            serviceOverride: _ServicoFalso(),
            onSelected: (_, __) => chamadas++,
          ),
        ),
      ));
      ctrl.text = 'Rua do GPS 1, Guarda';
      await tester.pump();
      expect(key.currentState!.temTextoPorConfirmar, isFalse);
      expect(chamadas, 0);
    });

    testWidgets('confirmarAoSair: false não chama o ecrã ao sair do campo',
        (tester) async {
      var chamadas = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AddressAutocompleteField(
              controller: TextEditingController(),
              confirmarAoSair: false,
              serviceOverride: _ServicoFalso(moradas: {
                'Rua X 1, Guarda': const MoradaGeocodificada(_guarda),
              }),
              onSelected: (_, __) => chamadas++,
            ),
            const TextField(key: Key('outro')),
          ]),
        ),
      ));
      await tester.enterText(find.byType(TextField).first, 'Rua X 1, Guarda');
      await _esperar(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(chamadas, 0);
    });
  });

  // ── Bloco C — moradas guardadas com um toque ─────────────────────────────
  group('atalhos de morada', () {
    test('Casa + destinos recentes, sem repetidos, até 3 recentes', () {
      final a = montarAtalhos(
        guardadas: const [
          {
            'label': 'Casa',
            'address': 'Av. Cidade de Safed n8 a 1d, Guarda, Portugal',
            'lat': 40.5399001,
            'lng': -7.2580,
          },
          {'label': 'Sem coords', 'address': 'Rua Y', 'lat': null, 'lng': null},
        ],
        corridas: const [
          // mesmo sítio que a Casa (a < 60 m) → não repete
          {'dest_label': 'Casa da Stela', 'dest_lat': 40.53991, 'dest_lng': -7.25801},
          {'dest_label': 'Hospital Sousa Martins, Guarda', 'dest_lat': 40.53, 'dest_lng': -7.27},
          {'dest_label': 'Hospital Sousa Martins, Guarda', 'dest_lat': 40.53, 'dest_lng': -7.27},
          {'dest_label': 'Estação da Guarda', 'dest_lat': 40.55, 'dest_lng': -7.24},
          {'dest_label': 'La Vie Guarda', 'dest_lat': 40.52, 'dest_lng': -7.25},
          {'dest_label': 'Quarto recente', 'dest_lat': 40.51, 'dest_lng': -7.22},
        ],
      );
      expect(a.map((x) => x.rotulo).toList(),
          ['Casa', 'Hospital Sousa Martins', 'Estação da Guarda', 'La Vie Guarda']);
      expect(a.first.recente, isFalse);
      expect(a.sublist(1).every((x) => x.recente), isTrue);
    });

    testWidgets('chip "Casa" preenche a morada E as coordenadas',
        (tester) async {
      AtalhoMorada? escolhido;
      final atalhos = montarAtalhos(guardadas: const [
        {
          'label': 'Casa',
          'address': 'Av. Cidade de Safed n8 a 1d, Guarda, Portugal',
          'lat': 40.5399001,
          'lng': -7.2580,
        },
      ], corridas: const []);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AtalhosMorada(
            atalhos: atalhos,
            onEscolher: (a) => escolhido = a,
          ),
        ),
      ));
      expect(find.text('Casa'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      await tester.tap(find.text('Casa'));
      await tester.pump();
      expect(escolhido?.morada, 'Av. Cidade de Safed n8 a 1d, Guarda, Portugal');
      expect(escolhido?.coords, const ll.LatLng(40.5399001, -7.2580));
    });

    testWidgets('sem atalhos não ocupa espaço', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AtalhosMorada(atalhos: const [], onEscolher: (_) {}),
        ),
      ));
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  // ── Bloco D — o botão diz o que falta ────────────────────────────────────
  group('botão de pedir', () {
    test('diz o que falta, por ordem', () {
      String? f({
        bool r = true,
        bool d = true,
        bool loc = false,
        bool calc = false,
        bool preco = true,
      }) =>
          oQueFaltaParaPedir(
              temRecolha: r,
              temDestino: d,
              aLocalizar: loc,
              aCalcular: calc,
              temPreco: preco);
      expect(f(r: false, loc: true), 'A procurar a tua localização…');
      expect(f(r: false), 'Escolhe o ponto de recolha');
      expect(f(d: false), 'Escolhe o destino');
      expect(f(calc: true), 'A calcular o preço…');
      expect(f(preco: false), 'A calcular o preço…');
      expect(f(), isNull);
    });

    test('motivo do pedido travado para o painel', () {
      expect(
          motivoPedidoTravado(
              geocodeFalhou: true, temRecolha: true, gpsFalhou: false),
          'geocode_falhou');
      expect(
          motivoPedidoTravado(
              geocodeFalhou: false, temRecolha: false, gpsFalhou: true),
          'gps_falhou');
      expect(
          motivoPedidoTravado(
              geocodeFalhou: false, temRecolha: false, gpsFalhou: false),
          'sem_recolha');
      expect(
          motivoPedidoTravado(
              geocodeFalhou: false, temRecolha: true, gpsFalhou: false),
          'sem_destino');
    });
  });

  // ── Bloco E — nada fica preso ────────────────────────────────────────────
  group('GPS e morada inversa', () {
    tearDown(() {
      LocationService.httpClientParaTestes = null;
      LocationService.applyLocationConsent(true);
    });

    testWidgets('GPS negado → o campo da recolha diz o que fazer',
        (tester) async {
      // Consentimento de localização recusado: o serviço devolve null sem
      // perguntar nada ao sistema (nunca lança, nunca prende).
      LocationService.applyLocationConsent(false);
      late ll.LatLng? pos;
      await tester.runAsync(() async {
        pos = await LocationService.getCurrentLocation();
      });
      expect(pos, isNull);

      // E o ecrã, com o GPS falhado e sem recolha, mostra a ajuda no campo.
      final ajuda = ajudaDaRecolha(gpsFalhou: true, temRecolha: false);
      expect(ajuda, 'Liga a localização ou escreve a morada');
      expect(ajudaDaRecolha(gpsFalhou: true, temRecolha: true), isNull);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            controller: TextEditingController(),
            serviceOverride: _ServicoFalso(),
            labelText: 'Ponto de recolha',
            helperText: ajuda,
            onSelected: (_, __) {},
          ),
        ),
      ));
      expect(find.text('Liga a localização ou escreve a morada'),
          findsOneWidget);
    });

    testWidgets('morada inversa lenta desiste aos 8 s (não prende)',
        (tester) async {
      LocationService.httpClientParaTestes = MockClient((_) async {
        await Future<void>.delayed(const Duration(minutes: 5));
        return http.Response('{}', 200);
      });
      var acabou = false;
      String? res = 'por responder';
      unawaited(LocationService.reverseGeocode(_guarda, 'chave-teste')
          .then((v) {
        res = v;
        acabou = true;
      }));
      await tester.pump(const Duration(seconds: 7));
      expect(acabou, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(acabou, isTrue);
      expect(res, isNull);
      // Deixa o pedido "lento" do cliente falso acabar dentro do relógio falso.
      await tester.pump(const Duration(minutes: 5));
    });
  });
}
