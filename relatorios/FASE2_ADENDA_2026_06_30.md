# FASE 2 — ADENDA · 2026-06-30
> Corrige as 2 premissas erradas: **NÃO é skew** (ambos os telemóveis no mesmo build novo).
> `flutter analyze lib`: **0 errors** (198 issues totais, iguais a antes — zero novos).

## Telas brancas — fluxo exacto reconfirmado
- Tile **"Enviar Encomenda"** → `SendPackageFormScreen` (1ª tela) = branco.
- Tile **"Levar Compras"** → `CarryGroceriesScreen` (botão "Solicitar entrega") → `CarryGroceriesFormScreen` (2ª tela, endereço) = branco.
- Comum às duas brancas: `AppBar`+`QuotePriceFooter`(bottomNav) renderizam, mas o **body** fica vazio.

## O que encontrei (bug REAL, não skew)
Phase-1 (MCP) disse "sem excepção" → não é crash. As duas telas partilham o `QuotePriceFooter` como `bottomNavigationBar`, e o seu `initState` chamava `_refresh()` que faz **`setState()` SÍNCRONO** no branch `pickup/dropoff == null` — exactamente o estado ao ABRIR o form. `setState` durante o mount do `bottomNavigationBar` = **"setState durante build"**. O mesmo padrão em `SendPackageFormScreen._prefillPickupFromGps` (setState síncrono no `initState`). É o **mesmo tipo de bug** do "Serviços tela branca" de 2026-06-09 (build durante build). Não gera linha em `debug_crash_logs` em release → batia certo com "sem excepção".

### Correções (ficheiro:linha)
- **`widgets/quote_price_footer.dart:51`** — `_refresh()` inicial diferido para `addPostFrameCallback` (nunca setState durante build).
- **`screens/send_package_form_screen.dart:40`** — `_prefillPickupFromGps()` diferido para pós-1º-frame.

## Instrumentação para confirmar no device (plano do CEO)
- **`main.dart` ErrorWidget.builder** — em **DEBUG** passa a mostrar o **erro real + stack no ecrã** (em vez de branco). Apanha excepções de build silenciosas. Release mantém a mensagem amigável.
- **`main.dart` +`logScreenBreadcrumb(screen, info)`** — reutiliza o RPC enriquecido do [F] (device/versão/rota/gms/user). NÃO é crash.
- **Breadcrumbs** em `SendPackageForm` e `CarryGroceriesForm`: na **entrada** (`initState`, com `mapsKeyEmpty`) e no **1º build** (`build#1 body a construir`).
  - Se aparecer `build#1` mas a tela continuar branca → é layout/paint (não excepção) — investigo o body.
  - Se aparecer só `initState` e **não** `build#1` → o body lança em build (o ErrorWidget DEBUG mostra o quê).
  - `mapsKeyEmpty=true` revelaria um `--dart-define GOOGLE_MAPS_API_KEY` em falta no build (há histórico de o CI não injetar defines).

## [D] Tile "Bora Motorista" — auth resiliente ✅
`stores/tvde_store.dart:44` `refreshAccess()` endurecido (pista dos `AuthApiException: Invalid Refresh Token`):
- só esconde o tile se `tvde_access` vier **EXPLICITAMENTE false**;
- linha ausente (RLS/sessão transitória) → **mantém** o estado actual;
- em erro de sessão → `auth.refreshSession()` + re-busca **uma vez** (guard anti-recursão) antes de desistir; nunca esconde por erro transitório.

## [E] Ícone/splash — continua BLOQUEADO no asset ⚠️
Reconfirmo: `assets/branding/bora_app_icon.png` é de **2026-05-28** e os mipmaps já foram regenerados a **2026-06-24** a partir dele. Se ambos os telemóveis (mesmo build) mostram o logo antigo, é porque **o asset no repo É o antigo** — o logo NOVO ("moto com capacete/mochila") **nunca foi colocado** em `assets/branding/`. Não posso fabricar o logo nem regenerar para o mesmo resultado. **Ação do Danilo:** larga o PNG novo nessa pasta → eu corro `dart run flutter_launcher_icons` e regenero tudo (mipmap-anydpi-v26 + mdpi→xxxhdpi). Há ainda `bora_logo.png` (também 05-28) — confirma qual é o ícone certo.

## Migration [F]
Sem alteração: `relatorios/MIGRATION_F_crash_logs_contexto_2026_06_30.sql` (aplicar via MCP) — os breadcrumbs usam o mesmo RPC enriquecido.

## Para o Danilo
1. Aplicar a migration [F] (os breadcrumbs precisam das colunas novas para gravar contexto).
2. Build novo + abrir Enviar Encomenda e Levar Compras→endereço → eu leio os breadcrumbs/erro em `debug_crash_logs` via MCP e fecho a causa exacta.
3. Larga o PNG do logo novo → regenero ícones.
