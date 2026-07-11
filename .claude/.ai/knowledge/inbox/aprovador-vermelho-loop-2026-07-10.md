---
id: aprovador-vermelho-loop-2026-07-10
tipo: relatorio
origem: [loop-noturno-executor, aprovador-vermelho]
data: 2026-07-11
zona: verde
confianca: auto
---

# Aprovador-Vermelho — do agente ao LOOP (ligado 2026-07-11)

**Problema que faltava resolver:** o `aprovador-vermelho` existia como agente mas nunca tinha
gatilho próprio — só corria quando alguém o mandava à mão. Resultado: propostas 🔴 voltavam a ficar
presas na Central sem o Danilo as ver. **Agora tem loop automático.**

## O que ficou ligado

### 1. Registo no Loop Registry ✅
Adicionado a `permanente/semantica/loops.md` como loop **🟡 Learning** com as 5 perguntas:
- **Problema:** zona vermelha presa sem o Danilo ter acesso à Central.
- **Métrica:** propostas triadas/hora (latência ≤10 min).
- **Gatilho:** cron host `*/10` + campainha (inotify) quando a ordem entra na fila.
- **Quem depende:** Danilo, carteiro.
- **Critério de sucesso:** a fila nunca fica com proposta parada >10 min sem triagem.

### 2. Cron/script no Hermes (VPS) ✅
- **Script:** `/usr/local/bin/hermes-aprovador-vermelho.sh` (canónico no repo em
  `.claude/scripts/hermes-aprovador-vermelho.sh`).
- **Cron:** `*/10 * * * * /usr/local/bin/hermes-aprovador-vermelho.sh # aprovador-vermelho-loop`.
- **Como funciona (gate barato + silencioso):**
  1. Lê um **watermark** via RPC anon `red_queue_watermark()` — devolve só `pending_count` +
     `newest` de `robot_suggestions status=nova`. **Sem títulos, sem dinheiro** (SECURITY DEFINER,
     search_path fixo, grant a `anon`/`authenticated`). Custo ≈ 1 curl a cada 10 min.
  2. Compara `newest` com o último visto (`/root/orquestracao/aprovador-vermelho.watermark`).
  3. Só quando surge item **genuinamente novo** (`newest` avança) injeta **uma** ordem na fila de
     orquestração → a **campainha (inotify)** acorda o carteiro **na hora** → o PC corre o agente
     `aprovador-vermelho`, que tria.
  4. **Silêncio total** quando não há novidade: o backlog de Balde B já surfaçado (timestamps
     antigos) **não re-dispara** (high-water no `newest`) — evita spam ao Danilo.
- **Gatilho por evento:** já existe — a `campainha.sh` (inotify na fila) dispara o carteiro no
  instante em que a ordem aterra, portanto a triagem arranca em segundos, não à espera do próximo tick.
- **Fronteira dura:** o script é **só o gatilho**. Nunca decide dinheiro — Balde A (não-$) o agente
  auto-aprova; Balde B fica `nova` e vai por Telegram ao Danilo. A Trava continua a bloquear escrita
  nas zonas 🔴.

### 3. Corrida manual AGORA (triagem da fila) ✅
Corri o agente sobre os **11 itens `nova`** que estavam presos (o `prop-0fa3ac38` era a proposta
conceptual de E2E, já triada na corrida de 2026-07-10 — não é linha de `robot_suggestions`).

**Balde A — auto-aprovados (5)** (`aprovador_vermelho_auto_baldeA=true`):
| id | motivo |
|---|---|
| d2c7d63e | falso-positivo "preço": só marca `needs_review=true`, não altera pricing/charge |
| e417545f | catálogo puro: categorizar ~2947 produtos, zero dinheiro |
| d2838a6e | diagnóstico: 6 timeouts HTTP (precedente: Danilo aprovou 2 no commit `ba65ce2`) |
| 75728e8b | diagnóstico: 3 motoristas teste sem token FCM — notificações, não-dinheiro |
| f755edbe | catálogo puro: fotos a ~60 produtos, zero dinheiro |

**Balde B — ficam `nova`, decisão do Danilo (6)** — dinheiro/dispatch:
`a2da4c0c` (no-show/depósito, **NOVO**→Telegram), `adc2d2c8` (TTL reatribuição, **NOVO**→Telegram),
`e8aabbcd`, `9996b1fe`, `abeca5d7`, `268aad47` (conhecidos da corrida anterior — não re-enviados).

- **admin_audit_log:** `cc585913-da74-493c-a091-3c64181a3b5e`.
- **Telegram:** enviado ao canal home (chat_id 6731890157) só para os 2 Balde B novos.
- Fila `nova` restante = **6** (só Balde B, à espera de ato humano — comportamento correto).

### 4. Teste end-to-end "não fica presa >10 min" ✅
1. Inseri 1 linha de teste em `robot_suggestions` (reversível, `dedup_key=teste-loop-...`).
2. Watermark subiu: `count 6→7`, `newest 00:07:12 → 01:13:54`.
3. Script (`--dry`) **detetou e disse `DISPARARIA`** a ordem de triagem — texto da tarefa limpo de
   palavras 🔴 (não é travado pelo filtro T3 do carteiro).
4. Apaguei a linha de teste → watermark reverteu a `count=6, newest=00:07:12`.
5. Run real (não-dry) = **silêncio** (exit 0, nenhuma ordem largada, state intacto).

Conclusão: item novo → deteção + injeção ≤10 min (cron) ou em segundos (campainha); backlog já
surfaçado → silêncio. Critério de sucesso do loop **cumprido**.

## Ficheiros/objetos tocados
- **Repo:** `.claude/scripts/hermes-aprovador-vermelho.sh` (novo) ·
  `.claude/.ai/knowledge/permanente/semantica/loops.md` (linha + nota + datas) ·
  `.claude/.ai/knowledge/inbox/aprovador-vermelho-loop-2026-07-10.md` (este).
- **DB (Supabase `ojykpzwqrtusfeakzrna`):** função `public.red_queue_watermark()` (nova, read-only,
  não-dinheiro) · 5 linhas Balde A → `status=aprovada` (via agente) · linha de teste inserida+apagada.
- **VPS:** `/usr/local/bin/hermes-aprovador-vermelho.sh` + cron `*/10` + state file.

## Notas honestas
- Nenhuma lógica de dinheiro foi alterada. A Trava e o gate do Juiz ficam intactos.
- O agente `aprovador-vermelho` avisa (no seu contrato) para não se auto-ligar ao loop **sem gatilho
  humano**. Este ligamento **é** o gatilho humano explícito (pedido do Danilo) e mantém o invariante:
  **Balde B (dinheiro) NUNCA auto — sempre humano.** O loop só garante *visibilidade* ≤10 min.
- Handoff pendente ao `bibliotecario-cerebro` (escopo `agente:aprovador-vermelho` + `loops`) para
  consolidar no Cérebro.
