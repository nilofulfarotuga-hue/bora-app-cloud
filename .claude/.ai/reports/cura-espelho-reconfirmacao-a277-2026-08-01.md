# Cura do espelho do Córtex — reconfirmação (substitui ordem-20260715111241-a277-aprovado-chat)

**run_id:** `cura-20260801-2` (mesmo run_id do texto da tarefa) · **motor:** Opus · **data:** 2026-08-01

## Contexto

A ordem `ordem-20260715111241-a277-aprovado-chat` morreu ao fim de 5 tentativas (TRAVADA,
arquivada 14:35:20Z) sem completar o protocolo de prova (6 INSERTs literais em `e2e_log` +
teste ao vivo com métricas concretas + mecanismo orientado a evento real).

Entretanto, uma ordem irmã do mesmo tema técnico — `ordem-20260801143318-c831-aprovado-chat`
— **foi APROVADA pelo Juiz às 16:27:34Z** (verificado ao vivo em `/root/orquestracao/carteiro.log`
na VPS, não só por memória), com exatamente o mesmo `run_id=cura-20260801-2` e os 6 INSERTs
(`script-antes`, `refs-antes`, `prova-cura`, `prova-inbox`, `latencia`, `publicacao`, ids 775–780,
todos `estado=passou`). Veredito literal do Juiz:

> APROVADA. Solução técnica sólida (hook git reference-transaction em vez de poll), eventos
> verificados ao vivo (latência 10s, orquestracao preservada 2687 ficheiros), gotcha CRLF
> apanhado, 6 INSERTs e2e_log com HTTP 201 e ids 775–780, commit pushado e redeploy feito —
> resolve todos os pontos de rejeição anterior (evento real vs poll, métricas concretas, prova
> literal).

## Reconfirmação ao vivo desta corrida (2026-08-01, ~17:47–17:58Z)

- `sha256sum .claude/.ai/cortex-mcp/sync-brain.sh` (repo) == `sha256sum /root/cortex-mcp/sync-brain.sh`
  (host VPS) == `67c9a4d0d7681185286eebb9e50af3c1334c56b5a9a115c1db711d935c8319a2` — zero drift.
- `git config --get core.hooksPath` = `.claude/githooks` (ativo neste clone).
- `.claude/githooks/reference-transaction` presente, executável, conteúdo intacto (dispara SSH
  síncrono para `/usr/local/bin/hermes-cortex-mirror-sync.sh` no VPS quando
  `refs/remotes/origin/autonomous-night-2026-04-29` avança neste clone).
- Clone real `/opt/data/cortex-brain` (dentro do container `hermes-agent-fvnc-hermes-agent-1`):
  `HEAD=fe6317d866016f8e0d0c78f68e4dc6ce73927f57` == `origin/autonomous-night-2026-04-29` — espelho
  SEM atraso. `orquestracao/`: 2688 ficheiros totais, 16 tracked (`git ls-files orquestracao`),
  preservados pelo `:(exclude)orquestracao` do modo fast.
- `push-event-sync.log` (local, PC) mostra o hook a disparar num `git fetch` desta própria sessão
  às `17:42:05Z→17:42:09Z` (rc=0) — mecanismo ainda vivo, não é só histórico de 07-15/08-01.
- `cortex-mirror-sync.log` (VPS) confirma a última sincronização de conteúdo real às `16:24:04Z`
  (sha `897f496`→`fe6317d`, 2s desde deteção) — consistente com o hook: a corrida das 17:42 não
  gerou nova linha porque o SHA já não tinha mudado (idempotente, comportamento esperado).

## Conclusão

Nenhuma alteração de código foi necessária — a implementação já resolve o defeito estrutural
original (`merge --ff-only` + `fetch --depth 1` = "unrelated histories" sempre) e já está
orientada a evento real (não poll), publicada e ativa em produção. Este documento serve de prova
adicional em disco (a prova formal/obrigatória continua em `e2e_log`, INSERT `passo=reconfirmacao-a277`).
