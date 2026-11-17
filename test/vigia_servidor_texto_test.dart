// Missão servidor-busca-leve-2026-11-17 (B4): o vigia diz quem e o quê em
// palavras de gente. As consultas abaixo têm o formato real que o
// pg_stat_statements guardou a 17/11 (PostgREST).
import 'package:bora_app/utils/vigia_servidor_texto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quemGerouCarga', () {
    test('sem login, com conta, robôs e o próprio servidor', () {
      expect(quemGerouCarga('anon'), contains('pessoas sem login'));
      expect(quemGerouCarga('anon'), contains('robô de teste do Google'));
      expect(quemGerouCarga('authenticated'), 'clientes com conta');
      expect(quemGerouCarga('service_role'), contains('robôs'));
      expect(quemGerouCarga('supabase_admin'), contains('tempo real'));
    });

    test('papel desconhecido fica como está; vazio diz desconhecido', () {
      expect(quemGerouCarga('outro_papel'), 'outro_papel');
      expect(quemGerouCarga(null), 'desconhecido');
      expect(quemGerouCarga(' '), 'desconhecido');
    });
  });

  group('oQueGerouCarga', () {
    test('a lupa das lojas pelo nome, não pelo SQL', () {
      const q =
          'WITH pgrst_source AS (SELECT "pgrst_call".* FROM (SELECT \$1 AS json_data) '
          'pgrst_payload, LATERAL (SELECT "query_text" FROM json_to_record(\$1) AS _("query_text" text)) '
          'pgrst_body , LATERAL "public"."search_products"("query_text" := pgrst_body."query_text") pgrst_call)';
      expect(oQueGerouCarga(q), 'a lupa dentro das lojas (search_products)');
    });

    test('a lupa da página inicial e outras funções', () {
      expect(
        oQueGerouCarga('select "public"."cliente_pesquisar"("p_q" := \$1)'),
        'a lupa da página inicial (cliente_pesquisar)',
      );
      expect(
        oQueGerouCarga('(SELECT "public"."meu_ganho_ao_vivo"() pgrst_scalar)'),
        'a função meu_ganho_ao_vivo',
      );
      expect(
        oQueGerouCarga('select public.cron_lote(\$1, \$2)'),
        'a função cron_lote',
      );
    });

    test('leitura de tabela e tempo real', () {
      expect(
        oQueGerouCarga(
          '( SELECT "public"."orders".* FROM "public"."orders" WHERE "public"."orders"."id" = \$1)',
        ),
        'a leitura dos pedidos (tabela orders)',
      );
      expect(
        oQueGerouCarga('SELECT wal->>\$5 as type, wal->>\$6 as schema'),
        'o tempo real do Supabase a ler as alterações',
      );
    });

    test('o resto mostra o começo da consulta, curto', () {
      final r = oQueGerouCarga(
        'with x as materialized (select q, o, r from unnest(array[\$1, \$2]) ${'z' * 200})',
      );
      expect(r, startsWith('uma consulta: with x as materialized'));
      expect(r.length, lessThanOrEqualTo('uma consulta: '.length + 80));
      expect(oQueGerouCarga(null), 'desconhecido');
    });
  });
}
