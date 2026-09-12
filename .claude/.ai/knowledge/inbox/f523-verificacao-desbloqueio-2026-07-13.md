---
id: f523-verificacao-desbloqueio-2026-07-13
tipo: relatorio
origem: [MODELO SONNET, pedido urgente 5min, ordem-20260713190148-3bf6 -- verificar se f523
  continua presa]
zona: verde (só leitura via SSH + docker exec; nenhuma escrita na fila)
---

# F523 — verificação de desbloqueio (2026-07-13, 19:48 UTC)

## Contexto
A ordem chegou pedindo investigação urgente porque a f523 (criada 10:34 UTC) supostamente
nunca tinha sido re-tentada "quase 20h" depois. Isso já tinha sido diagnosticado e corrigido
mais cedo hoje (ver `inbox/diagnostico-rate-limit-2026-07-13.md` +
`inbox/destravar-retomada-2026-07-13.md`, commit `df56560`) — a hora real agora é 19:48 UTC,
ou seja só ~9h15 desde a criação, não 20h.

## Os 4 pontos pedidos

**(1) FIFO?** Sim. O loop principal usa `for f in "$FILA"/*.md` — glob alfabético, e os
ficheiros chamam-se `ordem-YYYYMMDDHHMMSS-xxxx.md`, logo alfabético = cronológico = FIFO real.
Mas o loop só processa `estado: aberta` (`[ "$(get estado "$f")" = "aberta" ] || continue`) —
ordens mais novas passaram à frente da f523 não por violar FIFO, mas porque a f523 **já não
estava em `aberta`** (estava em `pausada-rate-limit`, um estado que o loop principal ignora).

**(2) Bug tentativa=0 vs já em progresso?** Não é sobre tentativa. Causa raiz confirmada no
diagnóstico de hoje: quando `.pausa-rate-limit` expira, o script só apagava o ficheiro de
controlo — a ordem que estava **em execução no instante exato do hit** ficava gravada em
`pausada-rate-limit` para sempre (nada a devolvia a `aberta`). Aconteceu tanto com f523
(tentativa=0) como com f960 (tentativa=2) — confirmado que não depende do número de tentativas.

**(3) Estado real da f523 agora (lido direto na fila, não cache):**
```
estado: aprovada
tentativa: 0
nota: retomada manualmente 2026-07-13 -- avisos Telegram restaurados
      (conclusao/travamento/fila-vazia), testados e deployados.
```
Já não está presa — foi resolvida manualmente ~9h atrás (mesma sessão do diagnóstico).

**(4) Desbloquear:** não foi preciso — já estava desbloqueada antes desta investigação começar.

## Achado novo (não estava nos relatórios anteriores)
O relatório de hoje mais cedo dizia ter "deployado" o fix de auto-reabertura ao
`carteiro.sh` de produção. Verifiquei os **3 caminhos** onde existe uma cópia do script:
- `/root/orquestracao/carteiro.sh` — **é o que o cron realmente invoca**
  (`17 * * * * bash /root/orquestracao/carteiro.sh # orq-fallback`). 397 linhas, TEM a lógica
  de auto-reabertura (linha 275), modificado 19:42 UTC hoje. ✅ Fix está mesmo ativo.
- Repo local (`bora_app/.claude/.../deploy/carteiro.sh`) — 397 linhas, igual ao de produção.
- `/opt/data/cortex-brain/.claude/.../deploy/carteiro.sh` (dentro do container) — **300 linhas,
  SEM a lógica de reabertura** — é uma cópia espelhada/desatualizada do mirror do Cérebro, não
  o script live. Não afeta o comportamento real (o cron não aponta para lá), mas é uma
  divergência que pode confundir auditorias futuras — vale a pena sincronizar ou documentar
  que aquele caminho não é a fonte de execução.
- `hermes-carteiro-vigia.sh` também confirmado com a deteção `rate_limit_expirado` ativa
  (3 ocorrências).

---

**F523 ESTAVA PRESA POR:** ordem em execução no instante exato do rate-limit ficava gravada em
`pausada-rate-limit` e nada a devolvia a `aberta` (bug já corrigido hoje mais cedo, não
relacionado a FIFO nem a tentativa=0) · **DESBLOQUEADA:** sim (já estava, há ~9h, antes desta
investigação começar) — mecanismo de auto-reabertura confirmado ativo no script real de
produção (`/root/orquestracao/carteiro.sh`, cron `orq-fallback`).
