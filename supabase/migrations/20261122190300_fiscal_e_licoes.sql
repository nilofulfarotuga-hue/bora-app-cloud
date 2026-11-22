-- Missão hermes-diretor-2026-11-20 — B5 (o fiscal) e B6 (os robôs aprendem). Só funções, vista, trigger e lições iniciais.
-- Precisa da migração …190000 (colunas novas do despacho, robos_casos_teste, mapa_app, índice único de licoes_robos).
-- Não mexe em preços, dinheiro, pedidos nem em RLS de zonas protegidas. Aplicar pela Claude.ai.
-- Reversão: ver o fim do ficheiro.

-- ───────────────────────── A) O FISCAL NO DESPACHO ─────────────────────────

-- Novo estado: a-auditar (a tarefa trouxe prova, falta o fiscal conferir).
alter table public.despacho drop constraint if exists despacho_estado_check;
alter table public.despacho add constraint despacho_estado_check check (estado = any (array[
  'aberta','executando','feita','falhou','a-espera-do-danilo','a-espera-do-pc','cancelada','a-auditar']));

-- Quem pode chamar as funções do fiscal sem ser pela chave de serviço (migrações e consola do projeto).
create or replace function public._hd_e_servico() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    session_user in ('postgres','supabase_admin','service_role')
      or coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb) ->> 'role') = 'service_role',
    false);
$$;
revoke execute on function public._hd_e_servico() from public, anon, authenticated;

-- Texto sem acentos e sem maiúsculas (para procurar botões).
create or replace function public._hd_norm(p text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select translate(lower(btrim(coalesce(p, ''))),
    'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
$$;
revoke execute on function public._hd_norm(text) from public, anon, authenticated;
grant execute on function public._hd_norm(text) to service_role;

-- O guarda: uma tarefa que precisa de auditoria não fecha sem prova, e só o fiscal a marca como auditada.
create or replace function public.despacho_fiscal_guarda() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_valida boolean;
begin
  -- auditada=true só se vier de despacho_auditar (que marca a sessão)
  if new.auditada is true and old.auditada is distinct from true
     and coalesce(current_setting('bora.fiscal', true), '') <> '1' then
    new.auditada := old.auditada;
    new.auditada_em := old.auditada_em;
  end if;

  if new.estado = 'feita' and old.estado is distinct from 'feita'
     and new.precisa_auditoria and new.auditada is not true then
    v_valida := new.prova_dados is not null
      and jsonb_typeof(new.prova_dados) = 'object'
      and (new.prova_dados ->> 'tipo') in ('select','log','ficheiro','url','mensagem')
      and nullif(btrim(coalesce(new.prova_dados ->> 'conteudo', '')), '') is not null;
    if v_valida then
      new.estado := 'a-auditar';             -- o fiscal confere depois
    else
      new.estado := 'aberta';                -- não fecha; não conta como tentativa
      new.terminada_em := null;
      new.auditoria_nota := 'sem prova: a tarefa só fecha com prova verificável';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.despacho_fiscal_guarda() from public, anon, authenticated;

drop trigger if exists despacho_fiscal_guarda on public.despacho;
create trigger despacho_fiscal_guarda before update on public.despacho
  for each row execute function public.despacho_fiscal_guarda();

-- O fiscal decide. Só para tarefas em a-auditar. Até 2 devoluções ao MESMO agente; à 3.ª falha: falhou.
create or replace function public.despacho_auditar(p_id bigint, p_ok boolean, p_nota text, p_quem text default 'fiscal')
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.despacho;
  v_nota text;
  v_n smallint;
begin
  select * into r from public.despacho where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'nao_existe');
  end if;
  if r.estado <> 'a-auditar' then
    return jsonb_build_object('ok', false, 'erro', 'estado_errado', 'estado', r.estado);
  end if;

  v_nota := left(coalesce(nullif(btrim(p_nota), ''), case when p_ok then 'conferido' else 'prova não confere' end), 600);
  perform set_config('bora.fiscal', '1', true);

  if p_ok then
    update public.despacho
       set estado = 'feita', auditada = true, auditada_em = now(),
           auditoria_nota = v_nota, terminada_em = coalesce(terminada_em, now())
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'feita', 'auditada', true);
  end if;

  v_n := r.auditoria_tentativas + 1;
  if v_n <= 2 then
    update public.despacho
       set estado = 'aberta', auditada = false, auditada_em = now(),
           auditoria_tentativas = v_n, auditoria_nota = v_nota, terminada_em = null,
           tarefa = tarefa || E'\n[FISCAL ' || v_n || '/2] ' || v_nota
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'aberta', 'devolvida', true, 'tentativa', v_n, 'para', r.para);
  end if;

  update public.despacho
     set estado = 'falhou', auditada = false, auditada_em = now(),
         auditoria_tentativas = v_n, auditoria_nota = v_nota
   where id = p_id;

  -- avisa o vigia, se já existir (vem de outra migração)
  if to_regprocedure('public.sentinela_registar(text,text,text,text,jsonb)') is not null then
    begin
      execute 'select public.sentinela_registar($1,$2,$3,$4,$5)'
        using 'sistema', 'urgente', 'fiscal-falhou-' || p_id,
              'O fiscal reprovou 3 vezes a tarefa ' || p_id || ' do agente ' || r.para,
              jsonb_build_object('despacho_id', p_id, 'agente', r.para, 'para', 'emerson', 'quem', p_quem);
    exception when others then
      null;   -- o aviso nunca pode impedir o fiscal de fechar a tarefa
    end;
  end if;
  return jsonb_build_object('ok', true, 'estado', 'falhou', 'tentativa', v_n);
end $$;
revoke execute on function public.despacho_auditar(bigint, boolean, text, text) from public, anon, authenticated;
grant execute on function public.despacho_auditar(bigint, boolean, text, text) to service_role;

-- Números das últimas 24 h, por agente.
create or replace view public.despacho_auditoria_24h with (security_invoker = true) as
select
  para as agente,
  count(*) filter (where terminada_em >= now() - interval '24 hours') as terminadas,
  count(*) filter (where terminada_em >= now() - interval '24 hours' and precisa_auditoria) as precisavam_auditoria,
  count(*) filter (where terminada_em >= now() - interval '24 hours' and precisa_auditoria and auditada is true) as auditadas_ok,
  count(*) filter (where auditada is false and auditada_em >= now() - interval '24 hours') as devolvidas,
  case when count(*) filter (where terminada_em >= now() - interval '24 hours' and precisa_auditoria) = 0 then null
       else round(100.0
         * count(*) filter (where terminada_em >= now() - interval '24 hours' and precisa_auditoria and auditada is true)
         / count(*) filter (where terminada_em >= now() - interval '24 hours' and precisa_auditoria), 1) end as pct_auditadas
from public.despacho
where terminada_em >= now() - interval '24 hours' or auditada_em >= now() - interval '24 hours'
group by para;
revoke all on public.despacho_auditoria_24h from public, anon;
grant select on public.despacho_auditoria_24h to authenticated, service_role;

create or replace function public.despacho_auditoria_resumo() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v jsonb;
begin
  if not (public._hd_e_servico() or public.is_admin()) then
    raise exception 'só para administradores' using errcode = '42501';
  end if;
  select jsonb_build_object(
           'terminadas', coalesce(sum(terminadas), 0),
           'precisavam_auditoria', coalesce(sum(precisavam_auditoria), 0),
           'auditadas_ok', coalesce(sum(auditadas_ok), 0),
           'devolvidas', coalesce(sum(devolvidas), 0),
           'pct_auditadas', case when coalesce(sum(precisavam_auditoria), 0) = 0 then null
                                 else round(100.0 * sum(auditadas_ok) / sum(precisavam_auditoria), 1) end,
           'por_agente', coalesce(jsonb_agg(to_jsonb(d) order by d.agente), '[]'::jsonb))
    into v
    from public.despacho_auditoria_24h d;
  return v;
end $$;
revoke execute on function public.despacho_auditoria_resumo() from public, anon, authenticated;
grant execute on function public.despacho_auditoria_resumo() to service_role, authenticated;

-- ───────────────────────── B) AS LIÇÕES DOS ROBÔS ─────────────────────────

create or replace function public.licao_robo_gravar(p_robo text, p_errou text, p_regra text, p_origem text default 'fiscal')
returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_robo text := lower(btrim(coalesce(p_robo, '')));
  v_errou text := left(btrim(coalesce(p_errou, '')), 600);
  v_regra text := left(btrim(coalesce(p_regra, '')), 600);
  v_id bigint;
begin
  if v_robo not in ('suporte','amigo','whatsapp','hermes') then
    raise exception 'robô inválido: %', p_robo;
  end if;
  if v_errou = '' or v_regra = '' then
    raise exception 'errou e regra não podem ficar vazios';
  end if;
  insert into public.licoes_robos (robo, errou, regra, origem)
  values (v_robo, v_errou, v_regra, coalesce(nullif(btrim(p_origem), ''), 'fiscal'))
  on conflict (robo, md5(lower(btrim(regra))))
  do update set vezes = public.licoes_robos.vezes + 1, ativa = true,
                arquivada_em = null, arquivada_por = null, editada_em = now()
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.licao_robo_gravar(text, text, text, text) from public, anon, authenticated;
grant execute on function public.licao_robo_gravar(text, text, text, text) to service_role;

create or replace function public.licoes_robo_texto(p_robo text, p_max int default 2500) returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_max int := greatest(coalesce(p_max, 2500), 0);
  v_out text := '';
  v_linha text;
  r record;
begin
  for r in
    select regra from public.licoes_robos
     where robo = lower(btrim(coalesce(p_robo, ''))) and ativa and arquivada_em is null
     order by vezes desc, id
  loop
    v_linha := '- ' || r.regra;
    if v_out = '' then
      v_out := left(v_linha, v_max);
      if length(v_linha) > v_max then exit; end if;
    elsif length(v_out) + 1 + length(v_linha) <= v_max then
      v_out := v_out || E'\n' || v_linha;
    else
      exit;
    end if;
  end loop;
  return v_out;
end $$;
revoke execute on function public.licoes_robo_texto(text, int) from public, anon, authenticated;
grant execute on function public.licoes_robo_texto(text, int) to service_role;

create or replace function public.robo_caso_gravar(
  p_robo text, p_pergunta text, p_deve_conter text[], p_nao_pode_conter text[],
  p_licao_id bigint default null, p_origem text default 'fiscal') returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_robo text := lower(btrim(coalesce(p_robo, '')));
  v_perg text := left(btrim(coalesce(p_pergunta, '')), 600);
  v_deve text[] := coalesce(p_deve_conter, '{}');
  v_nao text[] := coalesce(p_nao_pode_conter, '{}');
  v_id bigint;
begin
  if v_robo not in ('suporte','amigo','whatsapp','hermes') then
    raise exception 'robô inválido: %', p_robo;
  end if;
  if v_perg = '' then raise exception 'a pergunta não pode ficar vazia'; end if;
  if cardinality(v_deve) = 0 and cardinality(v_nao) = 0 then
    raise exception 'um caso de teste precisa de pelo menos uma condição';
  end if;
  -- a mesma pergunta do mesmo robô atualiza o caso em vez de duplicar
  select id into v_id from public.robos_casos_teste
   where robo = v_robo and lower(btrim(pergunta)) = lower(v_perg) and ativo limit 1;
  if v_id is not null then
    update public.robos_casos_teste
       set deve_conter = v_deve, nao_pode_conter = v_nao,
           licao_id = coalesce(p_licao_id, licao_id)
     where id = v_id;
    return v_id;
  end if;
  insert into public.robos_casos_teste (robo, pergunta, deve_conter, nao_pode_conter, licao_id, origem)
  values (v_robo, v_perg, v_deve, v_nao, p_licao_id, coalesce(nullif(btrim(p_origem), ''), 'fiscal'))
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.robo_caso_gravar(text, text, text[], text[], bigint, text) from public, anon, authenticated;
grant execute on function public.robo_caso_gravar(text, text, text[], text[], bigint, text) to service_role;

create or replace function public.robo_caso_resultado(p_id bigint, p_passou boolean, p_resposta text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.robos_casos_teste
     set ultimo_resultado = case when p_passou then 'passou' else 'falhou' end,
         ultima_resposta = left(coalesce(p_resposta, ''), 2000),
         ultima_corrida_em = now()
   where id = p_id;
  if not found then
    raise exception 'caso de teste % não existe', p_id;
  end if;
end $$;
revoke execute on function public.robo_caso_resultado(bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.robo_caso_resultado(bigint, boolean, text) to service_role;

create or replace function public.robos_regressao_resumo(p_robo text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v jsonb;
  v_robo text := nullif(lower(btrim(coalesce(p_robo, ''))), '');
begin
  if not (public._hd_e_servico() or public.is_admin()) then
    raise exception 'só para administradores' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'robo', v_robo,
    'casos_ativos', count(*),
    'passaram', count(*) filter (where ultimo_resultado = 'passou'),
    'falharam', count(*) filter (where ultimo_resultado = 'falhou'),
    'nunca_corridos', count(*) filter (where ultimo_resultado is null),
    'ultima_corrida', max(ultima_corrida_em),
    'pode_publicar', count(*) filter (where ultimo_resultado = 'falhou') = 0)
  into v
  from public.robos_casos_teste
  where ativo and (v_robo is null or robo = v_robo);
  return v;
end $$;
revoke execute on function public.robos_regressao_resumo(text) from public, anon, authenticated;
grant execute on function public.robos_regressao_resumo(text) to service_role, authenticated;

create or replace function public.mapa_app_tem(p_texto text, p_app text default null) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_q text := public._hd_norm(p_texto);
  v_app text := nullif(lower(btrim(coalesce(p_app, ''))), '');
  v_lista jsonb;
begin
  if not (public._hd_e_servico() or public.is_admin()) then
    raise exception 'só para administradores' using errcode = '42501';
  end if;
  if v_q = '' then
    return jsonb_build_object('existe', false, 'total', 0, 'encontrados', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('app', app, 'ecra', ecra, 'rota', rota, 'elemento', elemento,
                                               'tipo', tipo, 'ficheiro', ficheiro, 'versao', versao)
                            order by app, ecra), '[]'::jsonb)
    into v_lista
    from (select * from public.mapa_app
           where strpos(public._hd_norm(elemento), v_q) > 0 and (v_app is null or app = v_app)
           order by app, ecra limit 20) x;
  return jsonb_build_object('existe', jsonb_array_length(v_lista) > 0,
                            'total', jsonb_array_length(v_lista), 'encontrados', v_lista);
end $$;
revoke execute on function public.mapa_app_tem(text, text) from public, anon, authenticated;
grant execute on function public.mapa_app_tem(text, text) to service_role, authenticated;

-- ───────────────────────── Lições iniciais (todas confirmadas a 22/11/2026) ─────────────────────────
-- Cada uma entra para os 3 robôs de atendimento, só se ainda não existir.
do $$
declare
  v_licoes text[][] := array[
    -- 1. Editar perfil: botão existe em lib/screens/edit_profile_screen.dart e está no ramo de produção desde 11/11
    array['Disse ao cliente que não há maneira de mudar o nome ou o telemóvel na app.',
          'Na app do cliente, no ecrã Perfil, existe o botão «Editar perfil»: serve para mudar o nome e o telemóvel (o email não se muda). Se o cliente não o vir, deve atualizar a app.'],
    -- 2. Desconto de tokens: order_details_screen.dart e order_tracking_screen.dart (linha_desconto_tokens)
    array['Não soube dizer onde se vê o desconto dos tokens do cliente num pedido.',
          'Quando o cliente usa tokens, o desconto aparece na conta do pedido (no detalhe do pedido e no acompanhamento), numa linha «Desconto de tokens» a verde e com sinal de menos. O total menos esse desconto dá o valor pago.'],
    -- 3. Zona: platform_settings delivery_max_distance_km=15 e livro-areas-entrega-longa-distancia (12/11)
    array['Aceitei ou deixei em aberto uma entrega fora da Guarda (por exemplo Pinhel), mesmo com o cliente a oferecer pagar mais.',
          'A Bora entrega só na Guarda, num raio de cerca de 15 km do centro. Terras do distrito como Pinhel ficam fora, mesmo que o cliente pague a mais. Diz-o com simpatia e com certeza. A limpeza tem uma regra de área própria: segue o conhecimento da limpeza.'],
    -- 4. Regra dos tokens do cliente: platform_settings token_balance_max_use_pct=50 e token_payment_max_pct=50
    array['Disse que o cliente pode pagar um pedido todo com os tokens que tem.',
          'O cliente só pode usar, no máximo, metade do valor dos tokens que tem em cada compra. Os outros tokens ficam guardados para a vez seguinte.'],
    -- 5. Horário: livro-areas-whatsapp-loja (factos dados pelo Danilo a 31/08)
    array['Dei um horário de funcionamento do Bora como se fosse da própria Bora.',
          'O Bora não tem horário próprio: cada loja ou restaurante tem o seu, indicado na app na página da loja. A Bora trabalha todos os dias, incluindo domingos e feriados; a entrega depende de haver estafeta disponível nesse momento.'],
    -- 6. iPhone: livro-areas-lancamento-ios (20/09: no ar na App Store portuguesa)
    array['Disse ao cliente que a app ainda não existe para iPhone.',
          'Existe app para iPhone: «Bora - Entregas e Serviços», grátis na App Store portuguesa (https://apps.apple.com/pt/app/bora-entregas-e-servicos/id6809954739). Também há para Android na Play Store.']
  ];
  v_robos text[] := array['suporte','amigo','whatsapp'];
  i int;
  v_robo text;
begin
  for i in 1 .. array_length(v_licoes, 1) loop
    foreach v_robo in array v_robos loop
      if not exists (select 1 from public.licoes_robos
                      where robo = v_robo and md5(lower(btrim(regra))) = md5(lower(btrim(v_licoes[i][2])))) then
        perform public.licao_robo_gravar(v_robo, v_licoes[i][1], v_licoes[i][2], 'missao-hermes-diretor');
      end if;
    end loop;
  end loop;
end $$;

-- Reversão (se for preciso):
--   drop trigger despacho_fiscal_guarda on public.despacho;
--   drop function public.despacho_fiscal_guarda(), public.despacho_auditar(bigint,boolean,text,text),
--     public.despacho_auditoria_resumo(), public.licao_robo_gravar(text,text,text,text), public.licoes_robo_texto(text,int),
--     public.robo_caso_gravar(text,text,text[],text[],bigint,text), public.robo_caso_resultado(bigint,boolean,text),
--     public.robos_regressao_resumo(text), public.mapa_app_tem(text,text), public._hd_e_servico(), public._hd_norm(text);
--   drop view public.despacho_auditoria_24h;
--   (o estado a-auditar pode ficar no CHECK sem mal; antes de o tirar, passar essas linhas a aberta)
--   delete from public.licoes_robos where origem = 'missao-hermes-diretor';
