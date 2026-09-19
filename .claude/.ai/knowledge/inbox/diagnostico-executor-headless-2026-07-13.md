---
ordem: ordem-20260713055426-4833
tipo: diagnostico
data: 2026-07-13
zona: verde (só leitura)
---

# Diagnóstico executor headless (ordem 4833)

## (1) Como a ordem chega ao Claude Code no PC hoje?

**JÁ É HEADLESS, não interativo.** Cadeia real (prova = ficheiros):

1. VPS `carteiro.sh` (`/root/orquestracao/carteiro.sh`, deploy fonte
   `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`) lê `ordem-*.md` da fila e
   chama `pc_exec("$tarefa")`.
2. `pc_exec` invoca o script `pc-loop` (`.claude/.ai/hermes/orquestrador-carteiro/deploy/pc-loop`):
   ```sh
   printf '%s' "$*" | base64 | tr -d '\n=' | ssh -o ProxyCommand="tailscale nc %h %p" \
     -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 hermes@100.71.105.7 \
     "C:\\Users\\danil\\Desktop\\produtividade-ia\\hermes-bridge\\run-claude-loop.cmd --b64stdin"
   ```
   Isto é SSH direto **VPS → PC** via Tailscale (não a chave `id_ed25519_vps` do sentido
   PC→VPS — é o sentido inverso, login `hermes@100.71.105.7`, sshd nativo do Windows).
3. No PC, `run-claude-loop.cmd` (`C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\run-claude-loop.cmd`)
   decodifica a tarefa e corre:
   ```
   claude.exe -p --append-system-prompt "<GUARD>" --output-format stream-json --verbose
              --model <sonnet|opus> --dangerously-skip-permissions
              --max-turns 40 --max-budget-usd 10 < TASKFILE
   ```
   `-p` = **print mode headless**, sem janela, sem chat UI, imune a qualquer popup tipo
   "How is Claude doing" (esse popup só existe na app interativa/desktop, que este comando
   nunca abre).

**Confusão a desfazer:** existe SIM um mecanismo que usa automação de teclado/clique
(`pyautogui`) — `.claude/.ai/hermes/heartbeat-desktop/desktop-send.py`. Mas é um sistema
**separado e não relacionado**: só mantém viva a app PWA do Claude Desktop (heartbeat/keepalive),
correndo via schtask `Bora-heartbeat-desktop` na sessão interativa do Danilo. **Não participa em
nada da execução de ordens da fila de orquestração.** A hipótese da ordem ("o executor depende da
janela interativa") está **errada** para o caminho real das ordens — é headless desde o desenho.

## (2) Por que a 12ec ficou em tentativa 0? O processo local está vivo?

**O processo local está vivo:** `sshd` no Windows = `Running` / `Automatic` (verificado agora).
Não houve falha de entrega da ponte.

**Causa real, confirmada nesta sessão:**
- Às 07:13 (hora desta investigação) a fila VPS tinha **82 ficheiros `-aprv`/`-e2e`** acumulados
  desde 2026-07-12 07:16 — spam de dois crons (`hermes-aprovador-vermelho.sh` e
  `hermes-e2e-vigia.sh`, ambos `*/10min`) que o `carteiro.sh` processa **sequencialmente**
  (`for f in "$FILA"/*.md`, um de cada vez, bloqueante). 12ec/4833/abab foram criadas por
  último (05:46–05:56) — ficaram atrás de dezenas de itens na fila.
- RAM do PC **crítica**: 0.42 GB livres de 3.81 GB no momento da checagem — mesma causa-raiz já
  documentada na noite de 2026-07-12 (`project_ponte_ram_root_cause_2026-07-12`). Isto faz cada
  `claude.exe -p` remoto arrancar devagar ou nunca terminar, e a saída de `Get-Process` mostrou
  **11 processos `claude.exe`** vivos no PC, vários parados desde as 06:30 com CPU quase zero
  30 min depois — sinal de instâncias órfãs presas por falta de RAM, não de janela fechada.
- Ou seja: não foi falha de entrega, foi **fila entupida + RAM esgotada** a bloquear o
  processamento sequencial antes de chegar às ordens novas. (Ação já tomada fora deste
  diagnóstico: crons mortos + 82 ficheiros arquivados — ver relatório da limpeza desta sessão.)

## (3) Migração para `claude -p` headless é viável?

**Já É a arquitetura atual — não há migração a fazer.** `run-claude-loop.cmd` já usa `claude -p`
100% headless (sem GUI, sem clique, `--dangerously-skip-permissions`, `--output-format
stream-json`). O único componente que usa automação de janela/clique (`desktop-send.py`) é do
sistema de heartbeat/keepalive, não do executor de ordens — não precisa (nem faz sentido) migrar
porque o seu propósito É especificamente "provar que a app desktop está viva", o que exige
interação real com a janela.

O que falta não é headless — é **capacidade** (RAM) e **anti-entupimento da fila** (já em curso:
ver reengenharia 2026-07-12, commit `0a89855`). Próximo passo recomendado (fora do escopo deste
diagnóstico, que era só leitura): considerar teto de RAM/lock de concorrência para
`run-claude-loop.cmd` no PC (evitar >1-2 `claude.exe -p` simultâneos) e matar processos órfãos com
CPU ~0 há >10 min.

---

**EXECUTOR HOJE É: headless · MIGRAÇÃO HEADLESS: não aplicável — já é headless desde o desenho
(`claude -p` via SSH VPS→PC); o gargalo real era fila entupida por spam de cron + RAM crítica do PC,
não dependência de janela interativa.**
