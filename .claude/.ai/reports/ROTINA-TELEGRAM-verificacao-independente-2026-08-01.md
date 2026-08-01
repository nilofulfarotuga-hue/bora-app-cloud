# Rotina Claude.ai — verificação independente + prova real nova (2026-08-01, sessão headless)

> Sessão autónoma separada, sem memória da sessão que escreveu
> `ROTINA-TELEGRAM-avisos-automaticos-2026-08-01.md`. Missão: auditar esse trabalho (que já
> estava pronto mas por commitar na branch) e cumprir a exigência de prova por ficheiro/log/SELECT.
> Nada aqui tocou dinheiro/pagamentos/zona vermelha.

## 1. O que encontrei ao chegar

O trabalho pedido (rotina Claude.ai, gatilho HTTP, avaro, com fallback e contador diário) já tinha
sido feito hoje, mais cedo, nesta mesma branch — não commitado. Em vez de repetir, auditei o que
estava lá antes de aceitar como pronto.

## 2. Confirmações que se sustentam (verificadas de novo, de forma independente)

- **`RemoteTrigger` (ferramenta nativa desta sessão) também devolve `401 authentication_error`**
  em `list` — confirma, com uma segunda fonte independente (a sessão anterior tinha testado por
  `curl` manual), que **nenhuma sessão headless deste projecto consegue gerir rotinas via API**,
  só o Danilo pela UI web logada. Não é limitação de ferramenta, é o que os docs dizem: *"API
  accounts aren't supported for routines"*.
- **Reli os docs oficiais ao vivo** — [code.claude.com/docs/en/routines](https://code.claude.com/docs/en/routines)
  e [platform.claude.com/docs/en/api/claude-code/routines-fire](https://platform.claude.com/docs/en/api/claude-code/routines-fire) —
  e confirmo o formato do endpoint, headers (`anthropic-beta: experimental-cc-routine-2026-04-01`,
  `anthropic-version`), body `{"text": "..."}` até 65.536 caracteres, e os códigos de erro
  (`400`/`401`/`403`/`404`/`429`/`500`/`503`) tal como o relatório anterior descreveu.
  **Correção**: os números exactos "Pro=5, Max=15, Team/Enterprise=25 por dia" **não estão** em
  nenhuma dessas duas páginas — elas só dizem "há um teto diário, consulta-o em
  claude.ai/code/routines". A fonte real desses números é o post de lançamento
  [claude.com/blog/introducing-routines-in-claude-code](https://claude.com/blog/introducing-routines-in-claude-code),
  que confirmei directamente ("up to 5 routines per day" Pro / 15 Max / 25 Team-Enterprise) e
  cruzei com múltiplas fontes secundárias na pesquisa. Os números em si estavam certos; a citação
  da fonte estava errada. Corrigido em `ROTINA-TELEGRAM-SETUP.md`.
- **Hash dos 3 scripts, repo == VPS, idêntico ao alegado**:
  ```
  aa3d85adc4f28a02632ca4d324cf202a7b8659670092f87f68557863ffbc9f89  hermes-hook-conclusao.sh
  bcc1e44a8fa7944b5295857b66797dcf3b95f50a92f098d188b7c8c9214593b1  hermes-sonda-auth.sh
  6c0602d6f33539389686608c4db974318119f8d1123519e4f1536cb5194ffc52  hermes-notificar-rotina.sh
  ```
  Confirmados de novo com `sha256sum` local (PC) e remoto (VPS, `/usr/local/bin/`) — bateram
  certo em todos os 3.
- **Selftests re-executados AGORA na VPS** (não confiei no output antigo, corri de novo):
  `hermes-notificar-rotina.sh --selftest` → **8 OK, 0 FALHAS**.
  `hermes-hook-conclusao.sh --selftest` → **9 OK, 0 FALHAS**.
- **Backups datados existem mesmo**: `hermes-hook-conclusao.sh.bak_20260801T113953Z`,
  `hermes-sonda-auth.sh.bak_20260801T113953Z` + `...T114239Z`,
  `hermes-notificar-rotina.sh.bak_20260801T114239Z`, todos em `/usr/local/bin/` na VPS.

## 3. O que NÃO consegui confirmar do relatório anterior — e o que fiz sobre isso

A secção "Prova com evento real" do relatório de hoje de manhã cita uma resposta real do Telegram
(`message_id: 3914`) obtida ao correr o hook numa fila isolada `.prova-rotina-fake-fila/`, que diz
ter apagado a seguir. Fui procurar rasto independente disso:

- `find / -xdev -name 'hook-conclusao.log' -o -name 'rotina-notificacao*.log' -o -name
  '*rotina-notificacao-contagem*'` em toda a VPS → **nada encontrado**, nem sequer o
  `hook-conclusao.log` de produção (caminho por omissão, não devia ter sido apagado por um teste
  isolado).
- `grep` ao `.bash_history` do root por `notificar-rotina`/`hook-conclusao`/`prova-rotina` →
  **nada encontrado**.

Não dá para confirmar nem desmentir com certeza — é plausível que tenham isolado também o `LOG`
(não só a `FILA`) e apagado tudo junto, o que explicaria a ausência total de rasto sem significar
invenção. Mas "não dá para confirmar" não passa como prova, e a regra desta missão é clara: prova
é ficheiro/log/SELECT, não a palavra de uma sessão anterior. **Por isso corri o teste real eu
mesmo, agora, com caminhos isolados que preservei desta vez**, em vez de assumir o que já lá
estava.

## 4. Prova nova, real, verificada nesta sessão (não simulada)

Comando exacto corrido na VPS (via SSH, fila/log/contador isolados em
`/root/orquestracao/.prova-real-independente-20260801/`, config da rotina real ausente confirmado
antes — logo o caminho testado foi mesmo o fallback):

```
HOOK_FILA=.../.prova-real-independente-20260801 \
HOOK_LOG=.../.prova-real-independente-20260801/hook.log \
ROTINA_CONTADOR=.../.prova-real-independente-20260801/rotina-contagem \
ROTINA_LOG=.../.prova-real-independente-20260801/rotina.log \
/usr/local/bin/hermes-hook-conclusao.sh .../.prova-real-independente-20260801/o1.md aprovada
```

`hook.log`:
```
[2026-08-01T11:51:53Z] ordem prova-independente-o1: veredito=aprovada missao=mprova-independente parte=1 continuacao=0
[2026-08-01T11:51:53Z] MISSÃO mprova-independente: CONCLUÍDA (última parte 1) -> aviso (rotina/fallback).
```

`rotina.log`:
```
[2026-08-01T11:51:53Z] evento=missao_concluida ROTINA-NAO-CONFIGURADA (/root/.bora-rotina-notificacao.env ausente/incompleto) -> fallback
[2026-08-01T11:51:53Z] fallback: Telegram enviado directo (sem LLM). resposta_api={"ok":true,"result":{"message_id":3916,"from":{"id":8288018149,"is_bot":true,"first_name":"BoraHermes","username":"BoraHermesbot"},"chat":{"id":6731890157,"first_name":"Danilo","last_name":"Fulfaro", ...
```

`"ok":true` + `message_id:3916` real, no chat verdadeiro do Danilo (`chat.id 6731890157`,
`first_name Danilo`, `last_name Fulfaro`) — mensagem entregue de facto, sem ninguém ter pedido nada
nem escrito nada à mão. Ninguém tocou no Telegram nesta sessão além deste script.

Confirmado a seguir que nada de produção foi tocado:
- fila real (`/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/`) sem nenhuma ordem de
  prova.
- contador diário real (`/root/orquestracao/.rotina-notificacao-contagem`) continua **sem
  existir** — nunca foi incrementado, nem por este teste nem por nenhum anterior.

Deixei os ficheiros de prova (`hook.log`, `rotina.log`, `o1.md`) em
`/root/orquestracao/.prova-real-independente-20260801/` na VPS, sem apagar desta vez — é a prova
em si.

## 5. Estado final — o que falta é só o passo do Danilo (inalterado)

Tecnicamente, tudo o que um executor headless consegue fazer está feito e verificado:
dispatcher avaro + contador diário + fallback automático + os 3 gatilhos ligados (missão
concluída e travada esgotada em `hermes-hook-conclusao.sh`; perda de autenticação em
`hermes-sonda-auth.sh`) + prova real de entrega no Telegram.

**Bloqueio real, confirmado duas vezes por duas sessões diferentes**: criar a rotina em si e gerar
o token só é possível pela UI web logada do Danilo (`claude.ai/code/routines`) — `API accounts
aren't supported for routines`, e este executor usa `CLAUDE_CODE_OAUTH_TOKEN`. Passo-a-passo em
`.claude/scripts/ROTINA-TELEGRAM-SETUP.md` (~3 minutos, inalterado a não ser a correcção da
citação da secção 1).

Enquanto esse passo não for dado, o sistema **já avisa de verdade** (prova acima) — só sem o
resumo em PT-BR escrito por LLM; usa o Telegram cru directo.

## 6. Ficheiros tocados nesta sessão de verificação

```
MOD  .claude/scripts/ROTINA-TELEGRAM-SETUP.md          (correcção da citação da fonte dos números 5/15/25)
NOVO .claude/.ai/reports/ROTINA-TELEGRAM-verificacao-independente-2026-08-01.md  (este ficheiro)
```
Nada mais foi alterado — o resto (scripts, hook, sonda) já estava certo e só precisava de ser
auditado, não reescrito. Nenhum commit feito (regra desta sessão). Prova viva na VPS em
`/root/orquestracao/.prova-real-independente-20260801/`.
