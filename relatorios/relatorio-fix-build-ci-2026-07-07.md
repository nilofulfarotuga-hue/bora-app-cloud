# Fix do build CI — 2026-07-07

Branch: `autonomous-night-2026-04-29` · Workflow: `build_android.yml` (Build Android & Deploy to Google Play)

## O que falhou

Run **28858044145** (disparado pelo push da corrida noturna, `b6dacd8`) falhou em 3m19s na
compilação do `bundleRelease`:

```
lib/screens/restaurant_menu_screen.dart:1360:32: Error: Cannot invoke a non-'const'
constructor where a const expression is expected.  →  child: Semantics(
lib/widgets/market/market_product_card.dart:207:22: Error: Cannot invoke a non-'const'
constructor where a const expression is expected.  →  child: const Semantics(
```

**Causa raiz:** os fixes de acessibilidade da corrida noturna (commit `c4f2a5c`) embrulharam o
`Icon` do botão "+" em `Semantics(label: 'Adicionar', ...)` — mas o widget `Semantics` **não tem
construtor `const`** (delega para `Semantics.fromProperties` com um `SemanticsProperties` criado
em runtime), e ambos os usos estavam dentro de expressões `const` (`const Padding(...)` num caso,
`const Semantics(...)` direto no outro). Compila… não: rebenta no kernel_snapshot do release.

Nota: o `flutter analyze` por-ficheiro da noite não apanhou isto porque na altura analisei os
ficheiros *antes* destes dois edits específicos serem os últimos — lição: analisar SEMPRE depois
do último edit em cada ficheiro tocado, mesmo em fixes "triviais" de 3 linhas.

## O fix

`Icon` já expõe o parâmetro **`semanticLabel`** — vai parar exatamente ao mesmo sítio na árvore
de acessibilidade (o `Icon` embrulha-se em `Semantics` internamente), é `const`-compatível e o
diff fica menor:

```dart
// antes (não compila em contexto const)
child: Semantics(label: 'Adicionar', child: Icon(Icons.add, ...))
// depois
child: Icon(Icons.add, ..., semanticLabel: 'Adicionar')
```

- Ficheiros: `lib/screens/restaurant_menu_screen.dart` + `lib/widgets/market/market_product_card.dart`
- `flutter analyze` nos 2 ficheiros: **0 erros** (1 info pré-existente noutra linha, baseline)
- Commit do fix: **`90af328`** · push (com merge do bump 372 do CI): **`b319ea6`**

## Resultado

Run **28859407667** — ✅ **success** em 8m38s.
https://github.com/nilofulfarotuga-hue/bora-app-cloud/actions/runs/28859407667

A build nova (versionCode 372+) inclui agora, de facto, os 3 fixes de acessibilidade da noite
(sino de notificações, botão "+" adicionar produto, toggle online do estafeta) — os 2 flows de
cliente marcados "aguarda build" no relatório da corrida noturna podem ser re-testados quando
esta build chegar aos telemóveis via Play Internal Testing.

## A seguir

Retomar os itens abertos da corrida noturna (por ordem): TVDE (flows novos de raiz), Reservas de
mesa chegada/no-show (lado parceiro), Serviços (Barbearia Nobre), Limpeza (candidatura + upload),
Favores, transversais. Ver `relatorios/corrida-noturna-2026-07-06.md` §"Categorias NÃO cobertas".
