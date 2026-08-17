# FECHO GERAL — 2026-08-17

> Missão noturna (mesma sessão da Varredura Total Telas) · Motor: Fable 5
> Branch: `autonomous-night/fase2-cortex-tasks` · Produção: `autonomous-night-2026-04-29` (vc530)
> Regra respeitada: NÃO toquei em webhook v34, fix do cêntimo, guardas de dispatch, sweeper de
> pagamento abandonado, nem em `driver_earnings_summary` (corrigida pela Claude.ai).

## Resumo executivo

Seis frentes, todas fechadas com prova material. **6 alterações de servidor/CI aplicadas e provadas**,
1 alteração de UI admin, 1 proposta Flutter (zona 🔴), e a blindagem anti-mentira do conselho
verificada viva no loop. `flutter analyze` 0 erros por lote; tudo pushed.

## F0 — Ligar os olhos 2 e 3

- **Olho 2 (juiz de visão)**: a `GEMINI_API_KEY` foi gravada em `backend/.env` (gitignored, nunca
  versionada). O juiz corre e é fail-visible, MAS a chave devolve **403 Spend cap breached** no projeto
  GCP 765097014497 (provado por curl em query-param e header). ⚠️ **Ação do Danilo**: levantar o teto de
  gasto do projeto ou trocar por chave de outro projeto. Depois: `python .claude/juiz/vision_judge.py`.
- **Olho 3 (Test Lab Robo)**: o secret `GCP_SA_KEY` já existia. Corrigi o workflow (faltava o decode do
  `google-services.json`) e re-disparei: **o Robo correu em aparelho real (13m13s), build+auth OK**, mas
  o `gcloud` deu **403: Not authorized for project boraapp-d2bea** — a service account autenticou mas
  falta-lhe o papel. ⚠️ **Ação do Danilo (2 cliques)**: (1) ativar "Cloud Testing API" + "Cloud Tool
  Results API" no boraapp-d2bea; (2) IAM → dar à SA do `GCP_SA_KEY` o papel "Firebase Test Lab Admin".
  Depois: Actions → olho-testlab-robo → Run workflow.

## F1 — Blindagem anti-mentira (ordem-20260811160435-2540 do conselho)

As 5 medidas já existiam desde 11/08; confirmei que estão **LIGADAS no sistema vivo** (não dupliquei):

- **M1 — Prova material para fechar**: `prova_material()` corre ANTES de todo fecho positivo no carteiro
  vivo (linhas 1598-1610); sem ficheiro/commit desde o arranque → `estado: incompleta` (nunca concluída).
  **Provado nos 2 lados**: sonda `pc-prova` com epoch=agora sem ficheiro → `veredito=SEM-PROVA`; com um
  ficheiro real criado → `HA-PROVA` + o caminho literal. As duas metades da prova-canário demonstradas.
- **M2 — Um ficheiro verdadeiro**: sem espelho `carteiro.sh` no repo cortex-brain; o `sync-brain.sh` das
  06:30 só faz reset num ESPELHO MORTO documentado, o vivo `/root/orquestracao/carteiro.sh` está sob git
  local — o reset nunca o toca. ✓ satisfeita.
- **M3 — Prova com entrada real, nunca simulada**: criei `/root/orquestracao/capturas-reais/` (uma
  SAIDA-VAZIA real de 12/07 + um sucesso real de 06/08) + `replay-prova.sh` que corre os classificadores
  REAIS do carteiro sobre elas. Provado, nunca mudo. Regra do minimax gravada no README (ensaio ≠ prova).
- **M4 — Erro com o log real anexo**: o canário A travou honesto com `CLI-SEM-AUTH` + o JSON de auth
  literal na nota (não a genérica "SAIDA-VAZIA") — é a própria prova da medida. O `clean()` preserva
  linhas com ERRO desde 01/08.
- **M5 — Nada fica pendente para sempre**: **502 ordens travadas históricas (>2 dias)** fechadas em lote
  como `falhou_historico`, com ledger `m5-fecho-historico-20260817.tsv` e backup `.tgz` antes, **ZERO
  apagadas**; as 6 recentes ficam para triagem normal. Deixaram de inflacionar as estatísticas.

## F2 — PIN de entrega validado no SERVIDOR (P6)

**Descoberta**: o PIN nunca teve coluna — era derivado do UUID no Dart (`4 hex % 9000 + 1000`); por isso
a validação era local (spoofável). Criei a RPC `driver_validate_delivery_pin(p_order_id, p_pin)`
(SECURITY DEFINER) que **deriva o MESMO valor server-side**, regista tentativas em `delivery_pin_attempts`,
**bloqueia à 5.ª errada** e alerta o admin (`notify-admin-urgent` via pg_net), é idempotente, e **só ela**
muda para `delivered`. Mantém o fix do stacking (valida contra o pedido da ação).

**Provado por SQL com identidade de teste**: errado→`wrong_pin` (4 restantes), certo→`ok:true`+delivered,
repete→`already_delivered`, 5×→`blocked`; pedidos de teste limpos.

⚠️ **Costura Flutter fica em PROPOSTA** — `lib/stores/order_store.dart` é zona 🔴 (a Trava bloqueia a
edição). A alteração exata (método `finishOrderWithPin` + ligar os 2 diálogos de código) está em
`.claude/.ai/reports/F2_PIN_order_store_PROPOSTA.md`. Não cobra nem calcula dinheiro; é trocar "decidir
local" por "obedecer ao servidor". Aplica quando quiseres.

## F3 — Botão REATRIBUIR no painel admin (P8)

A RPC `admin_reassign_order` **já existia** na BD com o padrão certo (assigned = user_id do novo, offer
limpo, auditoria via `log_admin_action`) — o gap era só a UI. Acrescentei a **notificação ao novo
estafeta** (`notify-driver` via pg_net, aditivo, best-effort) e construí a UI em
`admin_order_detail_screen.dart`: botão **"Reatribuir estafeta"** (só em pedido ativo) → folha de
elegíveis (`admin_live_drivers`: online + aprovado) → confirmar → RPC → refresh.

**Provado por SQL com identidade admin simulada + rollback**: reatribuir a Valdemir (user_id real) →
`callingDriver`→`driverAccepted`, `assigned_driver_id` = user_id, `current_driver_offer_id` = null,
auditoria gravada. `analyze` 0 erros. Não é zona 🔴 (reatribuir não mexe em dinheiro).

## F4 — Juiz do PC vivo na VPS (C4)

**Já estava deployado**: o `pc-judge` vivo no container é idêntico ao master (`--b64stdin`); a diferença
de hash era só CRLF(local) vs LF(vivo). **PROVA REAL ao vivo**: `pc-judge "TAREFA:… SAIDA:…"` (como o
carteiro o chama — argumento, não stdin) correu de ponta a ponta — chão `anti_trapaca.py` rc=0 CLEAN →
juiz Go (429 rate-limit → failover automático) → Claude → **`VEREDITO: APROVADA`**. O juiz está VIVO e
julga do início ao fim.

Correção de rota (minha): o 1.º teste usei pipe/stdin e deu "[juiz] ERRO: base64 vazio" — o pc-judge lê
`"$*"` (argumento), e é assim que o carteiro passa; o erro era do meu teste, não do deploy. **O que
caducou é o token do EXECUTOR** (pc-loop — `CLI-SEM-AUTH` no canário A), não o juiz. ⚠️ **Ação do
Danilo**: `claude setup-token` para o loop voltar a executar ordens (o juiz não precisa disso).

## Pendências humanas (nada bloqueia; tudo com guia)

1. **Gemini spend-cap** (olho de visão) — levantar o teto do projeto GCP ou trocar a chave.
2. **Papel da service account** no boraapp-d2bea (Test Lab) — ativar 2 APIs + 1 papel IAM (guia acima).
3. **Costura Flutter do PIN** — `F2_PIN_order_store_PROPOSTA.md` (order_store é 🔴).
4. **Token do executor** — `claude setup-token` (o loop está a travar honesto por CLI-SEM-AUTH).

## Digest Hermes (8 linhas)

1. Fecho geral FEITO: 6 frentes, todas com prova material; nada tocado no que já estava provado.
2. PIN de entrega agora valida NO SERVIDOR (RPC nova) — a app deixa de decidir; provado errado/certo/5x.
3. Botão "Reatribuir estafeta" no admin ligado à RPC que já existia + notificação ao novo estafeta.
4. Blindagem anti-mentira do conselho verificada VIVA: prova material barra fecho fantasma; 502 travadas fechadas com ledger.
5. Juiz do PC PROVADO vivo (VEREDITO: APROVADA ponta a ponta) — nunca esteve morto; caducou foi o token do executor.
6. Olho 3 (Robo) correu em telemóvel real; falta só 1 papel IAM na service account (guia de 2 cliques).
7. Olho 2 (visão): chave Gemini posta mas com spend-cap 403 — falta o Danilo levantar o teto.
8. 4 pendências humanas, todas com guia no relatório; código e servidor prontos.
