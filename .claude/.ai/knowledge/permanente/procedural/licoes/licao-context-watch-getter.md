---
tema: licao-context-watch-getter · escopo: projeto · estado: atual · atualizado: 2026-07-05
id: licao-context-watch-getter
tipo: licao
origem: [lib/screens/client/cleaning/cleaning_tracking_screen.dart, commit c77ce08]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Getter com `context.watch` não pode ser chamado em callbacks (Flutter/Provider)

- **Contexto:** F3 da vertical LIMPEZA — `cleaning_tracking_screen` (sessão autónoma 2026-07-05).
- **O que correu mal / a descoberta:** um getter/helper que usa `context.watch<T>()` foi chamado
  dentro de um callback (fora do `build`) → **crash** ("watch() outside build").
- **Regra a aplicar:** em getters/helpers que também são usados em callbacks, usar
  `context.read<T>()`; reservar `context.watch<T>()` **só** para o corpo do `build`.
- **Evidência:** fix aplicado em
  `lib/screens/client/cleaning/cleaning_tracking_screen.dart` (`context.read<CleaningStore>()`
  nas linhas 35/58/67), commit `c77ce08`, 2026-07-05.
