---
tipo: handoff
data: 2026-07-15
origem: executor-autonomo (loop noturno)
tema: cadastro-parceiro / BUG3 scroll
---

# BUG 3 — scroll do wizard de cadastro de parceiro

## Pedido
Ecrã final do wizard (Passo 4 "Logo & Confirmação") não fazia scroll até ao fim,
cortando o botão CONTINUAR/submeter em ecrãs pequenos. Envolver o conteúdo num
scroll; verificar os outros passos do mesmo wizard (Dados do Estabelecimento,
Documentos, Conta de Acesso).

## Investigação
Ficheiro: `lib/screens/register_partner_screen.dart`. Os 4 passos do wizard
partilham o **mesmo** `Stepper`, que por sua vez está envolvido por um **único**
`SingleChildScrollView` externo (`build()`, linha ~511-517):

```dart
body: SafeArea(
  child: SingleChildScrollView(
    child: Stepper(
      physics: const NeverScrollableScrollPhysics(),
      currentStep: _currentStep,
      ...
```

Este fix (`physics: NeverScrollableScrollPhysics` no `Stepper`, delegando 100%
do gesto de arrastar ao `SingleChildScrollView` externo) **já estava commitado**
antes desta tarefa — commit `494f1c0` ("fix(parceiro): passo 4 do cadastro rola
até ao botão de submeter", 2026-07-14 11:31), confirmado presente e sem diff na
HEAD atual (`37d16cf`, branch `autonomous-night-2026-04-29`). `git status`/`git
diff` no ficheiro não mostraram alterações pendentes.

Como o `Stepper` inteiro (todos os 4 `Step`s) está dentro do mesmo scroll
externo — não há um `SingleChildScrollView`/`ListView` independente por passo —
o fix cobre uniformemente Dados do Estabelecimento, Documentos, Conta de Acesso
e Logo & Confirmação. Não há um segundo contentor scroll a testar separadamente.

Também confirmado: `MaterialApp` usa `locale: Locale('pt', 'PT')` com
`GlobalMaterialLocalizations` (`lib/main.dart`), então os botões nativos do
`Stepper` ("Continue"/"Cancel") já saem traduzidos para "Continuar"/"Cancelar" —
não há `controlsBuilder` custom a verificar.

Único `Stepper` adicional no projeto é `driver_signup_screen.dart` (wizard do
estafeta) — fora do escopo desta tarefa (mesmo wizard = só os passos do cadastro
de parceiro) e já tinha sido verificado como sem o mesmo bug no commit 494f1c0.

## Ação tomada
**Nenhuma alteração de código** — o bug já estava corrigido e commitado. Nada
para commitar/push nesta sessão.

## Limitação de teste
Este ambiente headless **não tem o SDK Flutter instalado** (`flutter` não
encontrado no PATH) — não foi possível correr `flutter analyze`/`flutter test`
nem abrir a app num emulador/dispositivo para confirmar visualmente o scroll.
A verificação foi feita por leitura de código (estrutura de widgets + git
history), confirmando que a árvore de widgets está correta para o
comportamento esperado. Recomenda-se confirmação visual num device pequeno
(ex.: emulador 5") na próxima sessão com toolchain disponível.

## Re-verificação (mesmo dia, execução seguinte)
Pedido chegou de novo ao loop autónomo (mesmo BUG3). Repeti a investigação de
forma independente: `lib/screens/register_partner_screen.dart` continua com o
`Stepper` (4 passos) dentro do único `SingleChildScrollView` externo com
`physics: NeverScrollableScrollPhysics`, sem diff pendente (`git status`/`git
diff` limpos no ficheiro; HEAD `3116e61`). Ambiente ainda sem `flutter` no
PATH. Conclusão inalterada: fix já presente para os 4 passos, nada a
alterar/commitar em código.

## Re-verificação #3 (2026-07-15, execução seguinte)
Terceiro pedido idêntico chegou ao loop autónomo. Repeti a investigação uma
vez mais, linha a linha: `lib/screens/register_partner_screen.dart`
(HEAD `a6e2c7b`, branch `autonomous-night-2026-04-29`) — `build()` continua
com `body: SafeArea(child: SingleChildScrollView(child: Stepper(physics:
const NeverScrollableScrollPhysics(), ...))))` (linhas 511-517), fechando só
no fim do `Stepper` (linha 883/884). Os 4 `Step`s (Dados do Estabelecimento,
Documentos, Conta de Acesso, Logo & Confirmação) estão todos dentro dessa
única árvore — confirmado por leitura completa do ficheiro (888 linhas), não
só da zona do `build()`. Nenhum `controlsBuilder` custom, nenhum `SizedBox`/
`Container` de altura fixa a cortar o botão "Continuar". `git status`/`git
diff --stat` no ficheiro continuam limpos. Ambiente ainda sem SDK Flutter
(`which flutter` falha) — não foi possível correr a app num device/emulador
pequeno para confirmação visual real; a verificação permanece por leitura
estrutural de código. Conclusão inalterada pela 3ª vez: fix já presente e
cobre os 4 passos, nada a alterar/commitar em código Dart.

**Nota para o Danilo:** este pedido já foi processado 3 vezes com a mesma
conclusão (mesmo código, mesmo resultado). Se ainda houver um bug real de
scroll no dispositivo, a causa provavelmente NÃO está em
`register_partner_screen.dart` — vale a pena verificar se o pedido original
se refere a outro ecrã (ex.: uma versão antiga do APK ainda instalada, ou um
wizard diferente do "cadastro de parceiro"), porque a análise estática deste
ficheiro não encontra mais nada para corrigir sem acesso a um device real.

## Re-verificação #4 (2026-07-15, execução seguinte)
Quarto pedido idêntico chegou ao loop autónomo (mesmo texto: BUG3 scroll do
Passo 4, verificar outros passos, commit+push). Desta vez consultei primeiro a
memória (`feedback_bug3_scroll_cadastro_ja_resolvido.md`), que já apontava
para este relatório e para a instrução de não repetir a investigação completa
sem checar o memo. Confirmação rápida em vez de reanálise total:
`git log --oneline -- lib/screens/register_partner_screen.dart` mostra
`494f1c0` ainda no histórico (agora com `f169f96` e `3c19043` por cima, ambos
sem tocar na estrutura do scroll); `git status`/`git diff` no ficheiro estão
limpos (HEAD `2ab9e5f`, branch `autonomous-night-2026-04-29`); grep confirma
`SingleChildScrollView` (linha 512) → `Stepper(` (linha 513) →
`NeverScrollableScrollPhysics()` (linha 517) inalterados. Ambiente continua
sem SDK Flutter (`which flutter` falha) — sem teste visual possível.
**Nenhuma alteração de código feita; nada para commitar/push.** Conclusão
inalterada pela 4ª vez.
