-- 24/11/2026 — missão limpeza-cancelamento-app-2026-11-24, BLOCO E.
-- A regra de cancelamento da limpeza mudou (migração 20261124055354, decisão do Danilo 05:46/05:52):
-- sem a profissional a caminho, cancelar é grátis; com ela a caminho, o cliente paga só a deslocação
-- (o maior entre cleaning_cancel_travel_comp_cents e a taxa de deslocação da vaga), por cada
-- profissional a caminho; profissional atrasada (cleaning_pro_late_no_fee_minutes) = grátis.
-- Os robôs (suporte e assistente) ainda explicavam a regra antiga (24 h grátis, 50 %, 100 %).
-- Só texto. Os números vêm de platform_settings no momento em que corre.

create table if not exists public.bkp_support_skills_20261124_cancelamento as
  select * from public.support_skills where skill_name = 'CLEANING_INFO';
create table if not exists public.bkp_assistant_knowledge_20261124_cancelamento as
  select * from public.assistant_knowledge where topic = 'limpeza';
create table if not exists public.bkp_support_knowledge_chunks_20261124_cancelamento as
  select id, source_file, chunk_index, chunk_text, content_hash
    from public.support_knowledge_chunks
   where source_file = 'docs/ajuda/ajuda-clientes.md' and chunk_text ilike '%Limpezas%';

do $$
declare
  v_min_cents int := coalesce((select (value #>> '{}')::int from public.platform_settings
                                where key = 'cleaning_cancel_travel_comp_cents'), 500);
  v_atraso    int := coalesce((select (value #>> '{}')::int from public.platform_settings
                                where key = 'cleaning_pro_late_no_fee_minutes'), 15);
  v_min text;
  v_sec text;
begin
  v_min := replace(to_char(v_min_cents / 100.0, 'FM990D00'), '.', ',') || ' €';

  v_sec := E'## Cancelar (regra de 24/11/2026)\n'
    || E'- Enquanto a profissional ainda NÃO está a caminho: cancelar é grátis, a qualquer hora.\n'
    || E'- Se a profissional JÁ está a caminho: o cliente paga só a deslocação dela, ' || v_min
    || E' (ou a taxa de deslocação dessa limpeza, se a morada for longe e a taxa for maior). Numa equipa, conta a deslocação de cada profissional que já ia a caminho.\n'
    || E'- Se a profissional ainda não começou ' || v_atraso || E' minutos depois da hora marcada: cancelar é grátis.\n'
    || E'- Pago por cartão ou MB Way: o que não for taxa volta sozinho ao mesmo cartão ou MB Way.\n'
    || E'- Antes de confirmar, a app mostra o valor certo para aquela limpeza: mandar ver lá (a limpeza marcada → "Cancelar limpeza").\n'
    || E'- Já não há as regras antigas de 24 horas, metade ou valor todo.';

  update public.support_skills
     set playbook_md = regexp_replace(playbook_md, E'## Cancelar\\n.*?\\n\\n## Regras', v_sec || E'\n\n## Regras'),
         updated_at = now()
   where skill_name = 'CLEANING_INFO' and active and playbook_md like E'%## Cancelar\n%';

  update public.assistant_knowledge
     set content = content
           || ' Cancelar: grátis enquanto a profissional não está a caminho; com ela a caminho, paga-se só a deslocação dela ('
           || v_min || ' ou a taxa de deslocação, se for maior); se ela não começou ' || v_atraso
           || ' minutos depois da hora, é grátis. A app mostra o valor antes de confirmar.',
         updated_at = now()
   where id = '43cc75ee-0f81-4ee2-a451-dedcb84db7ae' and content not ilike '%Cancelar:%';

  -- Manual do suporte (RAG): a página de ajuda do cliente (docs/ajuda/ajuda-clientes.md, secção Limpezas).
  update public.support_knowledge_chunks
     set chunk_text = replace(chunk_text,
           'Se cancelares nos primeiros 5 minutos depois de marcar, não pagas nada.',
           'Cancelar é grátis enquanto a profissional ainda não está a caminho. Se ela já estiver a caminho, pagas só a deslocação dela ('
           || v_min || ', ou a taxa de deslocação da limpeza se for maior); o resto do que pagaste por cartão ou MB Way volta sozinho. Se a profissional não começar '
           || v_atraso || ' minutos depois da hora marcada, cancelar é grátis. A app mostra o valor antes de confirmares.')
   where source_file = 'docs/ajuda/ajuda-clientes.md'
     and chunk_text like '%Se cancelares nos primeiros 5 minutos depois de marcar, não pagas nada.%';
  update public.support_knowledge_chunks
     set char_count = length(chunk_text)
   where source_file = 'docs/ajuda/ajuda-clientes.md'
     and chunk_text like '%Cancelar é grátis enquanto a profissional ainda não está a caminho.%';

  insert into public.assistant_learned (question_norm, question, answer, source, kind, active)
  values
  ('quanto pago se cancelar a limpeza',
   'Quanto pago se cancelar a limpeza?',
   'Enquanto a profissional ainda não está a caminho, cancelar é grátis, a qualquer hora. Se ela já estiver a caminho, pagas só a deslocação dela: '
     || v_min || ' (ou a taxa de deslocação da tua limpeza, se a morada for longe e a taxa for maior); numa equipa, conta a de cada profissional que já ia a caminho. Se pagaste por cartão ou MB Way, o resto volta sozinho para o mesmo cartão ou MB Way. Se a profissional não começar '
     || v_atraso || ' minutos depois da hora marcada, cancelar é grátis. Antes de confirmares, a app mostra o valor certo: abre a limpeza marcada e toca em "Cancelar limpeza".',
   'admin', 'resposta', true),
  ('o cliente cancelou a limpeza quando eu ja estava a caminho recebo alguma coisa',
   'O cliente cancelou a limpeza quando eu já estava a caminho. Recebo alguma coisa?',
   'Sim. Se marcaste "A caminho" na app e o cliente cancela antes de começares, o cliente paga a taxa de deslocação e tu recebes essa taxa menos a parte da Bora. O valor aparece no aviso do cancelamento, no teu histórico e entra no acerto da semana. Se o cliente cancelar antes de estares a caminho, não há taxa nem pagamento. Se chegares mais de '
     || v_atraso || ' minutos depois da hora sem começar, o cliente pode cancelar sem pagar e não há deslocação a receber.',
   'admin', 'resposta', true)
  on conflict do nothing;
end $$;
