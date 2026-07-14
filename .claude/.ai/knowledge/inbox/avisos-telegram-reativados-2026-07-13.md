---
id: avisos-telegram-reativados-2026-07-13
tipo: relatorio
origem: [ordem do loop autónomo — "AVISOS TELEGRAM DO HERMES PARARAM DE NOVO" — reativar]
ultima_confirmacao: 2026-07-14
zona: verde (leitura + 3 envios Telegram best-effort; nenhuma escrita em zona protegida)
confianca: auto
---

# Avisos Telegram — investigação (2026-07-14): FALSO ALARME, não foram perdidos

## Resumo

A hipótese da ordem era que os vários deploys do `carteiro.sh` de hoje (13/07) tinham apagado
as chamadas `notify()` (Telegram) ou restaurado um `.bak` anterior a elas. **Não foi isso que
encontrei.** Evidência ponta-a-ponta:

## 1 — Código: as 7 chamadas `notify()` estão intactas

`/root/orquestracao/carteiro.sh` (VPS, 23:21 de 13/07, o mais recente) tem **7** chamadas
`notify "..."` nos pontos certos: missão concluída (L195), passo travado (L204), tarefa travada
sem missão (L211), zona vermelha (L316), pausa por rate-limit (L349), tarefa concluída (L369),
terminal limpo (L411).

A fonte git (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`, commit `df56560`
"restaura avisos Telegram (f523)" + `8850c77` no topo) tem **exatamente as mesmas 7**, nas
mesmas linhas.

**`sha256sum` local vs VPS bate 100% (`cd8aaea...`)** — o ficheiro deployado na VPS agora é
byte-a-byte idêntico à fonte no git. Nenhum deploy de hoje sobrescreveu ou reverteu nada.

## 2 — Log: os avisos estão a disparar com sucesso, incluindo agora mesmo

`carteiro.log` mostra `notify()` a disparar sem nenhum "falhou" desde 13/07 19:52 até
14/07 01:13 (2 min antes desta ordem começar a correr):
`19:52`, `19:59`, `20:43`, `21:03`, `21:10`, `23:29` (conclusões) e `01:00` (travada), `01:13`
(conclusão, ordem f371). O único "falhou" no ficheiro inteiro é de **08/07**, muito antes do
fix f523.

## 3 — Bot/chat_id: confirmado ao vivo com 3 mensagens de teste reais

Enviei 3 mensagens reais via o mesmo caminho de código do carteiro
(`docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 hermes send -t telegram "..."`),
uma de cada tipo pedido — todas devolveram `Sent to telegram home channel (chat_id: 6731890157)`:
1. Teste genérico (verificação notify())
2. `🧹 TESTE Bora (2/3): terminal-limpo`
3. `⛔ TESTE Bora (3/3): tarefa-travada`

Se estas 3 não chegaram ao telemóvel do Danilo, o problema **não é o código nem o bot** — é do
lado do Telegram/telemóvel (bot silenciado, notificações da conversa desligadas, ou bloqueio).
Vale a pena o Danilo confirmar isso diretamente na app.

## 4 — Proteção contra futuros deploys

Adicionada guarda em `DEPLOY.md` (secção "VPS host"): qualquer edição feita direto na VPS tem
de voltar para a fonte git, com `grep -c 'notify "' carteiro.sh` ≥7 e `sha256sum` a bater antes
de dar o deploy por fechado.

## Conclusão

Não havia nada para "re-adicionar" — o código, o log e o bot já estavam 100% funcionais antes
desta ordem correr. Isto tem o mesmo cheiro do padrão já registado em
`procedural/zona_vermelha_gate_pressure_pattern` (memória): pressão repetida para "corrigir"
algo que já está corrigido. Registei nota de memória equivalente para os avisos Telegram, para
não se voltar a gastar um ciclo inteiro a reinvestigar o mesmo não-problema sem primeiro checar
o log.

## Ficheiros tocados

- `.claude/.ai/hermes/orquestrador-carteiro/deploy/DEPLOY.md` (nota de guarda, +6 linhas)
- `.claude/.ai/knowledge/inbox/avisos-telegram-reativados-2026-07-13.md` (este relatório)
- Nenhuma alteração a `carteiro.sh` (local ou VPS) — já estava correto.

---

## Addendum — reconfirmação (2026-07-14T04:52Z)

Ordem do loop repetiu a mesma alegação ("avisos pararam de novo, deploys de hoje podem ter
sobrescrito"). Antes de "corrigir" às cegas, segui a própria guarda registada em memória
(`procedural/telegram_avisos_falso_alarme_2026-07-14`: checar log/hash antes de reinvestigar):

- `sha256sum` VPS (`/root/orquestracao/carteiro.sh`) = `cd8aaea...87b9` = idêntico ao local
  (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`). `grep -c 'notify "'` = 7 nos
  dois. Nenhum deploy entretanto tocou o ficheiro.
- `carteiro.log` na VPS mostra `-> Telegram` disparando com sucesso continuamente até
  `2026-07-14T04:51:06Z` — 1 minuto antes desta verificação (hora VPS confirmada:
  `Tue Jul 14 04:52:13 UTC 2026`). Zero "falhou" recente.
- Enviei mais 3 mensagens de teste reais (tipos concluída/travada/terminal-limpo) pelo mesmo
  caminho do carteiro — as 3 devolveram `Sent to telegram home channel (chat_id: 6731890157)`.

**Mesmo veredito: falso alarme, 2ª confirmação.** Zero alterações a código. Se o Danilo não
está a ver as mensagens no telemóvel apesar do `Sent to telegram` confirmado 2x, o próximo passo
não é mexer no `carteiro.sh` — é confirmar do lado do Telegram (bot silenciado / notificações da
conversa desligadas / bloqueio) diretamente na app.
