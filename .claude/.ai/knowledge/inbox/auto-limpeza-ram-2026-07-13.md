# Auto-limpeza RAM/zumbis (2026-07-13)

## Problema

PC de Danilo trava e precisa de reiniciar. Confirmado ao vivo durante esta tarefa: RAM livre
caiu para **~140-220MB** num sistema com 3.9GB totais (`Win32_OperatingSystem.FreePhysicalMemory`),
com 11 processos `claude` a correr em simultâneo (9 do Claude Desktop `WindowsApps\Claude_*` + 2
CLI `claude.exe` do npm — uma delas era esta própria sessão). Não existia nenhum mecanismo
automático a limpar zumbis/RAM entre ciclos do carteiro nem como rede de segurança periódica.

## O que foi criado

1. **`deploy/auto-limpeza-ram.ps1`** — script principal. Base lógica: agente `limpeza-pc`
   (`produtividade-ia\.claude\agents\limpeza-pc.md`), adaptado para correr sozinho (sem
   invocação manual) com 2 tiers de deteção de zumbis + 1 fallback de RAM crítica:
   - **Tier A** (claude/cmd/python): delega em `executor-lock.ps1 -Action cleanorphans`
     (já existente, já testado em produção) — só mata processos com a impressão digital da
     esteira Bora na linha de comando E fora da árvore do dono atual do lock. **Não
     reimplementado** — reutilizado tal como está.
   - **Tier B** (cmd/conhost/python): novo — mata só processos com **processo-pai já morto**
     (órfão real, sinal inequívoco que não depende de fingerprint) e ~0% CPU há >10min.
     **Nunca inclui `claude`** nesta tier — fica só na Tier A já testada, por ser a categoria
     mais sensível.
   - **Fallback RAM crítica** (<300MB livres após as duas tiers): limpa `%TEMP%` e
     `C:\Windows\Temp`, mas **só ficheiros com mais de 15 minutos** (ver bug corrigido abaixo).
     Nunca toca `bora_app\`, `Documents\`, `produtividade-ia\` nem ficheiros de config (lista
     "NÃO APAGA NUNCA" do `limpeza-pc`).
   - Protege explicitamente por `Path` (`WindowsApps\Claude_*` = Claude Desktop, nunca tocado).
   - Log estruturado em `deploy/auto-limpeza-ram.log` (RAM antes/depois, o que foi morto).

2. **`deploy/auto-limpeza-ram.cmd`** — wrapper (mesmo padrão do `run-heartbeat-desktop.cmd`),
   aceita modo como argumento (`hook` | `schtask` | outro).

3. **Hook no `run-claude-loop.cmd`** — chamada `auto-limpeza-ram.cmd hook` adicionada **depois**
   do `claude -p` terminar e do lock ser libertado, antes do `exit /b`. Complementa o
   `cleanorphans` que já corria **antes** de cada ciclo (FASE 1.5) — agora há limpeza no início
   E no fim de cada ordem processada.

4. **Scheduled Task `BoraAutoLimpezaRAM`** — instalada, corre `auto-limpeza-ram.cmd schtask` a
   cada 15 minutos indefinidamente (repetição de 15min por 10 anos), mesmo padrão de
   principal/logon do `Bora-heartbeat-desktop` (`UserId=danil`, `LogonType=Interactive`,
   `RunLevel=Limited`), `ExecutionTimeLimit=5min`, `MultipleInstances=IgnoreNew` (nunca
   empilha se a anterior ainda estiver a correr).

## Bug apanhado e corrigido durante o teste ao vivo

Primeiro teste em modo real (`Remove-Item "$env:TEMP\*" -Recurse -Force` sem filtro de idade)
**apagou o próprio ficheiro de output de uma chamada de ferramenta desta sessão Claude Code**
(erro `ENOENT` visto ao vivo — "another Claude Code process... deleted it during startup
cleanup"). Corrigido: a limpeza de temp agora só apanha ficheiros com `LastWriteTime` há mais
de 15 minutos (`$TempAgeMin`), nunca ficheiros recentes que possam estar em uso por processos
ativos. Reteste confirmou que já não interfere.

## Testes (RAM livre antes/depois, confirmados ao vivo)

| Teste | Modo | Antes | Depois | Tier A | Tier B | Sessão Claude Code / Desktop |
|---|---|---|---|---|---|---|
| 1 (bug) | manual | 146MB | 162MB | KILLED:none | nenhum | sobreviveram, mas partiu output de 1 tool call |
| 2 (fix) | manual | 139MB | 199MB | KILLED:none | nenhum | intactos, sem efeitos colaterais |
| 3 (real) | via schtask (`Start-ScheduledTask`) | — | 214→206MB | KILLED:none | nenhum | intactos, `LastTaskResult=0` |

Em nenhum teste foi morto qualquer processo `claude` (nem Desktop nem CLI) — confirmado
explicitamente via `Get-Process -Id <PID desta sessão>` e contagem dos 9 processos
`WindowsApps\Claude_*` antes/depois de cada teste.

## Nota

RAM livre no sistema já esteve **abaixo de 300MB durante toda a tarefa** — confirma que o
gatilho de "RAM crítica" é real e vai disparar com frequência nas condições atuais do PC.
A causa raiz do consumo (11 processos `claude` simultâneos, 9 deles Claude Desktop) não é
resolvida por este script — ele só evita que **zumbis** e **temp acumulado** piorem a situação;
não mata processos legítimos em uso.

## Ficheiros tocados

- `deploy/auto-limpeza-ram.ps1` (novo)
- `deploy/auto-limpeza-ram.cmd` (novo)
- `deploy/run-claude-loop.cmd` (hook adicionado, comentário FASE 1.6)
- Scheduled Task `BoraAutoLimpezaRAM` (novo, fora do repo)

AUTO-LIMPEZA RAM ATIVA (schtask instalado) OK
