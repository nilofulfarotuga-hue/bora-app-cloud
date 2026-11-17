-- 17/11/2026 Claude.ai (pedido do Danilo 15:12: "o robô já sabe da farmácia, da A3? tem que pôr as novidades na app").
-- JÁ APLICADA em produção por MCP (migração novidades_farmacia_robos_17_11). Fica aqui para o repo ter o mesmo.
-- 1) Amigo Bora: "parceiros novos" deixava passar lojas ESCONDIDAS (so_lista_permissao) — a Farmácia da Sé foi anunciada
--    a 3 clientes entre 12 e 16/11 quando ainda estava escondida, e a A3 Guarda (escondida, só contas de teste) era a próxima.
--    Agora loja escondida só é anunciada a quem está na lista dela (o mesmo para faixas que apontam para loja escondida).
create or replace function public.assistant_amigo_contexto(p_user_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with p as (
    select coalesce((select lembrar from public.assistant_client_profile where user_id = p_user_id), true) as lembrar,
           coalesce((select perfil from public.assistant_client_profile where user_id = p_user_id), '{}'::jsonb) as perfil,
           (select atualizado_em from public.assistant_client_profile where user_id = p_user_id) as atualizado_em
  )
  select jsonb_build_object(
    'lembrar', (select lembrar from p),
    'perfil', case when (select lembrar from p) then (select perfil from p) else '{}'::jsonb end,
    'perfil_atualizado_em', (select atualizado_em from p),
    'ultimos_pedidos', case when (select lembrar from p) then coalesce((
        select jsonb_agg(x order by x.quando desc) from (
          select o.id as pedido_id,
                 to_char(o.created_at at time zone 'Europe/Lisbon', 'YYYY-MM-DD') as dia,
                 o.created_at as quando,
                 coalesce(nullif(o.vendor_name, ''), o.restaurant_id) as loja,
                 o.restaurant_id as loja_id,
                 o.service_type as tipo,
                 o.status as estado,
                 (select string_agg(trim(i->>'name'), ', ')
                    from (select e as i from jsonb_array_elements(case when jsonb_typeof(o.items) = 'array' then o.items else '[]'::jsonb end) e limit 3) z) as artigos
            from public.orders o
           where o.user_id = p_user_id
             and o.created_at > coalesce((select esquecido_em from public.assistant_client_profile where user_id = p_user_id), '-infinity'::timestamptz)
           order by o.created_at desc
           limit 5) x), '[]'::jsonb)
      else '[]'::jsonb end,
    'promocoes', coalesce((
        select jsonb_agg(jsonb_build_object('id', b.id, 'titulo', b.titulo, 'subtitulo', b.subtitulo,
                                            'tipo_destino', b.tipo_destino, 'destino', b.destino) order by b.ordem)
          from public.home_banners b
         where b.ativo
           and (b.inicio is null or b.inicio <= now())
           and (b.fim is null or b.fim > now())
           and coalesce(b.destino, '') <> 'assistente'
           -- faixa que aponta para loja escondida só para quem está na lista dela
           and not exists (select 1 from public.restaurants rr
                            where b.tipo_destino = 'loja' and rr.id = b.destino and coalesce(rr.so_lista_permissao, false)
                              and not exists (select 1 from public.loja_lista_permissao l
                                               where l.restaurant_id = rr.id and l.user_id = p_user_id))), '[]'::jsonb),
    'parceiros_novos', coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.name, 'categoria', r.category))
          from (select * from public.restaurants r
                 where coalesce(r.approved_at, r.created_at) > now() - interval '14 days'
                   and coalesce(r.coming_soon, false) = false
                   and coalesce(r.is_active_admin, true)
                   and coalesce(r.approval_status, 'approved') = 'approved'
                   and (not coalesce(r.so_lista_permissao, false)
                        or exists (select 1 from public.loja_lista_permissao l
                                    where l.restaurant_id = r.id and l.user_id = p_user_id))
                 order by coalesce(r.approved_at, r.created_at) desc
                 limit 5) r), '[]'::jsonb)
  );
$function$;

-- 2) Amigo Bora: conhecimento da Farmácia da Sé e das receitas (antes só sabia que existia a categoria).
insert into public.assistant_knowledge (topic, title, content, active, sort_order, updated_by, updated_at)
select 'farmacia', 'Farmácia da Sé e receitas',
'Farmácia: na página inicial, "Farmácia". A Farmácia da Sé (Guarda) já está aberta na Bora. Produtos sem receita (cosmética, higiene, bebé, medicamentos de venda livre) compram-se como em qualquer loja: escolher, pôr no carrinho e pagar. Medicamentos COM receita: dentro da loja da Farmácia da Sé, botão "Tenho receita": tirar foto da receita (ou escrever o número e o código), autorizar o estafeta a levantar em nome do cliente e enviar. A farmácia vê se tem os medicamentos e responde; depois aparece o valor dos medicamentos e a taxa do estafeta para o cliente confirmar e pagar (cartão, MB Way ou dinheiro). O estafeta levanta na farmácia e entrega em casa. Produto que não aparece na loja: botão "Não encontra o produto? Peça aqui". Para a medicação de todos os meses há "Repetir todos os meses". A farmácia tem de estar aberta (horário na página da loja). A Farmácia Teixeira chega em breve. Outras farmácias: só pelos Favores e só produtos sem receita. Nunca dar conselho médico nem dizer que medicamento tomar: isso é com o farmacêutico ou o médico.',
true, 137, null, now()
where not exists (select 1 from public.assistant_knowledge where topic = 'farmacia');

-- 3) Faixa de novidade na página inicial (o Amigo também a usa como "Já viste?").
insert into public.home_banners (titulo, subtitulo, imagem_url, cor_inicio, cor_fim, tipo_destino, destino, ordem, ativo, inicio, fim, patrocinado, parceiro_id, criado_em, atualizado_em)
select 'Novidade: Farmácia da Sé', 'Tens receita? Tira foto e o estafeta levanta por ti', null, '#16A34A', '#22C55E',
       'loja', 'farmacia-se-guarda', 1, true, now(), '2026-12-17 23:59:00+00', false, 'farmacia-se-guarda', now(), now()
where not exists (select 1 from public.home_banners where destino = 'farmacia-se-guarda');

-- 4) Robô do suporte: a skill dizia "farmácia só sem receita pelos Favores" e "receita = passar a humano". Cópia antes.
create table if not exists public.bkp_support_skills_favores_20261117 as
  select * from public.support_skills where skill_name = 'FAVORES_ONDE_ENCOMENDAR';

update public.support_skills set
  version = version + 1,
  updated_at = now(),
  playbook_md = $md$# FAVORES_ONDE_ENCOMENDAR

**Quando usar:** o cliente pergunta onde encomendar algo que NÃO está numa loja da app (tabaco, tabacaria, papelaria, pão de padaria, levantar uma encomenda, pagar uma conta, comprar algo numa loja de rua) OU pergunta por farmácia, medicamentos ou receitas. Ex.: "tabaco", "onde encomendar tabaco", "quero cigarros", "podem ir buscar X?", "tenho uma receita", "farmácia".

**Tools:** [] (resposta directa, não chamar tools)

## Resposta (Favores)
- Isto faz-se pelos **Favores** (Pedir um Favor) na app.
- Passos: abrir a app, escolher **Favores**, escrever o que quer (marca e quantidade) e onde comprar se tiver preferência, e confirmar. O estafeta compra e entrega à porta.
- O valor dos produtos é pago à parte, conforme o talão da loja.

## Farmácia
- A **Farmácia da Sé** já está na app (página inicial > **Farmácia**). Produtos sem receita compram-se como em qualquer loja.
- Medicamentos **com receita**: dentro da loja da Farmácia da Sé, botão **"Tenho receita"**: tirar foto da receita (ou escrever o número e o código), autorizar e enviar. A farmácia confirma o que tem, o cliente vê o valor e confirma, e o estafeta levanta e entrega em casa.
- Produto que não aparece na loja: botão **"Não encontra o produto? Peça aqui"**.
- A Farmácia Teixeira chega em breve. Outras farmácias: só pelos Favores e só sem receita.
- Nunca dar conselho médico nem dizer que medicamento tomar.

## Regras
- **Tabaco e álcool:** só para maiores de 18 anos. Avisar que o estafeta pode pedir documento de identificação na entrega e não entrega a menores.
- NUNCA mandar o cliente procurar tabaco nos supermercados ou lojas da app: os supermercados da app não vendem tabaco.
- Não inventar preços dos Favores; dizer que o valor aparece antes de confirmar.$md$,
  examples = coalesce(examples, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
    'user', 'tenho uma receita, vocês vão buscar?',
    'assistant', 'Sim! Na página inicial abre "Farmácia" e entra na Farmácia da Sé. Carrega em "Tenho receita", tira foto da receita e envia. A farmácia confirma o que tem, tu vês o valor e confirmas, e o estafeta leva-te os medicamentos a casa.'))
where skill_name = 'FAVORES_ONDE_ENCOMENDAR'
  and version = 1;
