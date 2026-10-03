# Provas — motorista-ficha-legal-2026-09-23

Migrações em produção (supabase_migrations.schema_migrations): 20260923183444, 20260923183552,
20260923183704, 20260923184217 — SQL literal em supabase/migrations/.
Edge Functions: tvde-recibo-viagem v2, ficha-fiscalizacao-email v1 (verify_jwt=true).

Rollback JWT 4f61dd31 (motorista): semaforo certificado valido 586d / carta a_expirar 17d / inspecao expirado -22d;
token reaproveitado igual=t; publica nif=null apolice=null carta ••••654; bloqueio "DOCUMENTO_EXPIRADO: Inspeção periódica".
Rollback aviso diario: 1a=2 avisos, 2a=0; 2 in-app; 2 pedidos push; 1 admin_notification.
Rollback admin (app_metadata.role=admin): admin_audit_log 711 -> 712; lista 4 (demo filtrado); motorista -> forbidden.
motorista_pode_ficar_online: {"ok":false,"expirados":["Inspeção periódica"]} -> corrigido {"ok":true}.
Grants: has_function_privilege anon=false em todas as funcoes novas excepto verificar_ficha_publica.
Real: recibo ride ba0dc6a0 -> nilofulfarotuga@gmail.com HTTP 200 resend 01a0cf90-7a46-71cc-a9d4-411a93ad0970.
Real (Gmail boraappbora, 18:40 UTC): "Recibo da tua viagem Bora" (4,00 + 1,00 = 5,00, MB Way) e
"A tua ficha de fiscalização TVDE (Bora)" com anexo ficha-fiscalizacao-bora.pdf e token 3vZdoB22ZHMz.
Pagina publica: verificar-valido-390.png / verificar-invalido-390.png (scrollWidth 390 = innerWidth 390).
flutter analyze: 0 erros. flutter test: 796 passaram. anti_trapaca.py: CLEAN. identidade-estafeta: OK.
