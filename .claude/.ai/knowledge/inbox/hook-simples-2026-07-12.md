# Hook simples (c287 SIMPLIFICADA) + retoma do E2E — 2026-07-12

Ordem **c287** (hook de conclusão por evento) estava presa 4/5 tentativas por ser grande demais
(as tentativas anteriores tentavam o pacote inteiro: script + deploy VPS + lançador de missão +
integração total do carteiro). Aplicada a instrução do Danilo: **fazer só a versão MÍNIMA**.

## Parte 1 — Hook mínimo: JÁ EXISTE e PASSA

A versão mínima que o Danilo descreveu **já está escrita** em
`.claude/scripts/hermes-hook-conclusao.sh` — um script bash simples (zero-Opus, corre no HOST),
sem IA sofisticada, que só olha o veredito terminal e age:

- **APROVADA** + missão com próxima parte `pendente` → promove `pendente→aberta` (silencioso).
- **APROVADA** + última parte da missão → Telegram com resumo final.
- **APROVADA** + ordem solta → concluída, silencioso (fim do spam por-ordem).
- **TRAVADA** + `continuacao < 2` → cria ordem de continuação simplificada (continua de onde parou,
  nota do juiz como contexto, 5 tentativas frescas) → silencioso, auto-resolve.
- **TRAVADA** + continuações esgotadas → Telegram (decisão: reformular/arquivar).
- **ZONA_VERMELHA** (dinheiro/destrutivo) → Telegram + espera o Danilo. Nunca auto.

Telegram ao Danilo **só em 2 casos**: (a) missão inteira fechou; (b) precisa de decisão dele
(travada esgotada ou zona vermelha). Caso contrário, silêncio — exatamente o pedido.

**Verificação:** `bash hermes-hook-conclusao.sh --selftest` → **7 OK, 0 FALHAS**
(promoção de parte, fecho de missão, continuação de travada, escalada no teto, conclusão silenciosa
de ordem solta). `bash -n` limpo. **Não foi preciso escrever código novo** — o mínimo já existia; a
c287 empancava só por estar acoplada às pendências grandes (deploy VPS + lançador de missão), que
NÃO fazem parte do mínimo e ficam para um passo separado (o carteiro em prod cai na rede de
segurança do watchdog até o deploy acontecer — sem regressão).

## Parte 2 — E2E parou: diagnóstico e retoma

**Causa raiz (dupla):**
1. O `loop-noturno.py` (schtask SYSTEM `\BoraE2E_LoopNoturno`, PID 5784) estava **pendurado** desde
   10:40 (~27 min sem evento, zero artefactos), preso num subprocesso scrcpy/adb morto — e detinha
   o lock de instância única `.loop-noturno.lock`, o que **impedia qualquer ciclo novo de arrancar**.
2. O device de teste **RZGYB1XQD2P** (single-device: corre todos os papéis) caiu para
   `unauthorized`. Provado que **`adb reconnect` NÃO limpa `unauthorized`** — só
   `adb kill-server && adb start-server` recupera (reusa a `~/.android/adbkey` já autorizada).

**Ações (operacionais, reversíveis — sem tocar código, sem commit):**
- `adb kill-server && adb start-server` → RZGYB1XQD2P voltou a `device`.
- `taskkill /F` no loop pendurado PID 5784 (libertou o lock como órfão) + matados scrcpy zombies
  (PIDs de 07:23–09:38).
- `schtasks /Run \BoraE2E_LoopNoturno` → novo `loop-noturno.py` (PID 12688) **vivo e persistente**
  (>1 min, não é crash-loop). App `pt.boraapp.bora` confirmada instalada nos 2 devices.
- Recuperação adb final → **ambos os devices `device`** (autorizados) no fecho.

**Estado final:** loop E2E vivo e a auto-curar; 2 devices autorizados.

## Nota para o Danilo (não urgente, não é dinheiro/decisão → sem Telegram)
O **RZGYB1XQD2P cai repetidamente para `unauthorized`** (flakiness física do USB — cabo/porta/power
suspend, não software). O loop já trata isto sozinho: o `garante_device` (loop-noturno.py:149-170)
faz kill-server+start-server+reconnect até 15× (~5 min) por ciclo, com a lição já documentada no
próprio código. Se persistir, vale reassentar o cabo USB desse telemóvel. O device estável é o
**N75LTG5X5DSKDMV4**.

## Ficheiros tocados
- **Criado:** este relatório (`.claude/.ai/knowledge/inbox/hook-simples-2026-07-12.md`).
- **Nenhum código alterado.** O hook mínimo já existia e passa; a retoma do E2E foi só operacional
  (adb restart, kill de processo pendurado, relançamento da tarefa agendada). Sem commit/push.
