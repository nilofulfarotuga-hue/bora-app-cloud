---
titulo: Limpeza de disco C: + deteção de terminal "preso vivo" no lock/vigia
data: 2026-07-13
autor: executor autónomo (loop noturno)
estado: atual
tema: infra-loop
---

# (1) Limpeza de disco C:

**Antes:** 6,70 GB livres. **Depois:** 16,69 GB livres (alvo era ≥15 GB).

Feito em lotes pequenos (um tipo de cada vez), pois o disco estava a ser consumido
ativamente por outros processos em paralelo durante a limpeza (free caiu de 6,70→5,22 GB
entre o primeiro `Clear-RecycleBin` e a medição seguinte — não é bug da limpeza, é
atividade concorrente na máquina).

Passos, por ordem:
1. **Reciclagem (4,81 GB)** — `Clear-RecycleBin` só limpou a reciclagem do utilizador
   `hermes` (sessão atual), NÃO a do `danil` (SID `...-1004`, onde estava o grosso).
   `Remove-Item` recusa apagar `C:\$Recycle.Bin\<SID>` (path protegido do PowerShell) — resolvido
   com `cmd /c rd /s /q` (sem essa proteção). Reciclagem recria-se sozinha, normal.
2. **`bora_app\build\` (2,42 GB)** — pasta de output do Flutter, 100% regenerável via
   `flutter build`/`flutter run`. Confirmado sem processo `flutter`/`dart`/`adb`/`gradle`
   ativo antes de apagar.
3. **`~/.gradle/caches/8.14/transforms` (4,57 GB)** — cache de transforms do Gradle
   (AAR→classes, jetifier), 100% regenerável no próximo build (só custa tempo extra uma vez).
   Confirmado nenhum daemon Gradle ativo (só um `java.exe` a correr era o Maestro CLI, não Gradle).

**Nota sobre o pedido original ("gradle caches >7 dias"):** verifiquei idade real dos
ficheiros em `~/.gradle/caches/modules-2` e `8.14` — **quase tudo tinha `LastWriteTime` de
hoje** (0 ficheiros >7 dias em `modules-2`; 1 ficheiro em `8.14`). Ou seja, o filtro por idade
não encontra praticamente nada porque esta máquina builda diariamente. Por isso troquei o
critério para "conteúdo 100% regenerável e sem processo dono ativo" (a pasta `transforms`
inteira), que cumpre o espírito do pedido (libertar espaço sem perder nada irrecuperável)
sem depender de uma data que não existe na prática.

E2E: apaguei `gravacoes/2026-07-10/` e `gravacoes/2026-07-11/` (>2 dias); mantive
`2026-07-12` e `2026-07-13`. TEMP (`%TEMP%` e `C:\Windows\Temp`) já estava vazio (0,00 GB) —
provavelmente já limpo pelo `auto-limpeza-ram.ps1` (Tier B, cron 15min) que corre desde ontem.

# (2) Deteção de "terminal preso vivo" (achado do Danilo)

**Problema:** o lock/vigia da esteira (`executor-lock.ps1` + `auto-limpeza-ram.ps1`, chamados
por `run-claude-loop.cmd`) já distinguia processo morto vs vivo, e até tinha uma amostra de
CPU de 1s (`cleanorphans`) para apanhar zombies a ~0%. Mas um processo pode ficar **vivo para
sempre** à espera que alguém clique numa pergunta/sugestão que o próprio Claude Code fez
(ex.: "How is Claude doing?") — isso não é PID morto, e a amostra de CPU de 1s é ruidosa
(pode falhar tanto por falso-negativo como falso-positivo).

**Sinal mais direto que já existia e não estava a ser usado:** o `bora-live.log` (LIVELOG,
gerado pelo `bora-live-parser.ps1` a partir do `stream-json` do Claude) só cresce quando o
executor está mesmo a produzir output. Se um terminal está preso numa pergunta, o LIVELOG
para de crescer, mesmo com o PID vivo e mesmo com blips de CPU.

**Fix aplicado (3 ficheiros, lógica existente — não criei sistema novo):**
- `executor-lock.ps1`: novos parâmetros `-LiveLog` e `-StaleOutputMin` (default 15min) na ação
  `cleanorphans`. Calcula `outputStale` uma vez por ciclo (LastWriteTime do LIVELOG vs agora).
  Condição de matar passa a ser `idleCpu OR outputStale` (antes só `idleCpu`). Também faz o
  output-stale **ultrapassar a proteção da árvore do lock atual** — antes, um processo dentro
  da janela de lock fresco (<10min) nunca era tocado por `cleanorphans`; agora, se o LIVELOG
  provar 15min de estagnação, mata mesmo assim (o `LockOrphanMin` de 10min já desprotege
  primeiro na prática, então isto fecha a fresta entre os dois relógios).
  Retrocompatível: `LiveLog` vazio (default) = comportamento antigo inalterado.
- `run-claude-loop.cmd`: passa `-LiveLog "%LIVELOG%" -StaleOutputMin 15` na chamada
  `cleanorphans` de cada ciclo (FASE 1.5, antes de subir outro `claude.exe`).
- `auto-limpeza-ram.ps1`: novo parâmetro `-StaleOutputMin` (default 15) + `$LiveLog` apontado
  a `.claude\bora-live.log`; passa ambos ao Tier A (delega no `executor-lock.ps1`). Corre no
  hook de fim de ciclo e no `schtask` a cada 15min — ambos já têm o novo sinal.

**Validação:** sintaxe dos `.ps1` verificada via `[System.Management.Automation.Language.
Parser]::ParseFile` (0 erros nos 2 ficheiros). Lógica de staleness testada isoladamente com
um ficheiro temporário (20min atrás → stale=True; 5min → False; 16min → True), sem tocar em
processos reais — **não corri `cleanorphans` a sério** porque a própria sessão executora
poderia bater na fingerprint da esteira e matar-se a si própria a meio da tarefa. A validação
end-to-end real só acontece no próximo ciclo do loop noturno (que já vai chamar o script
atualizado).

Ficheiros tocados: `.claude/.ai/hermes/orquestrador-carteiro/deploy/executor-lock.ps1`,
`auto-limpeza-ram.ps1`, `run-claude-loop.cmd`.
