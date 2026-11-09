select p.proname, pg_get_functiondef(p.oid) as def
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('is_admin','get_setting','log_admin_action','_admin_op_guard','_admin_broadcast_alvos','admin_broadcast_notification','_casa_bool','_casa_int','_casa_motivo','_casa_valores_validos','_casa_visivel','casa_config','admin_casa_interruptor','admin_casa_guardar_definicao','_casa_reabrir_valores','admin_casa_decidir_profissional','admin_casa_decidir_oficio','is_demo_user','_casa_exigir_admin')
order by p.proname;
