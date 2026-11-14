-- Missão editar-perfil-2026-11-11 — Bloco 3.
--
-- Aprovar um pedido ACCOUNT_UPDATE do robô (painel → Propostas do robô →
-- Aprovar) já mudava users.name/users.phone, mas: não normalizava o
-- telemóvel (aceitava "+351…", duas formas do mesmo número), não mexia no
-- metadata do login (a app do cliente continuava a mostrar o nome antigo),
-- não guardava o antes/depois e não avisava o cliente.
--
-- Troca SÓ o ramo ACCOUNT_UPDATE de admin_approve_action para passar pelo
-- núcleo _apply_user_profile_change e avisar o cliente. Os outros ramos ficam
-- byte a byte iguais: o corpo é lido do catálogo e cortado por âncoras, e a
-- definição antiga fica guardada em bkp_fn_admin_approve_action_20261111.
-- Só aceita as chaves name / full_name / phone (antes era uma lista do que
-- era proibido; agora é a lista do que é permitido).

create table if not exists public.bkp_fn_admin_approve_action_20261111 (
  def      text not null,
  def_md5  text not null,
  saved_at timestamptz not null default now()
);
alter table public.bkp_fn_admin_approve_action_20261111 enable row level security;
revoke all on public.bkp_fn_admin_approve_action_20261111 from public, anon, authenticated;

do $patch$
declare
  v_def text := pg_get_functiondef('public.admin_approve_action(uuid)'::regprocedure);
  v_ini int;
  v_fim int;
  v_novo text;
begin
  if strpos(v_def, '_apply_user_profile_change') > 0 then
    raise notice 'admin_approve_action já usa o núcleo — nada a fazer';
    return;
  end if;

  insert into public.bkp_fn_admin_approve_action_20261111 (def, def_md5)
  values (v_def, md5(v_def));

  v_ini := strpos(v_def, $a$WHEN 'ACCOUNT_UPDATE' THEN$a$);
  v_fim := strpos(v_def, $a$WHEN 'PASSWORD_RESET' THEN$a$);
  if v_ini = 0 or v_fim = 0 or v_fim < v_ini then
    raise exception 'âncoras ACCOUNT_UPDATE/PASSWORD_RESET não encontradas — nada mudado';
  end if;

  v_novo := substr(v_def, 1, v_ini - 1) || $blk$WHEN 'ACCOUNT_UPDATE' THEN
        -- editar-perfil 11/11/2026: o mesmo núcleo do "Editar perfil" da app e
        -- do painel — valida, normaliza o telemóvel, grava em users e no login,
        -- guarda o antes/depois em user_profile_changes.
        IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_action.action_payload) k
                    WHERE k NOT IN ('name', 'full_name', 'phone')) THEN
          RAISE EXCEPTION 'FORBIDDEN_FIELD — only name and phone allowed';
        END IF;

        v_new_name  := coalesce(v_action.action_payload->>'name',
                                v_action.action_payload->>'full_name');
        v_new_phone := v_action.action_payload->>'phone';

        IF nullif(btrim(coalesce(v_new_name, '')), '') IS NULL
           AND nullif(btrim(coalesce(v_new_phone, '')), '') IS NULL THEN
          RAISE EXCEPTION 'NOTHING_TO_UPDATE';
        END IF;

        v_updated := public._apply_user_profile_change(
          v_action.user_id, v_new_name, v_new_phone,
          auth.uid(), 'robo_aprovado', v_action.id);

        IF coalesce((v_updated->>'ok')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION '%: %', coalesce(v_updated->>'codigo', 'ACCOUNT_UPDATE_FAILED'),
                                  coalesce(v_updated->>'erro', '');
        END IF;

        IF coalesce((v_updated->>'alterado')::boolean, false) THEN
          PERFORM public._notify_profile_changed(
            v_action.user_id, v_updated->'campos', 'robo_aprovado');
        END IF;

        v_result := jsonb_build_object(
          'updated',  v_updated->'campos',
          'alterado', v_updated->'alterado',
          'name',     v_updated->>'name',
          'phone',    v_updated->>'phone',
          'user_id',  v_action.user_id
        );

      $blk$ || substr(v_def, v_fim);

  execute v_novo;
end
$patch$;
