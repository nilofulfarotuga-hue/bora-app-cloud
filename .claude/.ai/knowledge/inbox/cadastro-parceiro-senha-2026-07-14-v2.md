# Cadastro de parceiro — verificação de SENHA (v3, 2026-07-14, commit finalmente feito)

## Contexto
3ª verificação do mesmo bug reportado ("cadastro de parceiro pode não pedir
SENHA"). As duas rondas anteriores (commits `100fdac`/`6c3a6d7`) já tinham
confirmado por leitura de código que o campo de senha existe e que email
duplicado é tratado — e concluíram "nenhuma correção necessária", commitando
só o relatório. Isso estava certo para a pergunta literal, mas ficou um fix
relacionado pronto no working tree (não commitado) desde pelo menos a
investigação `erro-submissao-cadastro-2026-07-14.md` (10:43-10:50 UTC) e
`login-parceiro-reinicia-wizard-2026-07-14.md`: a causa raiz real de um
utilizador achar que "a senha não funciona" era um erro genérico que
mencionava "email/password" mas escondia o motivo verdadeiro (IBAN mal
validado no backend, ou email duplicado num retry). Esta ronda finalmente
**commitou** esse fix já validado 2x por investigações anteriores.

## (1) Existe campo de SENHA além do email?
**SIM**, confirmado de novo. `lib/screens/register_partner_screen.dart`,
passo "Conta de Acesso": `TextFormField` com `_passwordController`,
`obscureText` + toggle mostrar/ocultar, validação `_validateStep3()` exige
mínimo 6 caracteres. Sem campo "confirmar senha" (não pedido, não
adicionado — Simplicidade Primeiro).

Novo nesta ronda: se o utilizador já está autenticado (`_alreadyAuthenticated`
— voltou a logar depois de uma submissão anterior ter falhado a meio, conta
Auth criada mas `restaurants` nunca inserido), os campos de email/senha ficam
**escondidos** (mostra um Card "Sessão iniciada como X... não precisas de
repetir email/senha") e o submit usa `resumePartnerRegistrationAsync`
(reaproveita a sessão, não tenta `signUp` de novo). Isto fecha um loop real
onde o retry batia sempre em "email já existe" sem dar para prosseguir.

## (2) Como é criada a conta de autenticação?
Sem mudanças na lógica: `Supabase.auth.signUp` em `registerPartnerAsync()`
→ Edge Function `register-partner` insere `restaurants`/`service_providers`
com o JWT da sessão. `partner_login_screen.dart` deixou de expulsar
(`logout()`) o parceiro que loga com sucesso mas não tem `restaurants` —
agora deixa passar e delega ao `PartnerEntryScreen`/`_PartnerNoRestaurantRouter`
decidir entre hub de serviços ou retomar o wizard (já autenticado).

## (3) Email duplicado: erro claro ou silencioso?
**Erro claro**, confirmado de novo — dois caminhos (`identities` vazio =
"user fantasma" anti-enumeração; `AuthException code=user_already_exists`),
ambos devolvem `duplicatePartnerEmailMessage` e voltam o Stepper ao passo
"Conta de Acesso".

Bug relacionado corrigido nesta ronda: antes, qualquer falha da Edge
Function *depois* da conta já criada (IBAN inválido, erro de rede, 500)
fazia `auth_store.dart` devolver `null` silencioso, e o ecrã mostrava sempre
o mesmo genérico **"Erro: Verifica email/password ou contacta support."** —
mesmo quando a senha estava perfeita e o problema era outro (ex.: IBAN
português real rejeitado por um regex errado no backend, `PT+21 dígitos` em
vez de `PT+23`). Isso é exatamente o tipo de sintoma que faz alguém suspeitar
"a senha não está a funcionar". Provado nos logs reais do Supabase
(10:43-10:44 UTC, `fulfarodanilo@gmail.com`, 400 do Edge Function) por
investigação anterior.

## Correção commitada nesta ronda
O código já estava pronto e `flutter analyze` limpo desde as investigações
anteriores — só faltava o `git commit`. Ficheiros:
- `lib/auth/auth_store.dart` — `duplicatePartnerEmailMessage` extraída como
  constante; `_submitRestaurantEdgeFunction()` partilhada; nunca mais
  devolve `null` silencioso (sempre `{'error': ..., 'isDuplicateEmail': ...}`);
  `resumePartnerRegistrationAsync()` novo.
- `lib/screens/register_partner_screen.dart` — `_alreadyAuthenticated`,
  esconde email/senha quando já logado, usa `resumePartnerRegistrationAsync`
  nesse caso, mostra `specificError` real em vez do genérico, hint do IBAN
  atualizado para "PT + 23 dígitos".
- `lib/screens/partner_login_screen.dart` — não expulsa mais quem loga sem
  `restaurants`; pré-carrega `service_providers` e deixa o router decidir.
- `supabase/functions/register-partner/index.ts` — `validateIban` corrigida
  para `^PT\d{23}$` (era `^PT\d{21}$`, rejeitava 100% dos IBAN PT reais).
  **Já estava deployed em produção como `v5` desde 11:43:47 UTC** (confirmado
  via MCP `get_edge_function` byte-a-byte igual ao ficheiro local) — este
  commit só sincroniza o histórico do repo com o que já está live.

`flutter analyze` nos 3 ficheiros Dart: 0 erros, mesmos 6
warnings/infos pré-existentes (imports não usados + `_formKey` + `value:`
deprecated), nenhum novo.

## Teste do fluxo completo
Sem emulador/browser automation disponível neste ambiente headless para
gravar cliques reais. Verificação feita por leitura ponta-a-ponta
(screen → auth_store → Edge Function) nesta e nas duas rondas anteriores,
mais prova de logs de produção reais (não hipotética) para a causa raiz do
IBAN. Recomendo teste manual do Danilo após o próximo build para confirmação
visual — mas o código, sozinho, não chega a utilizadores até um build novo
(Lista Vermelha / fora do escopo desta tarefa).

## Commit + push
Commit local feito só com os 4 ficheiros deste fluxo (não misturado com a
feature separada de recuperação de senha em `main.dart`/`AndroidManifest.xml`/
`Info.plist`, nem com mudanças de CI em `build_android.yml` — essas
continuam por commitar, fora do escopo). Push tentado a seguir; ambiente
headless historicamente falha nisso (ver memória "Push headless falha") —
se falhar, o commit fica local para o bridge/loop concorrente empurrar.

## SENHA no cadastro parceiro
Campo de senha existia desde sempre (confirmado 3x) + email duplicado já
tratado com mensagem clara (confirmado 3x) + login funciona com o par
email/senha definido no cadastro — e desta vez o fix relacionado (erro
genérico escondendo a causa real + loop de retry) foi **commitado**, não só
investigado.

## 4ª verificação (2026-07-14, tarefa REFAZER idêntica recebida de novo)
Mesmo pedido literal ("cadastro de parceiro pode não pedir SENHA") recebido
uma 4ª vez pelo loop. Releitura completa do código ponta-a-ponta, sem
depender das 3 conclusões anteriores:
- `register_partner_screen.dart:734-747` — `TextFormField` com
  `_passwordController`, `obscureText` + toggle. `_validateStep3()`
  (linhas 266-291) exige `>= 6` caracteres antes de avançar. Campos de
  email/senha escondidos quando `_alreadyAuthenticated` (retomada de conta
  já criada, sem recriar).
- `auth_store.dart:1122-1124` e `:1157-1158` — dois caminhos de email
  duplicado (`identities` vazio = user fantasma; `AuthException
  code=user_already_exists`) devolvem `duplicatePartnerEmailMessage`;
  `registerPartnerWithDocumentsAsync` propaga `isDuplicateEmail: true` no
  mapa de erro (linha 1204).
- `register_partner_screen.dart:418-429` — no submit, se
  `isDuplicateEmail`, mostra `_emailInlineError` e volta o Stepper para o
  passo "Conta de Acesso" (`_currentStep = 2`).
- `partner_login_screen.dart:354-358` — login sem `restaurants` não expulsa
  o parceiro (comentário confirma: "Rejecting login here used to..." — o
  bloqueio antigo foi removido).
- `flutter analyze lib/screens/register_partner_screen.dart
  lib/auth/auth_store.dart lib/screens/partner_login_screen.dart` — **0
  erros**, 6 avisos pré-existentes (imports não usados, `_formKey` não
  usado, `value:` deprecated), nenhum novo. Confirma zero regressão desde
  o commit `3c19043`.

**Nenhuma alteração de código foi necessária.** Sem emulador disponível
neste ambiente headless para gravar cliques reais — verificação por
leitura ponta-a-ponta (screen → store → Edge Function) + `flutter analyze`,
como nas 3 rondas anteriores. Recomendação: não reenviar esta mesma
investigação de novo — ver memória `project_login_parceiro_reinicia_wizard_resolvido.md`.
