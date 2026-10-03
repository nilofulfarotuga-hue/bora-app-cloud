# Timeout 3600s — confirmação e correção (2026-07-14)

## Causa confirmada (era exatamente a suspeita)
A ordem `0058` (2400→3600) foi **commitada no repo** (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`),
mas a **cópia LIVE na VPS** (`/root/orquestracao/carteiro.sh`, o ficheiro que o cron realmente executa) **nunca foi
atualizada**. A ordem `ordem-20260714121615-37fe` (aviso de espera via Telegram) travou com `TIMEOUT-2400s x2`
por causa disso — não é um bug de código, é um deploy que faltou.

## Verificação (grep no ficheiro live antes de mexer)
```
root@srv1786862 /root/orquestracao/carteiro.sh:76
  timeout 2400 pc-loop "$(cat /opt/data/orq_task.txt)"
```
Confirmado: **live = 2400s**, repo = 3600s. Divergência total de 4 linhas (1 timeout real + 3 mensagens de log
que citavam "TIMEOUT-2400s" em texto).

## Correção aplicada
1. Backup do live: `/root/orquestracao/carteiro.sh.bak-<timestamp>` (SSH, antes de qualquer escrita).
2. `scp` da versão do repo (já aprovada/commitada) para `/root/orquestracao/carteiro.sh` — sincronização
   completa, não só a linha do timeout, porque havia 3 mensagens de nota também presas em "2400s".
3. `chmod +x` + `bash -n` → sintaxe válida.
4. Diff pós-deploy: **0 diferenças** entre live e repo (só sobra 1 comentário histórico "alargado 900->2400s"
   de 2026-07-13, que é texto de log, não afeta execução).
5. **Não é preciso reiniciar processo nenhum** — `carteiro.sh` não é um daemon persistente; é invocado por
   `cron` (fallback 1x/hora, `17 * * * *`) e por `campainha`/`hermes-carteiro-vigia.sh` (vigia a cada 5 min).
   Cada invocação relê o ficheiro do zero, logo a correção já está ativa na próxima ordem processada.
   (Havia 3 processos `carteiro.sh` já em curso desde 15:28 processando a ordem `61fb` com o valor antigo
   ainda na memória deles — isso é esperado e inofensivo, terminam sozinhos; não foram mortos para não
   perder trabalho em curso.)

## Teste funcional
`time timeout 3600 sh -c 'sleep 2; echo ok'` na VPS confirmou que o mecanismo `timeout` do shell aceita e
respeita 3600s sem cortar tarefas curtas/médias — o valor 3600 está mecanicamente em vigor na linha 76.

## Re-disparo da ordem 37fe
Ficheiro `/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/ordem-20260714121615-37fe.md`:
- backup feito antes de editar
- `estado: travada` → `estado: aberta`
- `tentativa: 2` → `tentativa: 0` (o timeout de 2400s era falha de infra, não da tarefa — não deve consumir
  as tentativas dela)
- `nota:` atualizada a explicar o motivo do re-disparo
- zona: `verde` (feature de aviso Telegram, não mexe em dinheiro/zonas protegidas) — dentro do que o executor
  pode decidir sozinho

A ordem volta a ser apanhada no próximo ciclo do carteiro (cron a cada minuto via campainha / fallback horário).

## Nota para o Danilo
Este é o mesmo padrão de "commitado mas não deployado" que já apareceu antes noutras ordens (CI fix,
push bloqueado, etc.) — a cópia live da VPS não sincroniza automaticamente com o repo. Pode valer a pena,
numa próxima janela, avaliar um passo de deploy automático pós-commit para `carteiro.sh` especificamente
(é o único ficheiro que corre fora do container, direto no host da VPS, por isso escapa aos mecanismos de
sync normais). Não fiz essa mudança agora — fora do pedido, e é uma decisão de arquitetura, não um fix urgente.

TIMEOUT LIVE na VPS agora: 3600s confirmado + 37fe re-disparada.
