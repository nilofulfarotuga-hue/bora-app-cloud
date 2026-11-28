// Planos de limpeza (28/11/2026): sem telemóvel não há pedido. As visitas do plano são reservas de
// limpeza e o servidor recusa-as sem telemóvel (SEM_TELEFONE), por isso o assistente do plano pede o
// telemóvel ANTES de criar o plano (a mesma porta do assistente de "Uma vez").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o assistente do plano garante o telemóvel antes de criar o plano', () {
    final src = File('lib/screens/client/cleaning/cleaning_plan_wizard_screen.dart').readAsStringSync();
    final comecar = src.indexOf('Future<void> _comecar() async {');
    final porta = src.indexOf("garantirContactoDoCliente(context, categoria: 'limpeza')", comecar);
    final criar = src.indexOf('_store.createPlan(', comecar);
    final sai = src.indexOf('if (!contactoOk || !mounted) return;', comecar);
    expect(comecar, greaterThan(0));
    expect(porta, greaterThan(comecar), reason: 'a porta do telemóvel está no _comecar');
    expect(sai, greaterThan(porta), reason: 'sem telemóvel não segue');
    expect(criar, greaterThan(sai), reason: 'o plano só se cria depois do telemóvel');
    expect(src, contains('widget.garantirContacto?.call(context)'), reason: 'os testes podem trocar a porta');
  });
}
