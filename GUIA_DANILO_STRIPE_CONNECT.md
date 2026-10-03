# GUIA — Stripe Connect passo a passo (pra você, Danilo)

> Fase 1 (2026-08-06): abrir contas, ver o estado delas e mostrar o extrato.
> **Nenhum dinheiro se move automaticamente ainda** — o acerto semanal continua
> manual. As transferências automáticas são a Fase 2.

---

## 1. Ativar o Connect no dashboard da Stripe

1. Entre em **https://dashboard.stripe.com** com a conta da Bora.
2. No menu da esquerda, clique em **Connect** (ícone de duas setas). Se for a
   primeira vez, aparece um botão **"Get started"** / **"Começar"**.
3. Escolha **"Platform or marketplace"** (plataforma/marketplace).
4. A Stripe vai pedir para **aceitar os termos de plataforma** ("Stripe
   Connected Account Agreement" + responsabilidades de plataforma). Leia e
   aceite — sem isso nada funciona.
5. Em **Connect → Settings** (Configurações do Connect):
   - **Branding**: coloque o nome "Bora", o logo (o B verde) e a cor
     `#16A34A`. É isso que o parceiro vê no onboarding.

## 2. Modelo de preços + criar o webhook novo

**Modelo de preços:**
1. Ainda em **Connect → Settings**, procure a seção de **pricing** /
   **"Who pays Stripe fees"**.
2. Escolha a opção em que **a plataforma gerencia os preços** ("You handle
   pricing and fees" / "Platform handles pricing"). É o modelo em que a Bora
   decide quem paga a taxa — que é exatamente o que a chave
   `stripe_fee_bearer` controla no nosso banco.

**Webhook novo (NÃO mexa no webhook que já existe!):**
1. Vá em **Developers → Webhooks** (Desenvolvedores → Webhooks).
2. Clique **"+ Add endpoint"** e cole esta URL:
   ```
   https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-connect-webhook
   ```
3. **IMPORTANTE:** marque **"Listen to events on Connected accounts"**
   (eventos de contas conectadas) — NÃO o modo "account" normal. Sem isso os
   eventos das contas dos parceiros não chegam.
4. Em **"Select events"**, marque exatamente estes 4:
   - `account.updated`
   - `account.application.deauthorized`
   - `payout.paid`
   - `payout.failed`
5. Salve. Na página do endpoint, clique em **"Reveal"** no
   **Signing secret** (começa com `whsec_...`) e copie.

## 3. Colar o secret no Supabase

1. Entre em **https://supabase.com/dashboard** → projeto **Bora**
   (`ojykpzwqrtusfeakzrna`).
2. Menu **Edge Functions → Secrets** (ou Settings → Edge Functions).
3. Clique **"Add new secret"** e crie com o nome EXATO:
   ```
   STRIPE_CONNECT_WEBHOOK_SECRET
   ```
   e cole o `whsec_...` que copiou no passo 2.
4. Enquanto esse secret não existir, o webhook responde 400 e não aceita
   nada (é de propósito — fail-closed, ninguém consegue forjar eventos).

Para o **modo teste** (passo 5) você também vai precisar de:
```
STRIPE_TEST_SECRET_KEY   →  a chave sk_test_... (Developers → API keys, com "Test mode" ligado)
BORA_STRIPE_MODE         →  test   (⚠️ voltar para "live" depois do teste!)
```
> ⚠️ `BORA_STRIPE_MODE=test` também muda o TVDE para modo teste (é o mesmo
> interruptor). Faça o teste num horário sem corridas, e volte para `live`
> logo depois.

## 4. Cadastro presencial com um parceiro (caso do Gilberto, Ouro e Prata)

O que levar/pedir (15–20 minutos no total):

1. **Antes de ir**: no painel admin → **Pagamentos Connect** → linha do
   parceiro → **"Reenviar link de cadastro"**. Abra o link no celular DELE
   (ou copie e mande por WhatsApp na hora).
2. **O que ele precisa ter em mãos:**
   - Cartão de Cidadão (ou título de residência) — a Stripe pede foto
     frente e verso em alguns casos;
   - **IBAN** da conta onde quer receber (foto do comprovativo ajuda);
   - **NIF** (pessoal e/ou da empresa);
   - Se for empresa (Lda./ENI): nome exato como está nas Finanças;
   - Celular (recebe SMS de confirmação) e email.
3. **O que ele confirma pessoalmente no telefone:** os dados, o IBAN, e o
   aceite dos termos da Stripe (último botão do fluxo).
4. A verificação da Stripe demora de **alguns minutos a 1-2 dias úteis**.
   O estado muda sozinho no app dele ("Em verificação" → "A receber
   normalmente") e no seu painel — é o webhook trabalhando.
5. Se ficar **"Bloqueado — faltam dados"**: o app dele mostra em português
   o que falta; é só tocar em "Continuar" e completar.

## 5. Testar em modo teste ANTES de ligar

1. Configure `STRIPE_TEST_SECRET_KEY` e `BORA_STRIPE_MODE=test` (passo 3).
2. No dashboard da Stripe, ligue o **"Test mode"** (canto superior direito)
   e crie um webhook de teste igual ao do passo 2 (test mode tem secret
   próprio — atualize `STRIPE_CONNECT_WEBHOOK_SECRET` com ele durante o teste).
3. No app (com uma conta de parceiro de teste), toque em
   **"Receber pagamentos" → Começar**. No onboarding de teste a Stripe
   aceita dados falsos (IBAN de teste: `PT50000201231234567890154`,
   telefone `000 000 000`, código SMS `000-000`).
4. Confira: painel admin → Pagamentos Connect → o estado do parceiro deve
   virar **"Ativa"** sozinho (webhook → banco). Se não virar, use
   **"Re-sincronizar"** na mesma tela e me avise.
5. Só depois de ver isso funcionando: volte `BORA_STRIPE_MODE=live`,
   reponha o secret do webhook live, e aí sim (quando a Fase 2 estiver
   pronta e você quiser) ligue `stripe_connect_enabled` no painel.

---

### Resumo do que já está pronto no sistema

| Peça | Onde |
|---|---|
| Colunas Connect nas 4 tabelas | `restaurants`, `service_providers`, `drivers`, `cleaners` |
| Configurações | `platform_settings` categoria `stripe_connect` (edita no painel admin) |
| Onboarding | Edge Function `stripe-connect-onboard` |
| Webhook Connect | Edge Function `stripe-connect-webhook` (separado do webhook de pagamentos) |
| Ações de admin | Edge Function `stripe-connect-admin` |
| Extrato | tabela `partner_statement_lines` + RPC `get_statement` |
| App parceiro/estafeta | "Receber pagamentos" + "Extrato" (PT-PT) |
| Painel admin | "Pagamentos Connect" (PT-BR) |

**Fase 2 (próximo prompt):** transferências automáticas no acerto semanal.
