# Cura do espelho Córtex — MOTOR OPUS, tentativa=3 (2026-08-01)

Ordem: `ordem-20260801143318-c831-aprovado` (sem `-chat`), run_id `cura-20260801-3`.

## Contexto

Tentativa=2 desta ordem (commit `6d61198`) foi **REJEITADA** pelo Juiz às 18:03:16Z:
> "Faltam detalhes em passo 3 (via-preservacao nao explicitada) e passo 6 (latencia-antes
> nao medida, so depois)."

O código/mecanismo já estava correto e publicado desde a tentativa anterior (hook
`.claude/githooks/reference-transaction` + `core.hooksPath=.claude/githooks`, cron
`cortex-mirror-sync-evento` como rede de segurança). Esta corrida **não mudou código** —
corrigiu os 2 gaps de prova apontados, com dados 100% frescos.

## Gap 1 — via-preservação (corrigido)

`sync-brain.sh` linha 35: `git checkout -f FETCH_HEAD -- . ':(exclude)orquestracao'`.
O pathspec `:(exclude)` faz o git ignorar por completo qualquer caminho dentro de
`orquestracao/`, seja ele tracked ou untracked. Teste ao vivo nesta corrida:
- Ficheiro canary novo/untracked sobreviveu ao `fast` sync.
- sha256 de um ficheiro tracked (`missao-lancamento-play-store.md`) idêntico antes/depois.
- 2 ficheiros tracked com apagamento local não commitado (status `D`) continuaram `D`
  depois do `checkout -f` — prova de que o exclude não restaura estado, só ignora o
  caminho inteiro. Ver INSERT `via-preservacao` (id 791) para o detalhe completo.

## Gap 2 — latência antes/depois (corrigido)

Medição real, mesmo commit de teste, duas configurações:
- **Antes** (hook desligado, só cron `cortex-mirror-sync-evento` 1x/min): push
  `857c1d2` às 18:10:49Z → espelho atualizado 18:11:04Z → **15s**.
- **Depois** (hook religado): push `02986a8` às 18:12:18Z → hook disparou 18:12:14Z,
  terminou 18:12:18Z (dentro da própria janela do `git push`) → espelho já mostrava
  `02986a8` na checagem seguinte (+1s) → **latência externa ~0s**, síncrona ao push.

Ver INSERT `latencia` (id 792) para o detalhe completo.

## Prova em `e2e_log` (fluxo=`cura-espelho`, run_id=`cura-20260801-3`)

| id | passo | estado |
|---|---|---|
| 788 | script-antes | passou |
| 789 | refs-antes | passou |
| 790 | prova-cura | passou |
| 791 | via-preservacao | passou |
| 792 | latencia | passou |
| 793 | prova-inbox | passou |

## Estado final

Mecanismo orientado a evento (hook `reference-transaction`) e rede de segurança (cron
1x/min) confirmados ativos e corretos. Nenhuma mudança de código nesta corrida — só
prova literal fresca dos 2 pontos que faltavam. Commit desta corrida publica este
relatório + os 2 markers de teste de latência (`_latencia-antes-marker.txt`,
`_latencia-depois-marker.txt`, deixados como artefacto de prova, não apagados).
