import 'package:flutter/services.dart';

/// Leitura tolerante do valor que o estafeta escreve à mão (talão, conta).
///
/// 28/10/2026 (missão geral, Bloco A): o campo tinha "7. 88" — o teclado meteu
/// um espaço depois do ponto — e `double.tryParse` falhava; o aviso aparecia
/// por trás da folha e o "Confirmar" parecia não fazer nada.
///
/// Tira espaços (normais, finos U+2009/U+202F, inseparáveis U+00A0), "€" e
/// letras; aceita vírgula OU ponto como separador decimal (um só, até 2 casas)
/// e devolve CÊNTIMOS inteiros, sem passar por `double` (sem erro de vírgula
/// flutuante): euros e cêntimos lêem-se como inteiros e 1 casa decimal vale
/// ×10 ("7.8" → 780). Vazio, sem dígitos, mais de um separador, mais de 2
/// casas, negativo ou zero → `null`.
int? valorEmCentimos(String? texto) {
  if (texto == null) return null;
  final limpo = texto.replaceAll(_lixo, '');
  final m = _formato.firstMatch(limpo);
  if (m == null) return null;
  final eurosTxt = m.group(1) ?? '';
  final centTxt = m.group(2) ?? '';
  if (eurosTxt.isEmpty && centTxt.isEmpty) return null;
  final euros = eurosTxt.isEmpty ? 0 : int.tryParse(eurosTxt);
  final cent = centTxt.isEmpty ? 0 : int.tryParse(centTxt);
  if (euros == null || cent == null) return null;
  final total = euros * 100 + (centTxt.length == 1 ? cent * 10 : cent);
  return total > 0 ? total : null;
}

/// Espaços de todo o tipo, "€" e letras (de qualquer alfabeto).
final RegExp _lixo =
    RegExp(r'[\s   €\p{L}]', unicode: true);

/// Dígitos, opcionalmente um separador (vírgula ou ponto) e até 2 casas.
final RegExp _formato = RegExp(r'^(\d*)(?:[.,](\d{0,2}))?$');

/// Só deixa escrever dígitos e UM separador decimal (vírgula ou ponto), com
/// no máximo 2 casas. O resto (espaços, "€", letras, sinal) é tirado em vez de
/// bloquear a tecla — assim "7. 88" fica "7.88". Uma edição que daria dois
/// separadores ou 3 casas decimais é recusada (fica o texto anterior).
class ValorEmEurosInputFormatter extends TextInputFormatter {
  const ValorEmEurosInputFormatter();

  static final RegExp _permitido = RegExp(r'^\d*(?:[.,]\d{0,2})?$');

  static bool _guardar(int codigo) =>
      (codigo >= 0x30 && codigo <= 0x39) || codigo == 0x2C || codigo == 0x2E;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final texto = newValue.text;
    final buf = StringBuffer();
    // guardadosAte[i] = quantos caracteres ficam entre os primeiros i — serve
    // para manter o cursor no mesmo sítio depois de tirar o lixo.
    final guardadosAte = List<int>.filled(texto.length + 1, 0);
    for (var i = 0; i < texto.length; i++) {
      final c = texto.codeUnitAt(i);
      if (_guardar(c)) buf.writeCharCode(c);
      guardadosAte[i + 1] = buf.length;
    }
    final limpo = buf.toString();
    if (!_permitido.hasMatch(limpo)) return oldValue;
    if (limpo == texto) return newValue;
    int mapa(int pos) =>
        pos < 0 ? pos : guardadosAte[pos > texto.length ? texto.length : pos];
    return TextEditingValue(
      text: limpo,
      selection: TextSelection(
        baseOffset: mapa(newValue.selection.baseOffset),
        extentOffset: mapa(newValue.selection.extentOffset),
      ),
    );
  }
}
