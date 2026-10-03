# Convenções da esteira de orquestração (FASE 1.7 — 2026-07-12)

Regras para escrever ordens que **não** queimam a conta nem estouram o timeout.

## Regra de tamanho de ordem (anti rate-limit / anti-timeout)

- **1 ordem = 1 objetivo pequeno** — algo que o executor fecha em **≤ 15 min** de trabalho real.
- **Trabalho grande = PÁGINA DE MISSÃO**, não uma ordem gigante. A missão tem passos pequenos
  encadeados (o carteiro dispara o próximo quando o anterior fecha `aprovada`).
- Uma ordem que **estoura os 900s** (timeout do executor) → o carteiro marca
  `nota: ⏱️ TIMEOUT-900s` e, ao 2.º timeout, **TRAVA com sugestão de dividir** — **nunca**
  re-tenta a mesma coisa 5×. Se vês `TIMEOUT` numa nota, **divide a tarefa**, não a re-submetas igual.

## Porquê (incidente 2026-07-12)

5 ordens seguidas morreram porque eram gigantes e auto-referenciais ("reescreve toda a arquitetura
de encadeamento" numa ordem só). Cada uma × até 5 tentativas × 900s × Opus **esgotou o limite de
sessão da conta** a meio da tarde (prova: `b049.saida.txt` = "You've hit your session limit").
Ver `inbox/diagnostico-esteira-2026-07-12.md`.

## Como escrever bem

- **Modelo por tarefa:** põe `[MODELO: OPUS]` no texto só quando é mesmo preciso raciocínio pesado.
  Sem tag → **Sonnet** (default económico). O executor lê a tag e escolhe o `--model`.
- **PROPOSE-ONLY:** começa a tarefa com `[PROPOSE-ONLY: ...]` quando toca zona sensível — o executor
  prepara mas **não aplica/commita**; espera o "vai" do Danilo.
- **Verbos de escrita em zona 🔴** (dispatch/pricing/Stripe/tokens/ledger) → a Trava (T3) manda para
  aprovação humana, não para o loop. Ler/testar essas zonas é verde; **escrever** é vermelho.

## Paredes de segurança (ordem em que travam)

| Parede | Ficheiro / mecanismo | Efeito |
|---|---|---|
| **STOP-TOTAL** | `.pausa-total` na fila | trava carteiro + campainha + os 5 crons |
| **PAUSA-RATE-LIMIT** | `.pausa-rate-limit` (auto) | conta no limite → pausa até ao reset, retoma sozinho |
| **T5 kill switch** | `_controlo.md: orquestracao_enabled` | liga/desliga só o carteiro |
| **T3 zona vermelha** | `zona_vermelha()` | dinheiro + intenção de escrita → humano |
| **T1 teto 5** | `tentativa >= 5` | ordem trava |
| **T2/T4** | budget/turns/tools nos `.cmd` do PC | teto por tentativa |

## Comandos do Danilo

- **Acompanhar ao vivo:** correr `assistir.cmd` na raiz do projeto (tail do `.claude/bora-live.log`).
- **PARAR TUDO:** `touch /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total`
- **RETOMAR:** `rm -f /docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total`
- **Arrancar uma missão:** `bash /root/orquestracao/carteiro.sh --iniciar-missao <id-da-missao>`
