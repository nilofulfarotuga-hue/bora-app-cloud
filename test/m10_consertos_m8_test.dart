// M10 (09/11/2026): dois defeitos visuais achados pela M8 no emulador,
// guardados pela fonte (os ecrãs precisam de sessão e lojas para se montarem).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) => File(caminho).readAsStringSync();

void main() {
  test('a barra do parceiro diz Aberta/Fechada e não aperta o nome da loja', () {
    final src = _ler('lib/screens/partner_dashboard_screen.dart');
    expect(src, contains("currentRestaurant.isOnline ? 'Aberta' : 'Fechada'"));
    expect(src, isNot(contains("'Loja aberta' : 'Loja fechada'")),
        reason: 'o texto comprido cortava o nome da loja em "Loj…"');
    // Emulador M10: mesmo curto, o botão nos ícones da barra cortava em
    // "Loja D…" — passou para a 2.ª linha do título (antes de `actions:`).
    final titulo = src.indexOf("key: const Key('estado_loja_barra')");
    final acoes = src.indexOf('actions: [', titulo);
    expect(titulo, greaterThan(0));
    expect(acoes, greaterThan(titulo));
  });

  test('o painel do parceiro mostra os euros no formato de Portugal', () {
    final src = _ler('lib/screens/partner_dashboard_screen.dart');
    expect(RegExp(r"'€\$\{").hasMatch(src), isFalse,
        reason: 'nada de "€9.65": usa euros.eur(...)');
    expect(src, contains('final formattedAmount = euros.eur(amount);'));
  });

  test('o carrossel dos habituais tem altura para o cartão inteiro', () {
    final src = _ler('lib/widgets/home/meus_habituais.dart');
    // 11/11/2026: cartão compacto de duas linhas com o botão ao lado. A altura
    // é `textScaler.scale(texto) + margem`, para crescer com a letra grande.
    final m = RegExp(r'textScalerOf\(context\)\.scale\((\d+)\)\s*\+\s*(\d+);')
        .firstMatch(src);
    expect(m, isNotNull, reason: 'a altura tem de acompanhar o tamanho de letra');
    final texto = int.parse(m!.group(1)!);
    final margem = int.parse(m.group(2)!);
    // 2 linhas de 16 px (Inter ≈ 19,4 px cada) cabem no texto reservado…
    expect(texto, greaterThanOrEqualTo(40));
    // …e o botão de 44 px mais 8+8 de margem cabe na altura mínima.
    expect(margem, greaterThanOrEqualTo(16));
    expect(src, contains('alturaCartao < 60 ? 60 : alturaCartao'));
    expect(src, contains('minimumSize: const Size(0, 44)'));
  });
}
