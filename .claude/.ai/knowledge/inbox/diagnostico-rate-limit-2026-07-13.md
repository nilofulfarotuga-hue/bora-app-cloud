---
id: diagnostico-rate-limit-2026-07-13
tipo: relatorio
origem: [diagnostico urgente, 5min, so-leitura, pedido Danilo — ordens f523 e f960 marcadas
  'pausada-rate-limit', 2026-07-13]
zona: verde (so leitura via SSH+docker exec na VPS; nada alterado)
---

# Diagnóstico rate-limit — ordens f523 e f960 (2026-07-13)

**Método:** SSH `root@srv1786862.hstgr.cloud` (chave `/c/Users/danil/.ssh/id_ed25519_vps`) →
`docker exec -u hermes hermes-agent-fvnc-hermes-agent-1` → leitura direta (`cat`, `cat -A`) dos
ficheiros da fila em `/opt/data/cortex-brain/orquestracao/`. Nada foi escrito ou corrigido.

## Texto exato encontrado

**Ordem `ordem-20260713103442-f523`** (criada 10:34:42Z, tentativa 0, autor claude.ai):
```
You've hit your session limit · resets 1pm (Europe/London)
```
(ficheiro `.saida.txt`, 61 bytes, `cat -A` confirma `M-BM-7` = o carácter `·` codificado em
UTF-8 + `^M` de fim de linha CRLF — não é lixo/corrupção, é o middle-dot normal do aviso do
Claude Code). `carteiro.log`: hit detetado ~11:26Z, calculou retoma `12:00 UTC` (1pm
Europe/London = 12:00 UTC, horário de verão BST).

**Ordem `ordem-20260713130657-f960`** (criada 13:06:57Z, tentativa 2, autor claude.ai):
```
You've hit your session limit · resets 6pm (Europe/London)
```
`carteiro.log`: hit detetado 13:22:57Z, calculou retoma `17:00 UTC` (6pm Europe/London = 17:00
UTC). Nota: esta ordem já tinha passado por 1 tentativa vazia (TIMEOUT-2400s/SAIDA-VAZIA) antes
do rate-limit na tentativa 2.

## O rate-limit é real ou é o script a ler mal?

**É REAL.** O texto capturado é a mensagem literal e nativa do próprio `claude.exe -p`
(headless) — o mesmo formato exato que o `limit_watch.py`/`carteiro.sh` foram desenhados para
reconhecer (`hit your session limit`), não uma leitura errada. Não há sinal de falso-positivo:
o padrão de deteção (`is_rate_limit()`) só dispara neste texto específico, que apareceu 2x hoje
com horas de reset diferentes e coerentes com jogadas de 5h.

## Estado ATUAL (18:25 UTC, no momento deste diagnóstico)

- `/opt/data/cortex-brain/orquestracao/.pausa-rate-limit` **não existe** — não há pausa ativa.
- `carteiro.log` mostra: `17:17:01Z PAUSA-RATE-LIMIT: reset atingido — retomo o ciclo`, e desde
  então a fila voltou a processar normalmente (nova ordem `ordem-20260713182230-a73d` aberta às
  18:22:32Z e em execução agora).
- **Conclusão prática:** o rate-limit de ambas as janelas (12:00 UTC e 17:00 UTC) já expirou.
  Neste momento (18:25 UTC) o executor NÃO está bloqueado — está a processar uma ordem nova.

## Por que é que f523 e f960 continuam a mostrar `estado: pausada-rate-limit`?

Bug estrutural encontrado (não corrigido, só reportado — fora do âmbito deste diagnóstico):
quando o `.pausa-rate-limit` global expira, o `carteiro.sh` limpa **só o ficheiro de controlo**
(`rm -f "$PAUSA_RL"`) e o loop principal só processa ordens com `estado: aberta`. A ordem que
estava a ser executada NO MOMENTO exato do rate-limit fica gravada com
`estado: pausada-rate-limit` (linha 280 do `carteiro.sh`) e **nada a devolve a `aberta`** depois
— por isso f523 e f960 ficam congeladas nesse estado para sempre, mesmo com a fila já a
funcionar normalmente para ordens novas. Não é a fila que está presa; é a etiqueta dessas 2
ordens específicas que ficou desatualizada.

## Janelas separadas: executor headless vs. chat interativo do Danilo

Confirmado pelos dois resets (calculados pelo próprio `claude.exe`, não localmente): a janela
que gerou o hit de `f523` tinha reset às 12:00 UTC — ou seja, tinha aberto por volta das ~07:00
UTC (janela de 5h). A segunda janela (hit de `f960`) tinha reset às 17:00 UTC, ou seja abriu
por volta das ~12:00 UTC — **exatamente na hora em que a primeira janela do executor tinha
acabado de resetar**. Isto mostra que o executor headless consome a janela de sessão inteira em
menos de 1h30 de cada vez que reabre (voo de tarefas autónomas back-to-back, `--max-turns 40`
cada), e reabre logo a seguir. A janela do executor começou, portanto, muito mais cedo do que
"agora" (18:25 UTC) nas duas ocasiões em que bateu o limite.

Não há aqui ficheiro/log que prove diretamente se a janela do chat web (claude.ai) é uma pool
de utilização SEPARADA da do Claude Code headless, ou partilhada pela mesma conta/plano — isso
não é observável a partir dos ficheiros locais. O que É observável e resolve a aparente
contradição do Danilo: **neste momento (18:25 UTC) ambos os resets (12:00 e 17:00 UTC) já
passaram há tempo**, logo não há paradoxo — a conta simplesmente já não está limitada em
nenhuma das duas janelas reportadas, e o executor já confirma isso ao processar uma ordem nova
com sucesso (`a73d`, 18:22:32Z).

---

**TEXTO EXATO DETETADO:** "You've hit your session limit · resets 1pm (Europe/London)" (f523,
~11:26 UTC) e "You've hit your session limit · resets 6pm (Europe/London)" (f960, ~13:22 UTC) ·
**É RATE-LIMIT REAL:** sim (foi real nas duas ocasiões de hoje, mas ambas as janelas já
expiraram — não há bloqueio ativo agora; f523/f960 só mostram o estado antigo por bug de
etiqueta não revertida, não porque a conta continue bloqueada).
