# Handoff ao bibliotecario-cerebro — missão endereco-web (2026-08-31)

Factos novos para o Cérebro, verificados nesta missão:

1. **O autocomplete de moradas da web tem 3 estados e plano B no servidor.**
   `PlaceAutocompleteService.fetchPredictionsWithStatus` devolve
   ready/loading/unavailable; a web cai na Edge Function `places-proxy`
   (autocomplete/geocode/detalhes, verify_jwt, rate-limit 40/min, cache 5 min)
   quando o SDK do Google não carrega. O widget `AddressAutocompleteField`
   nunca fica mudo: mostra estado em PT-PT e o modo manual "Usar esta morada".
   Estado do SDK vive em `window.boraMapsEstado` (index.html) — não renomear
   sem mexer no `place_autocomplete_service_web.dart`.

2. **A chave Google do servidor vive em `public.server_config`**
   (chave `google_maps_server_key`, RLS sem policies = só service role), porque
   o PC não tem supabase CLI nem token de gestão para secrets de env. A função
   lê primeiro o env `GOOGLE_MAPS_SERVER_KEY` se um dia existir.

3. **Cache-busting da web:** o CI carimba `$GITHUB_SHA` no lugar de
   `__BORA_COMMIT__` no index.html; em runtime compara-se com `/versao.json`
   (no-store via `web/_headers`) e limpa-se SW+caches com UMA recarga
   (guarda anti-loop em sessionStorage). Provado com navigation type=reload.

4. **Falhas de morada ficam em `web_health_events`** (motivos:
   script_bloqueado, timeout_sdk, sem_resultados, geocode_manual_falhou,
   proxy_falhou) e aparecem no ecrã admin "Saúde da Web" (PT-BR). INSERT
   aberto a anon de propósito (ecrãs de registo têm morada); SELECT só admin.

5. **Suspeita a investigar (missão própria):** a sessão guest@bora.com pode
   pedir corrida TVDE real (aconteceu no teste; motorista aceitou). Confirmar
   se é desenho. E o login web do cliente pode estar a falhar em silêncio —
   não confirmado, o robô de teste pode ter errado o campo.

6. **Lição reconfirmada:** `anti_trapaca.py` sem `--base` numa branch longa dá
   REJECT falso (base stale); com `--base <HEAD>` deu CLEAN. Já existe lição —
   esta é mais uma cicatriz a somar.

Relatório completo: `.claude/.ai/reports/endereco-web-2026-08-31.md`.
Provas: `.claude/.ai/provas/endereco-web-2026-08-31/`.
