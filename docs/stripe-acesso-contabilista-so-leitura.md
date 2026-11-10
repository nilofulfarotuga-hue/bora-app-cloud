# Dar ao contabilista acesso SÓ DE LEITURA à Stripe da empresa

> Missão fecho-contabilista-2026-11-10, bloco E (10/11/2026). **Só preparado — ninguém foi convidado.**
> Pendência no `e2e_log`: fluxo `pendencias-proxima-missao`, passo `stripe-hugo-so-ver`, e fluxo
> `fecho-contabilista-2026-11-10`, passo `E-stripe-hugo`.

## O que falta antes de fazer

1. **O email do Hugo Carvalho (DC Consultores).** Não está no sistema
   (`platform_settings.fecho_contabilista_email` está vazio). Quando chegar, grava-se também lá, para o
   fecho do dia 1 lhe ir por email.
2. **O "autorizo" do Danilo no momento.** Convidar um membro mexe na conta Stripe (é uma alteração de
   acessos), por isso não se faz sem a palavra dele nesse dia.
3. **A conta certa.** É a Stripe NOVA da empresa (Danilo Fulfaro da Silva - Unipessoal Lda, NIPC
   519686233), separada da pessoal. A Stripe pessoal antiga fica fora (regra de 10/11: o Hugo trata
   dela à parte).

## Passo a passo (quem tiver o login de administrador da Stripe da empresa)

1. Entrar em <https://dashboard.stripe.com> com a conta da empresa e confirmar, no canto de cima à
   esquerda, que a conta aberta é a da sociedade (não a pessoal).
2. Abrir **Definições → Equipa e segurança → Equipa** (<https://dashboard.stripe.com/settings/team>).
3. Carregar em **Adicionar membro** (*Add member*).
4. Escrever o email do Hugo.
5. Em **Funções** (*Roles*) escolher **só "Só visualização"** (*View only*). Não marcar mais nenhuma.
   - *View only* deixa ver pagamentos, reembolsos, transferências para o banco, faturas e relatórios,
     e exportar — mas não deixa alterar nada nem mexer em dinheiro.
   - Não dar *Administrator*, *Developer*, *Analyst*, *Refund Analyst* nem *Transfer Analyst*.
6. Se a Stripe perguntar a que contas se aplica, escolher **só a conta da empresa** (não a
   organização inteira, para não abrir a pessoal se estiverem na mesma organização).
7. Rever e carregar em **Enviar convites** (*Send invites*). O Hugo recebe um email da Stripe para
   aceitar e criar a palavra-passe dele (com verificação em dois passos).
8. Confirmar na lista da **Equipa** que o Hugo aparece com o papel *View only* e o estado
   "Convidado" e, depois de ele aceitar, "Ativo".

## Depois de feito

- Registar no `e2e_log` (fluxo `pendencias-proxima-missao`, passo `stripe-hugo-so-ver`, estado `ok`)
  com a data, quem convidou e o papel.
- Gravar o email do Hugo em `platform_settings.fecho_contabilista_email` (painel admin) para o fecho
  automático do dia 1 lhe ir também por email.
- Tirar o acesso, se um dia for preciso: na mesma página **Equipa**, menu (⋯) na linha do Hugo →
  **Remover membro**. Perde o acesso na hora.

## Fonte

Documentação da Stripe: "Manage access to your organization" (Add a team member) e a lista de papéis
do Dashboard (`view_only` = *View only*), consultada a 10/11/2026.
