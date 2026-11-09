select p.proname as nome, pg_get_function_identity_arguments(p.oid) as args, md5(p.prosrc) as md5_src, pg_get_functiondef(p.oid) as def
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('tvde_dispatch_sweep','tvde_offer_to_next','_tvde_chamada_de_reforco','_tvde_forcados','_registar_oferta_tvde','dispatch_reforco_horario_ok','get_setting','_tvde_fila_ligada','_haversine_km','tvde_driver_reservation_locked','tvde_driver_offer_allowed','fn_notify_tvde_driver_on_offer','fn_notify_tvde_client_on_status')
order by p.proname, p.oid
