---
id: licao-autocomplete-teclado
tipo: licao
origem: [address_autocomplete_field · bottom-sheets TVDE/favores · mega-fix 2026-07-18 Parte 9]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — dropdown de autocomplete atrás do teclado num bottom-sheet: fix no widget partilhado, não por ecrã

**Problema.** Ao escrever um endereço num bottom-sheet (destino da volta TVDE, parada adicional,
paragem em casa dos favores), a lista de sugestões do autocomplete aparecia **atrás do teclado** —
impossível de ver e de clicar. O utilizador não conseguia escolher a morada.

**Causa real.** O bottom-sheet não reservava espaço para o teclado nem deixava o conteúdo subir
com ele. Sem `isScrollControlled: true`, sem `Padding(bottom: MediaQuery.viewInsets.bottom)` e
sem `scrollPadding` no `TextField`, o teclado sobe por cima da folha e tapa a lista de
sugestões (que fica ancorada logo abaixo do campo).

**Regra generalizável.**
- Bottom-sheet com campo de texto + lista por baixo → SEMPRE:
  - `showModalBottomSheet(isScrollControlled: true, ...)`,
  - envolver o conteúdo em `Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom))`,
  - `scrollPadding` generoso no `TextField`, e a lista dentro de área rolável.
- O bug aparece em vários ecrãs porque todos usam o MESMO widget de morada. Corrigir no widget
  partilhado (`address_autocomplete_field.dart`) resolve todos de uma vez; corrigir ecrã-a-ecrã
  é trabalho repetido e incompleto por construção.

Quando o mesmo sintoma aparece em três ecrãs que partilham um widget, o bug é do widget. Sobe um
nível antes de corrigir. Ver [[licao-rpc-composite-null-row]].
