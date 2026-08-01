# Hook de conclusão POR EVENTO — redesenho do fluxo de conclusão de tarefas (2026-07-12)

**Pedido do Danilo:** o encadeamento de tarefas passa a ser **por EVENTO**, não por ronda de 10 min.
Quando uma ordem TERMINA (aprovada ou travada), o próprio fecho encadeia o próximo passo; só se
escala ao Danilo no fim. "O sistema resolve, não avisa."

## O que mudou (antes → depois)

| | Antes (ronda) | Depois (evento) |
|---|---|---|
| Encadeamento | esperava a ronda/cron para pegar o próximo | o **fecho** da ordem promove já a próxima parte |
| Ordem travada | "⛔ alarme vermelho" ao Danilo a cada ciclo | cria **ordem de continuação** sozinho (até 2×); só escala se esgotar |
| Ordem aprovada solta | Telegram "terminei aprovado" por-ordem (spam) | **silencioso** |
| Telegram ao Danilo | por-ordem (aprovada/travada) | **só 2 casos**: missão inteira fechou · precisa de decisão |
| Watchdog 10 min | mecanismo primário de deteção | **rede de segurança de último recurso** |

## PASSO 1 — Hook de conclusão (mecanismo PRIMÁRIO)
`.claude/scripts/hermes-hook-conclusao.sh` (bash no HOST, **zero-Opus** — não gasta o limite Claude.ai;
o juízo de qualidade já foi feito pelo pc-judge). O `carteiro.sh` chama-o no ponto de veredito
terminal. Decisão:
- **APROVADA** + missão com próxima parte `pendente` → promove `pendente→aberta` (campainha encadeia). Silencioso. → *(a) segue para a próxima ordem pendente da mesma missão*
- **APROVADA** + última parte → **missão concluída** → Telegram resumo.
- **APROVADA** + ordem solta → concluída, silenciosa.
- **TRAVADA** + `continuacao < 2` → cria **ordem de continuação** (continua de onde parou, nota do juiz como contexto, 5 tentativas frescas). Silencioso. → *(b) cria correção automática para continuar até resolver*
- **TRAVADA** + continuações esgotadas → Telegram (reformular/arquivar). → *(c) decisão*
- **ZONA_VERMELHA** → dinheiro/produção/destrutivo → Telegram + espera. Nunca auto. → *(c) decisão*

Equivalente-host do `cortex_nova_ordem`: o hook escreve `ordem-*.md` na fila (o `close_write` toca
a campainha inotify), tal como o MCP faz do lado do Claude.ai.

## PASSO 2 — Encadeamento de missão
**Missão = conjunto de ordens** com o mesmo `missao: <id>` + `parte: <n>`. Ao lançar, só a parte 1
nasce `aberta`; as restantes `pendente` (o carteiro só processa `aberta`). O hook vira a próxima
`pendente→aberta` a cada parte aprovada — encadeamento por **flip de estado**, determinístico, sem
parsear prosa. Não espera ronda.

## PASSO 3 — Telegram só em 2 casos
Toda a notificação passa pelo hook. O `carteiro.sh` **deixou de mandar Telegram por-ordem** (as 4
chamadas `notify` terminais foram substituídas por `hook_conclusao`). Só chega ao Danilo: (a) missão
inteira terminou (resumo), ou (b) decisão (zona vermelha / travada esgotada). Fim do "alarme
vermelho" de travada auto-resolúvel.

## PASSO 4 — Watchdog = rede de segurança de último recurso
O `hermes-watchdog.sh` (`*/10`) **não é alterado no código** — muda de PAPEL: passa a existir só
para o caso de o hook falhar e algo ficar mesmo parado. Continua a apanhar `travada >12h`,
`zona_vermelha` presa, container DOWN, disco, crashes — mas o caminho normal é o hook resolver
**antes**. Se o hook faltar/quebrar, o carteiro loga (`hook-conclusao ausente/erro`) e o watchdog
apanha. Documentado em `loops.md` (secção nova "Conclusão de tarefas: HOOK POR EVENTO + WATCHDOG").

## Ficheiros tocados
- **NOVO** `.claude/scripts/hermes-hook-conclusao.sh` — o hook (com `--selftest` embutido: **7/7 OK**).
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh` — helper `hook_conclusao` + 4 vereditos
  terminais delegam ao hook (removidos os `notify` por-ordem). `bash -n` OK.
- `.claude/.ai/hermes/orquestrador-carteiro/SKILL.md` — secção "Hook de conclusão" + invariante dos 2 casos.
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/DEPLOY.md` — passo de deploy do hook.
- `.claude/.ai/knowledge/permanente/semantica/loops.md` — arquitetura nova + linha no registry + watchdog reenquadrado.

## Verificação
- `hermes-hook-conclusao.sh --selftest` → **7 OK, 0 falhas** (promoção de parte, fecho de missão,
  continuação de travada, escalada no teto, conclusão silenciosa de ordem solta).
- `bash -n` limpo em `hermes-hook-conclusao.sh` e `carteiro.sh`.

## Pendências (deploy + integração — passo humano/loop)
1. **Deploy VPS** (headless não faz push nem alcança o host): copiar `hermes-hook-conclusao.sh` para
   `/usr/local/bin/` (`chmod +x`) e o `carteiro.sh` patched para `/root/orquestracao/`. Até lá, o
   carteiro em produção loga "hook ausente" e cai na rede de segurança (watchdog) — sem regressão.
2. **Lançador de missão** deve passar a criar as ordens com `missao:`/`parte:` e só a parte 1
   `aberta` (restantes `pendente`). O `maestro-autonomia` / `cortex_nova_ordem` ganham esses campos
   num passo seguinte; ordens sem `missao:` já funcionam (encadeamento só não se aplica).
