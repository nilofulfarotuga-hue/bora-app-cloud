---
data: 2026-07-14
agente: executor-loop-autonomo (SONNET)
tipo: bugfix-ui
---

# Cadastro de parceiro — passo 4 preso sem scroll (RESOLVIDO)

## Sintoma reportado (Danilo, teste ao vivo)
No wizard "Criar conta de parceiro", o passo 4 ("Logo & Confirmação") mostra o
resumo (nome, email, NIF, IBAN, documentos), mas a tela não fazia scroll nem
para cima nem para baixo. O texto "Ao submeter, sua conta ficará pendente de
análise (24-48h)" e o botão de submeter/continuar ficavam inacessíveis abaixo
da área visível — utilizador ficava preso, sem conseguir concluir o cadastro.

## Causa raiz
`lib/screens/register_partner_screen.dart` envolve o `Stepper` (Material)
dentro de um `SingleChildScrollView`:

```
SafeArea(child: SingleChildScrollView(child: Stepper(...)))
```

O `Stepper` vertical do Flutter é implementado internamente como um
`ListView(shrinkWrap: true, physics: <não definido>)`. Ao aninhar dois
scrolláveis no mesmo eixo (vertical) sem desativar a física do interno, o
gesto de arrastar é disputado na "arena de gestos": o `ListView` interno do
Stepper (mesmo com extensão de scroll ~zero, porque já está esticado ao
tamanho natural do conteúdo pelo `SingleChildScrollView`) continua a competir
pelo gesto e frequentemente "engole" o drag sem mover nada, impedindo o
`SingleChildScrollView` externo de rolar. É um footgun conhecido do Flutter ao
aninhar `ListView`/`Stepper` dentro de `SingleChildScrollView` sem
`physics: NeverScrollableScrollPhysics()` no widget interno.

## Fix aplicado
`lib/screens/register_partner_screen.dart` — adicionado
`physics: const NeverScrollableScrollPhysics()` ao `Stepper`, delegando 100%
do controlo de scroll ao `SingleChildScrollView` externo. Agora o passo 4
rola até ao fim, incluindo o texto de aviso e o botão "Continuar" (que no
último passo chama `_submit()` e envia o cadastro para `pending_approval`).

Comentário no código explica o porquê (não óbvio) para não regressar.

## Outros wizards verificados (mesmo pedido do Danilo)
- `lib/screens/driver_signup_screen.dart` (candidatura de estafeta) — também
  usa `Stepper`, mas **sem** aninhamento: o `Stepper` está direto no `body`
  do `Scaffold` (via `Form`), que dá altura limitada ao ecrã. Nesse caso o
  `ListView` interno do `Stepper` já rola normalmente por si só — é o padrão
  correto, sem o bug. Nenhuma alteração necessária.
- `lib/screens/cleaner/cleaner_apply_screen.dart` (candidatura de limpeza) —
  não usa `Stepper`; é um `ListView` simples direto no `body`, sem
  aninhamento de scrolláveis. Também correto, sem alteração necessária.
- Confirmado via grep (`Stepper(` em `lib/`) que só existem estes 2 usos de
  `Stepper` no projeto — não há outro wizard com este padrão.

## Validação
`flutter analyze lib/screens/register_partner_screen.dart` → 0 erros (só
warnings/infos pré-existentes, não relacionados com a mudança — imports não
usados e `value:` deprecated em `DropdownButtonFormField`, nenhum introduzido
por este fix).

Não foi possível testar em dispositivo/emulador físico neste ambiente
headless — validação foi estática (análise do widget tree + `flutter
analyze`). Recomenda-se confirmação visual do Danilo ao testar o build.

## Ficheiro tocado
- `lib/screens/register_partner_screen.dart` (+4 linhas, 1 parâmetro)

## Reconfirmação (2ª vez, mesma sessão de loop, 2026-07-14)
Tarefa recebida de novo, idêntica à original. Fix de `physics: const
NeverScrollableScrollPhysics()` no `Stepper` (linha 476) continua presente no
working tree — sem regressão. Reconfirmado `flutter analyze
lib/screens/register_partner_screen.dart` → 0 erros (mesmos 6
warnings/infos pré-existentes de antes, nenhum novo).

`git push` não foi executado: o branch local está 2 commits à frente do
remoto mas **30 atrás** (CI já correu builds/version bumps entretanto);
push para `autonomous-night-2026-04-29` dispara `build_android.yml`
(build de produção / Play Store) — Lista Vermelha para o executor headless.
Commit local (reconfirmação) fica pronto; push aguarda "vai" do Danilo ou
janela de sync explícita.
