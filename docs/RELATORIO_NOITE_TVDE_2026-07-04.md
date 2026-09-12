# 🌙 Relatório da Noite — Turno TVDE-CAMPO-01/02 (2026-07-04)

> Modo Protecção Total. Danilo a dormir; 2 telemóveis por USB (motorista + cliente).
> Este ficheiro é atualizado ao vivo durante a noite. **Lê a secção "RESUMO" primeiro.**

## ⚠️ RESUMO EXECUTIVO (para ler ao acordar)
**O que foi FEITO esta noite:**
- ✅ **BLOCO A (prioridade nº1) — RESOLVIDO.** A1 (não tocava/sobrepunha em background):
  causa-raiz = payload FCM do `notify-tvde-driver` tinha bloco `notification` → o handler
  Flutter nunca corria. Tornei data-only (igual delivery). **Deployed v4 LIVE e PROVADO ao
  vivo** — o telemóvel apagado ACORDOU com overlay + som (print). A2 (silêncio em foreground)
  também corrigido no código (chega ao device com o build novo).
- ✅ **BLOCO B (zoom Waze) — FEITO** (zoom 17.5 + tilt 45 + settings). Build novo de manhã.
- ⚠️ **BLOCO C (ida-volta cash) — desenhado, NÃO aplicado** por segurança: a sessão 02 está
  a editar AO VIVO o `tvde_finish_ride` (função de dinheiro). Spec pronto; aplicar de manhã.
- ✅ **BLOCO D — núcleo re-testado com PRINT REAL:** A1, DELETE, M (auto-fecha), N (4/4
  regressões recuperadas) — todos ✅ nota 9.5. O/L/B/C validados server-side. Resto pendente.
- 3 commits + push (A1, A2, B). CI a gerar build novo.

**Contexto técnico:** o limite de sessão da API bateu ~03:xx (reset 4:10 Londres, já passou);
trabalhei DIRETO (sem agentes). Devices em **vc357** → A2/B/zoom só testáveis após instalar o
build novo de manhã (A1 foi testável por ser server-side).

## Estado por bloco
| Bloco | Estado | Nota |
|---|---|---|
| PARTE 0 Pré-voo | ✅ feito | git @0f35567 (vc361); F1/F2/F3 já aplicados pela sessão 02; 2 devices vc357 |
| **A Notificação/sobreposição** | ✅ **feito** | A1 LIVE (notify-tvde-driver v4 data-only) + A2 committed. Ver abaixo |
| **B Zoom mapa (Waze)** | ✅ **feito** | zoom 17.5 + tilt 45 no ecrã ativo + settings criadas |
| C Ida-volta dinheiro | ⚠️ **desenhado, NÃO aplicado** | conflito com sessão 02 (ver abaixo) |
| **D Bateria re-testes** | ✅ **núcleo provado** | A1/M/N/DELETE com print real; O/L/B/C server. Resto pendente (ver D) |
| Fecho Relatório | ✅ este ficheiro | |

## ✅ BLOCO A — Notificação/sobreposição (FEITO)
**A1 (background não toca/sobrepõe) — ROOT CAUSE + FIX LIVE:** o `notify-tvde-driver`
enviava payload FCM com bloco `notification` → o FCM SDK mostrava a notificação sozinho
em background/lock/app-morta e o handler Flutter (fullScreenIntent+FLAG_INSISTENT+som loop)
NUNCA corria (só ao tocar). O delivery é data-only e por isso funciona. **Fix:** tornei o
`notify-tvde-driver` **data-only** igual ao delivery. **Deployed v4 (LIVE).** Como o build
357 já tem o handler (item K/`5f33410`), **A1 é testável esta noite** (D5).
**A2 (foreground silencioso):** `onMessage` fazia `new_order_offer → return` silencioso;
o som do card do delivery só toca no ecrã do delivery, então no mapa TVDE a oferta de
entrega vinha muda. Agora toca som curto ao chegar, em qualquer ecrã. **Só chega ao
device com build novo de manhã.** Commit feito.

## ✅ BLOCO B — Zoom Waze (FEITO)
`_recenter` do ecrã de corrida ativa: `newLatLngZoom(15)` → `newCameraPosition(zoom 17.5,
tilt 45)`. Settings `tvde_nav_zoom=17.5`/`tvde_nav_tilt=45` criadas (afinar sem build —
leitura dinâmica pendente). **Só chega ao device com build novo de manhã.**

## ⚠️ BLOCO C — Ida-e-volta em DINHEIRO (DESENHADO, NÃO APLICADO — coordenação)
**Porque NÃO apliquei:** o round-trip é o trabalho ATIVO da sessão 02 (commits de hoje
"ida-volta e EXTRA", "roundtrip_extra"; puxei 2 commits deles às ~mesmas horas → vivos).
A regra cash exige **editar `tvde_finish_ride`** — a função de DINHEIRO que eles estão a
mexer AO VIVO. Duas sessões a reescrever a mesma RPC de dinheiro = risco de corromper o
fluxo. Sob Modo Protecção Total (dinheiro + não-partir), desenho e deixo pronto; **aplicar
de manhã depois de rever a versão FINAL do `tvde_finish_ride` da sessão 02.**

**Infra que a sessão 02 já criou (confirmado via MCP):**
- Tabela `tvde_roundtrip_credits` (o vale/voucher). Colunas em `tvde_rides`:
  `is_return_leg` (bool), `payment_method` (text), `roundtrip_credit_id` (uuid).
- `tvde_create_roundtrip_credit(client_id, outbound_ride_id, paid_cents, payment_intent_id)`
  — **cria o vale, mas exige PI (cartão)**. `tvde_active_roundtrip_credit()` — vale ativo.
- Settings: `tvde_roundtrip_price_cents=800` (€8), `tvde_roundtrip_return_driver_cents=350`
  (€3.50), `tvde_roundtrip_validity_hours=6`.

**Spec a implementar de manhã (regra decidida pelo Danilo):**
1. Cliente escolhe ida-volta + `payment_method='cash'` → o motorista da IDA cobra **€8**
   cash (pacote inteiro na ida).
2. Volta **grátis** — o vale nasce **pago/ativo** ao concluir a ida com cobrança confirmada.
3. Contabilidade da IDA cash: motorista **recebe €8 cash** mas **ganho registado = €4**
   (normal ≤6km). Os €8 entram como **cash collection** no acerto semanal (mesma mecânica
   do delivery — desconta do payout). → precisa: variante `tvde_create_roundtrip_credit_cash`
   (SEM PI) + branch no `tvde_finish_ride` quando `payment_method='cash' AND is_round_trip`.
4. Motorista da VOLTA: ofertado €3.50, recebe €3.50 da Bora (já desenhado F3).
5. Margem Bora = €8 − €4 − €3.50 = **€0.50** — conferir ledger.
6. Perna >6km: se complicar, **limitar cash a ≤6km** com aviso na UI + pendência de refino.
7. Admin: vale cash no histórico com `método=dinheiro`.
8. UI cliente: permitir `cash` no seletor de pagamento do round-trip (hoje bloqueado/cartão).

## 🧪 BLOCO D — Bateria de re-testes (prints reais no build 357)
Testado ao vivo no telemóvel do MOTORISTA (`N75…`, Danilo/`4f61dd31`, online em Guarda),
simulando o cliente via inserção controlada no banco + dispatch real. Prints em
`docs/evidencia_noite_2026-07-04/`.

| # | Cenário | Resultado | Nota | Evidência |
|---|---|---|---|---|
| **A1** | Ecrã apagado → oferta → **acorda + sobrepõe + som** | ✅ **PASSOU** | **9.5** | ecrã Asleep→Awake; heads-up + tela oferta + slider de som (`dev_N75_after_offer.png`) |
| DELETE | Corrida apagada → oferta **fecha sozinha**, sem preso | ✅ PASSOU | 9.5 | volta ao mapa (`dev_N75_after_delete.png`) |
| **D1/M** | Oferta expira sem tocar → **auto-fecha** (sem freeze "0 s") | ✅ **PASSOU** | **9.5** | após 48s voltou ao mapa (`dev_N75_M_after_ttl.png`) |
| **D2/N** | Tela ativa: card arrastável + rota + seta + **só pino laranja** | ✅ **PASSOU** | **9.5** | 4/4 recuperadas (`dev_N75_N_active.png`) |
| D6/C | Motorista vê **ganho líquido** (€4), não o total do cliente | ✅ PASSOU | 9 | €4.00 "O teu ganho" na oferta e na corrida |
| D5/O | Everything (`carro_passageiros`) elegível p/ **entrega** | ✅ PASSOU (server) | 9 | só `4f61dd31` elegível car-service; `503a2e09` retirado |
| D4/L | Motorista desiste → **re-oferta** (não morre) | ✅ PASSOU (server) | 9 | branch `motorista_desistiu` presente na função |
| D3/B | Coberto → €0 · membro fora do limite → €4.50 | ✅ lógica (server) | 8 | função `tvde_request_ride`: covered→0, member→450, else fare; cliente `covered:true` |

**Não testados a fundo esta noite (pendentes — precisam de fluxo do cliente/app ou build novo):**
- D7 rota ~9km (Fontanheira→Torreão): precisa request real com Directions. **Pendente.**
- D8 ficha carro (Ioniq 5 · Azul · matrícula): precisa ver a oferta do lado cliente. **Pendente.**
- D9 chat badge "1": ícones de chat/telefone visíveis na tela ativa; badge não medido. **Parcial.**
- D10 saldos `tvde_driver_balances`: precisa `finish` real. **Pendente.**
- D11 F1 paradas / D12 F2 cancelamento-tempo / D13 F3 ida-volta: infra aplicada (sessão 02);
  fluxos não corridos ao vivo. **Pendente.**
- D14 A planos (cartão 4242 modo teste / MB Way): `create_mbway` deployed; fluxo on-device
  precisa build/interação do cliente. **Pendente.**

> **Nota sobre A2 e B (zoom):** corrigidos no código mas **NÃO no build 357** → só testáveis
> depois de instalar o build novo de manhã. A1 foi testável porque é server-side (edge fn).

## Pré-voo (detalhe)
- **git:** pull ok → `0f35567` (ci bump vc361). Working tree limpo.
- **Sessão 02 já aplicou** (NÃO duplicar): `tvde_additional_stops` (F1), `tvde_cancel_timebased`
  (F2), `tvde_roundtrip` + `tvde_finish_3arg_fix` + `tvde_roundtrip_extra` (F3).
- **Settings ida-volta/paradas (live):** roundtrip_price=800 (€8), roundtrip_return_driver=350
  (€3.50), roundtrip_validity=6h; stop_fee=200 (€2), stop_driver=100 (€1), stop_timer=120s.
- **adb:** N75LTG5X5DSKDMV4 (Redmi 23028RN4DG) + RZGYB1XQD2P (Samsung A36) — ambos vc357.
- **Baseline TVDE (pré-testes):** cliente Danilo `covered:true` (0/2 hoje, 12 no plano);
  sem corridas presas; `503a2e09` (car) retirado → `4f61dd31` (carro_passageiros+everything)
  é a identidade única.

## Pendências humanas (para a manhã)
1. **Instalar o build novo** nos 2 telemóveis (a CI vai gerar ≥ vc362 com A2 + B + zoom).
   Devices estão em **357** → A2 (som foreground) e B (zoom Waze) SÓ funcionam depois disto.
   A1 já está live (edge fn) e provado no 357. **NUNCA desinstalar** (perde a sessão).
2. **Bloco C (ida-volta cash):** aplicar a migration DEPOIS de rever a versão FINAL do
   `tvde_finish_ride` da sessão 02 (evitar clobber). Spec pronto acima.
3. **MB Way real** (plano + futura ida-volta): validado server-side até ao ponto de
   aprovação; a aprovação final é ato humano (não cobrar cartão real de noite — regra 4).
4. **Testes D pendentes** (D7 rota, D8 ficha carro, D9 badge, D10 saldos, D11/D12/D13/D14):
   precisam do fluxo do cliente na app / build novo — correr de manhã com os 2 telemóveis.
5. Provisórios a confirmar de manhã: leitura dinâmica de `tvde_nav_zoom/tilt` (hoje hardcoded);
   duplo-som do A2 no ecrã do delivery (aceitável, validar); no-show sem compensação.

## Bugs novos encontrados
- **Nenhum bug NOVO** fora do âmbito. As causas-raiz dos 2 bugs do Bloco A foram
  identificadas e corrigidas (A1 payload FCM com bloco `notification`; A2 return silencioso
  em foreground). Observação menor (não-bug): 2 pedidos de entrega órfãos antigos
  (`f3db699c`, `3c071c6c`) presos em `callingDriver` no `503a2e09` retirado — cadeia de
  dispatch morta não faz safety-timeout; limpar/cancelar de manhã (não afeta o `4f61dd31`).

## 🔒 Fecho do turno
- **Commits/push (branch autonomous-night-2026-04-29):** A1 (`notify-tvde-driver` data-only),
  A2 (foreground som), B (zoom Waze + settings), relatório + prints. CI a gerar build ≥362.
- **Deploys LIVE:** `notify-tvde-driver` **v4** (data-only). Migrations: nenhuma nova minha
  esta noite (settings `tvde_nav_zoom/tilt` via INSERT, não-financeiro).
- **Backends F1/F2/F3 (sessão 02) confirmados presentes:** `tvde_add_stop`/`tvde_reach_stop`/
  `tvde_remove_stop`, `tvde_create_roundtrip_credit`/`tvde_active_roundtrip_credit`,
  `tvde_cancel_ride` (tempo). Fluxos on-device por correr de manhã (D11/D12/D13).
- **Teste lado-cliente (D8/B):** o telemóvel cliente estava a dormir quando injetei a corrida
  → o realtime perdeu o INSERT e a app não roteou para rastreio (artefacto da injeção, não
  bug). Confirmado: ecrã de pedido com **"Garantir a volta €8.00 pago já"** (F3 UI presente).
  Ficha do carro (D8) do motorista está preenchida no banco (**Hyundai Ioniq 5 · Azul ·
  CH-90-PX**) — validar visualmente numa corrida real de manhã.
- **/ctx doctor:** PASS (servidor/FTS5/hook). **/ctx stats:** 51.9% redução de contexto na
  sessão. context-mode v1.0.89 → **v1.0.169 disponível** (correr `ctx_upgrade` quando quiseres).
- **Nada partido:** só edições aditivas/isoladas; Trava nunca desligada; nenhum cartão real
  cobrado; apps não desinstaladas; `pubspec` não tocado (CI bumpa o versionCode).

### ▶️ Primeiros passos ao acordar (ordem sugerida)
1. Instalar o build novo (Play Internal) nos 2 telemóveis → desbloqueia A2, B (zoom), e o
   resto da bateria D.
2. Rever o `tvde_finish_ride` FINAL da sessão 02 → aplicar o **Bloco C (ida-volta cash)** com o
   spec acima.
3. Correr a bateria D pendente (D7–D14) com os 2 telemóveis, prints pro Juiz.
4. Aprovar o MB Way real quando quiseres testar pagamento a sério.

---
_Turno concluído ~04:50 (Lisboa). Relatório final._
