---
id: parser-reset-minutos-2026-07-13
tipo: relatorio
origem: [MODO PROTECAO TOTAL, pedido Danilo, 2026-07-13 noite -- corrigir rl_resume_epoch() para
  aceitar "resets HH:MMam/pm" (com minutos), nao so hora redonda]
zona: verde (infra do carteiro, sem tocar dinheiro/tokens/zona_vermelha)
---

# Parser de reset de rate-limit passa a aceitar minutos (2026-07-13)

## Contexto: como se chegou aqui

Esta ordem é a 7ª mensagem da mesma investigação no mesmo dia. As primeiras 5 pediam, com
enquadramentos diferentes, para enfraquecer/remover o gate de segurança da fila (ver
`inbox/triagem-carteiro-ajuste-2026-07-13.md` e o histórico completo em memória
`project_zona_vermelha_gate_pressure_pattern`) — todas recusadas. A 6ª pedia para "corrigir" o
relógio da VPS e limpar a pausa da ordem `883f` por serem "falsas" — investigação read-only por
SSH provou o contrário: relógio da VPS bate ao segundo com fonte externa (Google HTTP Date), e a
mensagem de bloqueio (`You've hit your session limit · resets 11:50pm (Europe/London)`, 65 bytes)
é um bloqueio genuíno, não um falso-positivo — recusado de novo.

Esta 7ª mensagem já não pede para desbloquear nada à força nem tocar no relógio — pede só para
corrigir o parser `rl_resume_epoch()`, que de facto tinha uma limitação real (não um "falso
rate-limit"): só reconhecia formato de hora redonda ("resets 6pm"), não formato com minutos
("resets 11:50pm"). Quando não casava, caía no fallback defensivo `now+3600`, atrasando a
retomada em ~30min a 1h. Pedido aceite e executado com calma, testado, sem forçar a fila.

## O bug real

`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`, função `rl_resume_epoch()`:

```sh
txt=$(printf '%s' "$1" | grep -oiE "resets[^0-9]*[0-9]{1,2} *(am|pm)" | head -1)
```

A regex só captura `[0-9]{1,2}` seguido diretamente (com espaços opcionais) de `am|pm` — não
contempla `HH:MM`. Para "resets 11:50pm", o `:50` quebra o casamento logo a seguir aos dois
dígitos da hora, a função não extrai `hh`/`ap`, e cai em `echo $((now+3600))`. Foi exatamente o
que aconteceu com `883f`: pausa criada às 22:19:44Z, marcada para expirar às 23:19:44Z (+3600
exato), quando o reset real da Anthropic era ~22:50 UTC (23:50 BST).

## O fix

Regex passa a aceitar grupo opcional `(:[0-9]{2})?`; minutos extraídos separadamente
(`grep -oE ':[0-9]{2}'`) e passados a `date -d "today ${h24}:${mm}"` em vez do `${h24}:00` fixo.
Hora com zero à esquerda (`09`, `08`) passa por `sed 's/^0*//'` antes da aritmética `$((hh+12))`
para evitar que o shell a interprete como octal inválido. A conversão `Europe/London -> UTC`
(BST no verão) continua a ser feita pelo `TZ='Europe/London' date`, que já resolvia isto
corretamente antes — não precisou de lógica extra de fuso.

```sh
rl_resume_epoch(){
  local txt hh mm ap now h24 ep
  txt=$(printf '%s' "$1" | grep -oiE "resets[^0-9]*[0-9]{1,2}(:[0-9]{2})? *(am|pm)" | head -1)
  hh=$(printf '%s' "$txt" | grep -oE '[0-9]{1,2}' | head -1 | sed 's/^0*//')
  mm=$(printf '%s' "$txt" | grep -oE ':[0-9]{2}' | head -1 | tr -d ':')
  mm=${mm:-00}
  ap=$(printf '%s' "$txt" | grep -oiE 'am|pm' | head -1 | tr 'A-Z' 'a-z')
  now=$(date +%s)
  if [ -n "$hh" ] && [ -n "$ap" ]; then
    h24=$hh
    [ "$ap" = pm ] && [ "$hh" != 12 ] && h24=$((hh+12))
    [ "$ap" = am ] && [ "$hh" = 12 ] && h24=0
    ep=$(TZ='Europe/London' date -d "today ${h24}:${mm}" +%s 2>/dev/null)
    [ -n "$ep" ] && [ "$ep" -gt "$now" ] && { echo "$ep"; return; }
  fi
  echo $((now+3600))
}
```

O fallback `now+3600` mantém-se — só entra quando o formato é genuinamente desconhecido ou o
horário calculado já passou hoje (a mesma limitação de "sem rollover para amanhã" que já existia
antes; fora do âmbito deste pedido).

## Selftest (5 casos novos, 17/17 no total)

Testado na VPS real (Linux com tzdata correto) — a 1ª tentativa local no Windows Git Bash falhou
1/17 por o ambiente local não ter zoneinfo `Europe/London` (degrada para UTC), não por bug de
lógica; confirmado correndo o mesmo script via SSH.

```
OK   reset 11:50pm -> minutos preservados (23:50 Europe/London)
OK   reset 9:05am -> minutos preservados
OK   reset 12am -> epoch futuro (meia-noite)
OK   reset 12pm -> epoch futuro (meio-dia)
OK   reset 6pm -> formato hora redonda continua a funcionar
SELFTEST: TODOS OK (17/17)
```

## Deploy

1. Copiado para `/tmp/carteiro_teste.sh` no VPS, selftest correu isolado (não toca fila real) —
   17/17 OK. Ficheiro de teste removido depois.
2. Backup do produção: `/root/orquestracao/carteiro.sh.bak-2026-07-13d`.
3. Deploy para `/root/orquestracao/carteiro.sh` (o que o cron realmente invoca) — sha256
   `cd8aaeaad747...`, selftest confirmado no local de produção — 17/17 OK.
4. Commit + push no repo local, branch `autonomous-night-2026-04-29`.

## Resultado — sem forçar nada

Não limpei `.pausa-rate-limit`, não mudei `883f` para `aberta` à mão. Fiquei só a observar: a
pausa expirou sozinha às 23:19:44 UTC, e o próprio carteiro (nudge do vigia) reabriu `883f`
automaticamente às 23:20:06Z — log real:
```
[2026-07-13T23:20:05Z] PAUSA-RATE-LIMIT: reset atingido — retomo o ciclo
[2026-07-13T23:20:06Z] ordem ordem-20260713221432-883f: reaberta automaticamente (era pausada-rate-limit, reset já passou)
[2026-07-13T23:20:06Z] ordem ordem-20260713221432-883f: aberta (tentativa=0)
```
Às 23:22:43 UTC, `883f` já estava `estado: executando, tentativa: 1`. As restantes 7 ordens
(`a0e1, 80b0, 103b, c6e1, 5f89, 847d, a1e4`) continuam `aberta, tentativa: 0`, à espera do ciclo
normal do carteiro (FIFO, uma de cada vez) — comportamento esperado, não é bloqueio.

---
**PARSER RESET corrigido** (aceita `resets HH:MMam/pm`, além de `resets Hpm`) · **selftest 17/17**
· **fila retomada: sim** (sozinha, sem intervenção manual — `883f` em execução, resto a caminho).
