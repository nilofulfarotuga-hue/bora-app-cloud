# Fix — regressão do overlay de sugestões de morada (TVDE) — 2026-07-07

Branch: `autonomous-night-2026-04-29` · Escopo: **só client-side Flutter**, 1 ficheiro de widget
partilhado + 1 teste. Zonas protegidas intactas. Sem backend.

## Problema (regressão que a correção anterior causou)

No fix anterior (`0e39a71`), o `AddressAutocompleteField` passou a **abrir o overlay para CIMA**
quando o campo está a meio da página (ex.: destino do TVDE). Resultado: ao digitar, aparecia uma
**caixa branca grande e vazia** — as sugestões **não renderizavam**. Antes (a abrir para baixo) as
sugestões apareciam, mesmo que meio tapadas pelo teclado.

## Causa real: **layout (não a query)**

Confirmação de que é layout e não a busca de sugestões:

1. **Relato antes/depois do próprio Danilo:** a abrir **para baixo** as sugestões apareciam
   (logo a query dispara e a lista renderiza); a abrir **para cima** ficava caixa vazia. Ou seja, a
   query devolve resultados — o que quebrou foi **onde/como** a lista é desenhada.
2. **Reprodução em teste de widget** (novo, ver abaixo): o cenário do TVDE (campo **a meio de um
   `Scrollable`**) foi reproduzido; o caminho "para cima" era o único que mudava.
3. Nota: o Redmi ainda tem a **build 370** (anterior ao `0e39a71`), por isso a regressão nem sequer
   está no aparelho agora — a verificação visual do fix fica para a próxima build do CI (build local
   dá OOM na máquina de 4 GB).

**Mecanismo:** ao inverter o overlay para cima (`CompositedTransformFollower` com
`followerAnchor: bottomLeft` / `targetAnchor: topLeft`), a `ListView` com `shrinkWrap` dentro das
**constraints soltas do Overlay** não renderizava as linhas — sobrava o container (Material branco)
sem conteúdo visível. O caminho "para baixo" (`followerAnchor: topLeft`) nunca teve este problema.

## Correção (robusta, alinhada com o recomendado)

Em vez de perseguir o layout frágil "para cima", **removi-o** e mantive o **caminho comprovado**:

1. **Overlay abre SEMPRE para baixo** — o mesmo render que funciona na limpeza e nos outros ecrãs.
   Fim da caixa branca.
2. **Campo sobe ao focar (estilo Uber/Google):** no `_onFocusChanged`, ao ganhar foco, um
   `Scrollable.ensureVisible(alignment: 0.0)` leva o campo para o topo do `Scrollable`. Assim a
   lista (para baixo) tem espaço acima do teclado. **É no-op seguro** quando o campo não está num
   `Scrollable` — não afeta os ecrãs que não rolam.
3. **Sugestões rápidas e automáticas:** dispara a partir de **1 caractere** (era 3) e **debounce
   250 ms** (era 300). Digitar "r" já mostra ruas.

## Porque **não quebra a limpeza** (nem os outros 11 ecrãs)

- O `AddressAutocompleteField` é partilhado por **12 ecrãs** (TVDE, limpeza, favores, send/carry,
  parceiro, etc.).
- Na **limpeza** o campo está **no topo** e já abria **para baixo** — comportamento **inalterado**.
  O `ensureVisible` num campo já visível/no topo é praticamente no-op.
- O overlay-para-baixo é exatamente o comportamento **original** (pré-regressão) de todos eles →
  nenhum regride. O único acréscimo universal (`ensureVisible`) é seguro por construção (no-op sem
  `Scrollable`).

## Verificação

- **`flutter analyze`** só nos 2 ficheiros alterados: **No issues found** (71,8 s).
- **Teste de widget novo** `test/address_autocomplete_field_test.dart` — **3/3 verde**:
  1. sugestões renderizam (lista não vazia) quando há resultados;
  2. **campo a meio de um `Scrollable`** (o cenário do TVDE) **também** mostra as sugestões —
     é a prova direta de que a caixa vazia foi resolvida;
  3. 1 caractere já dispara sugestões.
  O teste injeta um `PlaceAutocompleteService` falso (test seam novo no construtor,
  `serviceOverride`) para não depender da rede.
- ⚠️ Verificação **visual no device** fica para a **próxima build do CI** (Redmi na 370, build
  local proibida). A lógica de render é a comprovada (para baixo) + `ensureVisible` (API padrão).

## Ficheiros

- `lib/widgets/address_autocomplete_field.dart` — remove abertura para cima; `ensureVisible` no
  foco; 1 caractere + debounce 250 ms; test seam `serviceOverride`.
- `test/address_autocomplete_field_test.dart` — **novo**, 3 casos (inclui campo em `Scrollable`).
