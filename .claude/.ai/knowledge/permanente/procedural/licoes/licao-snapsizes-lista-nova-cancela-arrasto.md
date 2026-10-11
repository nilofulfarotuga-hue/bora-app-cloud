---
tema: licao-snapsizes-lista-nova-cancela-arrasto · escopo: projeto · estado: atual · atualizado: 2026-10-11
id: licao-snapsizes-lista-nova-cancela-arrasto
tipo: licao
origem: [commit a1e7eddf, lib/screens/driver/tvde/tvde_ride_active_screen.dart (_TvdeCorridaGavetaState), test/tvde_corrida_motorista_fases_test.dart, flutter/lib/src/widgets/draggable_scrollable_sheet.dart:758 (Flutter 3.47.2), handoff do Juiz da missão cartao-corrida-motorista]
ultima_confirmacao: 2026-10-11
zona: verde
confianca: auto
---

# Lição: `snapSizes` com lista nova em cada build cancela o arrasto do dedo

- **Contexto:** missão `cartao-corrida-motorista` (11/10/2026), gaveta da corrida TVDE do
  motorista (`TvdeCorridaGaveta` / `_TvdeCorridaGavetaState`,
  `lib/screens/driver/tvde/tvde_ride_active_screen.dart`). O `DraggableScrollableSheet`
  recebia `snapSizes` como lista nova, criada em cada build.
- **A descoberta:** o `DraggableScrollableSheet` compara `snapSizes` por **identidade**. Em
  `_replaceExtent` (`draggable_scrollable_sheet.dart:758`, Flutter 3.47.2) faz
  `widget.snapSizes != oldWidget.snapSizes`. Com `snap: true` e com o arrasto ligado, agenda
  `goBallistic(0)` para o frame seguinte, e isso cancela o arrasto do dedo. Basta o pai
  redesenhar-se durante o gesto. Neste ecrã redesenha-se sempre: a mira e o SOS seguem a
  gaveta por `setState` num `NotificationListener<DraggableScrollableNotification>`, e o
  cronómetro bate de 1 em 1 s. **Resultado:** a gaveta só abria com toque, nunca com o dedo.
- **Porque o teste não apanhou:** o `tester.drag` manda o gesto inteiro de uma vez. Não há
  frames pelo meio nem pai a redesenhar-se, por isso a comparação nunca dispara.
- **Quem apanhou:** o revisor de contexto limpo (Juiz, maker/checker), não quem escreveu.
- **Regra a aplicar:**
  1. Lista de `snapSizes` guardada no `State` (`List<double>? _snaps`) e trocada **só quando o
     valor muda**, ou `const`. Nunca um literal novo dentro do `build`.
  2. Testar arrasto com o dedo a sério: `tester.startGesture` + `moveBy` em passos +
     `pump(const Duration(milliseconds: 16))`, **dentro de um pai que faz `setState` na
     `DraggableScrollableNotification`**. O `tester.drag` sozinho não prova arrasto num ecrã
     que se redesenha.
- **Não confundir:** a auditoria de 06/10 regista outro erro na folha arrastável, "Null check
  operator used on a null value" ao construir `DraggableScrollableNotification` (14 vezes,
  Android, versões 639 a 653; `permanente/memoria-claude-ai/prompt-auditoria-3-plataformas-2026-10-06.md:40`).
  Sintoma diferente. Esta lição não diz se esse erro está resolvido.
- **Evidência:**
  - Commit `a1e7eddf` (11/10/2026).
  - Conserto em `tvde_ride_active_screen.dart`: comentário `[Juiz 11/10]` (~linha 2710) e
    `snapSizes: _snaps` (linha 2802).
  - Teste `test/tvde_corrida_motorista_fases_test.dart:410`, "arrasto lento com o dedo abre a
    gaveta mesmo com o ecrã a redesenhar-se a cada frame". O arnês `_EcraQueSegue` faz
    `setState` na notificação. Contra o código antigo chumbava (0.234); com o conserto passa.
  - Emulador Android 15: gaveta aberta pelo dedo (0.220→0.367 e 0.233→0.591). Provas em
    `.claude/.ai/provas/cartao-corrida-motorista-2026-10-11/`.

`estado: atual`
