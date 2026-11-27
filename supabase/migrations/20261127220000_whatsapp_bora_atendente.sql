-- WhatsApp da Bora respondido pela assistente (27/11/2026, pedido do Danilo às 21:55):
-- "quero que o WhatsApp da Bora responda também o cliente automaticamente, por voz e por texto, que saiba
-- tudo o que o atendente por telefone sabe, que aprenda com os erros, e que pare quando eu assumir".
--
-- O cérebro é o mesmo do telefone (Edge Function voz-cerebro, Opus): no WhatsApp entra pelo assistente de
-- negócio da VPS (/opt/assistente-negocio, módulo bora_wa.py) como um tenant novo, tipo 'bora'.
--  1. assistant_tenants: aceita o tipo 'bora'; nasce o tenant "Bora" (sessão do número da Bora) em teste,
--     só com o número de teste do Danilo; a Boom sai do número da Bora (o Emanuel não respondeu ao teste).
--  2. voz_licoes: cada lição diz o canal onde vale (todos | voz | whatsapp) e de que conversa de WhatsApp veio.
--     As lições que só fazem sentido ao telefone (palavra de ligação, "obrigada por ligar", confirmar o
--     contacto, "Em que posso ajudar?" da saudação) ficam 'voz'.
--  3. assistant_contacts: revisão da conversa pelo treinador (mesma ideia das chamadas).
--  4. admin_conversa_devolver: "Devolver ao robô" no painel também desfaz o silêncio de quando o Danilo
--     escreve à mão no telemóvel (antes só desfazia o "Assumir" do painel).

-- 1. tenant
alter table public.assistant_tenants drop constraint if exists assistant_tenants_tipo_check;
alter table public.assistant_tenants add constraint assistant_tenants_tipo_check
  check (tipo = any (array['barbearia'::text, 'restaurante'::text, 'bora'::text]));

create table if not exists public.bkp_assistant_tenants_boom_20261127 as
  select * from public.assistant_tenants where slug = 'boom-burger';
alter table public.bkp_assistant_tenants_boom_20261127 enable row level security;
update public.assistant_tenants set mode = 'desligado', updated_at = now() where slug = 'boom-burger';

insert into public.assistant_tenants (slug, nome, sessao, mode, allowlist, blocklist, dono_destino, knowledge, motor,
                                      motores_reserva, orcamento_mensal_eur, tom, tipo)
select 'bora', 'Bora', 'vps-baileys:351937501673', 'teste', array['351931992662'], array[]::text[], '351931992662',
       jsonb_build_object('ficha', jsonb_build_object('dono', 'a equipa da Bora'), 'perguntas_aprendidas', '[]'::jsonb),
       'voz-cerebro', array[]::text[], 0,
       'Português de Portugal, como uma pessoa da equipa da Bora no WhatsApp: curto, simpático e seguro. Mesmo cérebro do telefone (voz-cerebro).',
       'bora'
where not exists (select 1 from public.assistant_tenants where slug = 'bora');

-- 2. lições por canal
alter table public.voz_licoes add column if not exists canal text not null default 'todos';
alter table public.voz_licoes drop constraint if exists voz_licoes_canal_check;
alter table public.voz_licoes add constraint voz_licoes_canal_check check (canal = any (array['todos'::text, 'voz'::text, 'whatsapp'::text]));
alter table public.voz_licoes add column if not exists conversa_wa text;
update public.voz_licoes set canal = 'voz' where id in (2, 3, 4, 7) and canal = 'todos';

-- 3. revisão das conversas de WhatsApp
alter table public.assistant_contacts add column if not exists revisao_ia jsonb;
alter table public.assistant_contacts add column if not exists revisto_ia_ate timestamptz;

-- 4. devolver ao robô: qualquer silêncio (painel ou telemóvel)
create or replace function public.admin_conversa_devolver(p_origem text, p_conversa_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n int := 0;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_origem = 'suporte_app' then
    return public.admin_suporte_devolver(p_conversa_id::uuid);
  elsif p_origem = 'amigo' then
    update public.assistant_conversations
       set equipa_ate = null, equipa_assumiu_por = null,
           status = case when status = 'handoff' then 'open' else status end
     where id = p_conversa_id::uuid;
    get diagnostics v_n = row_count;
  elsif p_origem = 'whatsapp_loja' then
    update public.assistant_contacts
       set silenciado_ate = null, silenciado_motivo = null
     where tenant_id = split_part(p_conversa_id, ':', 1)::uuid
       and numero = substr(p_conversa_id, length(split_part(p_conversa_id, ':', 1)) + 2)
       and silenciado_ate is not null;
    get diagnostics v_n = row_count;
  else
    raise exception 'origem_invalida';
  end if;
  perform public.log_admin_action('conversa_devolver', p_origem, p_conversa_id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'mudou', v_n > 0);
end
$function$;
