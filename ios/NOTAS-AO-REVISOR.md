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

FIRST SCREEN — PRIVACY AND COOKIES
The very first thing the app shows is a privacy and cookies sheet, over the
profile screen. It has three buttons: "Aceitar tudo" (Accept all), "Rejeitar"
(Reject) and "Gerir preferências" (Manage preferences). Tap any of the three to
continue — the app works fully either way. Our own automated walkthrough runs
with "Rejeitar", so nothing in the app depends on consent being granted:
notifications and GPS are the only things gated, and neither is needed to
browse, order or pay.

AFTER THAT — CHOOSE A PROFILE
The next screen asks which profile you are: "Sou Cliente" (customer), "Sou
Estafeta" (courier) or "Sou Parceiro" (partner store). For the review, tap
"Sou Cliente" and sign in with the demo account below.

REVIEWING FROM OUTSIDE PORTUGAL
The app serves Guarda only. The demo account has a saved address in Guarda
(Praca Luis de Camoes, 6300-725 Guarda), so
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

BUTTONS YOU WILL SEE (the app is in Portuguese)
  Sou Cliente / Sou Estafeta / Sou Parceiro   I am a customer / courier / partner
  Aceitar tudo / Rejeitar                     Accept all / Reject  (privacy sheet)
  Entrar                                      Sign in
  Supermercados / Restaurantes / Farmácia     Supermarkets / Restaurants / Pharmacy
  Lojas / Favores / Limpeza / Lavagem Auto    Shops / Errands / Cleaning / Car wash
  Beleza                                      Barber and beauty bookings
  Adicionar ao carrinho / Ver carrinho        Add to basket / View basket
  Finalizar pedido                            Checkout
  Dinheiro / Cartão / MB WAY                  Cash / Card / MB WAY
  Confirmar pagamento                         Confirm payment
  Em breve                                    Coming soon (store not open yet)
  Perfil > Apagar conta                       Profile > Delete account
  Agora não                                   Not now

WHAT THE APP INCLUDES
Grocery and shop delivery, pharmacy, restaurants, barber and beauty bookings,
home cleaning, errands, car wash, table reservations, party catering, and
ride-hailing ("Bora Motorista" on the home screen).

RIDE-HAILING (TVDE)
The app includes passenger ride-hailing, which in Portugal is regulated by
Decree-Law 45/2018 (TVDE). Drivers who take passenger rides are onboarded
separately from couriers and must hold a valid TVDE driver certificate and
drive a licensed TVDE vehicle; we collect and check those documents before a
driver can go online for rides. Passengers do not need any document. Our App
Store screenshots focus on delivery and services and do not feature
ride-hailing, but the feature is in the app and you will see it on the home
screen — we are not hiding it from you.

ALCOHOL AND TOBACCO
The supermarket catalogues we deliver from include alcoholic drinks, the same way
a supermarket shelf does. The app does not encourage consumption and has no
alcohol-themed content. We sell NO tobacco: we checked the whole catalogue and
the only nicotine item is a smoking-cessation gum sold by a licensed pharmacy.

REPORTING AND MODERATION (1.2)
Every conversation has a flag icon in the top bar: "Denunciar" (Report). It
offers reasons and opens our in-app support conversation with the report
already written, which our team reads and answers. Chat is one-to-one and tied
to a single order - it is not a social feed. Ratings with free text are
moderated from our admin panel and can be hidden.

SIGN IN WITH APPLE (4.8)
The app offers no third-party or social login. Accounts are email and password
only, so guideline 4.8 does not apply.

IF THE STORE LIST LOOKS EMPTY
Stores are shown for a delivery address in Guarda. The demo account already has
one saved, so this should not happen. If it does, open the address selector at
the top of the home screen and pick the saved address.

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

## Vídeo demonstrativo — onde vive e o que mostra

O YouTube saiu (decisão do Danilo, 2026-09-08): a conta `boraappbora@gmail.com`
não tem canal, e criar um obriga a aceitar os termos do YouTube e a assumir uma
identidade pública. Não vale a pena por causa de um vídeo. O vídeo passa a viver
numa página **não listada** do próprio site do Bora (`noindex, nofollow`, sem
ligação a partir de nenhum menu), e é esse endereço que vai nas notas.

O vídeo é a **app a correr a sério**, ligada ao servidor, com a conta demo — não
ecrãs desenhados. Ver `integration_test/demo_real_test.dart`.

- [ ] Endereço do vídeo — por preencher assim que a corrida do CI der capturas boas.


## Versao curta (<= 4000 caracteres) — e ESTA que vai para o campo

> O bloco longo acima tem 5720 caracteres e o campo *App Review Notes*
> do App Store Connect leva 4000. Esta e a versao que foi mesmo escrita
> na Apple, pela API, a 2026-09-08. Nao ha duas verdades: o que se muda
> aqui e o que se volta a enviar.

```
DEMO VIDEO (69 s, English captions)
https://boraguarda.com/provas/apple-review/
Launch, sign-in, all service categories, a real store, a real product at its
real price, the basket with the fee breakdown, checkout paying cash, and two
partner businesses. Captured on the iOS Simulator against our live server. An
updated recording also showing report, block and account deletion replaces it
with the next build.

WHAT BORA IS
A local delivery and services marketplace for Guarda, Portugal (~40,000
people): groceries, pharmacy, restaurants, barber and beauty bookings, home
cleaning, errands, car wash, table reservations and ride-hailing. One app,
three roles: customer, courier, partner store. Audience: adults in and around
Guarda. National delivery apps concentrate on large cities; Bora serves this
one.

DEMO ACCOUNTS
  Browsing:  demo@bora.app        / BoraDemo2026!  (do NOT delete)
  Deletion:  demo.apagar@bora.app / BoraDemo2026!  (disposable, recreated hourly)

HOW TO GET IN
1. A privacy sheet appears first: "Aceitar tudo" (Accept all), "Rejeitar"
   (Reject), "Gerir preferencias" (Manage). Any of the three continues;
   nothing in the app depends on consent.
2. Tap "Sou Cliente" (I am a customer) and sign in.
3. The demo account has a saved Guarda address, so stores load without GPS and
   from any country. If the list looks empty, open the address selector at the
   top of the home screen and pick it.
4. To order, choose "Dinheiro" (cash). Card and MB WAY are live and would
   charge a real card. Demo orders are sandboxed and never reach a real
   courier.

REPORTING AND BLOCKING (1.2)
User-generated content is one-to-one chat tied to a single order, plus star
ratings with optional text. Every conversation has a flag icon in the top bar:
it opens report reasons and, at the bottom, "Bloquear esta pessoa" (Block this
person). Blocking hides that person's messages and prevents writing to them,
with an Unblock button. Reports open our in-app support chat with the report
already written. Ratings are moderated from our admin panel.

ACCOUNT DELETION (5.1.1(v))
Perfil > "Apagar conta", in-app, no email needed. Name, contacts, address,
photos and documents are erased and access is permanently revoked. Only
anonymised invoices are kept, as Portuguese law requires them for 10 years.

PAYMENTS (3.1.5(a))
All payments are for physical goods and services consumed outside the app. No
digital content is sold, so no in-app purchase is used.

EXTERNAL SERVICES
Supabase (backend, authentication, realtime, storage), Stripe (card and MB
WAY), Firebase Cloud Messaging (push), Google Maps SDK / Directions / Places.
No AI services, no ad networks, no third-party analytics.

REGIONS
Offered in Portugal and Brazil, identical behaviour, no region-gated features.
Delivery runs only in Guarda: outside it you can browse and sign up but will
see no stores for your address. Interface in Portuguese with an English toggle.

RIDE-HAILING (TVDE)
"Bora Motorista" on the home screen. Regulated in Portugal by Decree-Law
45/2018. Ride drivers are onboarded separately and must hold a valid TVDE
certificate and a licensed vehicle; we check the documents before they can go
online. Passengers need none.

ALCOHOL AND TOBACCO
Supermarket catalogues include alcoholic drinks, like any shelf. The app does
not encourage consumption. We sell NO tobacco: the only nicotine item is a
smoking-cessation gum sold by a licensed pharmacy.

BACKGROUND LOCATION (courier only)
Only while a courier is Online and carrying a delivery, with a prominent
disclosure before the system prompt. Customers never have it.

SIGN IN WITH APPLE (4.8)
Email and password only, no third-party or social login, so 4.8 does not apply.

BUTTONS
  Entrar = Sign in | Supermercados = Supermarkets | Farmacia = Pharmacy
  Favores = Errands | Limpeza = Cleaning | Beleza = Barber and beauty
  Dinheiro = Cash | Em breve = Coming soon | Agora nao = Not now

CONTACT
boraappbora@gmail.com   +351 937 501 673
```
