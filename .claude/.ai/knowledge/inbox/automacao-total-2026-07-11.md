---
id: automacao-total-2026-07-11
tipo: relatorio
origem: [missão "automação total" do Danilo, 2026-07-11, executada diretamente por Claude Code
  em sessão interativa — a ordem equivalente na fila (`ordem-...-fb7f`) tinha esgotado 3
  tentativas via pc-loop com saída vazia]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: verificado
---

# Automação total — relatório (2026-07-11)

## Achado principal: o carteiro NÃO estava morto

O sintoma reportado ("ordens em `tentativa: 0` sem serem apanhadas") sugeria carteiro/ponte
mortos. Investigação por SSH (host da VPS, fora do container) mostrou o contrário: a campainha
(`inotifywait`) estava viva, o kill switch `orquestracao_enabled: true`, e o `carteiro.sh`
processava ordens continuamente. O problema real: **a própria ordem desta missão** (e outras 3
menores da mesma noite) ficavam presas num ciclo `aberta → executando → SAIDA VAZIA → reaberta`
porque o executor (`pc-loop`, timeout 900s / 40 turns / $10, modelo opus) não conseguia terminar
tarefas grandes dentro do orçamento por tentativa. Detalhe técnico + regra de diagnóstico em
`wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md`. Houve também, mais cedo na
noite, um erro de sintaxe real no `carteiro.sh` deployado (linha 80) que bloqueou despachos por
um período — já corrigido no commit `84b6e68` (antes desta sessão) e confirmado São nos logs
desde as 19h21.

Dado o executor não conseguir terminar a missão em 15 min, todas as 6 partes abaixo foram
implementadas **diretamente** nesta sessão interativa (SSH à VPS + edição local + deploy),
sem depender do pc-loop.

## Parte 0 — Reviver o carteiro
**Já estava resolvido** antes desta sessão (ver achado acima). Confirmado: campainha viva,
kill switch ligado, carteiro a processar. Nada para reviver — só diagnóstico e confirmação.

## Parte 1 — Evolution-engine acorda na hora — ✅ feito e testado
Novo `hermes-evolution-trigger.sh` (cron host `*/5`, canónico em `.claude/scripts/`). Dispara
quando: (a) ordem nova em `travada`, ou (b) mesma `nota` (motivo do CORRIGIR) repete 2x+ em
ordens tocadas nas últimas 2h. Injeta uma ordem `-evol` na fila pedindo ao evolution-engine para
analisar o caso concreto. Watermark por id evita repetir o mesmo disparo. **Testado:** 1ª corrida
semeou 10 ordens `travada` históricas sem disparar (dívida histórica ≠ evento novo); 2ª corrida
ficou em silêncio como esperado.

## Parte 2 — Aprovador-vermelho com cron de verdade — já existia, verificado saudável
Ao contrário do que a missão presumia ("hoje só corre à mão"), o cron `*/10`
(`hermes-aprovador-vermelho.sh`) **já estava instalado e a disparar** de hora em hora (log
confirma disparos regulares 13h-21h). Nada para criar aqui. **Achado à parte:** a fila
`robot_suggestions` não está a encolher (`count` ficou em 30 nas últimas 2 corridas) — sinal de
que as ordens de triagem que este cron cria também estão presas no mesmo gargalo do executor
900s (mesma causa da Parte 0). Não corrigido nesta sessão — recomendo o Danilo revisitar depois
de decidir o que fazer com o orçamento do executor (dividir tarefas / subir timeout / trocar
modelo).

## Parte 3 — Watchdog mais rápido + vigia de ordens paradas + alerta de crashes — ✅ feito e testado
`hermes-watchdog.sh` atualizado: cadência `0 */2` → `*/10`. +2 checagens: (a) ordem `aberta`
tentativa=0 parada >15min → alarme 🟢Core (o sintoma real de hoje, nunca coberto antes); (b)
crashes REAIS/24h via RPC nova `real_crash_count_24h()` (exclui breadcrumbs/rede/auth — testado:
0 crashes reais nas últimas 24h, dados mais recentes são de 2026-07-09). RPC nova aplicada em
produção + migration local `20260711220000_real_crash_count_24h_rpc.sql`.

## Parte 4 — Carteiro ganha auto-verificação de vida própria ("vigia do vigia") — ✅ feito e testado
Novo `hermes-carteiro-vigia.sh` (cron host `*/5`, **independente** do carteiro/campainha — não
morre junto). Lógica: só reinicia a campainha quando ela está genuinamente morta (`pgrep
inotifywait` falha) **e** há pelo menos indício de ordem parada; se a campainha está viva mas uma
ordem demora (tarefa pesada dentro do timeout normal), NÃO reinicia — evita reinícios
desnecessários que mascarariam o problema real (ver lição da Parte 0). Notifica Telegram só 1x
por episódio de morte (dedupe por ficheiro-sentinela), evitando spam. **Testado:** corrida ao
vivo confirmou "OK: campainha viva, sem ordens paradas" (estado normal atual).

## Parte 5 — Sinais automáticos no daily-pulse — parcialmente feito
- **Tickets de suporte: ✅ feito e testado.** RPC nova `support_tickets_open_count()` (migration
  local `20260711221000_support_tickets_open_count_rpc.sql`) + secção "🎫 Suporte" no
  `daily_pulse.py` + sinal automático se houver ticket >24h sem resposta. Testado: 3 tickets
  abertos, 3 com >24h — aparece corretamente no pulso E no `estado-vivo.md`.
- **`estado-vivo.md` deixou de truncar sinais.** Antes só pegava as primeiras 25 linhas do pulso
  (a secção Suporte ficava de fora por estar mais abaixo); agora sobe para 30 linhas + inclui a
  secção "Sinais" inteira por grep dedicado, para nunca mais depender da ordem/tamanho das
  secções acima.
- **Testadores 12×14d: NÃO feito** (honesto, não forçado). A service-account key do Play Console
  Developer API só existe localmente no PC (`Downloads/boraapp-d2bea-*.json`, ver memória
  `project_play_console_api.md`), não no VPS — mover ou copiar uma credencial sem confirmação
  explícita do Danilo não me pareceu prudente para uma automação de baixo risco/baixa urgência.
  Documentado como pendência explícita em `estado-vivo.md § Pendências`. Próximo passo sugerido:
  tarefa agendada do Windows local (não VPS) que lê a key já existente e escreve um sinal simples
  que o daily-pulse do VPS possa ler.

## Parte 6 — Monitor visual automático no runner E2E — ✅ feito (não testado ao vivo)
`runner.py` (`main()`) agora abre `monitor-bora.cmd` automaticamente (via `subprocess.Popen`,
não-bloqueante, `try/except` para nunca travar o teste) assim que os dispositivos são detetados,
antes de correr os fluxos. **Não testado ao vivo** porque o teste E2E está parado de propósito
(instrução explícita do Danilo de não mexer) — a mudança só ativa na próxima corrida manual.

## Registo
- Constituição: princípio #12 "maestro-que-nunca-dorme" gravado em `constituicao.md`.
- Loops: 2 loops novos (`evolution-trigger` 🟡, `carteiro-vigia` 🟢) + `Watchdog Hermes` (v1→v2)
  + `daily-pulse` (v2→v3) atualizados em `loops.md`, com nota narrativa do lote completo.
- Lição: `wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md` — distinção entre
  "mensageiro morto" e "mensagem grande demais para o orçamento", regra de diagnóstico em 4
  passos.
- Ordens da fila resolvidas (paravam de retentar em loop): `f6aa` (arquivada, superada),
  `ccf5`, `e750`, `82db` (aprovadas — trabalho já feito ou confirmado nesta sessão), `fb7f`
  (aprovada — esta missão).

## Scripts/migrations novos (canónico no repo)
- `.claude/scripts/hermes-evolution-trigger.sh`
- `.claude/scripts/hermes-carteiro-vigia.sh`
- `.claude/scripts/hermes-watchdog.sh` (atualizado)
- `supabase/migrations/20260711220000_real_crash_count_24h_rpc.sql`
- `supabase/migrations/20260711221000_support_tickets_open_count_rpc.sql`
- `.claude/testes-e2e/runner.py` (atualizado, +6 linhas)
- Deploy espelhado em `/usr/local/bin/` no host da VPS + `daily_pulse.py` atualizado dentro do
  container (`/opt/data/hermes/socio-ai/`, sem cópia canónica local — arquivo vive só no VPS,
  como já era antes desta sessão).

## O que NÃO foi tocado (por instrução explícita)
- O teste E2E em si (`run-tudo.cmd`, `loop-noturno.py`) — fica parado, de propósito.
- Nenhuma zona 🔴 (Stripe/pricing/tokens/dispatch) — nada nesta missão tocava dinheiro.
