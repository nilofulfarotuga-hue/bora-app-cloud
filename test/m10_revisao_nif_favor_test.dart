// M10 (09/11/2026): correções pedidas pelo revisor do ramo b2-nif.
import 'dart:io';

import 'package:bora_app/utils/favor_passos.dart';
import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) => File(caminho).readAsStringSync();

void main() {
  group('receita obrigatória só quando é farmácia a sério', () {
    test('farmácia, medicamento, remédio, receita médica e SNS pedem a foto', () {
      for (final t in [
        'Ir à farmácia buscar o Brufen',
        'Comprar medicamentos para a minha mãe',
        'um remédio para a tosse',
        'Levantar a receita médica',
        'receita do SNS',
      ]) {
        expect(textoExigeReceita(t), isTrue, reason: t);
      }
    });

    test('receita de bolo, parafarmácia e textos vazios não pedem', () {
      for (final t in [
        'Comprar os ingredientes da receita de bolo',
        'Champô na parafarmácia do Continente',
        'Levar a receita de culinária à vizinha',
        '',
      ]) {
        expect(textoExigeReceita(t), isFalse, reason: t);
      }
      expect(textoExigeReceita(null), isFalse);
    });

    test('o pedido do Favor só bloqueia Favores com compra', () {
      final src = _ler('lib/screens/errand_form_screen.dart');
      expect(src, contains('pareceFarmacia: _hasPurchase &&'));
      expect(src, contains('textoExigeReceita(_descCtrl.text)'));
    });
  });

  test('responder à caixa do NIF só para quem leva o pedido (não a oferta)', () {
    final sql = _ler('supabase/migrations/20261109005413_m10_nif_na_caixa.sql');
    final ini = sql.indexOf('FUNCTION public.estafeta_confirmar_nif_caixa');
    final trava = sql.indexOf("RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido')", ini);
    final info = sql.indexOf('v_info := public.driver_order_invoice_nif(p_order_id);', ini);
    expect(ini, greaterThan(0));
    expect(trava, greaterThan(ini));
    expect(info, greaterThan(trava), reason: 'a trava vem antes de ler o cartão');
    expect(sql, contains('REVOKE ALL ON public.order_nif_caixa FROM authenticated;'));
  });

  test('o cartão do NIF liberta o botão quando sai do ecrã', () {
    final src = _ler('lib/widgets/driver_invoice_nif_card.dart');
    final dispose = src.indexOf('void dispose()');
    expect(dispose, greaterThan(0));
    expect(src.indexOf('caixa.definirAplica(false)', dispose), greaterThan(dispose));
  });
}
