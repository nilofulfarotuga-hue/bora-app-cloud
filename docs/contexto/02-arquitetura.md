# 02 — ARQUITETURA TÉCNICA

## Apps e papéis

Um codebase Flutter, múltiplos papéis: **cliente**, **estafeta/motorista**, **parceiro**, **admin** (painel web PT-BR). Multi-role real: estafeta⇄limpador ligados por `user_id`. O mesmo codebase compila Android (Play) e Web (Cloudflare Pages).

## Modelo de dados — pontos que enganam

- **Restaurantes e mercados são a MESMA tabela `restaurants`**, separados pela coluna `category` (`restaurant`/`supermarket`/`store`/`pharmacy`). Não existe RPC de listagem nem view — o app cliente lê a tabela DIRETO (RLS `restaurants_public_read`: `approval_status='approved' OR is_admin`); o filtro por secção é feito no Flutter.
- **`restaurants.extra_categories text[]`**: uma loja aparece na secção S se `category=S` OU `S = ANY(extra_categories)`. Mesma loja, mesmo catálogo, mesmo painel — só visibilidade em mais secções. Helper Flutter: `belongsTo(secção)` em `lib/utils/business_mapper.dart` + router `lib/utils/business_opener.dart` (abre sempre com o layout da categoria PRINCIPAL).
- **Serviços vivem em `service_providers`** (NÃO em `restaurants`): barbearias, salões. Colunas de perfil rico: `about_text`, `gallery_urls jsonb`, `social_instagram`, `social_facebook`.
- Identidade admin via `app_metadata.role` no JWT (nunca user metadata); trigger `protect-admin-app-role` ativo.

## Backend Supabase

- Postgres + RLS em tudo que importa; Edge Functions pro que precisa de segredo/Stripe; `pg_cron` + `pg_net` pra dispatch e manutenção; Realtime pra tracking; Storage pra assets (`restaurant-assets/{id}/...`; buckets `receipts` e `order-photos` são PRIVADOS).
- Motor de dispatch delivery: Edge Function + Haversine + cron. TVDE: `tvde_dispatch_sweep` a cada 15s, TTL de oferta, rotação de motoristas.
- Fluxo de pagamento delivery: draft (`payment_drafts`) → paga → webhook cria a ordem. (TVDE foi corrigido pra nascer `aguarda_pagamento` — ver cap. 04.)
- Observabilidade: tabela `e2e_log` (prova real de execução de testes) + `orders` — SELECT é a única prova aceitável.

## CI/CD e deploy

- **`build_android.yml`**: em todo push na `autonomous-night-2026-04-29` builda AAB, auto-incrementa versionCode (commit `"ci: bump versionCode to N [skip ci]"`) e publica DIRETO no track fechado **alpha** do Play. `codemagic.yaml` é legado — não usar.
- **`build_web_deploy.yml`**: mesmo gatilho, builda Flutter Web e publica no Cloudflare Pages (bora-app-web.pages.dev). Token `CLOUDFLARE_API_TOKEN` no repo.
- Ambos têm `paths-ignore` de `**.md` e `.claude/**` — MAS avaliado sobre TODOS os commits do push (commit .md "dá boleia" a código pendente). `dart.yml` só em main; e2e-web só manual.
- Segredos: `DART_DEFINES_FILE_B64`; keystore alias `bora-app` (`bora-app-release.jks`); service account do Play reaproveitada do Codemagic.
- Espera ~10–15 min pós-push pro build aparecer no Play Internal Testing.
- Fallback web manual: `buscar-build-web.sh` + `deploy-web.sh` (o PC 4GB NÃO compila web local — OOM).
- Git no PC do Danilo: SSH quebrado (Permission denied publickey) — usar **HTTPS + credential.helper=manager + `pull --rebase --autostash`**, e SEMPRE confirmar que o commit chegou no GitHub.

## Sites e assets

- Repo público `nilofulfarotuga-hue/bora-site` (Cloudflare Pages → bora-site.pages.dev). Assets reutilizáveis em `assets/img/`: `bora_logo.png`, `apple-touch-icon.png`, `qr-playstore.png`, `google-play-badge.png`, `og-image.png`, `cat_*.png`. Clonável por HTTPS sem auth.
- Mini-sites de parceiros: HTML self-contained (imagens base64), publicados via `wrangler pages deploy` com o token de `bora-site/.env`, subdomínio `.pages.dev`.
- Link de teste do Play (opt-in universal): `https://play.google.com/apps/testing/pt.boraapp.bora` — é ESTE que instala; o `/store/apps/details` não abre pro público durante teste fechado.

## Ferramentas do ecossistema

- Claude Code CLI com plugin **Context Mode (CTX)** — `/ctx doctor` e `/ctx stats` no fim de sessões pesadas.
- MCPs disponíveis (Claude.ai): Supabase, Stripe, Gmail, Google Drive, Canva, Glovo, Uber, Uber Eats, Córtex Bora.
- `juiz_capture.py` pra prova visual (checa `adb devices` sozinho — celular do Danilo por USB com USB Debugging é usado automático).
