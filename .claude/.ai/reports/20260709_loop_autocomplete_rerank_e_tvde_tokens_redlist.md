# Loop autónomo — 2026-07-09 — Autocomplete (rerank Guarda-first) + TVDE tokens (🔴 red-list)

## Contexto
Teste real do Danilo (fotos) reprovou a versão anterior do autocomplete (aprovada só no Chrome/web):
- Digitar **"Continente"** → mostrava o Continente de OUTRA cidade em vez do da Guarda.
- Digitar **"Lavie"** (LaVie Shopping, Guarda) → ZERO resultados.

## Bug 1 — Autocomplete (ZONA VERDE — EXECUTADO)
Causa-raiz: o viés `location`+`radius` do Google Places (legado) é apenas um **empurrão de ranking
fraco** — não garante o resultado local no topo, e não surge comércio pequeno ("Lavie") sob
`country:pt` a partir do token isolado.

Fix determinístico (não depende de testar a API):
1. **Re-ranking Guarda-first** client-side (`_rankGuardaFirst`, ordenação estável): qualquer predição
   cuja `description`/`secondaryText` contenha "guarda" sobe ao topo, sem excluir as restantes.
   → resolve o "Continente de outra cidade em 1.º".
2. **3.º fallback** anexando `" Guarda"` à query quando viés + sem-viés vêm vazios. O Google devolve
   "Lavie Guarda" → LaVie Shopping. Só dispara em último caso → não penaliza moradas normais.

Ficheiros: `lib/services/place_autocomplete_service_io.dart` (Android/USB — o device do teste),
`lib/services/place_autocomplete_service_web.dart` (paridade; refactor `_requestPredictions`).
`flutter analyze` dos ficheiros tocados: **0 erros, 0 issues novos** (as 2 warnings `dart:html`/
`dart:js` são pré-existentes).

### ⚠️ Prova visual em device real — NÃO FOI POSSÍVEL nesta sessão
`adb devices` (adb em `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`) devolveu **lista vazia**
mesmo após `start-server` — nenhum telemóvel autorizado/ligado visível ao ambiente headless.
`juiz_capture.py` não existe em `.claude/juiz/`. **O fix está pronto mas continua por validar em
device real** — o Danilo deve correr `flutter run` no device (com `--dart-define=GOOGLE_MAPS_API_KEY=...`)
e testar "Continente" e "Lavie". Não aceitei aprovação web, conforme pedido — apenas não tive device.

## Bug 2 — TVDE gastar Bora Tokens (🔴 LISTA VERMELHA — PROPOSTA, NÃO APLICADO)
Toca `bora_tokens` (débito) + reduz o valor cobrado ao cliente (`tvde_ride_charge_cents`) → dinheiro.
Estado verificado:
- Migration fundação `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql` (só colunas
  aditivas `tokens_applied_count` / `tokens_applied_value_cents`) já existe (loop anterior), mas
  **NÃO foi aplicada a prod** — confirmado via SQL read-only: colunas ausentes em `public.tvde_rides`.
- Threading do desconto nas RPCs `tvde_request_ride` / `tvde_finish_ride` + débito real + toggle na UI
  de pagamento TVDE = **por fazer**, é o núcleo 🔴.

**⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (bora_tokens + valor cobrado). Não apliquei nada.**
`CONFIRMACAO NECESSARIA: aplicar migration fundação + threading do desconto de tokens no TVDE
(máx 50%, sem tocar no ganho zero) — só avanço com "vai".`

## Bugs relacionados encontrados
- `place_autocomplete_service_web.dart` usa `dart:html`/`dart:js` deprecados (migrar p/ `package:web`
  + `dart:js_interop`) — dívida técnica, não bloqueia.
