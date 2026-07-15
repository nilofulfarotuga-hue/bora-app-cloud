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
