-- REVERTER a migração 20261020162441_b_r1_favor_pellets_max_sacos (revisão B, ronda 1).
-- Tira só a linha de configuração criada por ela. Sem a linha, a app usa 2
-- (FavorDefinicoes.pelletsMaxSacos) e o painel deixa de a mostrar.
delete from public.platform_settings where key = 'favor_pellets_max_sacos';
