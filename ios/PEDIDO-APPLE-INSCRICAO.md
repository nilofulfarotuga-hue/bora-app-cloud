# Pedido de informação à Apple — inscrição TPBAQ8K3TF

> Escrito 2026-09-08 na missão `ios-lancamento`. **Não enviado** — só o Danilo
> envia, ou autoriza que se envie.
>
> **Onde se envia:** <https://developer.apple.com/contact/> — é o "contact us"
> que a própria Apple indica em
> <https://developer.apple.com/support/purchase-activation/>, na frase
> *"If you haven't received a membership confirmation within 24 hours of your
> purchase, contact us."*

---

## Porque se abre este caso

O que a Apple diz que devia ter acontecido, citado da página acima:

1. *"When you've submitted your purchase, you'll receive an **order
   acknowledgement email**."*
2. *"After your purchase has been processed, you'll receive a **confirmation
   email**."*
3. *"If you haven't received a membership confirmation **within 24 hours** of
   your purchase, contact us."*

O que se mediu a 2026-09-08, tudo de primeira mão:

| O quê | Onde se mediu | Resultado |
|---|---|---|
| Estado da inscrição | API do portal, `getTeams` | `enrollmentId TPBAQ8K3TF`, `enrollmentStatus "p"` (pending), `entityType "i"` (individual), `product "ad19"`, **`screeningStatus "purchase"`** |
| Equipas | mesma resposta | `teams: []`, `developers: 0` |
| App Store Connect | `olympus/v1/session` | HTTP 200 com o utilizador certo, mas **`provider: null`**, `availableProviders: []`, `roles: []`, `modules: []` |
| Histórico de compras | reportaproblem.apple.com | *"É necessário usar uma conta Apple que tenha sido utilizada anteriormente"* — a conta não tem compras |
| Emails da Apple | Gmail, `in:anywhere`, últimos 4 dias | **só dois**: "Agreement signed: Apple Developer Agreement" e o código de confirmação de email. **Nenhum** order acknowledgement, confirmação, recibo ou welcome |
| Banco | extracto do Danilo | 99,00 € cativados a 08/09 para **APPLE COM**, cartão terminado em **9744**, Novobanco, em processamento |

Ou seja: o banco mostra uma **cativação**, e o sistema da Apple **não mostra
compra nenhuma** — a inscrição está parada exactamente no passo `purchase`, e
nem o *order acknowledgement* chegou.

---

## Texto a enviar (inglês)

```
Subject: Enrollment TPBAQ8K3TF stuck at purchase — payment authorised by my
bank but no order acknowledgement

Hello,

I am enrolling as an individual in the Apple Developer Program and my
enrollment is not completing. I would like to understand what happened before
I attempt any further payment, because I do not want to be charged twice.

  Enrollment ID:   TPBAQ8K3TF
  Apple Account:   boraappbora@gmail.com
  Name:            Danilo Fulfaro da Silva
  Entity type:     Individual (sole trader), Portugal
  Date:            8 September 2026

What my bank shows
  A EUR 99.00 authorisation to "APPLE COM" was placed on 8 September 2026, on
  a Novobanco card ending 9744. My bank still shows it as pending/processing.

What your systems show me
  My enrollment status is still Pending, and the account page asks me to
  "complete your purchase now". App Store Connect signs me in but shows no
  team and no provider, so there is nothing I can work with yet.

What I did not receive
  Your Purchase and Activation page states that an order acknowledgement email
  is sent when a purchase is submitted, and a confirmation email once it is
  processed. I have received neither. The only two emails I have from Apple are
  the signed Apple Developer Agreement and an Apple Account email verification
  code, both from 8 September 2026.

My questions
  1. Did Apple receive and record a membership purchase for enrollment
     TPBAQ8K3TF? If so, what is its status?
  2. If no purchase was recorded, can the EUR 99.00 authorisation on my card be
     released, so that I am not charged for a membership I do not have?
  3. How should I complete the enrollment without risking a second charge?

I have deliberately not pressed the purchase button again. I can provide the
bank statement showing the authorisation if that helps.

Thank you,
Danilo Fulfaro da Silva
boraappbora@gmail.com
+351 937 501 673
```

---

## Regras para quem enviar isto

- **Nunca pagar outra vez.** Se a Apple pedir para repetir a compra, primeiro
  perguntar o que acontece à cativação de 99 € que já existe.
- Não aceitar nenhum acordo novo para "desbloquear" — em especial o
  *Alternative Terms Addendum for Apps in the EU*, que não se assina.
- Guardar o número do caso aqui e em `ios/LANCAMENTO-IOS-ESTADO.md`.
