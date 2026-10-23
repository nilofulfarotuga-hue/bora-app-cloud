-- Missão omniroute-23-10 (23/10/2026). Igual aos gémeos motor_estado/motor_chamadas: anon pode fazer
-- SELECT, mas a RLS (is_admin()) devolve 0 linhas. Sem isto o ecrã /admin/motores aberto sem sessão
-- rebentava inteiro com 42501 "permission denied for table omniroute_estado" (visto 23/10 às 06:22).
-- Já aplicada em produção.
grant select on public.omniroute_estado to anon;
