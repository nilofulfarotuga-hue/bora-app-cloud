---
id: e2e-reforco-botao-carrinho-2026-07-11
tipo: relatorio
origem: [executor autónomo · ordem 2a29 reforço]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# E2E — reforço do botão de adicionar ao carrinho + regra de ouro "nunca travar"

Reforço da ordem **2a29** (completar compra no mercado) com as 2 dicas do Danilo (app ao vivo,
2026-07-11). Zona **verde** (UI + infra de teste; sem dinheiro, sem zonas protegidas).

## DICA 1 — o botão de adicionar é um "+" PEQUENO, ícone sem texto, no canto do card

O Maestro não o achava por ser pequeno e sem texto. Implementei a **estratégia (a) — tocar por
id** (a mais robusta), com fallback para o caminho antigo comprovado:

- **Código Flutter — `Semantics(identifier: 'btn_add_carrinho')`** nos dois botões de "+":
  - `lib/screens/store_products_screen.dart` → `_QtyButton` ganhou parâmetro opcional
    `semanticId`, passado nos 2 pontos de "primeiro add" (grelha de browse + resultado de
    pesquisa). Envolve o botão em `Semantics(identifier:'btn_add_carrinho', button:true)`.
  - `lib/widgets/market/market_product_card.dart` → `_AddButton` (o "+" dos carrosséis)
    envolvido no mesmo `Semantics`.
  - `flutter analyze` dos 2 ficheiros: **No issues found**.

- **Flow `flows/cliente/delivery-mercado-cash.yaml`** — nova secção de adicionar, em *ladder*:
  1. `takeScreenshot: antes-de-adicionar-carrinho`
  2. **(a)** `tapOn: id: btn_add_carrinho` (`optional: true`) — adiciona SEM abrir o detalhe.
  3. espera curta pela prova (`Ver carrinho.*`, `optional`).
  4. **(b) fallback** `runFlow: when: notVisible "Ver carrinho.*"` → abre o detalhe pelo preço
     e usa o botão de TEXTO "Adicionar ao carrinho" (caminho antigo, comprovado), tudo `optional`
     + screenshot `fallback-abrir-detalhe-produto`.
  5. **prova real**: `takeScreenshot: estado-apos-adicionar` + `extendedWaitUntil "Ver carrinho.*"`
     (o botão fixo só existe com ≥1 item = o contador subiu) → toca para ir ao carrinho.

  > Compatível com o APK atualmente instalado: como o id `btn_add_carrinho` ainda não está no
  > APK instalado, o `tapOn: id` (optional) falha em silêncio e o **fallback** cria o pedido na
  > mesma. O caminho por id fica ativo assim que houver novo build+install (🔴, fora do autónomo).

## DICA 2 — REGRA DE OURO: falhou → tira foto + regista + segue (nunca trava/aborta)

Implementada em dois níveis + gravada como lição.

- **Nível YAML** (granularidade fina, dentro do fluxo Maestro): comandos arriscados com
  `optional: true`, `takeScreenshot` antes de cada um, e estratégias em ladder via
  `runFlow: when: notVisible`. A prova de sucesso vem sempre de um sinal do app.
- **Nível runner** (`runner.py`): nova função `screenshot_falha()` — quando um passo Maestro
  devolve `rc != 0`, o runner tira `adb exec-out screencap -p` → `gravacoes/falha-<slug>.png`
  e regista o caminho no `e2e_log` (via `e2e_diario`). Best-effort (uma foto que falhe nunca
  afunda o teste). `corre_maestro` passou a devolver também `foto`. Complementa os frames já
  extraídos do vídeo — é o ecrã EXATO do momento da falha, para o Claude.ai ver.
- **Lição gravada:** `.claude/.ai/knowledge/wiki/licoes/teste-nunca-trava-tira-foto-e-segue.md`.

## Ficheiros tocados
- `lib/screens/store_products_screen.dart` — `_QtyButton` + `semanticId: btn_add_carrinho` (2 sítios)
- `lib/widgets/market/market_product_card.dart` — `_AddButton` em `Semantics(identifier)`
- `.claude/testes-e2e/flows/cliente/delivery-mercado-cash.yaml` — ladder de adicionar + screenshots
- `.claude/testes-e2e/runner.py` — `screenshot_falha()` + wiring na falha do Maestro (+ `GRAVACOES`)
- `.claude/.ai/knowledge/wiki/licoes/teste-nunca-trava-tira-foto-e-segue.md` — lição (novo)

## Validação
- `flutter analyze` (2 ficheiros tocados): **0 issues**.
- `py_compile` de `runner.py` + `loop-noturno.py`: **OK**.
- YAML do fluxo parseia: **2 docs, 36 passos**.
- Execução real: ver secção abaixo (corrida no device presente).

## Execução real (delivery-mercado-cash)
<!-- RESULTADO_RUN -->
_(a preencher com o resultado da corrida)_
