# Guia — deixar o "Esqueci a senha" funcionando de verdade

**Data:** 31/07/2026 · **Tempo estimado:** 25 min (+ espera do DNS)
**Painel:** https://supabase.com/dashboard/project/ojykpzwqrtusfeakzrna

O código do app, do site e do painel admin **já está pronto e no ar**.
O que falta é só o que exige o **seu login** no Supabase e no Resend.

---

## ⚠️ Leia isto primeiro (30 segundos)

O envio de e-mail do Bora usa o **Resend**. Ele já está configurado —
mas está em **modo teste**. Modo teste significa: o Resend só entrega
e-mail para **um único endereço**, o `nilofulfarotuga@gmail.com`.

Traduzindo: hoje, se um cliente clicar em "Esqueci a senha", o servidor
aceita o pedido, o app diz "verifique seu e-mail"… **e o e-mail nunca sai**.
Nem para o `boraappbora@gmail.com`. Confirmei isso no log de hoje:

```
550 "You can only send testing emails to your own email address
(nilofulfarotuga@gmail.com). To send emails to other recipients,
please verify a domain at resend.com/domains"
```

Para sair do modo teste o Resend exige **um domínio seu**. Não dá para usar
`@gmail.com` — o Resend (como qualquer serviço sério de e-mail) não deixa
enviar em nome de um domínio que não é seu.

**Por isso o passo 1 é comprar um domínio.** Sem ele, nada do resto funciona.

---

## PASSO 1 — Comprar o domínio (~€12/ano)

O `boraapp.pt` está **livre** (verifiquei hoje). `bora.pt` e `boraapp.com`
já têm dono.

1. Abra https://www.amen.pt ou https://www.ptisp.pt (registradores portugueses).
2. Busque `boraapp.pt`.
3. Compre. Custa por volta de **€12 a €15 por ano**.
4. Anote o login do painel do registrador — vai precisar no passo 3.

> Não comprei por você porque é pagamento com o seu cartão.

**Por que recomendo continuar no Resend** (e não trocar por Brevo/SendGrid):
ele **já está ligado** ao Supabase — só falta verificar o domínio.
Trocar de serviço significa refazer a configuração inteira sem ganhar nada.
O plano grátis do Resend dá **3.000 e-mails por mês / 100 por dia**.
O Bora hoje tem 9 contas. Sobra muito.

---

## PASSO 2 — Verificar o domínio no Resend

1. Abra https://resend.com/domains
2. Entre com a conta que já existe (a do `nilofulfarotuga@gmail.com`).
3. Clique no botão **"Add Domain"** (canto superior direito).
4. Digite: `boraapp.pt`
5. Em "Region", escolha **EU (Ireland)** — é onde o Supabase do Bora está.
6. Clique **"Add"**.
7. A tela mostra **3 ou 4 linhas de DNS** (tipo MX, TXT e CNAME).
   **Deixe essa aba aberta** — vai copiar de lá no próximo passo.

---

## PASSO 3 — Colar o DNS no registrador

1. Abra o painel do registrador onde comprou o `boraapp.pt`.
2. Procure **"Gerir DNS"** / **"Zona DNS"** / **"DNS Records"**.
3. Para **cada linha** que o Resend mostrou, clique em "Adicionar registo" e copie:
   - **Tipo** (MX, TXT ou CNAME) → o mesmo do Resend
   - **Nome / Host** → o mesmo do Resend
   - **Valor / Destino** → o mesmo do Resend
4. Salve.
5. Volte na aba do Resend e clique **"Verify DNS Records"**.
6. Se aparecer "Pending", **espere e tente de novo**. O DNS demora de
   15 minutos a 4 horas. Não é erro seu.
7. Quando ficar **"Verified"** (verde), siga em frente.

---

## PASSO 4 — Trocar o remetente no Supabase

1. Abra https://supabase.com/dashboard/project/ojykpzwqrtusfeakzrna/settings/auth
2. Role até a seção **"SMTP Settings"**.
3. No campo **"Sender email"**, apague o que está lá e escreva:
   ```
   nao-responder@boraapp.pt
   ```
4. No campo **"Sender name"**, escreva:
   ```
   Bora
   ```
5. Confirme que **"Enable Custom SMTP"** está **ligado**.
6. Confirme que o Host é `smtp.resend.com` e a Port é `465`.
7. Clique em **"Save changes"** no fim da seção.

> Se o campo de senha (API key) estiver vazio ao salvar, gere uma nova em
> https://resend.com/api-keys → "Create API Key" → cole no campo
> **"Password"**. O usuário continua sendo `resend`.

---

## PASSO 5 — Site URL e Redirect URLs

1. Abra https://supabase.com/dashboard/project/ojykpzwqrtusfeakzrna/auth/url-configuration
2. Em **"Site URL"**, deixe exatamente:
   ```
   https://bora-app-web.pages.dev
   ```
3. Em **"Redirect URLs"**, clique **"Add URL"** e cole **uma de cada vez**:
   ```
   https://bora-app-web.pages.dev/#/redefinir-palavra-passe
   ```
   ```
   https://bora-app-web.pages.dev/**
   ```
   ```
   pt.boraapp.bora://reset-password
   ```
4. Clique **"Save"**.

> A primeira é a página nova de redefinir senha (é para lá que o link do
> e-mail leva). A segunda cobre o resto do site. A terceira é o link que
> abre o app no celular — **não apague**, os e-mails antigos ainda usam.

⚠️ **Não mude esse endereço depois.** Ele fica gravado no template do e-mail
e nos e-mails já enviados. Mudar quebra todos os links em trânsito.

---

## PASSO 6 — Texto do e-mail em português

1. Abra https://supabase.com/dashboard/project/ojykpzwqrtusfeakzrna/auth/templates
2. No menu da esquerda, clique em **"Reset Password"**.
3. No campo **"Subject heading"**, apague o texto em inglês e cole:
   ```
   Bora — redefinir a sua palavra-passe
   ```
4. No campo grande **"Message body"**, apague **tudo** e cole isto:

```html
<div style="font-family:Inter,Arial,sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="font-size:28px;font-weight:800;color:#16A34A;margin-bottom:24px">BORA</div>

  <h1 style="font-size:22px;font-weight:700;margin:0 0 12px">Redefinir a sua palavra-passe</h1>

  <p style="font-size:15px;line-height:1.6;margin:0 0 24px">
    Recebemos um pedido para definir uma nova palavra-passe na sua conta Bora.
    Carregue no botão abaixo para escolher uma nova.
  </p>

  <a href="{{ .ConfirmationURL }}"
     style="display:inline-block;background:#16A34A;color:#ffffff;text-decoration:none;
            font-size:16px;font-weight:600;padding:14px 28px;border-radius:10px">
    Definir nova palavra-passe
  </a>

  <p style="font-size:13px;line-height:1.6;color:#6B7280;margin:24px 0 0">
    Esta ligação é válida durante 1 hora e só pode ser usada uma vez.
  </p>

  <p style="font-size:13px;line-height:1.6;color:#6B7280;margin:12px 0 0">
    Se não foi você que fez este pedido, ignore este email — a sua
    palavra-passe atual continua a funcionar.
  </p>

  <hr style="border:none;border-top:1px solid #E5E7EB;margin:28px 0 16px">

  <p style="font-size:12px;color:#9CA3AF;margin:0">
    Bora — entregas, boleias e serviços na Guarda.<br>
    Este email foi enviado automaticamente. Não responda.
  </p>
</div>
```

5. Clique **"Save"**.

> O `{{ .ConfirmationURL }}` é o que vira o link. **Não apague nem edite** —
> é ele que carrega o token.

---

## PASSO 7 — Testar (é você que prova que funciona)

Use um e-mail seu que **não seja** o `nilofulfarotuga@gmail.com` —
esse funciona mesmo em modo teste e não prova nada. Use o `boraappbora@gmail.com`.

1. Abra https://bora-app-web.pages.dev
2. Escolha **Cliente** → tela de login.
3. Clique em **"Esqueci-me da palavra-passe"**.
4. Digite `boraappbora@gmail.com` → **"Enviar ligação"**.
5. A tela deve mostrar **"Verifique o seu email"**.
6. Abra o Gmail do `boraappbora@gmail.com`. O e-mail deve chegar em
   menos de 1 minuto (**veja o spam** na primeira vez).
7. Confira: assunto em português, botão verde, remetente `@boraapp.pt`.
8. Clique no botão verde.
9. Deve abrir a página **"Nova palavra-passe"** com dois campos.
10. Digite uma senha nova (mínimo 6) nos dois campos → **"Guardar nova palavra-passe"**.
11. Deve aparecer **"Palavra-passe alterada"**.
12. Volte ao login e entre com a senha nova. **Se entrar, está funcionando.**

**Teste extra (30 s):** clique **outra vez** no mesmo link do e-mail.
Tem que aparecer **"Ligação inválida"** com o botão "Pedir nova ligação".
Isso prova que o link é de uso único.

---

## O que eu já deixei pronto (só conferir)

| Item | Estado |
|---|---|
| Link "Esqueci-me da palavra-passe" no login de cliente, estafeta e parceiro | ✅ já está |
| Tela que pede o e-mail, em português de Portugal | ✅ já está |
| Resposta igual exista ou não a conta (não revela quem tem conta) | ✅ já está |
| Mensagem de "pediu rápido demais" (limite do servidor) | ✅ já está |
| Página web `#/redefinir-palavra-passe` | ✅ já está |
| Tratamento de link expirado / já usado | ✅ já está |
| Tela de nova senha com dois campos e mínimo visível | ✅ já está |
| Botão "Enviar link de redefinição de senha" no painel admin | ✅ já está |
| Painel mostra a data do último envio | ✅ já está |
| Envio fica registrado na auditoria | ✅ já está |
| Edge Function passou a mandar o endereço de retorno certo | ✅ já está (v11 no ar) |

---

## Resumo do que só você pode fazer

1. Comprar `boraapp.pt` (~€12/ano)
2. Verificar o domínio no Resend + colar o DNS
3. Trocar o remetente para `nao-responder@boraapp.pt` no Supabase
4. Colar as 3 Redirect URLs
5. Colar o texto do e-mail em português
6. Testar com o `boraappbora@gmail.com`

**Enquanto o passo 1 e 2 não estiverem feitos, o botão funciona mas o
e-mail não sai.** É esse o único bloqueio que resta.
