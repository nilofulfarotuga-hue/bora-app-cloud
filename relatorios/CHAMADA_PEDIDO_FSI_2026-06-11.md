# Chamada de pedido estilo Uber — USE_FULL_SCREEN_INTENT (Parte 2)
**Data:** 2026-06-11 · **Sessão dedicada** ao bug dos 10 dias (ecrã bloqueado/app morta não acorda)
**Modo:** PROTECÇÃO TOTAL · só mexer com certeza comprovada

---

## 1. Root cause (comprovado por documentação oficial + código)

A partir do Android 14 (A36 do Danilo = Android 16), `USE_FULL_SCREEN_INTENT` é
**special app access**: concedida por defeito só a apps de chamadas/alarmes. A
**Play Store revoga-a na instalação** para todas as outras — e os builds da Bora
vêm da Play (Testes Internos). Sem ela, o `fullScreenIntent` é **ignorado em
silêncio**: a notificação aparece normal na barra, sem acordar o ecrã. Sintoma
= exatamente o da Bora.

**Evidência adicional desta sessão** (source do plugin no pub cache,
`flutter_local_notifications-17.2.4/.../FlutterLocalNotificationsPlugin.java:1861-1889,2226-2248`):
- API oficial de verificação: `NotificationManager.canUseFullScreenIntent()` (API 34+)
- O `requestFullScreenIntentPermission()` do plugin abre
  `Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` e **devolve o estado real
  no regresso** (`onActivityResult → canUseFullScreenIntent()`). Ou seja, o
  método era fiável — os bugs estavam no NOSSO gate (ver §3).

### Porque é que o código "certo" falhava há 10 dias
O caminho bloqueado/morto já estava correto no código:
- Manifest: `USE_FULL_SCREEN_INTENT` + `TURN_SCREEN_ON` declarados ✓
- `MainActivity`: `showWhenLocked="true"` + `turnScreenOn="true"` ✓
- FCM BG handler posta notif rica com `fullScreenIntent: true` (canal v3, FLAG_INSISTENT) ✓
- App morta: FGS deteta main isolate morto (`bora_main_alive_ts` stale) →
  `postWakeActivityNotification` (FSI) — **nunca** `startActivity` direto de background ✓

Com a permissão revogada pela Play, tudo isto degrada para notificação normal.

## 2. Diagnóstico no device (passo 1 do plano) — ⚠️ PENDENTE

O A36 **não estava ligado por adb** durante a sessão (3 tentativas). O
diagnóstico live fica registado como dúvida aberta e é o **primeiro passo** do
teste abaixo. Duas formas de confirmar:

**A. Via adb (10 segundos):**
```
adb shell appops get pt.boraapp.bora USE_FULL_SCREEN_INTENT
```
- `deny`/`ignore` → root cause confirmado a 100%
- `allow`/`default` com o sintoma presente → reportar antes de concluir

**B. Sem adb (novo nesta sessão):** Perfil do estafeta → **Permissões de
pedidos** → linha "Ecrã inteiro (telemóvel bloqueado)" mostra ✅/❌.
Logs: `adb logcat | grep BORA-FSI` mostra `canUseFullScreenIntent=...` no
gate Online, no check silencioso e no snapshot do ecrã.

> Nota: se o Danilo alguma vez concedeu manualmente via o diálogo do gate
> (existe desde 2026-05-22), o estado pode ser `allow`. Mas o gate antigo tinha
> 3 bugs (§3) que permitiam passar sem conceder — e uma reinstalação/clear
> data volta a revogar.

## 3. O que mudou (5 ficheiros, cirúrgico)

### 3.1 `android/.../MainActivity.kt`
Novo método no bridge nativo existente (`pt.boraapp.bora/native`):
`canUseFullScreenIntent` → `NotificationManager.canUseFullScreenIntent()` em
API 34+; `true` em <14. Só leitura de estado; zero efeitos secundários.

### 3.2 `lib/services/permission_gate_service.dart`
Três bugs corrigidos no 4º passo do gate (FSI):
1. **Nunca verificava o estado** antes de pedir → agora `checkFullScreenIntentAllowed()`
   primeiro; concedida = sem diálogo nenhum (acaba o diálogo repetido a cada Online).
2. **`catch → return true`** silencioso mantém-se SÓ para erro real do plugin
   (degradação graciosa: heads-up continua), mas agora com log `[BORA-FSI]` e
   re-check pela bridge após settings (`after ?? granted ?? true`).
3. **`areAllGranted()` não incluía FSI** → revogação da Play era invisível.
   Agora inclui (null=indeterminado não chumba). O banner "CORRIGIR" do
   driver_home passa a disparar quando a Play revoga.
Novo: `snapshot()` devolve o estado das 4 permissões para o ecrã novo.

### 3.3 `lib/screens/driver_permissions_screen.dart` (NOVO)
Estado ✅/❌ das 4 permissões (ecrã inteiro, notificações, overlay, bateria)
com botão "Activar" individual; re-verifica ao voltar das Definições
(observer `resumed`). FSI usa o `requestFullScreenIntentPermission()` do
plugin (comportamento verificado no source).

### 3.4 `lib/screens/profile_screen.dart`
Tile "Permissões de pedidos" (só `role == driver`) → abre o ecrã novo.

### 3.5 `lib/services/notification_service.dart` (decisão registada do Danilo)
Botões **Aceitar/Recusar** da notificação de oferta do estafeta (2 sites: notif
rica do BG handler + `postWakeActivityNotification`):
- `showsUserInterface: false → true` (abre a app; nunca headless)
- `cancelNotification: true → false` (notif+som só morrem quando a oferta é
  tratada via `cancelDriverOfferNotification`)
- `_onLocalNotifTap`: accept/reject deixam de delegar ao handler HTTP headless;
  abrem a app — o rehydrate (`pending_offer`) + OrderStore apresentam o cartão.
- Botões do PARCEIRO e chat: **inalterados** (fora do scope).

## 4. O que NÃO mudou (e porquê)
- Caminho BG do gate (`_showOverlay`/flutter_overlay_window): morto-em-silêncio
  conhecido, mas removê-lo não está no plano → intocado.
- Edge Functions, dispatch, RPCs, pricing: zero alterações.
- `onBackgroundNotificationAction`: mantém handling antigo de accept/reject
  (defensivo p/ notifs postadas por processos pré-update) + parceiro.
- versionCode: NÃO tocado (CI auto-bumpa — regra 2026-06-09).

## 5. Play Console — PASSO MANUAL DO DANILO (obrigatório)
A Google exige **declaração do uso de USE_FULL_SCREEN_INTENT** na Play Console
(Conteúdo da app → declarações de permissões sensíveis). Declarar que a app é
de **entregas com despacho urgente ao estafeta** (time-sensitive). Sem isto a
Play pode rejeitar updates futuros. (A declaração NÃO devolve o auto-grant —
o pedido manual ao estafeta continua a ser o caminho.)

## 6. TESTE (3 cenários) — para o Danilo reproduzir com build ≥278
**Pré-requisitos:** instalar build novo; Perfil → Permissões de pedidos →
TODAS ✅ (em especial "Ecrã inteiro"); estafeta Online; som ligado.
**Regra operacional:** reset COMPLETO da order de teste antes de cada cenário
(status='callingDriver', assigned_driver_id=NULL, oferta fresca) — ordem
corrupta foi a falsa pista do TESTE A de maio.

1. **Background desbloqueado:** Bora em background (home do Android) → criar
   pedido de teste → notif rica com som em loop; tap no corpo OU em
   Aceitar/Recusar ABRE a app no cartão laranja. ✅ = decisão feita na app.
2. **Ecrã bloqueado:** bloquear o telemóvel → criar pedido → **<5s o ecrã
   ACENDE** com a app por cima do bloqueio (MainActivity showWhenLocked) +
   som alto em loop → Aceitar/Recusar funcionais no cartão.
3. **App morta:** swipe-kill da Bora (FGS continua) → criar pedido → FGS
   deteta main morto → notif FSI acorda o ecrã → app boota → rehydrate
   apresenta o cartão (<5s, oferta TTL 40s).

**Se o cenário 2/3 falhar COM a permissão ✅:** correr
`adb logcat | grep -E "BORA-OFFER|BORA-FSI|FGS_AUTO_REVIVE"` e guardar — não
voltar a mexer às cegas.

## 6.5 🚨 REGRESSÃO da Parte 1 corrigida (descoberta nesta sessão)

O último push da Parte 1 (commit "docs(relatorios): sessao Parte 1 device-fixes
M-A..M-E…") deixou **2 erros de compilação** em `restaurant_menu_screen.dart`
(código M-C, página Glovo):
1. `listEquals` sem import (`flutter/foundation.dart`) — linha 910
2. `model.id` em campo nullable sem promoção — linha 701

**Consequência:** o run do CI 27326861404 (2026-06-11 05:52) **FALHOU em 7m07s**
(builds OK demoram 27-52 min) → **o build ≥277 esperado pela Parte 1 nunca
chegou ao Play**. O último build bom é o do run de 2026-06-10 19:14.

**Fix nesta sessão:** import `foundation.dart show listEquals` + `model!.id`
sob o guard existente. `flutter analyze` = **ZERO erros** após o fix. O push
desta sessão produz o primeiro build com Parte 1 + Parte 2 juntas.

## 7. Validação da sessão
- `flutter analyze`: 0 **erros**; issues pré-existentes (infos/warnings) noutros
  ficheiros, 0 nos tocados — ver secção no fim do output da sessão.
- Kotlin: validado por build local (ver resultado no resumo da sessão).
- Diagnóstico live (passo 1): PENDENTE device — gate de conclusão do §2.
- Commits + push: ver hash no resumo da sessão.
