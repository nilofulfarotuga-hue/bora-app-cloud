# Fix: scroll travado — "Sugestões do Robot" (admin)

**Data:** 2026-07-22
**Ficheiro:** `lib/screens/admin/admin_robot_suggestions_screen.dart`
**Escopo:** só layout/scroll do tab "Sugestões". Nada de lógica de aprovação/rejeição,
`robot_suggestions`, dinheiro ou dispatch foi tocado.

## Causa

`_suggestionsTab()` montava um `Column` com 4 cartões de altura fixa no topo
(`_parityHeader` = Paridade Admin 360 + Parar Tudo + Dial de confiança,
`_proofSection` = Prova da auto-cura, `_metricsCard` = contadores, `_knowledgeCard` =
Motor de Conhecimento) e só a lista de sugestões ficava dentro de `Expanded` +
`ListView`. Quando a soma da altura dos 4 cartões passava da altura disponível do
ecrã (comum em telemóvel, sobretudo com a "Prova da auto-cura" a mostrar vários
itens), o `Expanded` ficava sem espaço (zero/negativo) — o `Column` não tem scroll
próprio, então nada abaixo dos cartões ficava alcançável: nem os filtros
Status/Nível, nem a lista de sugestões para aceitar/rejeitar.

**Itens escondidos abaixo da dobra antes do fix:** o filtro Status/Nível + a lista
inteira de sugestões (as ações de aceitar/rejeitar ficavam inacessíveis).

## Fix

`_suggestionsTab()` passou a ser um único `RefreshIndicator` → `SingleChildScrollView`
que envolve tudo (cartões + filtros + lista). A lista interna (`ListView.separated`)
ficou com `shrinkWrap: true` + `physics: NeverScrollableScrollPhysics()` — deixa de
ter scroll próprio e passa a fazer parte do fluxo do scroll externo único. O
pull-to-refresh continua a funcionar porque o `RefreshIndicator` está agora à volta
do `SingleChildScrollView` (que é o `Scrollable` real).

As outras duas tabs (Auto-execuções, Córtex 🔴) já tinham `Expanded(ListView)` sem
cartões extra a competir por espaço — não precisaram de alteração.

## Validação

- `flutter analyze` só no ficheiro alterado: **0 erros**. 6 avisos `info` (todos
  pré-existentes — `DropdownButtonFormField.value` deprecated e sugestões `const` —
  em linhas fora da zona editada, não introduzidos por este fix).
- Não testado num device real (sem UI runner disponível nesta sessão) — recomenda-se
  confirmar visualmente que a tela agora rola até ao fim (Motor de Conhecimento,
  filtros, lista completa de sugestões) antes de dar como 100% fechado.

## Próximo passo sugerido

Build + instalar no telemóvel para confirmar visualmente o scroll completo.
