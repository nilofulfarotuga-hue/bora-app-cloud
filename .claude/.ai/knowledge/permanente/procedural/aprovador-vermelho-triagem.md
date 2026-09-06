---
tema: aprovador-vermelho-triagem · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-27
---

# Aprovador-Vermelho — conhecimento de triagem (Balde A vs Balde B)

> Consolida o que o agente `aprovador-vermelho` já aprendeu a triar na fila `robot_suggestions`
> (Supabase `ojykpzwqrtusfeakzrna`), para não re-derivar a mesma análise a cada corrida. Mecânica
> do loop (watermark, FALLBACK 30MIN) está em `permanente/semantica/loops.md` — este ficheiro é só
> o conhecimento de triagem (o quê é Balde A/B e porquê).

## Lição: item Balde B parado há semanas em `status='nova'` NÃO é bug
É o comportamento correto e esperado: só o Danilo (via `AdminRobotSuggestionsScreen` + RPC/JWT
admin, ou "vai" no Telegram) muda o status de um item Balde B — o agente nunca decide dinheiro.
Exemplo real (2026-07-12): itens `268aad47` e `abeca5d7` (ambos criados 2026-06-22) seguiam
~20.5 dias em `nova`, já re-triados várias vezes no mesmo dia (11:26-11:27 UTC e de novo na
corrida FALLBACK 30MIN) sempre com o mesmo veredito Balde B — nenhuma re-triagem os promoveu,
como esperado. **O que seria bug:** o PRÓPRIO ato de triagem nunca ter corrido sobre o item
(staleness da triagem), não a staleness do item em si.

> **estado: superado (por evidência de 2026-07-16)** — o exemplo concreto acima (`268aad47`/
> `abeca5d7`, e os outros 3 do mesmo lote) já **não** está parado em `nova`: o Danilo decidiu
> (rejeitou) o lote inteiro de 5 em **2026-07-14 05:33:09 UTC** (verificado por SELECT direto
> em `robot_suggestions.status='rejeitada'` + `motivo_rejeicao` individual por item, corrida
> FALLBACK 30MIN de 2026-07-16). O **princípio geral** desta lição (staleness de item Balde B
> não é bug do agente) continua válido para itens futuros — só o exemplo ficou desatualizado.
> Ver linha nova em "Histórico de corridas" abaixo; não reconfirmar mais este lote específico.

## Funções cron conhecidas (repetem na fila via dedup_key `performance:slow-query-*`)
Prova real — corpo lido diretamente em `supabase/migrations/`:

- **`bora_dispatch_maintenance()`** (`supabase/migrations/20260531064411_fix_dispatch_maintenance_net_http_post.sql`, também em `20260429180000_fix_dispatch_maintenance_types.sql`) — cancela pagamentos
  abandonados (`UPDATE orders` status/payment_status), aplica 2 TTLs de auto-cancelamento do
  dispatch, chama `net.http_post` para a Edge Function `dispatch-engine`. **Balde B sempre** —
  coração do motor de dispatch + cancelamento de pagamento.
- **`_appointment_cron_auto_no_show()`** (`supabase/migrations/20260608000005_appointments_rpcs_admin_cron.sql:51-57`)
  — `UPDATE appointments SET status='no_show', deposit_status = CASE WHEN deposit_status='paid'
  THEN 'retained' ELSE deposit_status END`. **Balde B sempre** — decide reter ou não dinheiro do
  cliente. **Reconfirmado 2026-07-16** (item `8c9e9d08`, corpo relido fresco via
  `pg_get_functiondef`, escrita `deposit_status` confirmada intacta): Balde B **independente do
  verbo da proposta** — mesmo quando o item da fila só pede "otimizar a query" (não mudar
  lógica), qualquer edição a esta função toca zona protegida dinheiro. Não reanalisar caso a
  caso; qualquer sugestão que cite esta função cai em Balde B.

  **Regra de item agrupado (confirmada 2026-07-18, 4 corridas independentes no mesmo dia):**
  quando uma única linha da fila (`robot_suggestions`) agrupa mais de uma função — ex. item
  `9db0124a-964e-4b67-b098-c81a57c576a4` ("Otimizar queries lentas de cron jobs", `dedup_key
  performance:otimizar-cron-queries-lentas`) junta `_cron_check_orphan_orders` (Balde A) +
  `_cron_check_ghost_drivers` (Balde A) + `_appointment_cron_auto_no_show` (Balde B sempre) — o
  **item inteiro** cai em Balde B, mesmo que 2/3 das funções citadas sejam isoladamente Balde A.
  **Não há aprovação parcial** de uma linha da fila; a fila não permite decidir só a parte
  Balde A e deixar a Balde B pendente dentro do mesmo item. Confirmado por 4 triagens
  independentes no mesmo dia (2026-07-18) com o mesmo veredito, e por `admin_audit_log` (ações
  `robot_suggestion_baldeB_encaminhado` id `2910395b-6e78-4f39-9e2d-455e459d43af` 20:19:56 UTC,
  `robot_suggestion_baldeB_surfaced` id `7db4bb7a-c1df-4f81-821a-7f205ad351e2` 20:28:16 UTC, e
  `robot_suggestion_baldeB_reconfirmado` id `c71e5629-cae6-4045-8736-6ad16acdf022`
  (`reconfirmacao_numero=4`, corrida FALLBACK 30MIN ~20:42 UTC)). Item confirmado por SELECT
  direto ainda `status='nova'` nesta 4ª consolidação.
- **`_cron_check_orphan_orders()`** (`supabase/migrations/20260518112559_admin_notif_crons_4_6_7.sql:5-42`)
  — só `SELECT` sobre `orders` + `PERFORM notify_admin_event(...)` (insere em `admin_notifications`).
  Zero escrita em orders/wallets/ledger, zero chamada a Edge Function de cobrança/dispatch.
  **Balde A confirmado** — a categoria "toca dispatch/pedido" seria falso-positivo aqui; a função
  só observa/alerta, não decide.
- **`_cron_check_ghost_drivers()`** (verificado por `pg_get_functiondef` em produção,
  `ojykpzwqrtusfeakzrna`, corrida FALLBACK 30MIN 2026-07-16, item `bfe65453`) — só `SELECT` sobre
  `drivers` (`is_online=true` sem heartbeat há >5 min) + `PERFORM notify_admin_event(...)`. Zero
  UPDATE/DELETE, zero dinheiro, zero chamada ao dispatch-engine. **Balde A confirmado** — mesma
  família de `_cron_check_orphan_orders` (observa/alerta, não decide).

**Reconfirmado com `dedup_key` novo (2026-07-27):** `infra:otimizar-cron-jobs-marcacoes-drivers`
(id `9391dfac-00ac-4eaf-b5d9-1e1732bf1dd9`) agrupa as mesmas 2 funções acima sob categoria
rotulada `marcacoes` pelo gerador — mislabel, nada a ver com a tabela `reservations`; conteúdo
real confirmado por leitura de `supabase/migrations/20260518112559_admin_notif_crons_4_6_7.sql`.
Balde A aprovado, mesmo padrão de sempre. Sinal adicional (junto ao achado de dedupe abaixo) de
que o gerador de sugestões tem bugs de classificação de categoria.

**Novo tipo de Balde A confirmado, não-cron (2026-07-19):** itens de catálogo "marcar para
revisão manual" — `catalogo:produtos-sem-foto-revisao` (id `88bebaed-7e1f-4c0c-916a-b8756f078106`)
e `catalogo:produtos-sem-categoria-revisao` (id `86dc8990-a964-421a-85cc-329fb45a0591`), categoria
`catalogo` — confirmados por SELECT direto: `status='aprovada-emerson'`, `reviewed_at`
2026-07-19 11:20:14.30/16.45 UTC. Só marcam flag de revisão, zero escrita em preço/visibilidade/
dinheiro. Mesma família "observa/marca, não decide" das funções cron acima — esta secção cobre
Balde A em geral (título ficou estreito, mantido por histórico).

**Família estendida (2026-07-27):** `catalogo:produtos-preco-suspeito-revisao` (id
`a68ff603-d5c4-48b8-8755-47a91f5f0e78`, 7 produtos) auto-aprovado com o mesmo `payload_execucao=
{"type":"flag_products_review",...}` das duas ocorrências acima — a palavra "preço" no título é
falso-positivo do filtro T3, a ação real não altera preço nenhum, só sinaliza para revisão humana.
Confirma que a família Balde A "marcar para revisão" cobre qualquer variante de campo (foto/
categoria/preço), não só as 2 já vistas — reconhecer `catalogo:*-revisao` (sem "-ocultar") como
Balde A em corridas futuras sem re-derivar. `admin_audit_log` id
`1bfb8be9-94de-4dcc-891b-779452cb643c`.

**Novo tipo de Balde B confirmado, não-cron (2026-07-20):** categoria `operacao_pedidos`,
dedup_key `operacao_pedidos:pedido-preso-sem-atribuicao` — pedido preso sem atribuição
(`orders.status='created'`, `assigned_driver_id=NULL` por tempo anormal), proposta cita
"mecanismo de reatribuição automática com TTL". **Balde B sempre** — mesma lógica das famílias
cron acima: qualquer proposta que mexa em (re)atribuição de pedido toca `dispatch_engine` (zona
protegida vermelha), mesmo que o item concreto peça só "investigar causa raiz". 1ª ocorrência
confirmada (id `8ccc09bb-e5b7-458e-89f9-f179df67f942`, evidência `orders.id=7aa2e5f7-75d1-4ef4-
b854-e69b2e6fa62b`; ver linha 2026-07-20 em `aprovador-vermelho-historico-corridas.md`).
Reconhecer `operacao_pedidos:*` como família Balde B em corridas futuras sem re-derivar a análise.

> **estado: superado (item concreto, 2026-07-21)** — `8ccc09bb-e5b7-458e-89f9-f179df67f942` já não
> está em `nova`: confirmado por SELECT direto `status='rejeitada'`, `reviewed_at=2026-07-20
> 11:56:14 UTC`. A **regra geral** (família `operacao_pedidos:*` = Balde B) continua válida para
> itens futuros — só este exemplo concreto ficou decidido; não reconfirmar/re-analisar como
> staleness. Ver linha 2026-07-21 em `aprovador-vermelho-historico-corridas.md`.

## Nova família Balde B confirmada — `marcacoes:*` (reservas de mesa com pré-pagamento, 2026-07-24)
Categoria de dedup_key `marcacoes:*` cobre propostas sobre a tabela `reservations` (reservas de
mesa/restaurante com pré-pagamento €3 — CLAUDE.md §5), **distinta** da tabela `appointments`
(Reservas Pro de serviços, com `deposit_status` — ver função `_appointment_cron_auto_no_show()`
acima). **Correção de nomenclatura (2026-07-24):** `reservations` usa as colunas
`prepayment_cents` e `prepayment_pi` (confirmado por leitura de
`supabase/migrations/20260515100002_cancel_orphan_reservation.sql`) — **não**
`deposit_status`/`deposit_cents`/`deposit_pi`; esses nomes pertencem à tabela `appointments`, não
confundir as duas. O `status` da reserva fica `'pending_payment'` (não há um campo `deposit_status`
separado em `reservations`).

Funções reais confirmadas (por leitura de `supabase/migrations/` e `pg_get_functiondef` em
`ojykpzwqrtusfeakzrna`, corrida FALLBACK 30MIN 2026-07-24):
- **`cancel_orphan_reservation(p_reservation_id, p_payment_intent_id, p_reason)`**
  (`supabase/migrations/20260515100002_cancel_orphan_reservation.sql`) — SECURITY DEFINER, `DELETE`
  da reserva só se `status='pending_payment'` e `prepayment_pi` bate com o PI informado (defesa
  anti-spoofing). Idempotente; chamada pelo `stripe-webhook` em falha/cancelamento de pagamento.
- **`auto_close_no_show_reservations()`** (`supabase/migrations/20260503020000_reservation_rpcs_sync.sql:119`)
  — já trata no-show (marca `status='no_show'` após `reservation_no_show_grace_minutes`, default
  60min se ausente). O `cron.job` correspondente existe mas está **`active=false`** hoje.

Itens desta família triados como Balde B (dinheiro real — mexem em reserva com pré-pagamento
Stripe real):
- `marcacoes:liberar-slots-orfãos-ttl` (`1efa3e60-10de-423c-97fb-8a21148de370`) e
  `marcacoes:ttl-pending-payment` (`47a4a9e6-07c7-4846-864a-e400064c9b0a`) — propõem
  `update_setting reservation_orphan_pending_ttl_minutes`/`reservation_pending_payment_ttl_minutes`.
  A reserva órfã que motivou a proposta (`7c61663d-ec39-48a2-83b4-5e4cc081794f`, `prepayment_pi
  pi_3TvmY8GlT3R2jCYp1thQswqy`, €3) **já não existe** em `reservations` (0 linhas, SELECT direto
  2026-07-24) e hoje **zero** reservas estão `status='pending_payment'` — o incidente concreto
  resolveu-se sozinho (provável `cancel_orphan_reservation()` via webhook Stripe, ou ação manual —
  não confirmado qual). Isto **não promove** os itens a Balde A: a proposta em si automatiza
  escrita/cancelamento de reservas pagas, sem regra de refund definida — continua Balde B.
- `marcacoes:ajustar-politica-no-show` (`c068f901-e877-4df0-8b43-0ac1b1c04234`) — propõe
  `update_setting reservation_no_show_policy` incluindo `deposit_required_threshold:0.5` (exigir
  depósito conforme taxa de no-show). Os crons `reservas_pro_reminders_24h`/
  `reservas_pro_reminders_2h` já existem e já estão `active=true` — a parte "reminders" da proposta
  é redundante; só a parte do depósito é novidade real, e essa é dinheiro (CLAUDE.md §5: "no-show e
  cancel <2h = Bora 100%"). Balde B.
- `marcacoes:resolver-marcacoes-orfas` (`7cf1a393-82b5-40d6-8738-7d300e73f85a`, `nivel=3` — o
  próprio maestro já classifica 🔴, `payload_execucao=null`) — pede mecanismo de
  cancelamento/reatribuição automática de reserva paga. Evidência (2 reservas citadas) já stale
  (não existem mais). Balde B por nível + por conteúdo.

**Nenhuma das 3 chaves propostas (`reservation_orphan_pending_ttl_minutes`,
`reservation_pending_payment_ttl_minutes`, `reservation_no_show_policy`) existe hoje em
`platform_settings`, nem é consumida por nenhuma função/cron existente** (confirmado por grep no
repo local — zero matches em `supabase/` — e por SELECT em `platform_settings`, 2026-07-24) — só
criar a setting seria inerte isoladamente; o risco real é o PRÓXIMO passo (código que passe a
consumir a setting para agir sobre dinheiro). Reconhecer `marcacoes:*` como família Balde B em
corridas futuras, mesmo padrão de `operacao_pedidos:*` acima.

## Anomalia conhecida — backoff exponencial do script de gatilho
> **Movido para ficheiro próprio em 2026-07-27** (checagem #8 do `bibliotecario-cerebro` — este
> ficheiro tinha passado de ~24 KB): `hermes-aprovador-vermelho.sh` refiria `FALLBACK 30MIN`
> repetidamente sem backoff; fix committado em `e4444a4` foi depois revertido em silêncio por
> `f169f96`; deploy à VPS ainda pendente a 2026-07-24. Detalhe completo, histórico de
> reconfirmações e candidatura a ordem em
> `permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`.

## Confirmação: aprovação humana real de item Balde B via `robot_approve_plan` (2026-07-19)
Primeira prova concreta nesta base de conhecimento de que o Danilo de facto decide um item Balde B
pessoalmente pelo canal "vai"/Central, depois de avisos repetidos por Telegram — não é só teoria
do mecanismo de escalonamento. Item `01a67895-05fc-4a07-8b98-0bdef3f1c1a2` (dedup_key
`infra:otimizar-queries-cron-lentas-v3`, a 3ª variante do "padrão agrupado" — ver regra acima)
ficou `status='aprovada'`, `reviewed_by=c9fccf85-03ee-4efc-83bf-613f211a78ff` (confirmado por
SELECT em `auth.users` = `nilofulfarotuga@gmail.com`, `raw_app_meta_data.role='admin'` = Danilo),
`reviewed_at=2026-07-19 11:09:00.751141 UTC`; `admin_audit_log` confirma `action='robot_approve_plan'`,
mesmo `admin_id` e `created_at`, id `960fc592-2d9f-47c9-be26-81a7b8acfe3e` — via RPC humana com
JWT admin real, distinta de `robot_emerson_decide` (que o agente usa só para Balde A) e das ações
`robot_suggestion_baldeB_*` (que só reconfirmam/encaminham, nunca decidem dinheiro). O agente
nunca decidiu isto sozinho — confirma que o escalonamento Balde B funciona ponta-a-ponta na
prática, não só na regra. Verificado por SELECT direto (`robot_suggestions` + `admin_audit_log` +
`auth.users`) nesta consolidação, 2026-07-19.

> **estado: superado (lote fechado, 2026-07-21)** — as 2 variantes irmãs desta família também já
> foram decididas pelo Danilo (ambas `rejeitada`, confirmado por SELECT direto): `77c31fff-0330-
> 4981-813a-f2268c6f7bbe` (original, `reviewed_at=2026-07-19 21:09:50 UTC`) e `29ea4b41-1e28-420e-
> a7d3-2995c335d7e5` (`-v2`, `reviewed_at=2026-07-19 19:54:47 UTC`). As 3 variantes do lote
> `infra:otimizar-queries-cron-lentas[/-v2/-v3]` estão todas decididas (nenhuma em `nova`) — não
> re-analisar como staleness em corridas futuras. Um **dedup_key novo e distinto** para o mesmo
> padrão de queries lentas em cron (`infra:queries-lentas-cron`, sem o prefixo "otimizar-") surgiu
> em 2026-07-21 (`3adc1b43-3276-4d0f-94ed-f2e35657a5ce`) — tratar como ocorrência nova da mesma
> família de regra, não como reconfirmação do lote antigo. Ver `aprovador-vermelho-historico-
> corridas.md`, linha 2026-07-21.

## Mecanismo de aprovação Balde A e aviso de Balde B (confirmado 2026-07-18)

**`robot_emerson_decide` NÃO é um pipeline autónomo externo ("Emerson") — é a própria escrita do
agente `aprovador-vermelho`** quando aprova um item Balde A e a RPC direta de approve/reject da
Central exige JWT admin que o MCP (SELECT/execute_sql) não tem. `robot_emerson_decide(p_suggestion_id
uuid, p_decisao text, p_motivo text, p_ordem_id text)` é uma RPC `SECURITY DEFINER` real (confirmada
por `pg_proc`/`pg_get_function_identity_arguments` em `ojykpzwqrtusfeakzrna`, existe em produção)
que o próprio agente chama para gravar a decisão; o status resultante fica `'aprovada-emerson'`
(não `'aprovada'` simples) — é só o *marcador* de que foi este mecanismo de escrita que decidiu,
com a trava de servidor da própria RPC (regex de palavras vermelhas + categoria protegida) a
validar de novo antes de gravar. Nunca decide dinheiro sozinho: só grava Balde A já triado.

**Ponte Telegram PC→VPS confirmada como caminho direto para avisar o Danilo (2026-07-18):** quando
a sessão do agente corre no PC e tem acesso à chave `id_ed25519_vps` (nem sempre — 2 das 3 corridas
do mesmo dia não tinham), o comando abaixo entrega a mensagem de aviso de um item Balde B
diretamente, sem depender só de push in-system (que falha sem "Remote Control" ativo):
```
ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud \
  "docker exec -u hermes -i hermes-agent-fvnc-hermes-agent-1 hermes send -t telegram '<mensagem>'"
```
Confirmado por output real: `Sent to telegram home channel (chat_id: 6731890157)`, exit 0, e por
`admin_audit_log` (`action='robot_suggestion_baldeB_surfaced'`, `details.telegram_enviado=true`,
id `7db4bb7a-c1df-4f81-821a-7f205ad351e2`). Preferir este caminho a deixar só "pronto para a
próxima passagem" quando a chave estiver acessível na sessão.

## Achado 2026-07-27 — gerador de sugestões sem dedupe efetivo + novo subpadrão `catalogo:*ocultar`
Corrida FALLBACK_30MIN em que a fila `nova` saltou de 1-9 (histórico normal) para **30 itens**.

**Bug do gerador de sugestões (dedupe quebrado) — motivo real do salto, não é ataque nem nova
família de dinheiro:** 2 clusters de duplicados quase-idênticos em `robot_suggestions`, cada um
reciclando evidência IDÊNTICA/stale em vez de conferir propostas recentes antes de criar mais uma
linha com `dedup_key` incrementado. (a) **17 variantes** de "Ajustar o no-show rate para
marcações" (`marcacoes:ajustar-no-show-rate-threshold` base + `-v2`...`-v17`), evidência idêntica
`{"total":3,"no_show":1}` em todas, criadas a cada ~1-3h entre 2026-07-25 22h e 2026-07-27 05h —
propõem a setting `reservation_no_show_rate_threshold`, que **não existe** (distinta da já
existente `reservation_no_show_threshold_count=3`; confirmado por grep em
`supabase/migrations/` nesta consolidação: zero matches para o nome proposto, 2 matches para o
nome real). (b) **4 variantes** de "Resolver marcações pendentes órfãs"
(`marcacoes:resolver-marcacoes-pendentes-orfas` base+v2+v3 + `marcacoes:2efe0a26901c`), todas
citando os mesmos 2 IDs de reserva (`7c61663d-ec39-48a2-83b4-5e4cc081794f`,
`091ac601-4f54-4107-ab66-4ff6b7f2e55c`) — reconfirmado por SELECT direto nesta corrida: **0
linhas em `reservations` para ambos** (o primeiro ID já tinha sido confirmado stale em
2026-07-24; o gerador continua a reciclar evidência fantasma em propostas novas em vez de
verificar o estado atual). Bug de ROBUSTEZ do pipeline gerador (evolution-engine/robot-b), não é
lógica de dinheiro nova — fora do mandato do `aprovador-vermelho` corrigir (só roteamento).
Manifestação relacionada (não idêntica) à lição
`permanente/procedural/licoes/licao-spam-ordens-autoreferencial.md` — ver nota lá. Candidato a
ordem para `maestro-autonomia` avaliar.

**Novo subpadrão Balde B — `catalogo:*ocultar` (hide em massa), DISTINTO do padrão Balde A já
confirmado acima ("marcar para revisão", 2026-07-19):** 3 itens propõem `UPDATE
is_available=false` em massa — `catalogo:produtos-sem-foto-ocultar` + `-v2` (59 produtos) e
`catalogo:produtos-sem-categoria-ocultar` (1546 produtos) — escrita concreta e direta, diferente
do padrão Balde A confirmado (só "marcar flag para revisão manual"/"plano de revisão faseada",
sem escrita direta). Classificado Balde B por cautela (regra de ouro: dúvida → B) — não é
dinheiro (não toca pricing/dispatch/wallet/Stripe), é impacto de negócio (produtos deixam de
poder ser comprados) sem precedente de auto-aprovação para "ocultar". **Não confundir com o
padrão já validado de "marcar para revisão"** — dedup_keys parecidos (`catalogo:*`), efeito
proposto diferente; reconhecer `catalogo:*ocultar` como família Balde B em corridas futuras.

**Reconfirmado + dedup_key FUNDIDO (2026-07-27, corrida ~17:22 UTC):** `b454e9bc-b87d-4451-b861-
fc2596a6f652` (dedup_key `catalogo:produtos-sem-categoria-revisao-ocultar`, nível 3, severidade 4,
evidência `count=1546` — idêntica ao item irmão já Balde B `222e0b2b-e691-4074-a52a-f366a77df476`)
funde no MESMO `dedup_key` os nomes dos 2 subpadrões antagônicos (`revisao` = Balde A vs `ocultar`
= Balde B). Classificado Balde B pela intenção final do texto ("marcar para revisão e, após
análise, ocultá-los") e pela evidência batendo com o lote já Balde B — `payload_execucao=null` não
muda a classificação dado nível/severidade altos. Sinal adicional (junto ao bug de dedupe já
descrito acima) de que o gerador de sugestões também mistura rótulos de subpadrões antagônicos no
mesmo `dedup_key` — mesmo bug de robustez do pipeline, não uma nova categoria de dinheiro.
`admin_audit_log` id `9c7cd788-e074-4a88-ab6e-92c0ac5f4f39`.

Detalhe completo desta corrida (2 Balde A aprovados + 28 Balde B, IDs e `admin_audit_log`):
`aprovador-vermelho-historico-corridas.md`, linha 2026-07-27. Relatório:
`.claude/.ai/reports/aprovador-vermelho-2026-07-27-fallback30min.md`.

## Ver também
- `permanente/procedural/aprovador-vermelho-historico-corridas.md` — log corrida-a-corrida
  (partido daqui em 2026-07-20 por tamanho; ver checagem #8 do `bibliotecario-cerebro`).
- `permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md` — anomalia do backoff
  exponencial em `hermes-aprovador-vermelho.sh` (partido daqui em 2026-07-27 por tamanho).
- `permanente/semantica/loops.md` — mecânica do loop (watermark, FALLBACK 30MIN, dedupe).
- `permanente/semantica/backend-map-rpcs.md` — catálogo de nomes de RPC (Dispatch/Estafeta).
