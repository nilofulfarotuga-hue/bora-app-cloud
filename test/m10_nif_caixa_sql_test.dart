// M10 b2-nif (09/11/2026) — a migração do NIF na caixa, lida pela fonte.
// A prova a sério (rollback na base, com pedidos reais) está em
// docs/propostas/m10-2026-11-09/prova_nif_caixa.sql com a saída literal.
// Aqui guarda-se o contrato: uma regra só, NIF da Bora do setting, Favor com
// compra e ajudante cobertos, funções fechadas a anon e nada de dinheiro.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _mig = 'supabase/migrations/20261109005413_m10_nif_na_caixa.sql';
const _prova = 'docs/propostas/m10-2026-11-09/prova_nif_caixa.sql';

String _corpo(String sql, String funcao) {
  final i = sql.indexOf('CREATE OR REPLACE FUNCTION public.$funcao(');
  expect(i, greaterThanOrEqualTo(0), reason: 'falta a função $funcao');
  final fim = sql.indexOf(r'$fn$;', i);
  return sql.substring(i, fim);
}

void main() {
  final sql = File(_mig).readAsStringSync();

  test('a regra vive num sítio só e a função da app lê-a', () {
    final regra = _corpo(sql, '_nif_caixa_regra');
    expect(regra, contains("'errand'"));
    expect(regra, contains('errand_has_purchase'));
    expect(regra, contains('order_invoice_requests'));
    expect(regra, contains('client_billing_profile'));
    expect(regra, contains('public._nif_bora()'));

    final app = _corpo(sql, 'driver_order_invoice_nif');
    expect(app, contains('public._nif_caixa_regra(p_order_id)'));
    expect(app, contains('o.helper_driver_id = v_uid'),
        reason: 'o ajudante também vê o NIF');
    expect(app, isNot(contains('519686233')),
        reason: 'o NIF da Bora vem do setting, não do código');
    // Mesmo contrato que a app já lê (M1): ok, mostrar, pediu_fatura, nif.
    for (final k in ["'ok'", "'mostrar'", "'pediu_fatura'", "'nif'", "'texto'"]) {
      expect(app, contains(k));
    }
  });

  test('NIF da Bora: setting criado sem pisar o que lá está, lido e validado', () {
    expect(sql, contains("VALUES ('nif_compras_nao_parceiro', to_jsonb('519686233'::text)"));
    expect(sql, contains('ON CONFLICT (key) DO NOTHING'));
    final bora = _corpo(sql, '_nif_bora');
    expect(bora, contains("s.key = 'nif_compras_nao_parceiro'"));
    expect(bora, contains('public.nif_pt_valido('));
    final definir = _corpo(sql, 'admin_nif_bora_definir');
    expect(definir, contains("RAISE EXCEPTION 'NIF_INVALIDO'"));
    expect(definir, contains('public.log_admin_action('));
    // O talão guardado usa o mesmo NIF (sai o número escrito no código).
    expect(_corpo(sql, '_talao_nif_usado'), contains('public._nif_bora()'));
  });

  test('"Não consegui" exige motivo e avisa o admin uma vez só', () {
    final c = _corpo(sql, 'estafeta_confirmar_nif_caixa');
    expect(c, contains("RAISE EXCEPTION 'MOTIVO_EM_FALTA'"));
    expect(c, contains("'nif_nao_dado_na_caixa'"));
    expect(c, contains('v_antes.dado IS DISTINCT FROM false'));
    expect(c, contains('public.driver_order_invoice_nif(p_order_id)'),
        reason: 'quem confirma é quem pode ver');
  });

  test('fechadas a anon; as internas também a authenticated; tabela só admin', () {
    for (final f in [
      'driver_order_invoice_nif(text)',
      'estafeta_confirmar_nif_caixa(text, boolean, text)',
      'admin_nif_caixa_listar(integer)',
      'admin_nif_bora_definir(text)',
    ]) {
      expect(sql, contains('REVOKE ALL ON FUNCTION public.$f FROM PUBLIC, anon;'));
    }
    expect(sql, contains('REVOKE ALL ON FUNCTION public._nif_bora() FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public._nif_caixa_regra(text) FROM PUBLIC, anon, authenticated;'));
    expect(sql, contains('ALTER TABLE public.order_nif_caixa ENABLE ROW LEVEL SECURITY;'));
    expect(sql, contains('FOR SELECT TO authenticated USING (public.is_admin());'));
    expect(sql, contains('REVOKE ALL ON public.order_nif_caixa FROM anon;'));
  });

  test('não mexe em dinheiro nem em pedidos', () {
    final s = sql.toLowerCase();
    for (final proibido in [
      'update public.orders',
      'delete from public.orders',
      'insert into public.orders',
      'pricing',
      'dispatch',
      'bora_tokens',
      'wallet',
      'ledger',
      'stripe',
      'finalizar_talao',
    ]) {
      expect(s, isNot(contains(proibido)), reason: proibido);
    }
  });

  test('a prova em rollback corre esta migração inteira e acaba em PROVA_OK', () {
    final p = File(_prova).readAsStringSync();
    expect(p, contains(sql.trim()),
        reason: 'gerar a prova outra vez se a migração mudar');
    expect(p, contains("RAISE EXCEPTION 'PROVA_OK %', t_out::text;"));
    expect(p, contains('SET LOCAL ROLE authenticated;'));
    expect(p, contains('"2_sem_motivo": "MOTIVO_EM_FALTA"'));
  });
}
