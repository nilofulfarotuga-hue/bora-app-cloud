// Missão geral 28/10/2026, Bloco A — leitura tolerante do valor do talão.
// Caso real: o campo tinha "7. 88" (espaço depois do ponto) e o
// double.tryParse falhava; o estafeta carregava em Confirmar e nada.
import 'package:bora_app/utils/valor_em_centimos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _escrever(String antes, String depois) =>
    const ValorEmEurosInputFormatter().formatEditUpdate(
      TextEditingValue(
          text: antes, selection: TextSelection.collapsed(offset: antes.length)),
      TextEditingValue(
          text: depois,
          selection: TextSelection.collapsed(offset: depois.length)),
    );

void main() {
  group('valorEmCentimos — aceita', () {
    test('"7. 88" (o caso real) → 788', () {
      expect(valorEmCentimos('7. 88'), 788);
    });
    test('vírgula, ponto, euro e espaços à volta', () {
      expect(valorEmCentimos('7,88'), 788);
      expect(valorEmCentimos('7.88'), 788);
      expect(valorEmCentimos('7.88 €'), 788);
      expect(valorEmCentimos('€7,88'), 788);
      expect(valorEmCentimos(' 7,88'), 788);
      expect(valorEmCentimos('7,88 EUR'), 788);
    });
    test('espaços especiais: inseparável, fino e fino inseparável', () {
      expect(valorEmCentimos('7, 88'), 788);
      expect(valorEmCentimos('7 ,88'), 788);
      expect(valorEmCentimos('7,88 €'), 788);
    });
    test('uma casa decimal vale ×10', () {
      expect(valorEmCentimos('7.8'), 780);
      expect(valorEmCentimos('7,8'), 780);
    });
    test('sem casas decimais e só cêntimos', () {
      expect(valorEmCentimos('12'), 1200);
      expect(valorEmCentimos('12,'), 1200);
      expect(valorEmCentimos(',50'), 50);
    });
    test('sem erro de vírgula flutuante (0,29 / 1,15 / 4,35)', () {
      // (0.29 * 100).round() e afins é onde o double costuma trair.
      expect(valorEmCentimos('0,29'), 29);
      expect(valorEmCentimos('1,15'), 115);
      expect(valorEmCentimos('4,35'), 435);
      expect(valorEmCentimos('1234,56'), 123456);
    });
  });

  group('valorEmCentimos — recusa (null)', () {
    test('vazio, só espaços, só letras', () {
      expect(valorEmCentimos(null), isNull);
      expect(valorEmCentimos(''), isNull);
      expect(valorEmCentimos('   '), isNull);
      expect(valorEmCentimos('abc'), isNull);
      expect(valorEmCentimos('€'), isNull);
      expect(valorEmCentimos(','), isNull);
    });
    test('dois separadores ("7,8,8", "1.234,56")', () {
      expect(valorEmCentimos('7,8,8'), isNull);
      expect(valorEmCentimos('1.234,56'), isNull);
    });
    test('zero e negativo', () {
      expect(valorEmCentimos('0'), isNull);
      expect(valorEmCentimos('0,00'), isNull);
      expect(valorEmCentimos('-7,88'), isNull);
    });
    test('mais de 2 casas decimais', () {
      expect(valorEmCentimos('7,889'), isNull);
    });
  });

  group('ValorEmEurosInputFormatter', () {
    test('tira o espaço: "7. 88" fica "7.88"', () {
      expect(_escrever('', '7. 88').text, '7.88');
      expect(_escrever('7.', '7. ').text, '7.');
    });
    test('letras, euro e sinal não entram', () {
      expect(_escrever('', 'abc').text, '');
      expect(_escrever('', '7,88 €').text, '7,88');
      expect(_escrever('', '-5').text, '5');
    });
    test('segundo separador é recusado (fica o texto anterior)', () {
      expect(_escrever('7,8', '7,8,').text, '7,8');
      expect(_escrever('7,8', '7,.8').text, '7,8');
    });
    test('terceira casa decimal é recusada', () {
      expect(_escrever('7,88', '7,889').text, '7,88');
    });
    test('vírgula ou ponto, até 2 casas, passam iguais', () {
      expect(_escrever('7', '7,').text, '7,');
      expect(_escrever('7,', '7,8').text, '7,8');
      expect(_escrever('7.8', '7.88').text, '7.88');
    });
    test('o cursor acompanha o texto limpo', () {
      final v = _escrever('', '7. 88');
      expect(v.selection.baseOffset, 4);
      expect(v.selection.extentOffset, 4);
    });
  });
}
