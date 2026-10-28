import 'dart:io';

import 'package:bora_app/config/allergens.dart';
import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 17] Alergênicos no painel (obrigação
/// legal, Reg. UE 1169/2011). Antes só o parceiro os preenchia — 1 de 58 227
/// produtos tinha a informação.
void main() {
  test('os 14 alergênicos obrigatórios', () {
    expect(kAllergenLabels.length, 14);
  });

  test('ecrã no menu do painel, grava allergens e confirma a linha', () {
    final menu = File('lib/screens/admin/admin_menu_registry.dart').readAsStringSync();
    expect(menu.contains('builder: () => const AdminAlergenosScreen()'), isTrue);
    final s = File('lib/screens/admin/admin_alergenos_screen.dart').readAsStringSync();
    expect(s.contains(".update({'allergens': depois})"), isTrue);
    expect(s.contains(".select('id')"), isTrue, reason: '0 linhas = erro, nunca "salvo"');
    expect(s.contains("action: 'product_allergens_updated'"), isTrue, reason: 'auditado');
  });
}
