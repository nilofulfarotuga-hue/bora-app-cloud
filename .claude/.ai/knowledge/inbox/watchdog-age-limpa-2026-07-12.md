# Watchdog: age e limpa (2026-07-12)

Dois ajustes pedidos pelo Danilo (a foto do Telegram mostrava o watchdog a correr de 10/10 min
certo, mas só a AVISAR de ordens travadas antigas — sem agir — e a encher o Telegram com a
mesma lista). Feito ponta-a-ponta, zona verde.

## PARTE 1 — Arquivar ordens fantasma (fila 15 → 2)

Investiguei as **15 pendentes** da fila (14 `travada` + 1 `zona_vermelha`, todas de 2026-07-11,
`tentativa=5` esgotada). Vivem na VPS em
`/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/ordem-*.md`.

**Arquivadas 13** (`estado: travada → arquivada` + `arquivada_motivo`), todas com trabalho
superado por ordens posteriores:

| Ordem | O que era | Porque é fantasma |
|---|---|---|
| ordem-20260711010350-b992 | ligar aprovador-vermelho como loop | loop já construído (cron `*/10`) |
| ordem-20260711065111-85db | E2E completo 2 telemóveis | cadeia E2E — superada pelas seguintes |
| ordem-20260711111402-1eeb | mudar estratégia (largar telemóvel físico) | idem |
| ordem-20260711130903-caaa | scroll do Continente | idem |
| ordem-20260711134917-224d | continuar E2E (scroll fix) | idem |
| ordem-20260711140101-f20c | diagnóstico reset-role-screen | idem |
| ordem-20260711141648-f7dd | reset-role-screen corrigido, continuar | idem |
| ordem-20260711160110-2a29 | continuar E2E | idem |
| ordem-20260711162849-24db | continuar (ordem f6aa presa) | continuação E2E, superada |
| ordem-20260711192221-fb7f | missão automação total (E2E a correr) | superada pelo loop de hoje (12/07) |
| ordem-20260711223146-9770 | teste heartbeat-browser | superada por 1343 (trocou p/ desktop) |
| ordem-20260711225216-1343 | reconfigurar heartbeat → desktop-app | já construído (dir `heartbeat-desktop/` + inbox) |
| ordem-20260711230752-5d4b | libertar disco no PC | resolvido (loop corre bem hoje; disco VPS 28%) |

**Mantidas 2** (pendências reais, NÃO fantasma):
- `ordem-20260709110949-8448` (`zona_vermelha`) — 2 bugs incl. autocomplete Guarda; precisa de
  **build de produção 🔴** = decisão do Danilo.
- `ordem-20260711161408-7c4f` (`travada`) — **bug real em produção**: nomes de produtos do
  Continente com entidades HTML (`C&atilde;o`→`Cão`). O fix parece estar no working tree local
  (`update-products/index.ts`, `market_product_card.dart`, `store_products_screen.dart`
  modificados) mas por commitar/deploy → trabalho pendente genuíno.

Contagem após: `aprovada 33 · arquivada 16 · cancelada 7 · concluida 2 · executando 1 · aberta 1
· travada 1 · zona_vermelha 1`. A checagem "fila >10 à tua espera" deixa de disparar.

## PARTE 2 — Watchdog v3: deteta → age → só avisa se dinheiro/ambíguo

Reescrito `hermes-watchdog.sh` (canónico em `.claude/scripts/`, deploy espelhado em
`/usr/local/bin/` no VPS). Antes: `send "... — eu só aviso, não ajo"` com a MESMA lista a cada
10 min. Agora:

1. **AGE** (umbrella dos revivedores já existentes — não duplica lógica):
   - container Hermes DOWN → `docker start`;
   - campainha morta / ordem `aberta` t=0 >15min → chama `hermes-carteiro-vigia.sh`;
   - loop E2E parado a meio → chama `hermes-e2e-vigia.sh` (silencioso no TG → o watchdog reporta o ato).
2. **ESCALA só o que precisa de decisão** de dinheiro/ambíguo (sem reviver seguro):
   `zona_vermelha`, `travada` esgotada >12h, disco ≥85%, daily-pulse morto >26h, crashes reais >10/24h.
3. **Anti-spam por assinatura:** hash (`md5`) do conjunto de escaladas gravado em
   `/root/orquestracao/.watchdog.sig`. Só envia Telegram se a assinatura MUDOU. Mesma lista →
   silêncio; fila esvazia → reset (próximo problema avisa na hora). Ações reportam quando ocorrem
   (revivedores têm dedupe próprio).

**Prova (VPS):**
- `bash -n` OK local + VPS; deploy com `chmod +x`.
- 1ª corrida: `acoes=0 escalar=1` (só `zona_vermelha` 8448) → 1 aviso enviado; `.watchdog.sig` gravada.
- 2ª corrida: mesma assinatura → **0 envios** (dedupe provado).
- 7c4f ainda a 11h (mtime) → cruza o teto de 12h em breve e escala **uma vez** (assinatura nova),
  sem repetir. Telegram fica limpo.

## Documentação
`permanente/semantica/loops.md` atualizado: descrição da camada 1 + linha da tabela
(**Watchdog Hermes** v2→v3, "NUNCA age" → "DETETA→AGE→só avisa se dinheiro/ambíguo") + nota de
histórico datada.

## Ficheiros tocados
- **VPS:** 13 `ordem-*.md` (`travada→arquivada`) · `/usr/local/bin/hermes-watchdog.sh` (v3) · `/root/orquestracao/.watchdog.sig` (novo, estado)
- **Repo:** `.claude/scripts/hermes-watchdog.sh` (reescrito v3) · `.claude/.ai/knowledge/permanente/semantica/loops.md` (3 edições) · este relatório
