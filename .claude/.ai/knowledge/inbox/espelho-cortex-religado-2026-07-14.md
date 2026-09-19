---
id: espelho-cortex-religado-2026-07-14
tipo: relatorio
zona: verde (conteudo do Cortex copiado add-only via scp/tar; zero git push, zero commit, zero build)
criada: 2026-07-14
autor: claude code (executor loop, ordem-20260714153321-94ec)
---

# Espelho do Cortex "parado" — diagnóstico + fix (sem tocar Lista Vermelha)

## Resumo (uma linha)
ESPELHO CORTEX religado + relatórios de hoje visíveis: **sim**. Causa raiz **não** foi o
serviço do Cortex reiniciar — foi o `git push` do PC para o GitHub, que está bloqueado por
razões de infraestrutura já conhecidas ([[project_headless_push_credential]]), acumulando
~30 commits (e dezenas de ficheiros nunca sequer commitados) que nunca chegaram ao `origin`
de onde o espelho da VPS puxa.

## O que estava a acontecer (hipótese do pedido vs. realidade)

**Hipótese do pedido:** a ordem `79e8` de hoje reiniciou o serviço do Cortex e o processo de
espelho não voltou a arrancar.

**Verificado e descartado:** `docker inspect cortex-mcp` mostra `StartedAt=2026-07-09T06:15:45Z`
— o container **nunca reiniciou hoje**. A ordem `79e8` pedia para **desligar o gate de
aprovação humana** do `cortex_nova_ordem` (rotear tudo para a fila normal em vez de
`aprovacao_admin`) e fazer redeploy — foi **corretamente recusada** pelo executor que a
processou (`saida.txt`: `CONFIRMACAO NECESSARIA: remover o gate de aprovação humana...
recusado`). Zero código alterado, zero redeploy, zero restart. Registo cruzado com
[[project_zona_vermelha_gate_pressure_pattern]] (mais uma tentativa de enfraquecer o gate,
desta vez sob o disfarce de "ordem legítima bloqueada por engano").

## Causa raiz real

1. **Mecanismo de sync está saudável:**
   - Cron `30 6 * * *` (Lisboa) faz `sync-brain.sh hard` (fetch + `git reset --hard origin/…`)
     — a rede de segurança diária. Log confirma corridas todos os dias, inclusive hoje
     (`brain @ ba93c4b (modo=hard)`, correspondente ao HEAD do `origin` de ontem à noite).
   - Container `cortex-mcp` tem `--restart unless-stopped` (já a política correta).
   - `crontab -l` do root tem todas as entradas intactas (06h30 sync, 07h05 nightly, watchdogs
     a cada 5-10 min) — nada foi removido.
   - **Conclusão:** o mecanismo de sync em si não precisa de reparo nem de "reiniciar".

2. **O que estava mesmo parado:** o `origin/autonomous-night-2026-04-29` no GitHub está
   parado em `00c8623` / `2026-07-14T08:48Z` (bump versionCode 426). O `HEAD` local do PC
   (esta sessão) tem **30 commits à frente** (`df1f060`, 16:51) e **dezenas de ficheiros em
   `inbox/` nunca sequer commitados** (untracked). O espelho da VPS só sabe puxar do
   `origin` — como o `origin` não recebeu nada de novo, não havia nada para o cron ou para o
   `espelho-pull.sh` (sync "fast" por-tarefa) puxarem. Isto **não é um bug de hoje**: é a
   limitação já documentada em [[project_headless_push_credential]] — a sessão headless do
   executor no PC não consegue autenticar o `git push` (GCM/`wincredman` exige sessão
   interativa DPAPI) — confirmada 9x, e a "solução fácil" (instalar PAT/token persistente)
   já foi recusada várias vezes porque **qualquer push a esta branch dispara
   `.github/workflows/build_android.yml` sem filtro de path** — build de produção + upload
   Google Play. Ver [[project_ci_publishes_alpha]] e [[project_zona_vermelha_gate_pressure_pattern]].

3. **Achado secundário (não bloqueia o pedido de hoje, mas fica registado):** o próprio
   `cortex-mcp` (servidor MCP, escrita zona-verde ligada desde 2026-07-08) tenta empurrar
   as suas próprias edições para o `origin` via deploy-key SSH. `docker logs cortex-mcp`
   mostra pushes bem-sucedidos até `2026-07-11T21:13:03Z`, onde levou um
   `! [rejected] (non-fast-forward)` e **não voltou a tentar desde então** — a sua cópia
   local ficou "à frente" de forma órfã. O cron `hard` de amanhã (06h30) vai fazer
   `reset --hard` e descartar essa divergência local automaticamente (autoritário, por
   desenho) — não precisa de intervenção manual, só registo para quem for mexer no
   `server.mjs` no futuro.

## O que apliquei (reversível, zero Lista Vermelha)

Em vez de forçar o `git push` (que dispararia build de produção — recusado 9x antes pela
mesma razão, ver acima), copiei o **conteúdo** que já existe local e legitimamente
commitado/escrito no PC diretamente para o ficheiro-sistema do espelho na VPS:

```
tar czf - .claude/.ai/knowledge | ssh ... 'cd .../cortex-brain && tar xzf - --skip-old-files'
chown -R 10000:10000 .claude/.ai/knowledge   # uid do container cortex-mcp
```

- `--skip-old-files`: **nunca sobrescreve** nada que já exista na VPS (add-only).
- Zero `git commit`, zero `git push`, zero toque em `.git/`, zero CI disparado.
- `git reset --hard` de amanhã **não apaga** estes ficheiros (são *untracked* no clone da
  VPS; `reset --hard` só mexe em ficheiros *tracked* — confirmado lendo `sync-brain.sh`).
- Inbox do espelho passou de 71 para 133 ficheiros `.md` (bateu com o total local).

## Verificação (chamadas reais ao MCP, não suposição)

- `cortex_listar(filtro="inbox")` → `teste-vps-cloudflare-2026-07-14` aparece.
- `cortex_buscar("cloudflare")` → 9 resultados, incluindo `teste-vps-cloudflare-2026-07-14`
  com snippet completo.
- `cortex_buscar("erro-submissao-cadastro")` → 8 resultados: `erro-submissao-cadastro-2026-07-14`
  (v1 a v4) + `cadastro-parceiro-senha-2026-07-14-v2` + as ordens que os geraram.
- `cortex_ler("teste-vps-cloudflare-2026-07-14")` → devolve o conteúdo completo do relatório.

`inbox/credencial-git-restaurada-2026-07-14.md` (citado no pedido) **não existe** — nem no
PC nem em lado nenhum da VPS (procurado `/`, `/opt`, dentro do container). Não é um problema
de sync: esse relatório nunca chegou a ser escrito.

## Auto-restart / resiliência futura (pedido item 4)

Já estava correto, não precisou de mudança:
- `docker run --restart unless-stopped` no `cortex-mcp` (confirmado em `deploy.sh`).
- Crontab do root (`30 6 * * * … sync-brain.sh`) vive no host, sobrevive a qualquer restart
  do container Hermes ou do cortex-mcp — não são a mesma coisa.

## Fica para o Danilo (não é ação minha, é decisão dele)

O fix de hoje é um **penso rápido de conteúdo** — resolve "ver os relatórios de hoje agora".
O fix **durável** (o `origin` ficar mesmo atualizado, sem depender de eu repetir este scp)
só acontece quando os 30 commits retidos no PC chegarem ao GitHub — o que continua a
depender do "vai" do Danilo para o push (que também destrava o chat guiado e o fix do
cadastro de parceiro já prontos, ver [[project_chat_guiado_p1_ja_feito]] e
[[project_erro_submissao_iban_generico_resolvido]]), porque esse push dispara build de
produção. Não repeti o pedido de instalar credencial persistente — já foi recusado 9x pela
mesma razão e continua a ser a decisão certa.
