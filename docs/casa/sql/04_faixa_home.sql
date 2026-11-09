-- PUBLICAÇÃO 2 da Casa — passo 4: a faixa da home "Novidade: Casa & Manutenção" (14 dias).
-- O mesmo sistema de faixas de sempre (home_banners, painel > Faixas da home), destino Categoria → casa
-- (abre o CasaCategoriaScreen; com a Casa desligada o próprio ecrã diz "Brevemente").
-- Molde: a faixa "Novidade: Bora Assistente" (tipo categoria, verde #16A34A → #22C55E, sem imagem).
-- Janela: de agora a agora + 14 dias (o RLS de home_banners já só mostra o que está dentro da janela).
-- Para desligar ou mudar as datas: painel > Faixas da home. Idempotente (não cria uma 2.ª faixa da Casa ativa).
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;

  if exists (select 1 from public.home_banners
              where tipo_destino = 'categoria' and destino = 'casa' and ativo) then
    raise notice 'ja existe uma faixa da Casa ativa: nada a fazer';
    return;
  end if;

  insert into public.home_banners (titulo, subtitulo, cor_inicio, cor_fim, tipo_destino, destino,
                                   ordem, ativo, inicio, fim)
  values ('Novidade: Casa & Manutenção',
          'Montar móveis, pendurar, pequenas reparações',
          '#16A34A', '#22C55E', 'categoria', 'casa',
          1, true, now(), now() + interval '14 days')
  returning id into v_id;

  perform public.log_admin_action('home_banner_criar'::text, 'home_banners'::text, v_id::text,
    jsonb_build_object('titulo', 'Novidade: Casa & Manutenção', 'destino', 'categoria:casa',
                       'via', 'publicacao2-casa', 'dias', 14));
end
$pub$;

-- Prova (lê de volta):
select id, titulo, subtitulo, tipo_destino, destino, ordem, ativo, inicio, fim
  from public.home_banners
 where tipo_destino = 'categoria' and destino = 'casa'
 order by criado_em desc;
