-- tvde-conformidade-lei-59-2026 · segurança + correção pela lei — 2026-09-30
-- 1) Os gatilhos novos não se chamam por /rest/v1/rpc (aviso do linter
--    anon/authenticated_security_definer_function_executable).
revoke all on function public.fn_tvde_conformidade_online() from public, anon, authenticated;
revoke all on function public.fn_tvde_intermediacao_no_fim() from public, anon, authenticated;
revoke all on function public.fn_tvde_work_log_online() from public, anon, authenticated;
revoke all on function public.fn_tvde_pagamento_eletronico() from public, anon, authenticated;
revoke all on function public.fn_tvde_rides_prefs() from public, anon, authenticated;

-- 2) A pesquisa da Fase 0 (texto oficial da Lei 59/2026, DR 25/08/2026)
--    mostrou que a proibição de avaliar passageiros (antigo art. 19.º n.º 5)
--    foi REVOGADA e o art. 19.º n.º 2 c) passou a EXIGIR avaliação pelos dois
--    lados. O interruptor fica, mas não se liga.
update public.platform_settings
   set description = 'NÃO LIGAR. O prompt pedia esconder a avaliação do passageiro (antigo art. 19.º n.º 5), '
                  || 'mas a Lei 59/2026 revogou essa proibição e o art. 19.º n.º 2 c) passou a EXIGIR '
                  || 'avaliação pelos dois lados. Fica só para o caso de a AMT/IMT dizer o contrário.'
 where key = 'tvde_driver_rates_client_disabled';

update public.platform_settings
   set description = 'Art. 15.º n.º 6 (Lei 59/2026): a plataforma TEM de oferecer sempre a opção de preço fixo '
                  || 'fechado antes de pedir. Hoje o preço é recalculado pela distância real. '
                  || 'PROPOSTA — mexe no valor cobrado; só se constrói e liga depois do "vai" do Danilo.'
 where key = 'tvde_fixed_price_option_enabled';

update public.platform_settings
   set description = 'Art. 14.º n.º 2: bloquear motorista com CMTVDE, operador, veículo, seguro ou inspeção '
                  || 'caducados ou em falta. A CNPD recomenda que o bloqueio não seja 100% automático: o admin '
                  || 'revê na secção Conformidade TVDE e o motorista pode contestar por queixa. Só vale com o mestre ligado.'
 where key = 'tvde_compliance_block';
