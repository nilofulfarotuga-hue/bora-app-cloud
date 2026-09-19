--- missao ---
id: paridade-auto-vs-manual-2026-07-31
tipo: missao
cor: ⚫ Mission (arquiva ao concluir — loops.md)
estado: em_curso
autor: claude-code (Opus) via CEO-AI
criada: 2026-07-31
dono: maestro-autonomia
zona: verde
--- fim ---

# ⚖️ Missão: Paridade Auto vs Manual

> Corre **em paralelo/antes** de `nunca-mais-travar-2026-07-31`. Aquela trata de **por que a
> fila enchia**. Esta trata de **por que o executor engasga**. Causas diferentes.

## O problema (Danilo, confirmado pela Claude.ai 2026-07-31)
> "A tarefa que vem pelo loop tem de executar **exatamente igual** a eu colar o prompt no
> Claude Code. Não pode travar dizendo que a tarefa é grande."

Hoje não é igual — o caminho automático acrescenta 4 coisas que a sessão interativa não tem:

| | Danilo cola no Claude Code | Ordem pelo loop |
|---|---|---|
| teto de turnos | nenhum | `--max-turns 150` |
| teto de custo | nenhum | `--max-budget-usd 25` |
| timeout | nenhum | 4h (FASE 1.9) |
| **gate do Juiz** | **não existe** | ordem só fecha com linha `VEREDITO` |
| transporte | teclado | b64 → ssh stdin → `.cmd` → parser PowerShell |

**Prova de que o Juiz mata trabalho bom:** `ordem-20260722114449-a1d2-aprovado` (diagnóstico
só-leitura, autorizado pelo Danilo) queimou as 5 tentativas com `⚖️ JUIZ-SEM-VEREDITO`. Idem
`ordem-20260722115159-6244`. Em contraste `ordem-20260722110456-aa42` (curta e concreta) fechou
`aprovada` à 1ª.

**Discrepância a investigar primeiro (pode invalidar o resto):** a FASE 1.10 (commit `572efb1`,
2026-07-17) prometeu que o parser **nunca** devolve 0 bytes — emitiria `EXECUTOR-PAROU:
subtype=… turns=… custo=…`. Mas todas as ordens falhadas de 2026-07-31 (10:20, 16:50, 20:40,
21:20) trazem a nota genérica antiga `SAIDA-VAZIA`. Em 2026-07-20 só o `carteiro.sh` foi
deployado à VPS; o `run-claude-loop.cmd` e o `bora-live-parser.ps1` vivem no **PC**.
Hipótese: o lado do PC nunca recebeu a FASE 1.10. **As notas das ordens têm andado a mentir
sobre a causa real.**

## Partes (uma de cada vez, ~15 min cada)

| # | Parte | Estado |
|---|---|---|
| 1 | Descobrir a verdade e repor a honestidade da nota | ✅ FECHADA (2026-07-31) |
| 2 | Paridade com o caminho manual (tetos = pausa, Juiz não mata) | aberta |

### PARTE 1 — a verdade da nota  ✅ FECHADA
> Relatório: `.claude/.ai/reports/paridade-e-enchente-2026-07-31.md`
> **Veredito: a FASE 1.10 NÃO estava viva no PC** (parser vivo `0f94f9465595` vs repo
> `3afb0de7b248`; `grep -c EXECUTOR-PAROU` = 0; não é CRLF). Achado extra que corrige o
> briefing: os tetos vivos eram **40 turnos / $10**, não 150/$25 — 3.75× mais apertados.
> Deploy feito (hashes vivo == repo). Prova: parser devolve
> `EXECUTOR-PAROU: subtype=error_max_turns turns=150 custo=24.87` (61 bytes, antes 0).
1. **Diff real, não memória.** Comparar o que está VIVO no PC (`hermes-bridge/run-claude-loop.cmd`,
   `bora-live-parser.ps1`) com o commit `572efb1`. Reportar hash/linhas exatas. Confirmar se
   `--max-turns 150` / `--max-budget-usd 25` e o ramo `else { EXECUTOR-PAROU… }` lá estão de facto.
2. Se **não** estiverem: deployar a FASE 1.10 no PC e provar com um `type:result` sem
   `.result`/`.error` a devolver a linha `EXECUTOR-PAROU`.
3. Se **estiverem**: a saída é genuinamente 0 bytes — investigar o transporte (arg/stdin b64,
   `%TEMP%\bora_loop_task.txt`, `claude.exe` no Gestor de Tarefas) e dizer **exatamente** onde
   morre. Não chutar: já houve 2 atribuições erradas de causa. Se não souber, dizer que não sabe.
4. **Regra dura:** nenhuma nota de ordem pode voltar a dizer "tarefa grande demais" sem prova.
- **Prova exigida:** uma ordem real falhada a mostrar a nota específica e verdadeira.

### PARTE 2 — paridade com o caminho manual  `pendente`
1. **Tetos deixam de matar.** Parar por `max-turns`/`max-budget` é **pausa**, não falha → o
   carteiro cria continuação automática com o contexto (mecanismo já existe no
   `hermes-hook-conclusao.sh`, ramo `TRAVADA` + `continuacao < 2`) — silenciosa, sem Telegram.
   Subir o teto de continuações o suficiente para uma tarefa grande terminar; manter teto
   absoluto generoso e registar quando o atinge.
2. **O Juiz deixa de matar.** `JUIZ-SEM-VEREDITO` não consome tentativas da tarefa: re-tenta só
   o juiz (a tarefa não volta a correr); se falhar na mesma → veredito `PENDENTE` e ordem fecha
   como **concluída com revisão pendente**, não `travada`; revisão pendente vai ao daily-pulse,
   zero Telegram. Investigar **por que** o juiz não devolve veredito (rate-limit? modelo? prompt?)
   e corrigir a causa, não o sintoma.
3. **Zona vermelha fica exatamente como está:** notifica 1x e espera. É a única coisa que pára.
- **Prova exigida:** uma tarefa pesada de verdade corrida pelos dois caminhos — (a) colada numa
  sessão interativa, (b) injetada como ordem — a chegar ao mesmo resultado final. (b) pode
  precisar de 2-3 continuações; o que não pode é morrer `travada` onde (a) termina.

## Regras
- Zona **verde**: só infra de orquestração (`carteiro.sh`, `run-claude-loop.cmd`,
  `bora-live-parser.ps1`, hook, juiz). Não tocar em pricing/wallet/tokens/comissões/Stripe/dispatch.
- Divergência **VPS vs repo/PC**: o carteiro corre na VPS, o executor e o parser correm no PC.
  Deployar num lado não é deployar no outro — verificar hash dos dois.
- Antes de commit/push, verificar o que viaja junto na branch (boleia do `paths-ignore`).
- Prova por ficheiro/log/SELECT. Nunca pela palavra do executor.

## Veredito final exigido
1. A FASE 1.10 estava viva no PC, sim ou não? → ⏳
2. A mesma tarefa pesada termina pelos dois caminhos, sim ou não? → ⏳

## Registo de execução
- 2026-07-31 — missão criada; Parte 1 iniciada.
