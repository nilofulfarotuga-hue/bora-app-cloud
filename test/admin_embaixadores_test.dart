import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// [guarda-primeiro · 26/10/2026] O ecrã "Embaixadores" (códigos IPG e quanto
/// pagar por semana) tem de existir no painel, ao lado dos Promo Codes, e a
/// busca tem de o encontrar por "IPG" e "embaixador" — regra da paridade admin.
/// A conta em si (2 €/cliente, teto 20 €/semana, exclusões) vive no banco e foi
/// provada em rollback; ver supabase/migrations/20261025231500_embaixador_ipg.sql.
void main() {
  final sections = adminMenuSections();
  final all = adminMenuAllItems();

  test('Embaixadores vive em "Mais dinheiro", logo a seguir aos Promo Codes', () {
    final din = sections.firstWhere((s) => s.id == 'dinheiro');
    final mais = din.items.firstWhere((i) => i.id == 'dinheiro_mais');
    final titulos = mais.filhos.map((i) => i.title).toList();
    final p = titulos.indexOf('Promo Codes');
    expect(p, isNonNegative);
    expect(titulos[p + 1], 'Embaixadores');
  });

  test('a busca encontra o ecrã por IPG, embaixador e politécnico', () {
    for (final q in ['IPG', 'embaixador', 'politecnico']) {
      expect(all.where((i) => i.matches(q)).map((i) => i.id),
          contains('dinheiro_embaixadores'),
          reason: 'a busca por "$q" não encontrou o ecrã');
    }
  });
}
