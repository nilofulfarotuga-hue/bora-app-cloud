# Cadastro de parceiro — verificação de SENHA (v2, 2026-07-14)

## Contexto
Tarefa pedia para REFAZER a verificação de um possível bug: cadastro de parceiro
poderia não pedir SENHA. Investigação por leitura de código (sem device/emulador
disponível para gravar cliques reais — ver nota no fim).

## (1) Existe campo de SENHA além do email?

**SIM.** `lib/screens/register_partner_screen.dart` linhas 733-752, no passo
"Conta de Acesso" (Step 3 do Stepper):

- `TextFormField` com `controller: _passwordController`, `obscureText`,
  ícone de mostrar/ocultar senha.
- Validação em `_validateStep3()` (linha 277-282): mínimo 6 caracteres,
  bloqueia avançar com SnackBar "Senha mínima de 6 caracteres".
- Não existe campo separado "confirmar senha" — só um campo de senha. A
  tarefa não pediu isso como correção obrigatória (só perguntou se existe
  campo de senha), então não foi adicionado (Simplicidade Primeiro — não
  adicionar UI não pedida).

Exceção: se o utilizador já está autenticado (`_alreadyAuthenticated`, caso de
retomar um cadastro cuja submissão anterior falhou a meio), o passo não pede
email/senha de novo — mostra um Card informativo e reaproveita a sessão.

## (2) Como é criada a conta de autenticação no fim?

Fluxo em `lib/auth/auth_store.dart`:

1. `registerPartnerWithDocumentsAsync()` chama `registerPartnerAsync()`, que
   faz `Supabase.auth.signUp(email, password, data: {...})` — cria a conta
   real no Supabase Auth com `bora_role=partner`.
2. Se `res.session == null` (confirmação de email exigida por config), tenta
   `signInWithPassword` na hora para já deixar sessão ativa.
3. Com o JWT da sessão, invoca a Edge Function `register-partner`
   (`supabase/functions/register-partner/index.ts`), que extrai `user_id` do
   token e faz `INSERT` em `restaurants` (ou `service_providers` p/ categoria
   `beauty`) com `approval_status='pending'`.

Login subsequente (`partner_login_screen.dart` → `loginPartnerAsync`,
auth_store.dart:1349) cai no fallback `signInWithPassword` para contas não
hardcoded — o mesmo par email/senha definido no cadastro funciona para logar
depois.

## (3) Email já existente: erro claro ou falha silenciosa?

**Erro claro, tratado em dois caminhos** (auth_store.dart):

- Supabase devolve um "user fantasma" com `identities` vazio quando o email
  já tem conta confirmada (proteção anti-enumeração, não lança exceção) —
  detetado explicitamente (linha 1122-1124).
- `AuthException` com `code == 'user_already_exists'` (HTTP 422) — validado
  ao vivo contra o projeto Supabase (comentário no código confirma).

Ambos os casos devolvem a constante `duplicatePartnerEmailMessage` = "Este
email já tem uma conta. Faz login em vez de criar uma nova conta." O ecrã
(`register_partner_screen.dart:418-438`) mostra isso como `errorText` inline
no campo de email **e** SnackBar, e volta automaticamente ao passo "Conta de
Acesso" (`_currentStep = 2`) para o utilizador corrigir.

## Correções aplicadas
**Nenhuma.** As três perguntas já estavam resolvidas no código atual — não é
código novo desta sessão (não aparece nos commits recentes tocando estes
ficheiros; a funcionalidade é mais antiga). `flutter analyze` nos dois
ficheiros: 0 erros (só 4 warnings de imports não usados + 1 campo não usado
+ 1 info de API deprecated, pré-existentes, fora do escopo desta tarefa).

## Limitação do teste
Não havia emulador Android/iOS nem ferramenta de automação de browser
disponível neste ambiente headless para gravar o fluxo real (criar conta com
email novo, submeter, logout, logar de novo). A verificação foi feita por
leitura completa do código-fonte (screen → auth_store → Edge Function) e
confirmação de que a lógica é consistente ponta-a-ponta. Recomendo um teste
manual rápido do Danilo caso queira confirmação visual.

## Sem push
Sem alterações de código — nada para commitar além deste relatório. Commit
local apenas (push seguiria bloqueado por Lista Vermelha/ambiente headless,
mas não se aplica aqui pois não há mudança funcional).
