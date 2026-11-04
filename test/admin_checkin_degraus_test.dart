// Painel admin do check-in (04/11/2026, bloco E): os degraus vêm TODOS do servidor, ordenados pelo dia.
// Antes eram 4 chaves fixas e os degraus novos (Leonidas, Burger King, McDonald's...) não apareciam.
import 'package:bora_app/screens/admin/admin_checkin_premios_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lista todos os degraus do servidor, pelo dia, e ignora as outras definições', () {
    final defs = <String, dynamic>{
      'checkin_marco_ativo': true,
      'checkin_marco_ciclo_dias': 30,
      'checkin_marco_texto': 'texto',
      'checkin_marco_mes': {'dia': 30, 'tipo': 'servico'},
      'checkin_marco_semana': {'dia': 7, 'tipo': 'tokens'},
      'checkin_marco_bigmac': {'dia': 13, 'tipo': 'produto'},
      'checkin_marco_leonidas_barra': {'dia': 8, 'tipo': 'produto'},
      'checkin_marco_estragado': {'tipo': 'produto'},
      'checkin_escada_ativa': true,
    };
    expect(chavesMarcosDe(defs), ['semana', 'leonidas_barra', 'bigmac', 'mes']);
  });
}
