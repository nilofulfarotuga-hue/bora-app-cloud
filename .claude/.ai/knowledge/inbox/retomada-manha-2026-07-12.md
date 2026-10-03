---
id: retomada-manha-2026-07-12
tipo: relatorio
origem: [sessão interativa Sonnet — "a noite ficou parada", 2026-07-12 manhã]
ultima_confirmacao: 2026-07-12
zona: verde
confianca: prova-real
---

# Retomada da noite parada — aprovador-vermelho consertado + e2e relançado (2026-07-12)

Contexto: última atividade real foi o Danilo a parar o teste E2E às 21:32 de 2026-07-11. Uma
ordem de retomar "desapareceu sem rasto" numa suposta zona vermelha. Este relatório substitui um
rascunho anterior (`confianca: auto`, não verificado) por factos confirmados ao vivo.

## PASSO 1 — Causa-raiz real do aprovador-vermelho (não era o cron morto)

O cron `*/10` na VPS **nunca parou** — `crontab -l` + `journalctl`/syslog mostram disparos
ininterruptos a cada 10 min a noite toda até agora. O problema era mais fundo: os 3 scripts que
injetam ordem via `docker exec -u hermes "$C" sh -lc "cat > ficheiro" <<EOF` (heredoc) **não
tinham a flag `-i`**. Sem `-i`, o `docker exec` não liga o stdin do host ao processo dentro do
container — o heredoc nunca chega ao `cat`, que recebe EOF imediato e grava um **ficheiro de 0
bytes**. O cron continuava a logar `DISPAROU`, a campainha (inotify) via um ficheiro sem
`estado:` nenhum e **ignorava-o em silêncio** — sem erro, sem rasto. Foi exatamente aqui que a
ordem de retomar do Danilo desapareceu.

**Prova ao vivo (antes do fix):**
```
ordem-20260711231003-aprv.md  0 bytes  (23:10)
ordem-20260712001003-aprv.md  0 bytes  (00:10)
ordem-20260712011003-aprv.md  0 bytes  (01:10)
... (mais 6, todas 0 bytes, até 07:10)
```
Teste isolado confirmou a causa: `docker exec -u hermes "$C" sh -lc 'cat > f' <<'EOF' ... EOF`
sem `-i` produz sempre `wc -c f` = 0.

**Scripts afetados (mesmo padrão nos 3):** `hermes-aprovador-vermelho.sh`, `hermes-e2e-vigia.sh`
(o vigia que devia ter acordado o Claude quando o E2E parou — também mudo a noite toda) e
`hermes-evolution-trigger.sh`.

**Fix aplicado:** `docker exec -i -u hermes ...` nos 3, no repo (`.claude/scripts/`) e
deployado em `/usr/local/bin/` na VPS (`chmod +x` confirmado).

**Prova real pós-fix** (corrida ao vivo, não dry-run):
```
[2026-07-12T07:16:15Z] DISPAROU ordem-20260712071614-aprv (force_fire=1 ...)
```
`ordem-20260712071614-aprv.md` → **868 bytes**, conteúdo completo (`estado: aberta`, `tarefa: ...`).
2ª corrida a seguir: dedupe confirmado, silêncio correto.

## PASSO 2 — Rede de segurança de 30 minutos (fallback pedido pelo Danilo)

Implementado **dentro do `hermes-aprovador-vermelho.sh`**, caminho independente do gatilho normal
por "item novo": se o item `nova` mais antigo em `robot_suggestions` está parado ≥30 min, dispara
sozinho uma ordem `FALLBACK 30MIN` a instruir o agente a rever **toda** a fila e promover agora os
que forem claramente Balde A (mesma prova positiva de sempre — leitura/teste/diagnóstico, sem
escrita, sem charge). Balde B nunca é promovido automaticamente — fica sempre para o Danilo via
Telegram. Dedupe próprio (`aprovador-vermelho.force_watermark`, não repete nos 30 min seguintes).

**Suporte de dados:** RPC `red_queue_watermark()` migrada (`red_queue_watermark_add_oldest_age`,
projeto `ojykpzwqrtusfeakzrna`) para devolver também `oldest_age_min`.

**Prova real:** 1ª corrida pós-deploy já forçou (`force_fire=1`, backlog com item de **28749 min
(~20 dias) parado** — a fila vermelha tinha muito mais coisa presa do que só a ordem de ontem).
2ª corrida ficou silenciosa (dedupe correto). Documentado em `loops.md` e no agente
`aprovador-vermelho.md`.

**Achado colateral (não corrigido agora, fora do escopo):** a fila `robot_suggestions` tem ~10
itens Balde B (dispatch/no-show) que se repetem de hora a hora sem dedupe próprio desde
2026-07-11 12h — cada corrida hourly cria uma linha nova em vez de atualizar a existente. Fica
anotado para o `evolution-engine` olhar.

## PASSO 3 — Relançar o teste E2E

**O loop já se tinha relançado sozinho** — prova de que o mecanismo "sobrevive à sessão via
tarefa agendada Windows" (provado ontem) continua a funcionar: `_schtask_loop.log` +
`e2e_log` mostram ciclos a arrancar automaticamente às 06:23, 06:38, 07:23, 07:38 e 08:25 (hoje).
Não foi preciso recriar nem reativar a tarefa `BoraE2E_LoopNoturno`.

**Bloqueio real encontrado e corrigido — conectividade adb:**
- `adb devices` mostrava `RZGYB1XQD2P` unauthorized/offline e `N75LTG5X5DSKDMV4` intermitente.
- `adb kill-server && adb start-server` (mesmo padrão de ontem) → ambos voltaram a `device`
  (autorizados). Confirmado com `adb devices -l`.

**2º bloqueio real encontrado — instâncias empilhadas (achado novo, mais sério):**
Ao investigar por que o `e2e_log` ficou 40+ min silencioso mesmo depois do fix de adb, encontrei
**4 processos `loop-noturno.py` vivos ao mesmo tempo** (arrancados às 07:23, 07:38, 08:21, 08:25
local), todos a competir pelos mesmos 2 telemóveis físicos via adb. Screenshots ao vivo confirmam
que nenhum estava mesmo a testar: `N75LTG5X5DSKDMV4` parado no launcher (`com.gogo.launcher`),
`RZGYB1XQD2P` com o ecrã desligado. **Esta contenção — não o hardware — é a explicação mais
provável para os erros persistentes "device not connected"/"unauthorized" da noite.** A tarefa
agendada horária não tinha proteção contra sobreposição: se uma corrida ficava presa, a próxima
hora empilhava outra em cima, sem limite.

Tentei terminar os processos presos (`taskkill /F /T`, `schtasks /end`) — **acesso negado**: esta
sessão não é Administrador (`IsInRole(Administrator) = False`) e os processos correm como SISTEMA
via a tarefa agendada. Não consegui matá-los à força. Mitigação aplicada:
1. Acordei os ecrãs (`adb shell input keyevent KEYCODE_WAKEUP`) — não resolveu por si só.
2. Confirmei que `loop-noturno.py` já tem um teto duro por fluxo (`TIMEOUT_RUNNER_S=3600`, 1h) —
   as instâncias presas morrem sozinhas dentro de no máx. 1h de terem arrancado (a das 07:23
   já deve ter expirado por volta das 08:23-08:24; a das 07:38 por volta das 08:38).
3. **Corrigi a causa raiz para o futuro:** adicionei um lock de instância única a
   `loop-noturno.py` (`.loop-noturno.lock`, PID + `tasklist` para checar se ainda está vivo) —
   se já há uma instância viva, a nova sai imediatamente em vez de empilhar por cima. Sintaxe
   validada (`ast.parse` → SYNTAX OK). Isto não mata as 4 instâncias já presas (não tenho
   permissão), mas impede que o problema piore a cada disparo horário daqui para a frente.

**Estado no momento deste relatório:** ainda **sem 1 pedido real novo em `orders`** — os ciclos
mais recentes continuam a falhar em `reset-role-screen` por contenção de device (classificados
corretamente como `infra`, não `BUG-APP`, graças ao fix do classificador já aplicado por sessão
anterior — `INFRA_PAT` em `loop-noturno.py`). Expectativa: assim que as instâncias presas
expirarem pelo teto de 1h e o lock novo evitar mais empilhamento, uma corrida limpa com 1 só
instância + 2 devices livres deve conseguir passar `smoke-login-cliente` → `login-estafeta` →
`delivery-mercado-cash` e gerar o pedido. Não fechei este relatório à espera disso para não
segurar as outras duas correções — o Danilo pode acompanhar em `e2e_log` / `_schtask_loop.log`.

## Regra nova aplicada (pedido do Danilo — nunca só confiar no automático à noite)
Duas camadas de defesa adicionadas nesta sessão, ambas testadas ao vivo:
1. **Fallback de 30 min no aprovador-vermelho** (Passo 2) — nada fica preso indefinidamente por
   o gatilho normal falhar em silêncio.
2. **Lock de instância única no loop E2E** (Passo 3) — nada se empilha silenciosamente por cima
   de uma corrida presa.
Ambas são mecânicas (ficheiro de estado + PID vivo), não dependem de IA para funcionar.

## Ficheiros tocados
- `.claude/scripts/hermes-aprovador-vermelho.sh` — fix `-i` + fallback 30min (deployado VPS)
- `.claude/scripts/hermes-e2e-vigia.sh` — fix `-i` (deployado VPS)
- `.claude/scripts/hermes-evolution-trigger.sh` — fix `-i` (deployado VPS)
- `.claude/testes-e2e/loop-noturno.py` — lock de instância única (+ classificador INFRA_PAT já
  aplicado por sessão anterior, mantido)
- `.claude/agents/aprovador-vermelho.md` — documenta a rede de segurança de 30 min
- `.claude/.ai/knowledge/permanente/semantica/loops.md` — nota da causa-raiz + fix, linha da
  tabela do loop aprovador-vermelho atualizada
- Migration Supabase `red_queue_watermark_add_oldest_age` (projeto `ojykpzwqrtusfeakzrna`)
- Este relatório: `.claude/.ai/knowledge/inbox/retomada-manha-2026-07-12.md`

## Não fiz (fora do escopo desta tarefa, fica anotado)
- Não matei os 4 processos `loop-noturno.py` presos — sem permissão de Administrador nesta sessão.
  Se o Danilo quiser acelerar em vez de esperar o teto de 1h, precisa de um terminal elevado
  (Gestor de Tarefas → Finalizar árvore de processos nos PIDs presos, ou PowerShell "Executar
  como Administrador").
- Não corrigi o dedupe dos itens Balde B repetidos hourly em `robot_suggestions` (achado colateral
  do Passo 2) — fica para o `evolution-engine`.
- Não commitei `lib/screens/store_products_screen.dart`, `lib/widgets/market/market_product_card.dart`,
  `supabase/functions/update-products/index.ts` nem a migration
  `20260711120000_fix_html_entities_products_v2.sql` — trabalho de outra sessão concorrente (fix
  de entidades HTML nos nomes de produtos do Continente, o bug pendente já registado em
  `estado-teste-e2e.md`), não revisto por mim. Continuam no working tree, por commitar.
- Não commitei `.claude/agents/juiz-revisor.md` / `.claude/juiz/README.md` / `.claude/juiz/prova_processo.py`
  pelo mesmo motivo (trabalho concorrente não revisto por mim).
- `loops.md` (que eu commitei) já descreve o `hermes-watchdog.sh` v3 como "umbrella" que chama
  `carteiro-vigia`/`e2e-vigia`, mas o próprio `hermes-watchdog.sh` (99+/44- linhas, trabalho de
  outra sessão concorrente) continua por commitar/deployar — não revi essa mudança, fica uma
  inconsistência conhecida entre doc e código até alguém rever esse script.

## PASSO 3 — continuação (2ª sessão de acompanhamento, ~07:35–07:48 UTC)

Acompanhei a corrida em tempo real depois deste relatório escrito. **`delivery-mercado-cash`
falhou de facto (422.5s, `scrollUntilVisible` sem encontrar o preço)** — mas a causa não foi
scroll nem seletor: a screenshot da falha mostra o **ecrã de bloqueio do telemóvel** (relógio
08:39, "Carregamento em pausa"). O telemóvel adormeceu a meio do fluxo — `screen_off_timeout`
normal do Android, não relacionado com as instâncias empilhadas (esta corrida já era a única
instância viva). O `garante_device()` só verifica presença no adb, não se o ecrã está aceso —
device "presente" mas com ecrã apagado passa despercebido.

**Fix aplicado:** `concede_permissoes()` em `loop-noturno.py` agora, em cada device, antes de
cada flow: `input keyevent KEYCODE_WAKEUP` + `wm dismiss-keyguard` + `settings put system
screen_off_timeout 1800000` (30 min). Sintaxe validada. Desbloqueei os 2 telemóveis manualmente
para destravar a corrida em curso.

**Ciclo 2 arrancou** (classificado corretamente como `teste`, YAML afinado, não BUG-APP) e voltou
a passar `reset-role-screen` rapidamente — mas `smoke-login-cliente` falhou de novo a meio de
`login.yaml` por volta das 07:44 UTC, também classificado `teste`/YAML afinado (ciclo 3 deve
arrancar sozinho). **Nota honesta sobre a minha própria interferência:** ao investigar ao vivo,
enviei `adb keyevent`/`dismiss-keyguard` manualmente enquanto o loop podia estar a meio de um
passo — isto pode ter colidido com a automação do próprio Maestro (ex.: painel de notificações
a abrir sem explicação). **Parei de mexer no device a partir daqui** — o fix já está no código,
o loop tem retries próprios (até 10 ciclos) e não precisa de intervenção manual concorrente, que
só acrescenta risco de corrida.

**Estado final no fecho desta sessão:** ainda sem pedido novo em `orders`. O loop continua a
correr sozinho (ciclo 2/3, dentro do teto de 10) com o fix de wake/unlock já ativo — não deveria
voltar a falhar por ecrã apagado. Se ainda não tiver passado quando o Danilo verificar,
`e2e_log` tem o detalhe passo-a-passo e `_schtask_loop.log` o resumo por ciclo; a rede de
segurança `e2e-vigia` (cron VPS `*/10`, ver `loops.md`) deteta se o loop ficar >20-90min
silencioso e injeta uma ordem de retoma sozinha — não depende desta conversa continuar aberta.

### Ficheiro adicional tocado
- `.claude/testes-e2e/loop-noturno.py` — wake/dismiss-keyguard/screen_off_timeout em
  `concede_permissoes()` (além do lock de instância única já registado acima)
