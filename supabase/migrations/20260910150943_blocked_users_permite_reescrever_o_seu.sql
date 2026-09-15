-- A app grava o bloqueio com `upsert(..., onConflict: 'blocker_id,blocked_ref')`.
-- Um upsert e' INSERT ... ON CONFLICT DO UPDATE, e por isso precisa TAMBEM de
-- politica de UPDATE. A tabela so tinha SELECT, INSERT e DELETE: se a linha ja
-- existisse (lista em cache desactualizada, ou outro telemovel), o bloqueio era
-- recusado pela RLS e a pessoa via "Nao foi possivel concluir" -- justamente no
-- mecanismo que a Apple exigiu ao recusar a primeira submissao.
--
-- Continua fechada ao dono: cada um so reescreve os seus.
create policy blocked_users_reescreve_os_seus
  on public.blocked_users
  for update
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);