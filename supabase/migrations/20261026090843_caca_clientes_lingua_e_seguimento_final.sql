-- 26/10/2026 (geral-sabado-24-10, bloco 6): a linha "Propostas diárias" passa para o Emerson
-- (caça-clientes). Ordem do Danilo 24/10 08:16: "Sim pode desligar mas passa tudo pro Emerson".
--  - lingua por prospect (pt-PT, fr, en, pt-BR): o carteiro escolhe o rodapé na língua certa;
--  - seguimento_final_texto por proposta: o último seguimento leva o texto próprio (na língua
--    da empresa, com o link direto da demo https://bora-demos.pages.dev/<slug>/);
--  - nunca Espanha: a fila não devolve endereços .es (LSSI).
alter table public.prospects_presenca add column if not exists lingua text not null default 'pt-PT';
alter table public.prospect_propostas add column if not exists seguimento_final_texto text;

create or replace function public.carteiro_fila(p_chave text, p_forcar boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'vault'
as $function$
declare v_on boolean; v_hoje integer; v_resto integer; v_local timestamp := now() at time zone 'Europe/Lisbon';
        v_janela boolean; v_novas jsonb; v_seg jsonb; v_agora jsonb; v_max integer;
begin
  perform public._caca_chave_ok(p_chave);
  select coalesce((value #>> '{}')::boolean, false) into v_on from public.platform_settings where key = 'caca_clientes_enabled';
  if not coalesce(v_on, false) then return jsonb_build_object('ligado', false, 'novas', '[]'::jsonb, 'seguimentos', '[]'::jsonb); end if;
  select least(20, greatest(0, coalesce((value #>> '{}')::integer, 5))) into v_max from public.platform_settings where key = 'caca_clientes_max_dia';
  v_max := coalesce(v_max, 5);
  v_janela := p_forcar or (extract(isodow from v_local) between 1 and 5 and v_local::time between time '09:30' and time '11:30');
  with f as (update public.prospect_propostas r set estado = 'sem_resposta', atualizado_em = now()
              from public.prospects_presenca p
             where p.id = r.prospect_id and r.estado = 'enviada' and r.seguimentos >= 2 and p.proximo_seguimento_em <= now()
             returning r.prospect_id)
  update public.prospects_presenca p set estado = 'sem_resposta', proximo_seguimento_em = null, atualizado_em = now() from f where p.id = f.prospect_id;
  select count(*) into v_hoje from public.prospect_propostas
   where canal = 'email' and enviado_em is not null and (enviado_em at time zone 'Europe/Lisbon')::date = v_local::date and destinatario not ilike 'boraappbora@%';
  v_resto := greatest(0, v_max - v_hoje);
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_agora from (
    select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', p.email, 'assunto', r.assunto, 'texto', r.texto, 'lingua', p.lingua) x
      from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
     where r.estado = 'pronta' and r.canal = 'email' and r.enviar_agora and p.email_verificado and coalesce(p.email,'') <> ''
       and p.email not ilike '%.es'
       and p.estado not in ('recusou','recusado','cliente','descartado','pausado') order by r.id limit 5) q;
  if v_janela then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_novas from (
      select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', p.email, 'assunto', r.assunto, 'texto', r.texto, 'lingua', p.lingua) x
        from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
       where r.estado = 'pronta' and r.canal = 'email' and not r.enviar_agora and p.email_verificado and coalesce(p.email,'') <> ''
         and p.email not ilike '%.es'
         and p.estado not in ('recusou','recusado','cliente','descartado','pausado')
       order by p.pontuacao desc nulls last, r.id limit v_resto) q;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_seg from (
      select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', r.destinatario, 'assunto', r.assunto,
                                'texto', r.texto, 'thread_id', r.gmail_thread_id, 'rfc_message_id', r.rfc_message_id, 'numero', r.seguimentos + 1,
                                'texto_final', r.seguimento_final_texto, 'lingua', p.lingua) x
        from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
       where r.estado = 'enviada' and r.canal = 'email' and r.seguimentos < 2 and p.proximo_seguimento_em <= now()
         and coalesce(r.destinatario, '') not ilike '%.es'
         and p.estado = 'enviada' order by p.proximo_seguimento_em limit 15) q;
  end if;
  return jsonb_build_object('ligado', true, 'janela', v_janela, 'enviadas_hoje', v_hoje, 'max_dia', v_max,
                            'novas', coalesce(v_agora, '[]'::jsonb) || coalesce(v_novas, '[]'::jsonb), 'seguimentos', coalesce(v_seg, '[]'::jsonb));
end $function$;
