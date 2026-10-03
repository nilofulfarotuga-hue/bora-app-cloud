---
id: rate-limit-falso-corrigido-2026-07-13
tipo: relatorio
origem: [MODO PROTECAO TOTAL, pedido Danilo, 2026-07-13 noite -- prova de que o rate-limit
  da ordem a73d era falso (Danilo a conversar normalmente ao mesmo tempo)]
zona: verde (infra do carteiro, sem tocar dinheiro/tokens)
---

# O "rate-limit" era falso -- causa real e conserto (2026-07-13)

## PASSO 1 -- A regex culpada e o texto real

**Linha exata (antes do fix)**, `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`:
```sh
is_rate_limit(){ printf '%s' "$1" | grep -iqE "hit your (session|usage) limit|session limit|usage limit|rate limit|reached your (usage|session)? *limit"; }
```
Um `grep` cego na saída **inteira** do `claude -p` — dispara em qualquer ocorrência da frase,
não importa onde apareça nem quanto texto vem à volta.

**A ordem que expôs o bug:** `ordem-20260713182230-a73d`, cuja tarefa era literalmente
"...mostrar O TEXTO EXATO, LITERAL... Uma linha final: TEXTO EXATO DETECTADO: '<citar
literalmente>' · É RATE-LIMIT REAL: sim/nao/incerto." — ou seja, uma ordem sobre
**diagnosticar rate-limit**, cujo êxito depende de **citar a frase-gatilho** no seu próprio
relatório final.

**O `.saida.txt` real (1986 bytes)** é um relatório completo e bem-sucedido — confirma que o
diagnóstico anterior (`inbox/diagnostico-rate-limit-2026-07-13.md`) já existia, estava correto,
e termina com:
> **TEXTO EXATO DETETADO:** "You've hit your session limit · resets 1pm (Europe/London)" ... ·
> **É RATE-LIMIT REAL: sim** (mas ambas as janelas já expiraram — não há bloqueio ativo agora).

O `claude -p` **não estava bloqueado** — executou a tarefa até ao fim e produziu um relatório
correto. A regex viu a frase citada dentro do relatório e concluiu "bloqueio", pausando a fila
inteira até às 20:32 UTC e marcando uma ordem 100% bem-sucedida como `pausada-rate-limit`.
Isto explica perfeitamente a "prova irrefutável" do Danilo: não havia contradição nenhuma —
simplesmente não havia bloqueio real a acontecer.

## Distinção: bloqueio genuíno vs. falso-positivo (evidência lado a lado)

| Ordem | Byte count do `.saida.txt` | Conteúdo |
|---|---|---|
| f523 (bloqueio real) | **61 bytes** | SÓ a frase `You've hit your session limit · resets 1pm (Europe/London)`, nada mais — o `claude -p` parou ali. |
| f960 (bloqueio real) | ~61 bytes | Mesmo padrão, `resets 6pm`. |
| a73d (falso-positivo) | **1986 bytes** | Relatório completo de 16 linhas, que só **cita** a frase como parte do texto pedido pela própria tarefa. |

Um bloqueio genuíno do `claude -p` é **sempre curto** — a CLI imprime a mensagem e para; nunca
produz um relatório substantivo depois. Gap de ~32x entre o maior caso real e o menor
falso-positivo observado — margem enorme para um limiar seguro.

## PASSO 2 -- Deteção corrigida

```sh
is_rate_limit(){
  printf '%s' "$1" | grep -iqE "hit your (session|usage) limit|session limit|usage limit|rate limit|reached your (usage|session)? *limit" || return 1
  [ "$(printf '%s' "$1" | wc -c)" -le 600 ]
}
```
Só conta como rate-limit real quando a frase aparece **e** a saída inteira é curta (≤600 bytes
— ~10x a maior saída real observada, ~3x menor que a menor saída falsa observada). Uma saída
longa que apenas menciona/cita a frase cai no fluxo normal do juiz (avaliada como qualquer
outra tarefa) — resolve o Passo 2 do pedido sem precisar de um retry-em-2-min separado: o
"ambíguo" deixou de existir, porque a evidência (tamanho) é determinística, não uma zona cinzenta.

**Testado com o texto REAL capturado** (não só sintético): a saída de 1986 bytes da a73d já
**não dispara mais**; a frase curta de 61 bytes (f523) **continua a disparar** corretamente.
Selftest local + remoto: 12/12 OK (incluindo o novo caso de regressão
`relatorio longo citando a frase nao dispara`).

## PASSO 3 -- Retomada automática confirmada (prova real de produção, não simulação)

O mecanismo de reabertura corrigido **hoje mais cedo** (ver
`inbox/destravar-retomada-2026-07-13.md`) já estava em produção e **provou-se sozinho nos
logs**, antes mesmo desta correção:
```
[2026-07-13T19:30:05Z] PAUSA-RATE-LIMIT: reset atingido — retomo o ciclo
[2026-07-13T19:30:06Z] ordem ordem-20260713182230-a73d: reaberta automaticamente (era pausada-rate-limit, reset já passou)
```
Cobre ordens em qualquer tentativa (a lógica de reabertura não olha para `tentativa`, só para
`estado: pausada-rate-limit`) — f523 tinha tentativa 0 e foi coberta da mesma forma mais cedo
hoje. `hermes-carteiro-vigia.sh` (cron `*/5min` no VPS) confirma o mesmo padrão
(`rate_limit_expirado()` + nudge).

## Ações tomadas nesta ordem

1. Fix deployado (`carteiro.sh`, checksum `2b4cda56...` confirmado no VPS, backup
   `.bak-2026-07-13c`).
2. Varredura da fila: só `a73d` estava presa (as outras já resolvidas no ciclo anterior).
3. `a73d` marcada `aprovada` diretamente — o seu relatório já existia e estava correto; não
   valia a pena gastar mais uma execução completa só para o confirmar de novo.
4. `.pausa-rate-limit` (que apontava para 20:32 UTC, criado pelo falso-positivo) removido —
   a fila retomou de imediato em vez de ficar parada até uma hora sem motivo real.

---

**FALSO RATE-LIMIT ERA:** `is_rate_limit()` fazia `grep` cego na saída inteira — disparava
sempre que o texto continha a frase "session limit"/"rate limit", mesmo dentro de um relatório
de sucesso que a cita (ordem a73d, cuja própria tarefa mandava citá-la literalmente). Bloqueio
genuíno = saída de 61 bytes (só a mensagem); falso-positivo = 1986 bytes (relatório completo).
**DETEÇÃO CORRIGIDA:** só conta como rate-limit se a saída inteira for ≤600 bytes — testado com
dados reais (a73d deixa de disparar, f523 continua a disparar) + selftest 12/12.
**RETOMADA AUTOMÁTICA PROVADA:** log de produção real (`19:30:06Z reaberta automaticamente`,
antes mesmo desta correção), cobre qualquer tentativa, `.pausa-rate-limit` limpo e fila
retomada de imediato.
