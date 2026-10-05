---
tema: licao-esqueleto-row-largura-fixa-transborda · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-esqueleto-row-largura-fixa-transborda
tipo: licao
origem: [commit 744fe903, lib/widgets/home/home_feed.dart (_RailEsqueleto), test/home_esqueleto_ecra_estreito_test.dart, .claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — faixa horizontal feita com `Row` de largura fixa transborda e derruba o autoteste

- **Contexto:** a home nova do cliente (commit `4f434d3a`) mostra um esqueleto cinzento
  (`_RailEsqueleto`, `lib/widgets/home/home_feed.dart`) enquanto as lojas carregam.
- **A descoberta:** o esqueleto era uma `Row` com 3 cartões de 140 px + 3 espaços de 12
  (`Spacing.md`) = **456 px numa linha fixa**. Não cabe em nenhum telemóvel. No emulador
  Android do CI (379 px) transbordou **77 px**; no simulador iPhone (408 px) **48 px**. O
  Flutter atira "A RenderFlex overflowed…" e o autoteste cai como
  **`Multiple exceptions (2) were detected`**.
- **O que custou (05/10/2026):** caíram o **Android #498** (`4f434d3a`), o **Android #499** e o
  **iOS #165** (ambos em `aedb956b`). Nos dois #499/#165 o envio nem chegou a correr: o job
  "Build AAB & upload" ficou `skipped` e o "IPA assinado → App Store Connect" também (lido com
  `gh run view`).
- **A pista enganou:** a varredura iOS dizia **"Falhas: 0. Por varrer: 0"** e o log acabava num
  ecrã inocente ("a abrir parceiro-Gerir produtos") — era só onde o registo do passo parou. A
  causa estava no **início** do log, no bloco `EXCEPTION CAUGHT BY RENDERING LIBRARY`
  (`Row ← SizedBox ← Column ← _RailEsqueleto`, `home_feed.dart:671`). O erro do convidado
  (`invalid_credentials`) aparecia igual na #497, que passou — não era a causa.
- **Regra a aplicar:**
  1. Faixas horizontais — reais **ou** esqueleto — são `ListView` horizontal (que corta o que
     sobra), **nunca** `Row` com filhos de largura fixa. O conserto foi esse:
     `ListView(scrollDirection: Axis.horizontal, physics: NeverScrollableScrollPhysics())`.
  2. Testar a largura de telemóvel antes de empurrar: **320 / 379 / 408 px** (o teste
     `test/home_esqueleto_ecra_estreito_test.dart` faz isto; contra o código antigo dá 0/3 com
     136 / 77 / 48 px, os mesmos números do CI; com o conserto `+3: All tests passed!`).
  3. Autoteste do CI caído com "Multiple exceptions": procurar `EXCEPTION CAUGHT BY RENDERING
     LIBRARY` no topo do log antes de acreditar na última linha.
- **Família:** mesma família dos bugs #2 e #22 de `permanente/episodica/bugs-resolvidos.md`
  (layout flex sem limite certo) — aqui na largura, lá na altura.
- **Evidência:** commit `744fe903` (`home_feed.dart` 7 linhas + teste novo de 76 linhas);
  CI: Android #499 run 37344821010 e iOS #165 run 37344820901 (failure); Android #500
  (`744fe903`) success; relatório `.claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md` B2+B3.

`estado: atual`
