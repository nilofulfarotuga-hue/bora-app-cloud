# TVDE — FECHO FINAL V2 (sessão única: work_mode + dual-driver + fila back-to-back + varredura)

> 2026-07-02 · CEO-AI / Claude Code (Fable 5) · branch `autonomous-night-2026-04-29`
> Sessão anterior: c1d20c2 (3 P0 + P1 principais). Esta sessão fecha o vertical.
> Gates finais: `flutter analyze` **0 erros** · Juiz anti-trapaça **CLEAN** (9 ficheiros,
> zero batota) · Supabase advisors **0 ERROR** (357 WARN/45 INFO = baseline pré-existente).

---

## 1. PARTE 1 — WORK_MODE NO DISPATCH DE ENTREGAS ✅ (autorizado pelo Danilo)

`dispatch-engine` **v58 deployed** (ACTIVE, `verify_jwt=false` preservado; v57 em prod
era byte-idêntica ao repo — sem drift, sem clobber). Diff mínimo: **17 linhas funcionais**
(+7 de cabeçalho, +1 log de versão). Ofertas, timeouts, rotação, claim TTL e pricing intactos.

### Diff EXATO da dispatch-engine (funcional)
```diff
@@ dispatchOrder (query de cycle-reset) @@
     let q = supabase.from('drivers').select('id').eq('is_online', true)
-    if (reqCar) q = q.eq('vehicle_type', 'car')
+      .or('work_mode.is.null,work_mode.neq.rides_only')
+    if (reqCar) q = q.in('vehicle_type', ['car', 'carro_passageiros'])

@@ findNextDriver (seleção de elegíveis) @@
-  let q = supabase.from('drivers').select('id,lat,lng,vehicle_type').eq('is_online', true)
+  // work_mode: 'rides_only' nunca recebe entregas (default 'everything' — zero regressão)
+  let q = supabase.from('drivers').select('id,user_id,lat,lng,vehicle_type').eq('is_online', true)
+    .or('work_mode.is.null,work_mode.neq.rides_only')
   ...
-  let elig = reqCar ? drivers.filter((d: any) => d.vehicle_type === 'car') : drivers
+  // dual-driver: carro de passageiros conta como carro
+  let elig = reqCar ? drivers.filter((d: any) => d.vehicle_type === 'car' || d.vehicle_type === 'carro_passageiros') : drivers
+  if (!elig.length) return null
+  // dual-driver: corrida TVDE ativa → sem ofertas de entrega (tvde_rides.driver_id = user_id)
+  const { data: busyTvde } = await supabase.from('tvde_rides').select('driver_id')
+    .in('status', ['motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'])
+    .not('driver_id', 'is', null)
+  const busyUids = new Set((busyTvde ?? []).map((r: any) => r.driver_id))
+  elig = elig.filter((d: any) => !d.user_id || !busyUids.has(d.user_id))
```
(+ `v57 INVOKED` → `v58 INVOKED` no log, para verificação em prod.)

**Gate:** invocação real da v58 → `{ok:true}`; simulação SQL sobre dados reais confirma a
semântica (`everything` passa; `rides_only` excluído por `work_mode <> 'rides_only'`;
`carro_passageiros` online entra no pool; ocupado em corrida sai).

⚠️ **NOTA IMPORTANTE — a Trava não disparou nesta sessão.** Os hooks/deny vivem em
`bora_app/.claude/`, mas a sessão corre da pasta-mãe `projetosflutter/` → a proteção
determinística **não estava ativa** (a edição e o deploy da engine passaram sem bloqueio).
A alteração estava explicitamente autorizada por ti, mas isto é uma **lacuna real da Trava**:
qualquer sessão lançada da pasta-mãe contorna os hooks. Sugestão: replicar
`settings.json` (deny+hooks) em `projetosflutter/.claude/` ou lançar sessões sempre de `bora_app/`.

## 2. PARTE 2 — DUAL-DRIVER ✅

**Regra implementada:** `carro_passageiros` + toggle `work_mode`:
`rides_only` → só corridas · `everything` (default) → corridas + entregas.
Pagamento de entrega = tabela de estafeta normal (nenhuma fórmula tocada).

- **a) Elegibilidade** — engine v58 (acima): `carro_passageiros` entra no matching de
  entregas (e conta como carro nos serviços que exigem carro).
- **b) Exclusão de ocupado (2 sentidos)** —
  corrida ativa → sem entregas (engine v58); entrega ativa → sem corridas
  (migration `20260702150000`: `NOT EXISTS orders(assigned_driver_id=d.id::text,
  status driverAccepted/pickedUp/onTheWay)` em `tvde_offer_to_next`; nota de identidade:
  `tvde_rides.driver_id`=auth uid vs `orders.assigned_driver_id`=drivers.id::text).
- **c) Flutter motorista** — a home TVDE observa o `OrderStore`: com `everything`, oferta ou
  entrega em curso **empurra o `DriverHomeScreen` existente** como rota (zero telas
  duplicadas; back devolve ao modo corridas) + botão "Entregas" na AppBar para retomar
  manualmente. `DriverModel.workMode` + `supportsService`: `carPassengers` passa a aceitar
  entregas quando `everything` (era `return false` fixo).
- **d) Toggle** — labels PT-PT: "Só corridas de passageiros" / **"Corridas + entregas (tudo)"**.

**Gates:** 1) everything+livre → elegível a entrega E corrida (sim SQL + engine) ✓
2) everything+corrida ativa → excluído de entregas (filtro busyTvde) ✓
3) rides_only → fora do pool de entregas ✓ 4) estafeta normal → inalterado (work_mode
default 'everything', filtros defensivos com IS NULL) ✓.

## 3. PARTE 3 — CORRIDAS EM FILA (BACK-TO-BACK, ESTILO UBER) ✅

Migration `20260702160000_tvde_queue_back_to_back.sql` (aplicada em prod):
- `tvde_rides.is_queued` (aditiva, default false) + chave
  **`tvde_queue_pickup_radius_km` = 3** (categoria tvde → aparece/edita-se no ecrã admin
  de settings automaticamente; `0` desliga a fila).
- **`tvde_offer_to_next` com 2 níveis:** 1º livres online (comportamento atual intacto —
  **livre ganha SEMPRE**); 2º só se nenhum livre → motoristas `em_andamento` com destino a
  ≤ raio do pickup novo, sem fila (máx 1) e sem entrega ativa. Mecânica de oferta intacta
  (`current_offer_driver_id`/`offer_expires_at`) → **sweep/rotação/tried_driver_ids
  funcionam sem alteração** para ofertas em fila.
- **`tvde_accept_ride`:** motorista `em_andamento` aceita → `motorista_atribuido` +
  `is_queued=true` (guard `queue_full` para máx 1). Livre → fluxo original intacto.
- **`tvde_finish_ride`:** financeiro **byte-idêntico**; no fim ativa a fila
  (`is_queued=false` → `motorista_a_caminho`) — a mudança de status dispara o push
  'a_caminho' pela infra `notify-tvde-client` existente (trigger intacto).
- **`tvde_cancel_ride`:** cancelar a ativa também ativa a fila; terminal limpa `is_queued`.

**GATE backend (DO-block com rollback, zero persistência) — 8/8 ✅:**
livre_ganha ✓ · ocupado_perto_oferta ✓ · aceite_em_fila ✓ · max1_sem_oferta ✓ ·
finish_ativa_fila ✓ · a_caminho_sem_fila ✓ (só `em_andamento` recebe) ·
refila_em_andamento ✓ · cancel_ativa_fila ✓.

**Flutter motorista:** oferta em fila = **banner compacto** no topo do ecrã ativo
(valor + recolha + countdown + aceitar/recusar; NUNCA modal full-screen com passageiro a
bordo; som vem do push, intacto). Aceitar → chip "Próxima corrida na fila" no painel.
Finalizar → transição automática no MESMO ecrã para a corrida ativada ('a caminho', com
botão Navegar existente) + aviso "ganhaste €X". Store: `queuedRide` separado do
`activeRide` (a fila nunca rouba o ecrã ativo), poll/loadCurrent também em `em_andamento`.

**Flutter cliente:** `is_queued` → tracking mostra **"O teu motorista está a terminar uma
viagem próxima"** + subtexto "Serás o próximo…" + cartão do motorista (mantém-se) — sem
spinner infinito. Ativação → transição normal 'a caminho' + push.

**Admin (PT-BR):** badge **"Em fila (back-to-back)"** nas corridas ao vivo;
`tvde_queue_pickup_radius_km` editável na config (admin_list_settings, dinâmico).

## 4. PARTE 4 — VARREDURA FINAL

### 4a) `admin_tvde_drivers_list` corrigida ✅ (migration `20260702170000`)
- `active_rides`/`total_rides`: `r.driver_id = d.id` → **`d.user_id`** (FK real de
  `tvde_rides.driver_id` é `drivers(user_id)`).
- **Bónus (mesma causa-raiz, encontrado agora):** o join do saldo
  `tvde_driver_balances b ON b.driver_id = d.id` também estava errado (o saldo grava por
  auth uid em `tvde_finish_ride`) → corrigido para `d.user_id`.
- **Gate:** contagens da RPC = SELECT count(*) direto (3 finalizadas / 0 ativas / saldo 3.00
  para o único motorista atual; nota: nele `id==user_id` por coincidência — o join novo é
  correto por construção da FK).

### 4b) Itens P1 restantes da matriz ✅ (todos)
| Item | Estado | Onde |
|---|---|---|
| M11 resumo do ganho pós-corrida | ✅ (já existia: TvdeDriverRateScreen "Ganhaste €X"; back-to-back mostra aviso ao transitar) | rate screen / active screen |
| M12 ecrã de ganhos + histórico | ✅ NOVO | `tvde_driver_earnings_screen.dart` (hoje/semana/histórico 60d; botão na AppBar da home) |
| M16 nome do passageiro no motorista | ✅ NOVO | RPC `tvde_ride_passenger_name` (só o motorista da corrida; REVOKE public/anon) + linha "Passageiro: X" no painel ativo |
| C5 ETA no tracking do cliente | ✅ NOVO | "O motorista chega em ~X min" / "Chegada ao destino em ~X min" (haversine, 30 km/h — mesma média da engine) |
| C4 animação suave do carro | ✅ NOVO | lerp 12 passos × 80 ms entre polls (mesmo padrão do DriverStore) |

### 4c) Espera no pickup + no-show ✅
- Coluna aditiva `tvde_rides.arrived_at` (set em `tvde_driver_arrived`).
- Chave **`tvde_noshow_wait_minutes` = 5** (editável no admin; lida no app via `get_setting`).
- Motorista chegou → chip com temporizador "À espera do passageiro · mm:ss"; passada a
  janela → chip vermelho + item "Passageiro não compareceu" **habilita** no menu ⋮
  (antes fica desabilitado). Estado próprio já existia (`no_show` no CHECK + ator
  `no_show` no cancel). **Sem cobrança** (`tvde_cancel_fee_cents=0` intacto — decisão tua, P2).

### 4d) Paridade admin ✅
work_mode por motorista (ver/editar — já existia, mantém) · **estado dual** nos motoristas
TVDE (pills "N em curso" + "N na fila" + "Entrega em curso" via `queued_rides` +
`has_active_delivery` novos na RPC) · badge fila nas corridas ao vivo · raio + janela
no-show nas settings (dinâmico).

### 4e) Checklist "IGUAL À UBER" — estado real item a item
⚠️ Doc drift: o BORA_MOTORISTA_PLANO.md refere "checklist §9" mas o documento termina no §8
— o checklist canónico é a matriz TVDE_PARIDADE_UBER.md. Estado final:

**Motorista:** M1 mapa ✅ · M2 online/offline ✅ · M3 ganhos do dia ✅ · M4 resumo do dia 🟡 P2
(ganhos+histórico cobrem; falta "tempo online") · M5 oferta full-screen+som+countdown ✅ ·
M6 distância ao pickup ✅ · M7 oferta toca (triplo fallback) ✅ · M8 fluxo completo ✅ ·
M9 Navegar ✅ · M10 chegou→push ✅ · M11 ganho pós-corrida ✅ · M12 ganhos+histórico ✅ ·
M13 avaliar ✅ · M14 rating recebido ❌ P2 · M15 cancelar/no-show ✅ (+ janela de espera) ·
M16 nome do passageiro ✅ (ligar/chat ❌ P2) · M17 preferências ✅ (+ dual-driver PLENO) ·
M18 som contínuo ❌ P2 · **NOVO: fila back-to-back ✅ · dual-driver ✅**
**Cliente:** C1 ✅ · C2 ✅ · C3 ✅ · C4 animação ✅ · C5 ETA ✅ · C6 cartão motorista ✅ ·
C7 ✅ · C8 sem-motorista ✅ · C9 push ✅ · C10 ✅ · C11 ✅ · C12 ✅ · C13 chat ❌ P2 ·
C14 ligar ❌ P2 · **NOVO: mensagem de fila ✅**
**Admin:** A1–A8 ✅ + badge fila + estado dual + raio/janela configuráveis ✅
**Backend:** B1–B8 ✅ + exclusões dual-driver ✅ + fila (tiers/ativação/sweep) ✅ + arrived_at ✅

## 5. P2 PENDENTES (não implementados — pós-launch)
M4 tempo online do dia · M14 rating recebido visível · M18 som contínuo na oferta ·
C13/C14 chat + ligar motorista · deep-link do push tvde_ride_status para o tracking ·
cobrança de no-show (fluxo pronto; valor/cobrança = decisão do Danilo) ·
multi-fila >1 (Uber usa 1; mantido 1).

## 6. DECISÕES DO DANILO (pendentes de sempre)
- Pagamentos cartão/MB Way no TVDE (Fase 7) — hoje cash + assinatura por admin.
- Valor de `tvde_cancel_fee_cents` (0) e cobrança de no-show.
- Licença IMT / legislação TVDE.
- **Lacuna da Trava** (§1): replicar deny/hooks na pasta-mãe ou lançar sessões de `bora_app/`.

## 7. OBJETOS ALTERADOS
**Prod (aplicado):** engine v58 deployed · migrations `20260702150000_tvde_dual_driver_busy_exclusion`,
`20260702160000_tvde_queue_back_to_back`, `20260702170000_tvde_varredura_admin_noshow_passageiro`
(ficheiros no repo em `supabase/migrations/`).
**Flutter (9 ficheiros, +714/−31):** `driver_model` (workMode+supportsService) ·
`tvde_ride` (is_queued/arrived_at/label fila) · `tvde_driver_store` (fila/oferta-em-viagem/
janela no-show/finish-cancel com ativação) · `tvde_driver_home_screen` (ponte entregas +
botão Entregas + Ganhos + labels + poll) · `tvde_ride_active_screen` (banner oferta compacta +
chip fila + espera/no-show + passageiro + transição) · `tvde_ride_tracking_screen`
(fila + ETA + animação) · `admin_tvde_rides_screen` (badge) · `admin_tvde_drivers_screen`
(estado dual) · **novo** `tvde_driver_earnings_screen`.

## 8. CHECKLIST DE TESTE NO DEVICE (para o Danilo)
1. **Mapa/online:** login motorista TVDE → mapa com a tua posição; toggle Online.
2. **Oferta a tocar:** pede corrida como cliente → telemóvel do motorista toca (heads-up),
   ecrã de oferta com countdown; aceitar → ecrã ativo; "a caminho" chega por push ao cliente.
3. **ETA + carro suave:** no tracking do cliente vê "chega em ~X min" e o carro a deslizar
   (não saltar) a cada ~5 s.
4. **Espera/no-show:** motorista marca "Cheguei" → chip mm:ss; antes de 5 min o menu ⋮ tem
   "não compareceu" desabilitado; passa 5 min → habilita (fica vermelho no chip).
5. **Fila back-to-back:** com a viagem A `em_andamento` (passageiro a bordo) e SEM outros
   motoristas livres, pede corrida B com pickup a <3 km do destino de A → banner compacto
   no topo do ecrã da viagem A; aceita → chip "Próxima corrida na fila"; o passageiro B vê
   "o teu motorista está a terminar uma viagem próxima"; finaliza A → o ecrã passa sozinho
   para B 'a caminho' (+ aviso "ganhaste €X") e o passageiro B recebe push 'a_caminho'.
6. **Máx 1:** com B na fila, pede corrida C → C não oferece ao motorista (roda/sem motorista).
7. **Dual-driver:** motorista TVDE com "Corridas + entregas (tudo)" online e livre → cria
   um pedido de entrega → a home TVDE abre o fluxo de estafeta com o cartão laranja; aceita
   e executa como estafeta normal; enquanto a entrega decorre, corridas TVDE não chegam.
8. **rides_only:** muda para "Só corridas de passageiros" → entregas deixam de chegar
   (verifica no admin: work_mode do motorista).
9. **Admin:** corridas ao vivo com badge "Em fila (back-to-back)"; motoristas TVDE com
   pills "em curso/na fila/Entrega em curso"; settings tvde com raio (3) e janela (5) editáveis.
10. **Ganhos:** ícone 📊 na home TVDE → hoje/semana/histórico.
