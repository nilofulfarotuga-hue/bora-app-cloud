# Vigília de 10 minutos barata — sem queimar o limite do Claude (2026-07-12)

**Contexto:** Danilo já em ~75% do limite semanal. Objetivo: usar o Hermes (VPS 24/7, IA
barata / zero-IA) como vigia frequente que **só deteta e dispara** — nunca acorda o Claude à toa.

## O que foi feito

### PASSO 1 — cron `*/10` de verificação LEVE (só SQL + bash, sem Opus)
As três checagens do prompt ficam cobertas por vigias baratos no **host da VPS** (não chamam
Opus, não gastam o limite do Claude.ai):

| Check do prompt | Loop responsável | Cron | Estado |
|---|---|---|---|
| (a) `e2e_log` sem escrita >20min = teste parou → tocar campainha p/ retomar | **`hermes-e2e-vigia.sh`** (NOVO) | `*/10` | ✅ criado + instalado |
| (b) ordem `tentativa=0` >15min = carteiro morto → revivê-lo | `hermes-carteiro-vigia.sh` (já existia) | `*/5` | ✅ ativo |
| (c) registo travado crítico via query read-only → criar ordem | `hermes-evolution-trigger.sh` (travadas→ordem) + `hermes-watchdog.sh` (avisa) | `*/5` + `*/10` | ✅ ativos |

**Novo script:** `.claude/scripts/hermes-e2e-vigia.sh` (canónico no repo) → instalado em
`/usr/local/bin/hermes-e2e-vigia.sh` no VPS.
- **1 GET minúsculo** ao PostgREST (`e2e_log?select=created_at&order=created_at.desc&limit=1`,
  tabela anon-legível — a mesma que o `tail_e2e_log.py`/`heartbeat` já leem). Zero custo de IA.
- **Regra:** dispara ⇔ `20 ≤ mins_desde_última_escrita ≤ 90` **E** `last_write ≠ watermark`.
  - `<20min` → loop vivo, não toca.
  - `20–90min` → estava ativo e ficou em silêncio (parou **a meio**) → toca **1x**.
  - `>90min` → parado há muito (terminou/nem arrancou) → não há teste "a meio" p/ retomar → não toca.
- **Ação = tocar a campainha:** injeta 1 ordem `aberta` zona verde na fila (via
  `docker exec -u hermes … cat > /opt/data/cortex-brain/orquestracao/ordem-…-e2e.md`, mesmo
  método do `evolution-trigger`). A campainha (inotify) acorda o PC → o Claude Code retoma o E2E.

### PASSO 2 — só acorda o Claude quando há algo REAL (anti-spam)
- **Dedupe pelo próprio `last_write`** (ficheiro `/root/orquestracao/.e2e-vigia.last_write`):
  enquanto o teste não voltar a escrever, o `last_write` não muda → **não re-dispara**. 1 disparo
  por episódio de silêncio, no máximo. Mesmo padrão watermark do `aprovador-vermelho`/`evolution-trigger`.
- **Seed-sem-disparar no go-live:** semeei o watermark com o `last_write` atual
  (`2026-07-12T06:39:11…`), por isso o episódio de silêncio JÁ existente **não** acorda o Claude
  agora. Só um episódio **novo** (o loop escrever de novo e voltar a cair) dispara. Consistente
  com como o `evolution-trigger` semeia o backlog histórico sem ruído.

**Provas dos testes:**
```
DRY (antes do seed):  DISPARARIA ordem-…-e2e — e2e_log silencioso há 30min (last_write=…06:39…, prev=vazio)
DRY (após o seed):    mins=30 na janela MAS já toquei para last_write=…06:39… — silêncio (anti-spam)
```
→ deteta o caso real **e** fica calado quando já tratado. Exatamente o comportamento pedido.

### PASSO 3 — arquitetura documentada em `loops.md`
Adicionada a secção **"As 3 camadas de vigília (barata → cara)"** + a linha do novo loop 🟣
`e2e-vigia` na tabela + `atualizado: 2026-07-12`:
1. **Watchdog-Hermes** (10 min · SQL+bash · VPS) — só deteta e dispara (dedupe; sem episódio = 0 disparos).
2. **Bora Loop Routine** (1x/hora · carteiro+campainha) — puxa a ordem e corre o esquadrão no PC.
3. **Claude.ai / Claude Code** (só quando chamado) — nunca por cron cego; protege o limite semanal.

### PASSO 4 — prova de cron `*/10` ativo (`crontab -l`)
```
*/10 * * * * /usr/local/bin/hermes-watchdog.sh # watchdog-loops
*/10 * * * * /usr/local/bin/hermes-aprovador-vermelho.sh # aprovador-vermelho-loop
*/10 * * * * /usr/local/bin/hermes-e2e-vigia.sh # e2e-vigia (toca campainha p/ retomar loop E2E parado — automacao-total 2026-07-12)
*/5  * * * * /usr/local/bin/hermes-evolution-trigger.sh # evolution-trigger
*/5  * * * * /usr/local/bin/hermes-carteiro-vigia.sh # carteiro-vigia (vigia do vigia)
```

## Notas
- Custo por tick do `e2e-vigia` = 1 HTTP GET anon ≈ 0. Nada de Opus, nada do limite do Claude.ai.
- O `e2e-vigia` NÃO abre nada de pagamentos — a ordem que injeta di-lo explicitamente e é zona verde.
- Ficheiros: `.claude/scripts/hermes-e2e-vigia.sh` (novo), `permanente/semantica/loops.md` (secção+linha+data).
  Instalação VPS: `/usr/local/bin/hermes-e2e-vigia.sh` + linha de cron + watermark semeado.
