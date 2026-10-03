# Auditoria Estafeta — Completa (vs Uber/Glovo/iFood Driver)
> Data: 2026-04-24
> Âmbito: fluxo do estafeta (driver) da Bora App — registo, login, home, oferta, aceitação, mapa básico, pickup, entrega, ganhos, stacking, cancelamento. Mapa/GPS profundo está coberto por outro agente.
> Ficheiros analisados: `lib/screens/driver_*.dart`, `lib/dispatch/*.dart`, `lib/auth/auth_store.dart`, `lib/services/sound_service.dart`, `lib/services/navigation_service.dart`, `lib/screens/driver_order_action_helper.dart`, `lib/widgets/mandatory_photo_picker.dart`, `supabase/functions/dispatch-engine/index.ts`.

---

## 🔴 BUGS CRÍTICOS

### [BUG-DR-001] `lib/dispatch/driver_capacity_service.dart:21-27` — `canAssignOrder` ignora todas as regras de stacking documentadas
**Descrição:** O método aceita qualquer ordem desde que o driver esteja online e tenha menos de 3 assignments. Não distingue logística (sendPackage / carryGroceries — que NÃO podem ser batched), ordens partner (max 2, mesmo vendor ou ≤800 m), ordens non-partner (max 3, mesmo vendor), nem aplica a regra FIFO ≤200 m mencionada no `CLAUDE.md`. Os parâmetros nomeados (`partnerRadiusMeters`, `partnerMaxOrders`, `nonPartnerMaxOrders`) estão marcados como "Legacy named params kept for API compatibility — no longer used".
**Impacto:** Dispatch atribui ordens incompatíveis (ex.: estafeta com sendPackage activo recebe outra). `shouldPrioritize` continua a usar `vendorName` mas o gating já não é aplicado. Comparado com Glovo/Uber Eats/iFood, isto cria batches impossíveis de cumprir e quebra a SLA.
**Fix:** Restaurar lógica:
```dart
if (!driver.isOnline) return false;
if (order.serviceType == OrderServiceType.sendPackage ||
    order.serviceType == OrderServiceType.carryGroceries) {
  return driver.activeAssignments.isEmpty;
}
final n = driver.activeAssignments.length;
if (order.isPartnerStore) {
  if (n >= 2) return false;
  if (n == 0) return true;
  return driver.activeAssignments.any((a) =>
      a.vendorName == order.vendorName ||
      _distanceMeters(a.pickupLocation, order.pickupLocation) <= 800);
}
if (n >= 3) return false;
if (n == 0) return true;
return driver.activeAssignments.every((a) => a.vendorName == order.vendorName);
```

### [BUG-DR-002] `lib/screens/driver_map_screen.dart:1252` — Código de entrega de 4 dígitos desactivado em produção
**Descrição:** `const bool kRequireDeliveryCode = false;` com comentário "PIN bypass activo para testes". O `_showDeliveryCodeDialog` (linhas 944-1015) existe mas o branch é dead-code (`// ignore: dead_code`).
**Impacto:** Estafeta pode marcar como "entregue" sem validação. Sem prova de entrega. Glovo/Uber Eats/iFood exigem PIN ou foto obrigatória.
**Fix:** Mudar para `true` antes de produção, OU substituir por foto obrigatória (proof of delivery).

### [BUG-DR-003] `lib/screens/driver_login_screen.dart:25-26` — Credenciais hard-coded no controller
**Descrição:** `_emailController = TextEditingController(text: 'driver@bora.app')` e `_passwordController = TextEditingController(text: '123456')`.
**Impacto:** App de produção mostra credenciais demo no login. Risco de segurança e UX. Concorrentes nunca pré-preenchem.
**Fix:** Limpar para `''` em release; só preencher em `kDebugMode`.

### [BUG-DR-004] `lib/screens/driver_earnings_screen.dart:227-274` — Conversão de tokens é race-condition (lost-update)
**Descrição:** O fluxo é: (1) `consume_tokens` RPC, (2) insert em `driver_transactions`, (3) `select balance from driver_balances`, (4) `update balance = current + valorEur`. Não há transação. Duas conversões simultâneas (clique duplo, replays) lêem o mesmo `current` e a 2ª sobrescreve a 1ª.
**Impacto:** Saldo do estafeta pode ficar incorrecto. Tokens consumidos sem crédito de €. Glovo/Uber usam atomic upserts ou RPC server-side.
**Fix:** RPC `convert_tokens_to_balance(p_user_id, p_amount)` que faça consume + balance increment numa transação SQL única.

### [BUG-DR-005] `supabase/functions/dispatch-engine/index.ts` + `lib/screens/driver_home_screen.dart:1573` — Timeout 40 s no cliente vs servidor
**Descrição:** O dialog usa `Duration(seconds: 40)`. Mas o card inline `_DriverOrderAlertCard` (linhas 1910, 1925, 2150) também usa 40 s **clamped**, ignorando o `driverOfferExpiresAt` real do servidor se este for maior. O backend autoritativo está em `dispatch-engine/index.ts` com `OFFER_TIMEOUT_SECONDS`. Se servidor for, por ex., 30 s, o estafeta vê 40 s mas a oferta já expirou aos 30 s no DB.
**Impacto:** Estafeta tenta aceitar oferta já expirada → erro confuso. UX inferior aos concorrentes.
**Fix:** Ler valor único de `driverOfferExpiresAt` e usar somente esse delta como fonte. Eliminar `clamp(0, 40)` rígido.

### [BUG-DR-006] `lib/screens/driver_home_screen.dart:1517-1556` + `1471-1475` — Stacking offer DESCARTA (não fila) ofertas concorrentes
**Descrição:** Comentário explícito linha 1532-1533: *"Second offer is DISCARDED (not queued) — the offers stream will re-emit the pending order after the current dialog closes"*. Em `_handleNewOrders` quando `_isShowingDialog || _currentShowingOrderId != null`, novas ofertas são ignoradas até re-emissão. Se a stream não re-emitir (offer expira no servidor antes do dialog fechar), o estafeta perde a oferta sem ver.
**Impacto:** Ofertas adicionais (estafeta com 1 entrega activa) podem desaparecer silenciosamente. Glovo enfileira ofertas em "stack" visível.
**Fix:** Manter fila local FIFO `_pendingOffers: List<String>` e mostrar a próxima após dismiss.

### [BUG-DR-007] `lib/screens/driver_home_screen.dart:1419-1427` — `rejectAvailableOrder` é local-only sem chamada ao backend
**Descrição:** `_handleRejectOrder` chama `orderStore.rejectAvailableOrder(order)` mas não há prova no código de driver_home de que isso notifique o servidor para acionar a próxima rotação. O comentário de `dispatch-engine/index.ts` diz "call _invokeDispatch when a driver explicitly rejects (fast-path rotation)" — verificar se `rejectAvailableOrder` faz esse invoke.
**Impacto:** Se rejeitar não dispara dispatch fast-path, o cliente espera até o timeout do servidor (atraso ~OFFER_TIMEOUT_SECONDS).
**Fix:** Confirmar em `OrderStore.rejectAvailableOrder` que adiciona o driverId a `tried_driver_ids` e invoca a edge function imediatamente.

### [BUG-DR-008] `lib/screens/driver_signup_screen.dart:144-236` — Signup não valida força da password nem formato IBAN/matrícula
**Descrição:** A validação de password (linha 407) só verifica que `confirmPassword == password`. Não há min length, complexidade. IBAN é apenas trim+upper sem checksum MOD-97. Matrícula é apenas non-empty.
**Impacto:** Drivers conseguem registar com password "1" e IBAN inválido — impossível pagar. Concorrentes validam IBAN com checksum.
**Fix:** Validar min 8 chars + 1 dígito; validar IBAN PT com `IbanValidator`; matrícula via regex `^[A-Z]{2}[-]?\d{2}[-]?[A-Z]{2}$|^\d{2}[-]?\d{2}[-]?[A-Z]{2}$|^...$`.

### [BUG-DR-009] `lib/screens/driver_order_action_helper.dart:32-48` — Pickup e delivery não exigem foto / proof of delivery
**Descrição:** Os `DriverOrderAction` para `driverAccepted → pickedUp`, `pickedUp → onTheWay`, `onTheWay → delivered` chamam directamente `pickUpOrder/startDelivery/finishOrder` sem photo proof.
**Impacto:** Sem evidência de entrega ⇒ disputas insolúveis. iFood, Uber Eats e Glovo todos exigem foto na entrega (especialmente "deixar à porta") OU PIN.
**Fix:** Para `OrderStatus.onTheWay → delivered`, requerer ou foto OU PIN; persistir em `orders.delivery_proof_photo_url`.

### [BUG-DR-010] `lib/screens/driver_signup_screen.dart:225-235` — `is_online: false` + `lat: 38.7223` (Lisboa hard-coded)
**Descrição:** Novo driver é registado em Lisboa fixa. Se o estafeta estiver no Porto, a primeira sessão começa com localização errada até o GPS atualizar. Combinado com `_startIdleLocationTracking` que tem early-return se sem permissão GPS.
**Impacto:** Drivers no Porto inicialmente não recebem ofertas (200 km do dispatch). Concorrentes não pré-povoam coords.
**Fix:** Tornar `lat`/`lng` opcionais no insert, ou popular via `Geolocator.getCurrentPosition()` durante signup.

---

## 🟡 BUGS MÉDIOS

### [BUG-DR-011] `lib/screens/driver_home_screen.dart:1925, 1931` — Countdown clampado a 40 s ignora extensões
Servidor pode estender expiração; clamp `(0, 40)` corta. Mostrar valor real.

### [BUG-DR-012] `lib/screens/driver_home_screen.dart:1485-1495` — Sound restart loop pode ficar agressivo
Se `_soundService.isPlaying == false` por interrupção temporária, restart imediato pode causar duplo-loop em race com `playLoop` já em flight.

### [BUG-DR-013] `lib/screens/driver_login_screen.dart:225` — `loginDriverAsync` retorna `success` mesmo quando session é guest
Linhas 247-258 fazem fallback re-check, mas a 1ª `loginDriverAsync` poderia retornar `true` apenas pelo cache em-memória. UX inconsistente.

### [BUG-DR-014] `lib/screens/driver_home_screen.dart:1522-1528` — Decisão entre card inline vs popup é baseada em `myOrders.isNotEmpty` 
Ok no papel, mas `myOrders` inclui ordens em qualquer estado activo. Se driver tem ordem `delivered` ainda na lista (por race do realtime), a 2ª oferta vai para popup quando devia ir para card.

### [BUG-DR-015] `lib/dispatch/dispatch_engine.dart` — Classe inteira é stub no-op mas continua a ser injetada
Linha 32: "Desativado. Backend controla o dispatch.". Provider em `main.dart` ainda cria via `ProxyProvider2`. Código morto que confunde leitores.

### [BUG-DR-016] `lib/screens/driver_map_screen.dart:1252` — `kRequireDeliveryCode` é `const` local; mudar requer rebuild
Usar feature flag remota (Supabase config table) para activar PIN sem novo APK.

### [BUG-DR-017] `lib/screens/driver_signup_screen.dart:222-235` — `approval_status: 'pending'` é texto livre
Deve ser enum DB (`pending|approved|rejected`); `driver_login_screen.dart:276` faz `?? 'approved'` — se a coluna for NULL o estafeta passa direto. Default-aprovação é uma porta aberta.

### [BUG-DR-018] `lib/auth/auth_store.dart:765-770` — `resetDriverPassword` não verifica que o email pertence a um driver
Pode ser usado para enumerar emails (mesmo fluxo p/ todos os roles). Não é catastrófico mas Glovo restringe.

### [BUG-DR-019] `lib/screens/driver_home_screen.dart:1419` — Reject sem confirmação
Tap acidental rejeita; concorrentes pedem confirmação só para rejeições rápidas (<5 s) ou marcam como timeout.

### [BUG-DR-020] `lib/widgets/mandatory_photo_picker.dart` — Sem compressão antes de upload (apenas `imageQuality: 85`, `maxWidth: 1600`)
Em conexões lentas, upload de >1 MB bloqueia o fluxo. Deve ter retry com backoff.

### [BUG-DR-021] `lib/screens/driver_earnings_screen.dart:248-265` — Após token conversion não há rollback se balance update falhar
Se `consume_tokens` foi feito mas o update do balance falha, tokens perdidos sem €. Sem compensação.

### [BUG-DR-022] `lib/screens/driver_map_screen.dart` — `_FinalizePurchaseDialog` (linha 1834+) aceita qualquer valor
Não compara com `payment_buffer_total` nem alerta divergência >5%. iFood compara e exige justificação.

### [BUG-DR-023] `lib/screens/driver_home_screen.dart:84` — `_startIdleLocationTracking` é fire-and-forget sem retry
Se falhar (permissão), driver fica sem position updates até reabrir app.

### [BUG-DR-024] `lib/screens/driver_home_screen.dart:1568` — `showDialog` no `_showNewOrderDialog` usa `useRootNavigator: true` — bom; mas se driver estiver em DriverMapScreen com keyboard aberto, popup tapa input
Prevenir abertura sobre input activo.

### [BUG-DR-025] `lib/screens/driver_signup_screen.dart:159` — Bicicletas isentas de foto-veículo
Mas Glovo/iFood pedem foto da bike também (provar que é eléctrica/normal). Considerar.

---

## 🟢 BUGS BAIXOS

### [BUG-DR-026] `driver_home_screen.dart:1573` — Timer 40 s declarado dentro do `builder` — recriado em cada rebuild se dialog rebuilda
Mover para `initState` de um wrapper StatefulWidget.

### [BUG-DR-027] `driver_home_screen.dart:25` — Import comentário `package:supabase_flutter/supabase_flutter.dart' show Supabase;` — `show` é boa prática mas import ainda usa dynamic

### [BUG-DR-028] `driver_login_screen.dart:194` — Texto `'Esqueci a palavra-passe'` (sem '?') é inconsistente com cliente que usa 'Esqueceu a palavra-passe?'

### [BUG-DR-029] `driver_home_screen.dart:373-374` — Botão "Teste mode" exposto em production AppBar
`_handleTestMode` deveria ser gated por `kDebugMode`.

### [BUG-DR-030] `driver_earnings_screen.dart:46-115` — 4 queries sequenciais ao Supabase no `_loadBalance`
Use `Future.wait` para paralelizar.

### [BUG-DR-031] `driver_signup_screen.dart:25-26, 38` — `text: '+351'` no phone controller — boa intenção mas usuário pode apagar e ficar inválido

### [BUG-DR-032] `driver_home_screen.dart:1916` — `late final AnimationController _controller` declarado mas nunca usado para animar countdown — só `_secondsLeft`

### [BUG-DR-033] `driver_map_screen.dart:1500` — Strings "Recolha"/"Entrega" hard-coded sem i18n

### [BUG-DR-034] `driver_home_screen.dart:1682` — String literal `'+€3.00 +50 tokens'` em vez de calculo dinâmico
Deve vir de `BusinessRules` para mudar sem rebuild.

### [BUG-DR-035] `driver_home_screen.dart:48` — `SoundService` instanciado per-screen; já existe outro em `NotificationService` (comentário do source confirma)
Redundância; centralizar.

---

## 🔴 MELHORIAS CRÍTICAS

### [MEL-DR-001] Heatmap de zonas com alta procura — vs Uber Eats Driver / iFood
Uber/iFood mostram um heatmap em tempo real ("hotspots"). Bora não tem. Proposta: tile-layer no `DriverMapScreen` quando idle, alimentado por agregação `orders WHERE created_at > now()-30min GROUP BY h3_index`.

### [MEL-DR-002] Aceitar oferta com swipe — vs Glovo Courier
Glovo usa swipe-to-accept (anti tap acidental). Bora usa botão simples. Adicionar `Dismissible`/`SwipeButton` no `_DriverOrderAlertCard`.

### [MEL-DR-003] Pré-visualização de rota com ganho/km e tempo estimado — vs Uber Eats
Uber mostra "€X · Y km · Z min" antes de aceitar. Bora mostra só € e km. Adicionar ETA via `directions_service`.

### [MEL-DR-004] Fila visível de ofertas concorrentes (stacking) — vs Glovo
Glovo mostra "+1 outra oferta a chegar em 30s". Bora descarta (BUG-DR-006). Pintar badge no card e tornar oferta visível pendente.

### [MEL-DR-005] Modo pausa / "última entrega" — vs todos
Estafeta termina o turno: pode pedir "última entrega" e fica offline depois. Bora só tem online/offline binário.

### [MEL-DR-006] Saldo em tempo real + payout instantâneo — vs Uber Instant Pay
Bora exige conversão manual de tokens; sem botão "Sacar agora" (instant payout). Adicionar SEPA-instant integration.

### [MEL-DR-007] Foto obrigatória de proof-of-delivery — vs todos
Resolver BUG-DR-009. Disponibilizar `MandatoryPhotoPicker` para `OrderStatus.delivered` transition.

### [MEL-DR-008] Notificação push fora da app — verificar `NotificationService.saveTokenForDriver` é fire-and-forget
Sem confirmação de que push chega quando app está killed. Glovo/Uber garantem wake-up.

---

## 🟡 MELHORIAS MÉDIAS

### [MEL-DR-009] Ratings recebidos do cliente visíveis — Bora mostra balance/tokens mas não rating médio
Como Uber: estrela média + total entregas. Já existe `auditoria-mapa-estafeta.md`/BUG-018 a referir falta de persistência.

### [MEL-DR-010] Indicador "encomenda preparada / aguardando" no card 
Glovo mostra "comida pronta há 3 min" — melhora urgência.

### [MEL-DR-011] Auto-night-mode no mapa — Uber faz após sunset.

### [MEL-DR-012] "Cancel reason" categorizado quando driver cancela — actualmente `_handleCancelDelivery` não pede razão.

### [MEL-DR-013] Histórico exportável (PDF/CSV) para IRS — Glovo Courier exporta extracto mensal.

### [MEL-DR-014] Agendamento de turnos (booking de slots) — Uber Eats permite reservar slots de alta procura.

### [MEL-DR-015] Atalho rápido para chat com cliente — verificar se `chat_screen` é acessível em 1 tap a partir de `driver_map_screen`.

### [MEL-DR-016] Modo "vou parar 5 min" (intervalo) sem ir offline — concorrentes têm pause/break.

### [MEL-DR-017] Feedback háptico em accept/reject — só vibração na chegada da oferta (linha 1508). Acção devia confirmar.

### [MEL-DR-018] Badge "novo" no histórico quando há transacção desde último login.

---

## 🟢 MELHORIAS BAIXAS

### [MEL-DR-019] Ícones diferenciados por tipo de serviço no card (restaurante/farmácia/super).
### [MEL-DR-020] Mostrar nome do cliente no card antes de aceitar (privacidade: só primeira inicial).
### [MEL-DR-021] Mensagem motivacional ao atingir milestone semanal.
### [MEL-DR-022] Atalho para reportar problema (foto + descrição) directamente do `driver_map_screen`.
### [MEL-DR-023] Animação de ganho ao concluir entrega (€ a flutuar).
### [MEL-DR-024] "Tour" no primeiro login pós-aprovação.
### [MEL-DR-025] Painel "drivers online perto de mim" para sense de comunidade (opt-in).

---

## Pontuação vs concorrentes

| Eixo | Bora | Uber Eats Driver | Glovo Courier | iFood Entregador |
|---|---|---|---|---|
| Onboarding | 6/10 | 9 | 9 | 8 |
| Recepção de ofertas | 7/10 | 10 | 10 | 9 |
| Stacking | 4/10 (BUG-001/006) | 9 | 10 | 8 |
| Pickup/Delivery proof | 3/10 (BUG-002/009) | 10 | 9 | 9 |
| Ganhos / payout | 5/10 (BUG-004) | 10 | 8 | 8 |
| Mapa / navegação | n/a (outro agente) | — | — | — |
| UX micro-detalhes | 6/10 | 9 | 9 | 8 |
| Segurança/auth | 5/10 (BUG-003/017) | 9 | 9 | 9 |

**TOTAL ≈ 50/100** (ex-mapa). Falhas críticas em capacity service, proof-of-delivery e race-condition em tokens puxam fortemente a nota. Estrutura geral (Provider chain, OrderStore, dispatch backend-driven) é sólida.

---

## Recomendação — top 5 a atacar primeiro

1. **BUG-DR-001** — Restaurar lógica de stacking em `DriverCapacityService.canAssignOrder`. Impacto operacional directo.
2. **BUG-DR-002 + BUG-DR-009** — Activar PIN OU exigir foto de proof-of-delivery antes de `delivered`. Bloqueio legal/disputas.
3. **BUG-DR-004** — Atomizar conversão de tokens em RPC SQL. Risco financeiro directo.
4. **BUG-DR-006** — Substituir "discard" por fila FIFO local de ofertas concorrentes.
5. **BUG-DR-003 + BUG-DR-017** — Remover credenciais hard-coded e default-aprovação `?? 'approved'`. Risco de segurança.
