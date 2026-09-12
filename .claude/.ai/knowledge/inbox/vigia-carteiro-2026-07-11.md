# Vigia do vigia (carteiro) — verificado e testado (2026-07-11)

**Tipo:** relatório de execução · **Zona:** 🟢 verde (infra do loop, não toca dinheiro)
**Origem:** fatia da ordem fb7f "automação total" — dividida; esta é **só a PARTE 4** (o vigia do vigia).

## O que se pediu
Um cron simples e separado no Hermes (a cada 5 min) que revive o **carteiro/campainha** quando
ele morre: se a campainha (inotify) estiver morta e há ordens paradas em `tentativa=0` há >15min,
reiniciar sozinho e avisar no Telegram. Testar. Registar em `loops.md`. Só isto.

## Descoberta
A PARTE 4 **já tinha sido construída e implantada** no commit `6b83b84`
(`feat(automacao): evolution-trigger + carteiro-vigia + watchdog rapido…`). Ou seja, uma tentativa
anterior da ordem-gigante fb7f já aterrou este pedaço. Em vez de duplicar, **verifiquei e testei**
o que está no ar.

## Estado atual (confirmado no VPS `srv1786862.hstgr.cloud`)
- **Script:** `/usr/local/bin/hermes-carteiro-vigia.sh` (roda no HOST, independente do container/inotify).
- **Cron:** `*/5 * * * * /usr/local/bin/hermes-carteiro-vigia.sh # carteiro-vigia` — ativo.
- **Cópia canónica no repo:** `.claude/scripts/hermes-carteiro-vigia.sh` — SHA256 **idêntico** ao
  deployed (`a11247a8…f54a`). Em sync.
- **Registo em `loops.md`:** já presente (linha 46, 🟢 Core, dono `Hermes(host)`).
- **Log:** `/root/orquestracao/carteiro-vigia.log`.

## Lógica (como decide "morto")
- **Vivo** = `pgrep inotifywait…orquestracao` de pé **E** sem ordem `estado: aberta` `tentativa=0`
  parada há >15min.
- **Morto** = inotifywait ausente → **reinicia** `campainha.sh` (nohup) + Telegram (1× por episódio,
  dedupe via `.carteiro-vigia.avisado`; o próximo tick saudável apaga o marcador).
- Campainha viva mas ordem parada → NÃO reinicia (é tarefa pesada em curso, não morte) — evita
  reinícios à toa.

## Teste end-to-end (feito agora, real)
1. Matei o `inotifywait` da campainha → confirmei `MORTA`.
2. Corri o vigia à mão. Log:
   - `MORTA: campainha não está viva (inotifywait ausente) — vou reviver por precaução`
   - `REVIVIDA: campainha reiniciada com sucesso (pid novo)`
3. Confirmei **exatamente 1** processo `inotifywait…orquestracao` vivo de novo.
4. `.carteiro-vigia.avisado` criado às 21:52 → **Telegram enviado 1×** (sem spam). ✅
- Gotcha registado: `pkill -f "inotifywait.*orquestracao"` **auto-mata** o próprio shell SSH (a linha
  de comando contém o padrão). Usar `ps -eo … | grep "[i]notifywait"` para inspecionar sem auto-match.

## Ficheiros tocados nesta execução
- **Criado:** `.claude/.ai/knowledge/inbox/vigia-carteiro-2026-07-11.md` (este relatório).
- Nada em `lib/`, nada de dinheiro, sem commit/push.
- No VPS: só ação reversível de teste (matar+reviver a campainha) — estado final = saudável.

## Pendente (outras 7 fatias da fb7f — 1 ordem separada cada, uma de cada vez)
evolution-engine · aprovador cron · watchdog · testadores · tickets · crashes · monitor auto.
