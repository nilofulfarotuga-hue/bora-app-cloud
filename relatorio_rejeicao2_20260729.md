# Relatório — 2ª rejeição Bora App (Envio 121, bundle 501) — 29/07/2026

> Investigação a fundo pedida pelo Danilo ("não adivinhes, não mais tentativa e erro").
> **Conclusão: a causa real NÃO é Advertising ID / Data Safety. É LOCALIZAÇÃO EM SEGUNDO PLANO.**

## 1. Texto EXATO da rejeição do Envio 121 (Estado da política)
São **DOIS** problemas, ambos rejeitados a **29/07/2026**:

**Problema 1 — "Política de permissões e APIs que acessam informações sensíveis: Problemas com o vídeo enviado"**
> "Encontramos um dos dois problemas a seguir no seu vídeo: não foi possível ver o vídeo informado na declaração ou ele não reflete com precisão a experiência no app.
> Seu vídeo precisa demonstrar todos os elementos a seguir:
> - A funcionalidade declarada do recurso no app em ação
> - Como o recurso usa a localização em segundo plano
> - Como o usuário aciona a declaração em destaque de localização em segundo plano
> - A permissão de execução baseada no dispositivo exibida (com consentimento do usuário)"
>
> Como corrigir: "1. Leia o artigo da Central de Ajuda sobre localização em permissões em segundo plano. 2. Confira se o vídeo está acessível e/ou faça alterações nele para demonstrar o recurso declarado que exige acesso à localização em segundo plano. 3. Reenvie o app."
>
> Vídeo atualmente na declaração ("Experiência na app"): `https://youtube.com/shorts/JEyOj7und6M` (inacessível ou inadequado).

**Problema 2 — "Solicitação de consentimento e declaração em destaque: Não há uma declaração em destaque"**
> "Seu app não obedece à secção Solicitação de consentimento e declaração em destaque da política de dados do usuário.
> **O app acessa a permissão BACKGROUND_LOCATION sem uma declaração em destaque.**
> Onde foi encontrado este problema: Este problema também pode ser encontrado noutras localizações. Verifique todas as áreas da sua app quando corrigir o problema."

## 2. O que o grep encontrou (auditoria de código) — ficheiro por ficheiro
- `pubspec.yaml`: **só** `firebase_core: ^3.0.0` e `firebase_messaging: ^15.0.0`.
- **ZERO** ocorrências de: `firebase_analytics`, `firebase_crashlytics`, `google_mobile_ads`, `app_tracking_transparency`, `firebase_installations`.
- `android/` (manifests-fonte): **ZERO** `AD_ID`, `AdvertisingId`, `getAdvertisingIdInfo`, `com.google.android.gms.permission.AD_ID`.
- `lib/`: **ZERO** `FirebaseAnalytics`, `AdvertisingId`, `setAnalyticsCollectionEnabled`.
- `android/app/src/main/AndroidManifest.xml` **TEM**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, **`ACCESS_BACKGROUND_LOCATION`**, `FOREGROUND_SERVICE_LOCATION`.
- `lib/stores/consent_store.dart`: banner GDPR/ePrivacy (toggles localização/analytics/notificações) — **NÃO** é a "prominent disclosure" da Google.
- `lib/screens/driver_permissions_screen.dart`: trata ecrã-inteiro / notificações / overlay / bateria — **não** trata localização em segundo plano nem declaração em destaque.

## 3. Qual identificador está de facto a ser enviado, e é configurável?
- **Não há Advertising ID.** A app não tem SDK de anúncios nem de analytics. A hipótese do prompt (AD_ID/Advertising ID) está **empiricamente descartada**.
- O único identificador de dispositivo é o **token FCM** (`firebase_messaging`), usado para notificações push — **legítimo**, e **já corretamente declarado** no Data Safety ("Dispositivo ou outros IDs": Recolhido=Sim, Partilhado=Não, Finalidade=Funcionalidade da app — verificado na sessão anterior).
- O verdadeiro dado sensível em causa é a **LOCALIZAÇÃO EM SEGUNDO PLANO** (`ACCESS_BACKGROUND_LOCATION`), que o estafeta usa para rastreio de entregas/corridas. É **necessária** ao produto (não se remove sem partir o core do estafeta).

## 4. Opção escolhida (A ou B) e porquê
**NENHUMA das duas.** As opções A e B do prompt tratam ambas de Advertising ID / Data Safety, que **não são** o problema (grep prova). Aplicá-las seria exatamente a "tentativa e erro" que o Danilo mandou evitar.

O problema real (localização em segundo plano) exige duas coisas — e **ambas colidem com as regras desta tarefa**:
- **(a) Declaração em destaque (prominent disclosure) no app** — um ecrã, mostrado ao estafeta **antes** de usar a localização em segundo plano, com a linguagem exigida pela Google (ex.: *"O Bora recolhe a tua localização para rastrear e partilhar a tua posição durante entregas e corridas, mesmo quando a app está fechada ou não está a ser usada"*, com Aceitar/Agora não). **Isto é código que toca a UX de localização** — e a REGRA desta tarefa diz "Não toques em permissões de localização".
- **(b) Vídeo de demonstração** — mostrar a app a correr, a disclosure a aparecer, o utilizador a conceder a permissão e o recurso de rastreio em ação; carregar (YouTube não listado) e atualizar o URL na declaração. **Isto é um entregável humano** — não consigo gravar a app a correr num dispositivo real.

## 5. O que foi alterado
- **NADA de código foi alterado.** Não toquei em localização (regra), não apliquei A/B (irrelevantes), não falsifiquei vídeo.
- Investigação read-only apenas.

## 6. Estado do build/reenvio
- **Nenhum reenvio feito.** O bundle 501 continua correto para os problemas anteriores (sem `READ_MEDIA_IMAGES`; Data Safety completo). Não é preciso bundle novo — este bloqueio é de **declaração + disclosure + vídeo**, não de código do AAB. Um reenvio do 501 sem resolver a disclosure e o vídeo seria recusado uma 3ª vez.

## 7. Estado final do envio na Play Console
- **Atualização rejeitada (29/07/2026)** — 2 problemas de política ativos (localização em segundo plano: vídeo + declaração em destaque). Envio 121 rejeitado.

---
## Recomendação (decisão do Danilo)
O caminho certo, sem tentativa e erro:
1. **Construir a declaração em destaque de localização em segundo plano** no app (ecrã dedicado, wording da Google, antes do pedido de permissão do estafeta). É código que toca localização → preciso do teu "vai" para o fazer (ou dá ao agente `estafeta-motorista` + `compliance-pt`). Posso entregar como PROPOSTA para aprovares.
2. **Gravar o vídeo de demonstração** (app + disclosure + concessão da permissão + rastreio) e atualizar o URL na declaração da Play Console. **Tem de ser humano** — eu não gravo a app real.
3. Só depois de (1) e (2) reenviar o **mesmo bundle 501** para revisão.

⚠️ Isto mexe em LOCALIZAÇÃO (regra tua de não tocar). Está tudo diagnosticado; **confirma como queres avançar**.

---
## ADENDA — decisão "Constrói e aplica" (autorizado pelo Danilo)

**Investigação extra antes de construir (não adivinhar):**
- Verifiquei a arquitetura: `driver_location_service.dart` está DEPRECATED (no-ops); o GPS é escrito pela DriverMapScreen no **main isolate**; o FGS task handler **não acede a GPS** (só polling + heartbeat). O serviço foreground está declarado `foregroundServiceType="dataSync|remoteMessaging"` — **NÃO** `location`.
- Conclusão: `ACCESS_BACKGROUND_LOCATION` **é mesmo usada** (o stream de GPS do main isolate continua enquanto Online + app minimizada, mantido vivo pelo FGS). **Não é sobre-declaração** — removê-la partiria o rastreio. Por isso a via "disclosure + vídeo" é a correta.
- (Alternativa futura, mais complexa e arriscada, que evitaria o vídeo: re-arquitetar para um foreground service do tipo `location` (while-in-use) + remover `ACCESS_BACKGROUND_LOCATION`. NÃO feita agora — risco de partir o rastreio de fundo.)

**O que foi construído (código):**
- Novo `lib/widgets/background_location_disclosure.dart` — declaração em destaque modal, wording da Google (recolhe localização **mesmo com a app fechada/não em uso** + finalidade + ação afirmativa Aceitar/Agora não), com persistência em SharedPreferences.
- Ligada em `lib/screens/driver_home_screen.dart` (`_handleOnlineToggle`) e `lib/screens/driver/tvde/tvde_driver_home_screen.dart` (`_toggleOnline`): mostrada **ANTES** de ficar Online; recusar = não fica Online.

**Verificação (Juiz):**
- `flutter analyze` (3 ficheiros): **0 erros** (só 15 infos/lints, maioria pré-existente).
- Chão anti-trapaça (`anti_trapaca.py --base HEAD`): **✅ CLEAN, exit 0** (0 testes tocados, diff mecânico limpo).
- Zonas protegidas intactas (UX de localização, não dispatch/pricing/tokens/Stripe).

**Commit + push:** `5ef866c feat(estafeta): declaracao em destaque...` → dispara build da CI → **bundle 503** (com a disclosure).

## FALTA (ação humana — só o Danilo):
1. Esperar o build do **bundle 503** (CI, ~9 min).
2. **Gravar o vídeo** de demonstração com o 503 instalado: estafeta fica Online → aparece a declaração em destaque → Aceitar → concede a permissão de localização → o rastreio a funcionar. Carregar (YouTube não listado).
3. Play Console → declaração de permissões (localização em segundo plano) → **atualizar o URL do vídeo** (substituir o `JEyOj7und6M`).
4. Criar/editar o lançamento de produção com o **bundle 503** (NÃO o 501 — só o 503 tem a disclosure) → enviar para revisão.
