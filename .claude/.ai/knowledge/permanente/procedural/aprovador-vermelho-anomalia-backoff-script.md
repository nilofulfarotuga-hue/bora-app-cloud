---
tema: aprovador-vermelho-anomalia-backoff-script · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-27
---

# Aprovador-Vermelho — anomalia do backoff exponencial em `hermes-aprovador-vermelho.sh`

> Partido de `aprovador-vermelho-triagem.md` em 2026-07-27 pelo `bibliotecario-cerebro`
> (checagem #8 — o ficheiro principal tinha passado de ~24 KB). Este ficheiro cobre só a
> anomalia do script de gatilho (`FALLBACK 30MIN` refirando sem backoff) e o seu histórico de
> fix/regressão — conhecimento de mecanismo/infra, não regras de triagem Balde A/B (essas
> continuam em `aprovador-vermelho-triagem.md`).

## Anomalia conhecida — FIX aplicado no repo, PENDENTE DE DEPLOY na VPS (2026-07-13)
`hermes-aprovador-vermelho.sh` disparava `FALLBACK 30MIN` sempre que o item `nova` mais antigo
ficava parado ≥`STALE_MIN` (30 min) **e** o cooldown do `STATE_FORCE` também era `STALE_MIN`
(30 min) — ou seja, o mesmo valor servia de gatilho e de cooldown, então enquanto os 5 itens
Balde B continuassem por decidir na Central, o script refiria para sempre a cada ~30 min (13
reconfirmações idênticas confirmadas em `admin_audit_log` até 2026-07-13, item mais antigo parado
~20,9 dias desde 2026-06-22 — muito antes do próprio FALLBACK_30MIN existir, criado 2026-07-12).
Zero risco de dinheiro (Balde B nunca é promovido sozinho), mas era execução de agente
desperdiçada + ruído em `admin_audit_log`/inbox. Reportado 9+ vezes pelo próprio agente sem
correção aplicada — fora do mandato de roteamento dele.

**Correção aplicada (13ª/16ª corrida, 2026-07-13):** backoff exponencial no ficheiro canónico do
repo `.claude/scripts/hermes-aprovador-vermelho.sh` — novo `MAX_BACKOFF_MIN=360` (teto 6h) e dois
novos ficheiros de estado (`STATE_FORCE_N` = nº de disparos forçados consecutivos sem o backlog
encolher; `STATE_FORCE_COUNT` = último `count` de itens `nova` visto no disparo forçado). A cada
`force_fire`, o intervalo de cooldown passa a ser `STALE_MIN * 2^fire_n` (30→60→120→240→360 min,
depois fica no teto); se `count` descer face ao último disparo forçado (sinal de que o Danilo
decidiu algo na Central), o backoff reinicia em 30 min. O comportamento do disparo em si não
mudou (continua só a acordar o agente com instrução para rever a fila; nunca aprova Balde B
sozinho) — só o espaçamento entre disparos repetidos do MESMO lote não resolvido. Confirmado por
`git diff` (`.claude/scripts/hermes-aprovador-vermelho.sh`, +33/−10 linhas) nesta consolidação.

> **estado: superado (achado corrigido, 2026-07-24)** — o trecho abaixo ("PENDENTE DE DEPLOY: o
> fix está só no working tree, ainda não commitado") estava **incorreto**. Verificação real por
> `git log --all -p -- .claude/scripts/hermes-aprovador-vermelho.sh` (não só `--oneline`, que
> escondia o conteúdo do diff) mostra que o backoff **foi sim committado** no repo canónico, em
> `e4444a4` ("feat(robot-b): Emerson decide sozinho a fila de sugestoes", 2026-07-14 05:38:43 UTC)
> — `MAX_BACKOFF_MIN=360` + `STATE_FORCE_N`/`STATE_FORCE_COUNT` confirmados nesse commit. O que
> aconteceu depois: o commit seguinte que tocou este ficheiro, `f169f96` ("fix(parceiro): commita
> fixes do cadastro que ficaram só na working tree (Ronda 8)", 2026-07-15 00:26:11 UTC — sobre
> cadastro de parceiro, **sem relação nenhuma** com o aprovador-vermelho), **reverteu em
> silêncio** as 3 linhas do backoff de volta ao `STALE_MIN=30` fixo antigo — dano colateral de um
> commit que varreu ficheiros de uma working tree desatualizada (mesmo padrão de "commit
> concorrente arrasta edição de outro executor" já visto noutras sessões). Confirmado por `git
> show f169f96 -- .claude/scripts/hermes-aprovador-vermelho.sh` (diff mostra `MAX_BACKOFF_MIN`,
> `STATE_FORCE_N`, `STATE_FORCE_COUNT` a serem removidos) e por leitura direta do ficheiro em
> HEAD (2026-07-24): hoje só existe `STALE_MIN=30` fixo, sem backoff nenhum. Ou seja: **não é
> "só falta deploy à VPS"** — o próprio repo local perdeu o fix por regressão silenciosa; deploy
> à VPS é irrelevante enquanto o repo não tiver o fix de novo. Correção real: reimplementar o
> backoff (conteúdo exato ainda recuperável via `git show e4444a4:.claude/scripts/hermes-
> aprovador-vermelho.sh`), commitar isoladamente (não junto com commits de outro domínio) e só
> depois fazer o deploy manual à VPS. Candidato a ordem para `maestro-autonomia` ou o Danilo.
> Gaps de ~5-12 min vistos em 2026-07-16/20/24 (em vez de 30→60→120→240) agora têm explicação
> completa: o fix nunca esteve ativo por mais de 1 dia no repo. Mecânica do loop/`STALE_MIN`:
> `permanente/semantica/loops.md`.

**Reconfirmação 2026-07-20 11:33 UTC:** gaps entre 5 corridas consecutivas do item `8ccc09bb`
(reconfirmações nº2→nº7) ficaram todos em ~5-8min, não no padrão 30→60→120→240min — deploy na VPS
segue pendente. Ver detalhe corrida-a-corrida em `aprovador-vermelho-historico-corridas.md` (linha
2026-07-20).

**Reconfirmação 2026-07-24 ~07:39 UTC (a confirmar, amostra n=2):** FALLBACK_30MIN disparou 2× em
~12min para os mesmos 4 itens `marcacoes:*` (07:27:50 UTC e ~07:39:28 UTC, mesmo watermark/item
mais antigo parado). Consistente com a mesma anomalia acima (deploy do backoff exponencial ainda
pendente na VPS) — gap de 12min está na mesma ordem de grandeza dos 5-8min já vistos em
2026-07-20, não no padrão 30→60→120→240min esperado pós-fix. Ainda amostra pequena; não tratar
como confirmação definitiva sem mais corridas. Ver detalhe em
`aprovador-vermelho-historico-corridas.md` (linha 2026-07-24, "2ª corrida").

**Reconfirmação 2026-07-27 (a confirmar, ver linha 2026-07-27 do histórico de corridas):** a
corrida FALLBACK_30MIN desta data disparou sobre uma fila de 30 itens (salto vindo de 1-9) — a
causa do salto em si foi identificada como um bug distinto do gerador de sugestões (ver "Achado
2026-07-27" em `aprovador-vermelho-triagem.md`), não a anomalia de backoff desta página. Gap
face ao aviso Telegram anterior foi de ~3 dias (2026-07-24 08:13:43 UTC → 2026-07-27), acima do
limiar de supressão anti-spam — não dá sinal novo sobre o estado do deploy do backoff em si
(não houve reconfirmações em sequência rápida nesta corrida para medir o gap).

**3ª corrida 2026-07-27 (reconfirmação, `admin_audit_log` real 17:40:33 UTC):** confirmado de novo
por `Grep` direto em `.claude/scripts/hermes-aprovador-vermelho.sh` que o repo **ainda só tem
`STALE_MIN=30` fixo** (linha 42), sem `MAX_BACKOFF_MIN`/`STATE_FORCE_N`/`STATE_FORCE_COUNT` — o fix
de `e4444a4` continua revertido. O relatório original desta corrida estimou um gap de ~7min desde o
aviso anterior (17:22:09 UTC), mas o `admin_audit_log` (29 linhas `robot_suggestion_baldeB_reconfirmado`,
`created_at` 2026-07-27T17:40:33.097901 UTC, confirmado por SELECT direto nesta consolidação) mostra
um gap real de **~18min23s** — corrigido aqui porque a estimativa original não batia com a evidência.
18min continua abaixo do piso não corrigido de 30min entre disparos forçados, mas é MAIOR que os gaps
de 5-12min já vistos em 2026-07-20/24 — não reforça a hipótese de "gap cada vez mais chamativo"
levantada no relatório original; amostra ainda pequena e mecanismo do `STATE_FORCE` continua sem
confirmação direta nesta sessão (só inferido pelo comportamento observado).

**4ª e 5ª corridas 2026-07-27 (mesmo lote, gaps a encurtar):** disparos às ~17:51:43 UTC (4ª,
`.claude/.ai/reports/aprovador-vermelho-2026-07-27-1750z-4a-corrida.md`) e ~18:02 UTC (5ª,
`.claude/.ai/reports/aprovador-vermelho-2026-07-27-1802z-5a-corrida.md`) sobre o mesmo lote de 29
itens, zero novidade de classificação. Sequência de gaps do dia: 16:57:45 → 17:22:09 (25min) →
17:40:33 (18min) → 17:51:43 (11min) → ~18:02 (~10min) — padrão de **encurtamento**, o oposto do
30→60→120→240min esperado pós-fix. Reconfirmado por `Grep` direto nesta consolidação:
`.claude/scripts/hermes-aprovador-vermelho.sh` (HEAD, 2026-07-27) continua só com `STALE_MIN=30`
fixo (linha 42), sem `MAX_BACKOFF_MIN`/`STATE_FORCE_N`/`STATE_FORCE_COUNT` — o fix de `e4444a4`
segue revertido por `f169f96`, ainda não reaplicado. 5 reconfirmações do mesmo lote em ~1h20 é
puramente operacional (execução de agente + ruído em `admin_audit_log`/Telegram); nenhuma promoção
indevida de Balde B, nenhuma classificação errada — a fila seguiu corretamente triada o tempo
todo. Candidato a ordem para `maestro-autonomia`/Danilo: reaplicar o backoff isolado num commit
próprio (conteúdo recuperável via `git show e4444a4 -- .claude/scripts/hermes-aprovador-vermelho.sh`).

Flag `aprovador_vermelho_auto_baldeA` = `true` (ligada) confirmada antes de cada auto-aprovação.
Relatório completo (com todos os addenda até o 9º): `.claude/.ai/reports/aprovador-vermelho-2026-07-12-fallback30min.md`;
12º addendum: `.claude/.ai/reports/aprovador-vermelho-2026-07-13-12a-corrida.md`;
13º addendum: `.claude/.ai/reports/aprovador-vermelho-2026-07-13-13a-corrida.md`;
corrida 2026-07-16 (lote antigo fechado + 9 itens novos): `.claude/.ai/reports/aprovador-vermelho-2026-07-16-fallback30min.md`.
Histórico bruto das corridas 2026-07-10/11: `inbox/aprovador-vermelho-2026-07-10.md`,
`inbox/aprovador-vermelho-loop-2026-07-10.md`.

## Ver também
- `permanente/procedural/aprovador-vermelho-triagem.md` — conhecimento de triagem (Balde A/B).
- `permanente/procedural/aprovador-vermelho-historico-corridas.md` — log corrida-a-corrida.
- `permanente/semantica/loops.md` — mecânica do loop (watermark, FALLBACK 30MIN, dedupe, `STALE_MIN`).
