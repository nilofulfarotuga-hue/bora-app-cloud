# App Review Information — Bora

> Texto para colar em **App Store Connect → App Review Information → Notes**.
> Em inglês, porque é quem o lê. Pontos curtos, sem prosa.
> Escrito 2026-09-07 (missão `ios-lancamento`). Rever antes de submeter.

---

## Demo accounts — please use the right one for each test

| Account | Password | Use it for |
|---|---|---|
| `demo@bora.app` | `BoraDemo2026!` | **Browsing the app.** Do NOT delete this account. |
| `demo.apagar@bora.app` | `BoraDemo2026!` | **Testing account deletion only.** Disposable. |

**Why two accounts:** deleting an account is permanent and irreversible by design
(guideline 5.1.1(v)). If you delete the browsing account you lose access mid-review.
`demo.apagar@bora.app` exists solely for that test and is automatically recreated
every hour, so it is always available even if you delete it more than once.

---

## Notes to paste (English)

```
THE APP
Bora is a local delivery and services marketplace for the city of Guarda, Portugal
(population ~40,000). One app, three profiles: customer, courier, and partner store.

REVIEWING FROM OUTSIDE PORTUGAL
The app serves Guarda only. The demo account has a saved address in Guarda, so
stores load without needing GPS or being physically in Portugal. You can also browse
as a guest without an account.

TWO DEMO ACCOUNTS — PLEASE READ
  Browsing:  demo@bora.app / BoraDemo2026!   (do not delete this one)
  Deletion:  demo.apagar@bora.app / BoraDemo2026!   (disposable, for the 5.1.1(v) test)
Deletion is permanent by design. The second account exists so that testing deletion
does not lock you out of the app. It is automatically recreated every hour.

ACCOUNT DELETION (5.1.1(v))
Profile > "Apagar conta" (Delete account), inside the app, no email required.
Personal data is destroyed: name, contact details, address, photos and uploaded
documents. Access is permanently revoked — the credentials stop working and password
recovery is not possible. Financial records are kept in anonymised form only, as
Portuguese tax law requires invoices to be retained for 10 years; they no longer
carry the person's name or contacts. If the account has an order, booking or ride in
progress, the app explains what is blocking and asks the user to wait.

PLACING A TEST ORDER
Choose "Dinheiro" (Cash) as the payment method. Card and MB WAY are live payment
methods and would charge a real card. Orders placed from the demo account are
sandboxed and are never dispatched to real couriers.

PAYMENTS (3.1.5(a))
All payments are for physical goods and services consumed outside the app (food and
grocery delivery, cleaning, rides, bookings). No digital content is sold, so no
in-app purchase is used.

BACKGROUND LOCATION (courier profile only)
Location in the background is only used while a courier is actively Online and
carrying a delivery. A prominent disclosure screen is shown BEFORE the system
permission prompt, and the iOS background location indicator stays visible while
tracking. Customers never have background location.

THIRD-PARTY NAMES
Store names shown in the app are used descriptively, to say where an order is
collected from. Partner stores have signed agreements with us.

NO ACCOUNT REQUIRED TO BROWSE
The app opens and shows stores without signing in (4.0).

CONTACT
boraappbora@gmail.com · +351 937 501 673
```

---

## URLs para o App Store Connect — ATENÇÃO ao endereço

O site redireciona `/privacidade.html` → `/privacidade` com **HTTP 308**. O que
vai para a Apple é o endereço **final**, sem `.html` — um URL que redireciona
funciona, mas é ruído desnecessário numa revisão.

| Campo no App Store Connect | URL |
|---|---|
| Privacy Policy URL | `https://boraguarda.com/privacidade` |
| Support URL | `https://boraguarda.com/faq` |
| Marketing URL | `https://boraguarda.com` |

Verificado no ar a 2026-09-07: HTTP 200, sem marcadores por preencher, com o
responsável identificado (Danilo Fulfaro da Silva, empresário em nome
individual, NIF 322151171) e com a secção 6 sobre eliminar a conta.

## Por fazer antes de submeter

- [ ] Link do vídeo demonstrativo no YouTube (não listado) — Bloco 4, por gravar
      assim que o Job A compilar.
