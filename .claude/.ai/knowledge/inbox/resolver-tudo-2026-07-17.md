# RESOLVER TUDO — 2026-07-17 (sessão interativa MODO PROTECÇÃO TOTAL)

Ordem A→B→C→D→E do Danilo. Autorização da Parte B **verificada na base ANTES de agir**
(as 4 propostas `aprovada_danilo` + os 2 `admin_audit_log` existem e os timestamps batem).
Nada enfraqueceu nenhuma trava: `zona_vermelha()`, classificador, Lista Vermelha, Juiz e
`zonas_diff.py` ficaram INTACTOS.

## Tabela resumo

| Parte | Estado | Prova (commit + output real) |
|---|---|---|
| **A** Push admin persistente | ✅ FEITO (DB provado live; Flutter code-complete; Edge v13 deployada) | commit `61b60cb` + migration `admin_persistent_push_pending_actions` + Edge Fn v13 |
| **B** Carteiro respeita autorização | ✅ CÓDIGO FEITO + 3 casos provados (deploy VPS + libertar ordens = aguarda "vai") | commit `8076bff` + migration `cortex_auth_verify_helpers_partB` |
| **C** 4 bugs do app | ✅ Bug 2 corrigido; Bugs 1/3/4 diagnosticados (1=dado, 3/4=já corrigidos, falta build) | commit `bf45404` |
| **D** `tvde_mark_noshow` | ✅ PROPOSTA PRONTA — 🔴 dinheiro, NÃO aplicada (aguarda "vai") | commit `5e7c1c8` (ficheiro proposta) |
| **E** Google Play | ✅ DIAGNOSTICADO (só) — targetSdk cumpre; textos abaixo | sem commit de código (só diagnóstico) |

Commits desta sessão (branch `autonomous-night-2026-04-29`, **locais — ver "Push" no fim**):
`61b60cb` (A) · `8076bff` (B) · `5e7c1c8` (D) · `bf45404` (C).

---

## PARTE A — Push persistente para o admin ✅

**O padrão persistente do estafeta** vive em `lib/services/notification_service.dart`, canal
`bora_orders_urgent_v3` (`Importance.max`) com `fullScreenIntent:true, ongoing:true,
autoCancel:false, onlyAlertOnce:false, additionalFlags:[4]` (FLAG_INSISTENT). O push do admin
usa o canal `bora_admin_urgent` (a Edge Fn `notify-admin-urgent` já o pedia).

**Feito:**
1. **DB (aplicado em prod + PROVADO):** helper `notify_admin_urgent_push` insere linha
   `severity=high` em `admin_notifications` (o badge do sino + o inbox já existiam) **e** dispara
   `notify-admin-urgent` (modo generic) via pg_net, best-effort (falha não quebra a DML). 4 triggers
   novos + o TVDE reaproveitado (sem duplicar). Escolha registada: **sem bridge global** em
   `admin_notifications` (havia 267 inserts `high` como `robot_b_suggestion` que já empurram —
   bridge global duplicaria).
2. **Edge Fn `notify-admin-urgent` v13:** push generic agora `sticky=true` + `PRIORITY_MAX`
   (fica no ecrã até agir). Crosstalk intacto. `verify_jwt=true` preservado.
3. **Flutter:** canal `bora_admin_urgent` (`Importance.max`) criado no arranque
   (`main.dart _setupForegroundAndUrgentChannel`); 5 rotas nomeadas novas; `admin_push_service`
   trata `type=admin_generic` → `data['route']`; o toque no inbox agora navega para o `deep_link`.
   Registo do token admin JÁ existia (`admin_push_service.registerForAdmin`), badge de não-lidas
   JÁ existia. `dart analyze` dos ficheiros tocados = 0 issues.

**PROVA (output literal):** inseri teste nas 5 origens → 5 linhas criadas em `admin_notifications`,
todas `severity=high` com o deep_link certo:
```
cortex_red_proposal        high  /admin/robot
driver_application_pending  high  /admin/drivers/approval
partner_application_pending high  /admin/partners/pending
cleaner_application_pending high  /admin/cleaning/cleaners
tvde_driver_application_pending high /admin/tvde/access-requests
```
`net._http_response`: as 5 chamadas → **status 200**, cada uma `push_attempted:2, push_success:1,
push_cleaned:1`. Logs da Edge Fn: `POST | 200 | .../notify-admin-urgent` (×3+ às 10:14:26).
Linhas de teste **apagadas** no fim (confirmado: notif=0, cortex=0, driver=0, rest=0, cleaner=0).

**Device:** `adb devices` vazio → **não provado no ecrã** (honesto). A persistência (canal max +
sticky) está no código/servidor mas não foi vista num telemóvel real.

**Admin panel:** já tinha inbox + badge; só liguei o `deep_link` à navegação. Sem ecrã novo.

---

## PARTE B — Carteiro respeita autorização humana verificável ✅ (código)

Mudou **só** isto: o carteiro deixa de re-gatilhar T3 numa ordem que o Danilo **já** autorizou na
Central e é **verificável na base**. `zona_vermelha()`/classificador/Lista Vermelha/Juiz/
`zonas_diff.py` **intactos** — toda ordem de dinheiro sem autorização real continua a parar.

**Feito:**
- **DB (aplicado, inerte até deploy):** 2 RPCs read-only — `cortex_verify_audit_id(uuid)` (o
  carteiro re-verifica contra `admin_audit_log`, **nunca** confia no ficheiro) e
  `cortex_get_auth_for_pid(text)` (o sync lê a autorização autoritativa).
- **sync:** `fetch_auth()` grava `autorizado_por_admin/autorizado_em/audit_id` no frontmatter,
  **só da base**. **carteiro:** `audit_id_valido()` + gate T3 salta só se o `audit_id` existir mesmo
  na base. **BARREIRA** documentada no código: só o passo 2 do sync escreve esses campos.

**PROVA 3 casos (harness local + RPC real contra a base):**
```
CASO (a) money SEM campo autorizado    -> TRAVA (zona_vermelha)
CASO (b) money + audit_id INEXISTENTE  -> TRAVA (zona_vermelha)
CASO (c) money + audit_id REAL (7398)  -> CORRE
```
RPC real: `cortex_verify_audit_id('35040d36…')=true`, `('00000000…')=false`;
`cortex_get_auth_for_pid('prop-df32746d')` devolve o bundle real (admin `c9fccf85…`, audit
`35040d36…`). `bash -n` + `py_compile` = OK.

**PENDENTE (aguarda "vai" — é o portão do dinheiro a ir LIVE):**
1. Deploy dos 2 scripts no VPS (o commit **não** auto-deploya — deploy é passo separado do git).
2. Libertar/fechar as ordens 370c (`prop-5a437bbf`, audit `8daec8c4…`) e 7495 (`prop-633618b5`,
   audit `aa7bfe5d…`), e marcar a 7398 `respondida`. São ordens de dinheiro na orquestração viva.

---

## PARTE C — 4 bugs ✅

**BUG 1 — km errada.** Código está **correto** (`order_eta_service.dart` haversine, null-guarded;
**zero** `2.0`/`0.0` hardcoded no `lib`). No código atual as cadeias têm coords reais e distintas
(SELECT: Auchan/Continente/BK/McDonald's… todas diferentes) → distâncias reais 0.1–2.4 km; o
"2.0 fixo" reportado é do **APK antigo**. Os **locais** (pizza danilo/pizzaria Paulista) partilham
`40.5402657,-7.2673597` = o centróide default do cliente → 0.0 km (dado, não código).
`Pizzaria Teste Noite` tem lng `-6.9136762` (30 km fora da Guarda) = dado partido.
→ **Fix real = (1) admin poder editar lat/lng do restaurante; (2) cliente usar GPS real.**
**Admin panel: SIM** — hoje `admin_partner_detail_screen` mostra o endereço mas **não** edita
coords. Recomendo campo lat/lng no detalhe do parceiro (não construído aqui — ver "decisão").

**BUG 2 — fluxo 3 opções ✅ CORRIGIDO.** Causa: `showOptions = isPartner && (reservas||takeaway)`
saltava o ecrã de opções para parceiros sem esses flags. Agora `showOptions = isPartner` → todo
parceiro entra pelo `RestaurantOptionsScreen`, que já mostra só os serviços activados. `dart analyze`
= 0 issues. **Admin panel:** os flags já se editam no dashboard do parceiro e no admin.

**BUG 3 — toggles do parceiro ✅ JÁ CORRIGIDO no código.** `restaurant_store.dart` persiste
(`.update({reservations_enabled/takeaway_enabled/curbside_enabled})`) e relê no load
(`_restaurantFromRecord`), com revert-on-failure. RLS `restaurants_update_own` =
`(user_ = auth.uid()) OR is_admin()` → o parceiro pode gravar o próprio. **Falta só build.**
**Admin panel:** não precisa (admin já consegue como workaround).

**BUG 4 — autocomplete Guarda ✅ JÁ CORRIGIDO no código** (os 3 sub-bugs): retry `"<q> Guarda"`
+ merge, bias Guarda `components=country:pt` (`place_autocomplete_service_io.dart`); campo sobe com
`ensureVisible` + sugestões para baixo (`address_autocomplete_field.dart`); dropdown da parada TVDE
com `useSafeArea` + altura dinâmica (`tvde_ride_tracking_screen.dart`). **Falta só build.**
**Admin panel:** não precisa.

---

## PARTE D — `tvde_mark_noshow` 🔴 PROPOSTA (NÃO aplicada)

Confirmado por SQL: a RPC **não existe**; `tvde_cancel_ride` aceita `p_actor='no_show'` mas cobra
**€0** (o buraco). Settings `tvde_noshow_driver_fee_cents=350` e `tvde_noshow_wait_minutes=5`
**já existem**. Escrevi a proposta completa em
**`.claude/.ai/knowledge/inbox/proposta-tvde-mark-noshow-2026-07-17.sql`**:
- `tvde_mark_noshow(ride)`: motorista marca após 5 min (`arrived_at`); cobra 100% da tarifa;
  estafeta €3,50 fixo; Bora fica com a diferença; sem reembolso; idempotente; grava `admin_audit_log`.
- `tvde_admin_revert_noshow` + `admin_list_tvde_noshows` + spec do ecrã admin `/admin/tvde/noshows`.

⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico (responde "vai").**

---

## PARTE E — Google Play (só diagnóstico) ✅

**1. Target API level — CUMPRE.** O CI (`build_android.yml`) usa **Flutter 3.41.2** (pinado).
`android/app/build.gradle.kts` faz `targetSdk = flutter.targetSdkVersion`; no Flutter 3.41.2
(`FlutterExtension.kt:34`) isso é **36** (Android 16), `compileSdk=36`. O mínimo do Google Play a
partir de 31/08/2026 é API **35** → **targetSdk 36 cumpre com folga**. Risco único: se a versão do
Flutter no CI descer, o targetSdk desce junto. Recomendação (não alterei nada): manter o pin
3.41.2; opcionalmente fixar `targetSdk=35` explícito no `build.gradle.kts` como cinto-e-suspensórios.

**2. Verificação de developer (só no Play Console, login do Danilo):**
1. Play Console → **Configurações → Detalhes da conta do programador**.
2. Confirmar tipo de conta (Pessoal ou Organização) e o **nome legal + morada** exatos.
3. Verificar **telefone** e **email** (recebe código).
4. Se for Organização: fornecer **número D-U-N-S**; se Pessoal: documento de identidade.
5. Concluir antes do prazo que o Console indicar (banner "Verifique a sua identidade").
(Só dá para ver/fazer dentro do Console com o login `boraappbora@gmail.com` — não adivinho o estado.)

**3. Data Safety / localização — o Manifest pede:** `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`. **Texto EXATO a declarar** (secção
Segurança dos dados → Localização):
> **Localização — Localização aproximada + Localização precisa.**
> *Recolhida:* Sim. *Partilhada com terceiros:* Sim (com o estafeta/motorista para a entrega/corrida,
> e Google Maps para rotas). *Finalidade:* Funcionalidade da app (mostrar pedidos próximos, calcular
> entrega, rastrear a corrida/entrega em tempo real). *Obrigatória:* Sim para pedir/entregar.
> *Em segundo plano:* Sim — o estafeta/motorista partilha localização em background durante uma
> entrega/corrida ativa (foreground service). *Encriptada em trânsito:* Sim. *Pode pedir remoção:* Sim.

---

## O que ficou por fazer e porquê
- **Push A no ecrã do telemóvel:** sem device por USB (`adb devices` vazio) — não simulei o visual.
- **Deploy live da Parte B + libertar ordens 370c/7495/7398:** é o portão do dinheiro a entrar em
  produção → espera "vai" (Lista Vermelha, em caso de dúvida trava).
- **Bug 1 (editar coords no admin):** é feature nova de admin (UI+RPC), não a construí nesta sessão
  para não estourar o âmbito; deixei o ponto de fix e a recomendação.
- **git push:** bloqueado (ver abaixo) — commits estão locais.

## Precisa de decisão do Danilo (2 linhas cada)
- **Parte D (tvde_mark_noshow):** aplico a proposta SQL + construo o ecrã admin? Cobra cliente e
  paga estafeta → responde **"vai"**.
- **Parte B live:** faço o deploy dos 2 scripts no VPS e fecho 370c/7495/7398 com a autorização real?
  É o portão do dinheiro a ir live → responde **"vai"**.
- **Bug 1 admin coords:** queres que eu adicione edição de lat/lng no detalhe do parceiro no admin?

## Push (importante)
O remote é SSH (`git@github.com:nilofulfarotuga-hue/bora-app-cloud.git`) e esta shell só tem a chave
da ponte VPS (`id_ed25519_vps`), **não** a deploy key do GitHub → `git push` dá `Permission denied
(publickey)`. Consistente com o padrão conhecido ("só committar local; o executor/loop empurra").
Os 4 commits (`61b60cb`, `8076bff`, `bf45404`, `5e7c1c8`) estão **locais** na branch. Para publicar,
corre no teu terminal: `! git push origin autonomous-night-2026-04-29` (ou deixa o executor com a
deploy key empurrar). ⚠️ o push dispara build de produção.

---

# FASE 2 — "Sim a tudo" (aplicado LIVE, 2026-07-17)

Depois do "Sim a tudo" do Danilo (interativo), com re-verificação por SQL:

| Item | Estado | Prova |
|---|---|---|
| 1. PARTE D aplicada + ecrã admin | ✅ LIVE | RPCs `tvde_mark_noshow`/`tvde_admin_revert_noshow`/`admin_list_tvde_noshows` aplicadas (existem por SQL); ecrã `AdminTvdeNoShowsScreen` + rota `/admin/tvde/noshows` (commit) |
| 2. PARTE B live | ✅ LIVE + PROVADO | auth re-verificada (4 props aprovada_danilo, 2 audits); scripts deployados no VPS (backup+atómico+`bash -n` OK); teste ao vivo `audit real→true / falso→false`; ordens 370c/7495/7398/2e9f → `respondida` (commit 8076bff) |
| 3. BUG 1 admin coords | ✅ | RPC `admin_update_partner_coords` aplicada + cartão de coords no `admin_partner_detail_screen` (commit) |
| 4. PUSH HTTPS | ✅ | `git fetch`+`rebase --autostash`+`push` HTTPS → `eaab0cc..3fe2387` (exit 0), sem --force |
| 5. CI | ✅ causa REAL corrigida | log real: faltava `lib/screens/reset_password_screen.dart` (main.dart importava-o); NÃO era o race do versionCode. Ficheiro committado; build seguinte a confirmar |
| 6. Fila Córtex | ✅ | f70e→respondida (vigia+ponte, fac12c9/d82f820/64fe36b/331db13); e2c8→respondida (Fase 4, 318a81f); **f8cc OAuth já LIVE** — container `cortex-mcp` corre `ACCESS_TTL=2592000` (30d, era 1h) + `CORTEX_TOKEN` estático; health: com token 200 / sem 401; commit 0e89757 → respondida |

**Diagnóstico f8cc (para o Danilo, passos numerados):**
1. Causa do "cai de hora em hora": o OAuth do cortex-mcp emitia `access_token` com `expires_in=3600` (1h). ✅ já corrigido para `2592000` (30d) no `server.mjs` (commit 0e89757) e **já a correr** no container (processo confirmado).
2. Token estático (alternativa que nunca expira): o código lê `CORTEX_TOKEN` (server.mjs:14) e o container **já tem** essa env setada (via deploy.sh). Health-check com esse token = HTTP 200.
3. Para ti não teres de reconectar: o teu conector "Córtex Bora" no claude.ai agora recebe tokens OAuth de **30 dias** — deixa de cair de hora em hora. Se algum dia quiseres zero-expiração para clientes programáticos, usa o `CORTEX_TOKEN` como `Authorization: Bearer` (fica só na VPS, não o exponho aqui).
4. Nada a fazer da tua parte além de, se ainda estiver a cair, desconectar+reconectar UMA última vez para apanhar um token novo de 30d.

Commits FASE 2 (todos em origin via HTTPS): Parte B `55bd28f`, Parte D proposta `5e21c4f`,
Parte C `05b7744`, relatório `d17a2ba`, CI-fix `4f09a6c`, ecrãs admin `3fe2387` (+ Parte D RPC/Bug1
RPC aplicadas direto na base via MCP).
