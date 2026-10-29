// Favores — beco sem saída na morada (missão geral 28/10/2026, ponto f).
//
// Cicatriz: o campo de morada oferecia "Usar esta morada: …" quando não havia
// sugestões, e a morada seguia SEM coordenadas. O passo seguinte do Favor
// ("Onde entregar", "Levar Compras") recusava-a com "Escolhe uma sugestão da
// lista" — mas, sem sugestões, não havia nada para escolher: beco sem saída.
//
// Agora os ecrãs que exigem coordenadas ligam `exigirCoordenadas`: "Usar esta
// morada" procura a morada no mapa; se acha, avança com coordenadas; se não
// acha, diz-o no próprio campo, não segue às cegas e o campo continua livre
// (escrever outra vez, escolher uma sugestão). Estes testes provam-no sem rede.
import 'dart:io';

import 'package:bora_app/services/place_autocomplete_service.dart';
import 'package:bora_app/widgets/address_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Dentro da cidade da Guarda (< 5 km do centro): a procura aceita-a sem
/// precisar de conferir com sugestões.
const _naGuarda = ll.LatLng(40.5399001, -7.2580);

const String _avisoNoCampo =
    'Não encontrei esta morada no mapa. Escolhe uma sugestão ou acrescenta a cidade (ex.: Guarda).';

/// Serviço falso: o geocode só conhece as moradas de [moradas]; as sugestões
/// vêm de [sugestoes] (mutável, para o teste as "ligar" depois); o Place
/// Details responde com [locais].
class _ServicoFalso extends PlaceAutocompleteService {
  _ServicoFalso({Map<String, ll.LatLng>? moradas})
      : moradas = moradas ?? <String, ll.LatLng>{},
        locais = <String, ll.LatLng>{};

  final Map<String, ll.LatLng> moradas;
  List<PlacePrediction> sugestoes = const [];
  final Map<String, ll.LatLng> locais;

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async =>
      sugestoes;

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async =>
      locais[placeId];

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async => moradas[address];

  @override
  void resetSession() {}

  @override
  void dispose() {}
}

class _Escolha {
  String? morada;
  ll.LatLng? coords;
  int chamadas = 0;
}

Future<_Escolha> _montar(
  WidgetTester tester, {
  required _ServicoFalso servico,
  required bool exigirCoordenadas,
  List<String>? escritas,
}) async {
  final escolha = _Escolha();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AddressAutocompleteField(
        controller: TextEditingController(),
        serviceOverride: servico,
        exigirCoordenadas: exigirCoordenadas,
        onChanged: escritas?.add,
        onSelected: (morada, coords) {
          escolha.chamadas++;
          escolha.morada = morada;
          escolha.coords = coords;
        },
      ),
    ),
  ));
  return escolha;
}

/// Escreve e deixa o debounce (250 ms) + a pesquisa + o overlay acontecerem.
Future<void> _escrever(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField), texto);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump();
}

Future<void> _carregarUsarEstaMorada(WidgetTester tester) async {
  expect(find.textContaining('Usar esta morada'), findsOneWidget);
  await tester.tap(find.textContaining('Usar esta morada'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Favor: "Usar esta morada" com exigirCoordenadas', () {
    testWidgets('a morada tem coordenadas no mapa → avança com elas',
        (tester) async {
      final escolha = await _montar(
        tester,
        servico: _ServicoFalso(moradas: {'Rua da Torre 5, Guarda': _naGuarda}),
        exigirCoordenadas: true,
      );
      await _escrever(tester, 'Rua da Torre 5, Guarda');
      await _carregarUsarEstaMorada(tester);

      expect(escolha.chamadas, 1);
      expect(escolha.morada, 'Rua da Torre 5, Guarda');
      expect(escolha.coords, _naGuarda);
      // O campo confirma onde ficou no mapa e não mostra erro nenhum.
      expect(find.text('Morada encontrada no mapa.'), findsOneWidget);
      expect(find.text(_avisoNoCampo), findsNothing);
    });

    testWidgets(
        'sem coordenadas: NÃO segue às cegas, diz porquê no campo e não prende',
        (tester) async {
      final servico = _ServicoFalso(); // não acha nem sugere nada
      final escritas = <String>[];
      final escolha = await _montar(
        tester,
        servico: servico,
        exigirCoordenadas: true,
        escritas: escritas,
      );
      await _escrever(tester, 'Rua que ninguém conhece 12');
      await _carregarUsarEstaMorada(tester);

      // Não chamou o ecrã com uma morada sem coordenadas (era o beco).
      expect(escolha.chamadas, 0);
      // Mensagem clara, no próprio campo, com o que fazer a seguir.
      expect(find.text(_avisoNoCampo), findsOneWidget);
      // Sem spinner preso a rodar.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // O campo continua editável: escreve outra coisa → o aviso some e o
      // ecrã é avisado da edição (para largar coordenadas antigas).
      final antes = escritas.length;
      servico.sugestoes = const [
        PlacePrediction(
          placeId: 'p1',
          description: 'Rua da Torre, Guarda, Portugal',
          primaryText: 'Rua da Torre',
          secondaryText: 'Guarda, Portugal',
        ),
      ];
      await _escrever(tester, 'Rua da Torre, Guarda');
      expect(escritas.length, greaterThan(antes));
      expect(find.text(_avisoNoCampo), findsNothing);

      // E volta a poder escolher uma sugestão, que avança com coordenadas.
      expect(find.text('Rua da Torre'), findsOneWidget);
      servico.locais['p1'] = _naGuarda;
      await tester.tap(find.text('Rua da Torre'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(escolha.chamadas, 1);
      expect(escolha.morada, 'Rua da Torre, Guarda, Portugal');
      expect(escolha.coords, _naGuarda);
    });

    testWidgets('falhar duas vezes seguidas também não prende o campo',
        (tester) async {
      final escolha = await _montar(
        tester,
        servico: _ServicoFalso(),
        exigirCoordenadas: true,
      );
      await _escrever(tester, 'asdf qwer 99');
      await _carregarUsarEstaMorada(tester);
      expect(find.text(_avisoNoCampo), findsOneWidget);

      // Muda uma letra e tenta de novo: volta a aparecer o modo manual e o
      // campo responde (não ficou num estado "a carregar" para sempre).
      await _escrever(tester, 'asdf qwer 98');
      expect(find.text(_avisoNoCampo), findsNothing);
      await _carregarUsarEstaMorada(tester);
      expect(find.text(_avisoNoCampo), findsOneWidget);
      expect(escolha.chamadas, 0);
    });
  });

  group('Outros ecrãs (exigirCoordenadas desligado) mantêm o de sempre', () {
    testWidgets('sem coordenadas a morada escrita segue na mesma (null)',
        (tester) async {
      final escolha = await _montar(
        tester,
        servico: _ServicoFalso(),
        exigirCoordenadas: false,
      );
      await _escrever(tester, 'Rua que ninguém conhece 12');
      await _carregarUsarEstaMorada(tester);

      expect(escolha.chamadas, 1);
      expect(escolha.morada, 'Rua que ninguém conhece 12');
      expect(escolha.coords, isNull);
      expect(find.text(_avisoNoCampo), findsNothing);
    });
  });

  group('Os dois formulários do Favor ligam a opção (contrato)', () {
    int conta(String ficheiro, String padrao) =>
        RegExp(RegExp.escape(padrao)).allMatches(File(ficheiro).readAsStringSync()).length;

    test('Favor "Onde entregar" e "paragem em casa" exigem coordenadas', () {
      expect(conta('lib/screens/errand_form_screen.dart',
          'exigirCoordenadas: true'), 2);
    });

    test('Levar Compras: a entrega exige coordenadas e usa a procura boa', () {
      const f = 'lib/screens/carry_groceries_form_screen.dart';
      expect(conta(f, 'exigirCoordenadas: true'), 1);
      expect(conta(f, 'procurarMoradaEscrita'), greaterThanOrEqualTo(1));
      // Nada do 1.º resultado cru do geocode (os 11 km da "Rua do Comércio").
      expect(conta(f, '.geocodeAddress('), 0);
    });
  });
}
