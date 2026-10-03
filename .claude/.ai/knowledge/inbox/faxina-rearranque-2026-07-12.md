---
id: faxina-rearranque-2026-07-12
tipo: relatorio
zona: verde (infra de orquestração; nada de dinheiro tocado)
criada: 2026-07-12
autor: claude.ai (execução manual da ordem bd3f + instruções diretas do Danilo)
---

# Faxina da fila + zona-VPS + re-arranque limpo da missão

Execução direta das 3 tarefas (ordem `bd3f` + mensagem do Danilo). Loop foi
**pausado** (kill switch) durante a faxina e **reativado** antes de disparar A+B.

## 1) Faxina da fila (container `/opt/data/cortex-brain/orquestracao/`)
- **167 ordens arquivadas** → `orquestracao/arquivo/` (nada apagado):
  - 98 por sufixo — **-evol 42 · -aprv 50 · -e2e 6** (spam do loop auto-referencial)
  - 7 travadas nomeadas — 6188, 29b9, c287, a837, b049, tste, 9a91
  - 2 órfãos da missão — `-A`/`-B` de 18:36 (dispatch velho, substituído)
  - 60 terminais de histórico — aprovada/concluida/cancelada/arquivada/zona_vermelha/travada
- **Fila: 168 → 3** (só `bd3f` [aprovada, fechada manualmente] + A + B novos).
  Única não-terminal antes da faxina era a própria `bd3f`. **Só resta a missão + A/B ativos.**

## 2) Cron do spam parado na raiz — guarda EVOL-1  ✅
Causa: `hermes-evolution-trigger.sh` contava as próprias saídas (`-evol/-aprv/-e2e`)
como "travadas novas" / "nota repetida" → auto-disparo em loop.
- Aplicada a **guarda EVOL-1** nos 3 loops de scan (seed, travadas-novas, find de notas):
  ignora ficheiros `*-evol/*-aprv/*-e2e`.
- Canónico do repo (`.claude/scripts/hermes-evolution-trigger.sh`) + **vivo**
  (`/usr/local/bin/`, backup `.bak-evol1-20260712`). `bash -n` OK.
- `--dry` no vivo → **"sem gatilho — silêncio"**. Cron mantém a função legítima, agora seguro.

## 3) Classificador de zona (VPS)  ✅ 12/12
O carteiro vivo (`/root/orquestracao/carteiro.sh`) já é **idêntico** ao canónico do repo
(md5 `ace105ca…`) — a `zona_vermelha()` corrigida (com `NEG` anti-falso-positivo) **já estava
deployed**. Provado a correr `_zona_fn_test.sh` contra a função viva:
**TODOS OK (12/12)** — 5 verde (teste/leitura de $) + 7 vermelha (escrita real). Falsos-positivos
de zona vermelha resolvidos de vez.

## 4) Re-arranque limpo da missão `missao-plano-mestre-2026-07-12`
- A e B repostos a **pendente**; **E → `adiado`** (E2E não dispara).
- `carteiro.sh --iniciar-missao` → **2 passos disparados**:
  - `ordem-20260712194301-…-A` (SONNET, disco C ≥25GB + avisos Telegram + SA key testers)
  - `ordem-20260712194301-…-B` (SONNET, estabilidade adb/USB)
  - Prefixo real `[MODELO: SONNET]` **sem** `[PROPOSE-ONLY]` → executam. C=PROPOSE-ONLY e D
    encadeiam quando A/B fecharem. Nenhum C/D/E disparado agora.

### Nota (bug cosmético, não corrigido)
No `carteiro.sh`, o `log` usa `${propose:+, propose-only}` que imprime ", propose-only"
sempre que o campo `propose_only` existe (mesmo `nao`). O **prefixo** está correto
(`[ "$propose" = sim ]`), só a linha de log engana. Não crítico — reportado, não tocado.

---
**FILA LIMPA + ZONA-VPS ATIVA + A/B a correr, E adiado.**
