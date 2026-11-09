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
  });

  test('o carrossel dos habituais tem altura para o cartão inteiro', () {
    final src = _ler('lib/widgets/home/meus_habituais.dart');
    final m = RegExp(r'height:\s*(\d+),\s*\n\s*child: ListView\.separated')
        .firstMatch(src);
    expect(m, isNotNull);
    // 12+12 de margem + nome (16) + 2 linhas de produtos (16 × 1,25) + botão 44.
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(136));
  });
}
