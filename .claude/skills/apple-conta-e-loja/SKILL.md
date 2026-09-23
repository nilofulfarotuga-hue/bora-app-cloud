---
name: apple-conta-e-loja
description: >
  Lições provadas sobre a conta Apple Developer e a App Store da Bora: como se lê o estado
  real (email por inteiro, API por país, lookup público), o ciclo do estatuto de comerciante
  (DSA) e o que a verificação exige, quando se reenvia e quando não, o que a API faz e não faz,
  e a regra do repo público com dados pessoais. Usar em qualquer missão que toque a conta
  Apple, o App Store Connect, a disponibilidade por país, o DSA ou uma submissão iOS.
metadata:
  versao: 1.0
  criada: 2026-09-16
  execucoes: 4
  sucessos: 4
  falhas: 0
  ultima_execucao: 2026-09-23
  zona: verde
---

# apple-conta-e-loja — a conta Apple e a loja, sem meias leituras
> Escrita a 16/09/2026 na missão `ios-portugal-2026-09-16`. Porquê: o mesmo erro — dar o
> estado da Apple por meia leitura — aconteceu **duas vezes** (08/09: "pago" quando era só
> cativação no banco; 13/09: "declarado e corrigido" quando o email era uma **reprovação**).
> Cada regra tem a cicatriz e a prova (e2e_log, fluxo `ios-portugal-2026-09-16`).

## 1. Ler o email da Apple POR INTEIRO antes de dizer o estado
- O email "Action needed: Update your trader contact information" (13/09 22:12 UTC) é uma
  **reprovação** ("we weren't able to verify…"), com modelo interno "DSA Failed Verification
  Email". Os digests de 13/09 leram-no como confirmação. **Nunca resumir um email da Apple pelo
  assunto ou pelo snippet**: abrir o corpo (Gmail MCP, `PLAIN_TEXT`) e citar a frase.
- Os emails "We received your trader contact information" colam as linhas da morada sem
  separador ("R. do Torreão 14" + "1 andar" saiu "141 andar"). Antes de acusar um dado de
  errado, confirmar no ecrã/registo — o número 14 estava certo.
- O email da Apple nunca diz **porquê** reprovou. O porquê descobre-se por medição (ficheiros
  enviados, registos, documentos) — ver §3.

## 2. Reserva no banco não é pagamento (08/09)
- "99 € cativados" no banco ≠ compra concluída. A prova de pagamento é o email da encomenda
  (`your_order_PT@orders.apple.com`) **e** a mudança do `getTeams` (a inscrição fecha e nasce
  a equipa). Nunca pagar outra vez por causa da página "complete your purchase".

## 3. O ciclo do estatuto de comerciante (DSA) e o que a verificação exige
- Fluxo oficial (página da Apple, lida 16/09): contacto (morada/telefone/email) → validar
  email por código → validar **telefone por código** (verificação manual só se o número não
  receber códigos) → **documento actual que prove nome e morada** ("business or legal
  records") → rever → Confirmar. **Todos os comerciantes** dão dados da conta de pagamento se
  ainda não estiverem no App Store Connect; art. 30(1)(c) do DSA exige-os.
- A verificação compara **letra a letra**: nome do formulário = nome do documento = nome da
  inscrição; morada com número **e andar**; código postal. Um extracto bancário com o nome
  sem o "da" e um formulário sem o andar foram a inconsistência de 08/09.
- Documento certo para pessoa singular em Portugal: **Certidão de Domicílio Fiscal** do
  Portal das Finanças (Obter → Certidões → Efectuar Pedido → tipo "Domicílio Fiscal (Morada)";
  o PDF sai na hora, **bilingue PT/EN**, com código de validação). Complemento: título de
  residência frente/verso. O comprovativo de actividade não está nesse menu (fica opcional).
- Estados vistos no App Store Connect: "Em revisão" (13/09→) **sem botão** — não se edita nem
  se carrega nada; o link "Resubmit" do email só abre `/business`. A saída é o **suporte por
  escrito** (`developer.apple.com/contact` → App Setup → Availability and Pricing → Email),
  que devolve um Case ID e, quando precisa, um **link seguro** para o documento (fórum 818212,
  759771). Fila normal 1–3 semanas; há casos de >1 mês.
- Telefone: escolher **sempre** o código SMS. A verificação manual de 08/09 mandou documentos
  que não mostram o número — não tinha como ser verificada.

## 4. Quando reenviar e quando NÃO
- Reenviar só com **erro concreto provado** no que está em revisão, e **uma vez**. Reenviar
  às cegas volta ao fim da fila e repete a falha (o reenvio de 13/09 corrigiu o andar mas
  levou o mesmo documento com o nome errado).
- Se o que está em revisão já está certo → **não reenviar**; só o caso escrito a pedir o
  ponto de situação e o link seguro.
- Nunca declarar "não comerciante" para desbloquear: é falso (actividade aberta, a app é
  negócio) e a Apple remove a app. Nunca tirar a app de venda, mexer no Brasil, criar versão
  nova nem reenviar para revisão por causa do DSA — o bloqueio é da conta, não da app.

## 5. Lookup por país e `contentStatuses` — a prova de "no ar"
- `https://itunes.apple.com/lookup?id=<appId>&country=<xx>` → `resultCount` 1/0 por país. A
  página `apps.apple.com/<xx>/app/id…` dá **404** enquanto o país estiver fechado; a sem país
  também dá 404 se o país do visitante estiver fechado.
- API: `GET /v1/apps/{id}/appAvailabilityV2?include=territoryAvailabilities` → por território
  `available` (o que **nós** escolhemos) e `contentStatuses` (o que a **Apple** deixa). O `id`
  de cada linha é base64 de `{"s":"<appId>","t":"<ISO3>"}`. Vistos: `AVAILABLE`, `CANNOT_SELL`,
  `TRADER_STATUS_NOT_PROVIDED` (em revisão), `TRADER_STATUS_VERIFICATION_FAILED` (reprovado),
  `CANNOT_SELL_INFREQUENT_*ALCOHOL_TOBACCO_DRUGS` (classificação etária num país).
- "Disponível 1 / Não é possível vender 1 / Não disponível 173" na página de Preço e
  disponibilidade = BR aberto, PT escolhido mas bloqueado, resto não seleccionado.

## 6. O que a API faz e não faz
- Faz: apps, versões (`appStoreState`, `releaseType`), `contentRightsDeclaration`,
  classificação etária, localizações e URLs, disponibilidade por território, submissões.
- Não faz: formulário de comerciante, documento, estado "Em revisão", acordos/banco/impostos
  (só no App Store Connect e nos emails). O endpoint interno `complianceInfo` devolve vazio;
  `legalEntities` (protobuf) guarda a morada da inscrição e a do comerciante lado a lado.
- A mesma API responde pela **sessão do Chrome** em `appstoreconnect.apple.com/iris/v1/…`
  — mede-se sem tocar na chave `.p8` (que vive em `~/.bora-cofre/apple/`, nunca no repo).
- O portal `developer.apple.com` responde a `POST services-account/QH65B2/account/getTeams`
  com a inscrição (morada, código postal, expiração, `autoRenew`, `acceptedLatestAgreement`).
- As SPAs da Apple (contacto, App Store Connect) **não renderizam em aba escondida**; com o
  agente do Chrome em segundo plano, remendar `document.visibilityState`/`requestAnimationFrame`
  ou trazer a aba à frente. Capturas de ecrã falham nessa condição; o texto da página não.

## 6b. Aprovada não é publicada — `releaseType` manda (23/09)
- A Apple aprovou a 1.0.2 a 22/09 às 22:44 UTC e a App Store **serviu a 1.0 o dia inteiro**.
  Não houve avaria: a versão tinha `releaseType: MANUAL` e ficou em
  `PENDING_DEVELOPER_RELEASE` à espera de um clique. **"Review complete" no email não quer
  dizer publicada** — a prova é `appStoreState`.
- Lançar sem navegador: `POST /v1/appStoreVersionReleaseRequests` com a relação
  `appStoreVersion`. Devolve 201; o 201 não prova nada — reler `appStoreState` até
  `READY_FOR_SALE`. Depois disso o `itunes lookup` ainda serve a versão antiga por uns
  minutos: medido a 23/09, release request às 10:54:57Z e lookup já com 1.0.2 às 11:08 —
  **~14 min**, não as 2 h que se temiam. Não é falha; espera-se e relê-se.
- **O lookup sem anti-cache mente muito depois de a propagação acabar.** Às 11:35Z, com a
  loja já a servir a 1.0.2, um `curl` simples ao lookup devolveu HTTP 200 com `version=1.0`
  e `currentVersionReleaseDate` de 12/09 — o retrato antigo inteiro, credível e errado.
  Juntar sempre `&t=<epoch>` ao URL (e `Cache-Control: no-cache`); sem isso lê-se o CDN, não
  a loja, e parece uma regressão que não existe. Usar o script, nunca um `curl` à mão:
  `provas/ios-lancar-102-20260923/lookup_no_ar.py` (sai 0 se a loja serve a versão esperada).
- Para não repetir: criar a versão já com `releaseType: AFTER_APPROVAL` (lançamento
  automático após aprovação). É o que o CI passou a fazer sozinho em
  `.github/scripts/ios_publicar.py`, chamado pelo `build_ios.yml` a seguir ao `altool`.
- Submeter pela API é `reviewSubmissions` (abrir) + `reviewSubmissionItems` (pôr a versão
  lá dentro) + `PATCH submitted:true`; `appStoreVersionSubmissions` é a via velha.
- Nome de versão: a Apple recusa repetir ou descer — a seguinte é sempre superior à maior
  que já existe (ver [[comboio-da-apple-fecha-com-a-versao-aprovada]]).
- O "O que há de novo" só se escreve nos idiomas que a **ficha** tem. A 23/09 a ficha só
  tinha `pt-PT` — não existe `en-US`, e escrever nele daria erro.

## 7. Repo público e dados pessoais
- `bora-app-cloud` é **público**; `.claude/.ai/provas/` e `reports/` vão para o GitHub.
  Documentos, IBAN, NIF, data de nascimento, números de documentos e capturas das páginas de
  negócio da Apple ficam **só** em `C:\Users\danil\_PRIVADO\<missão>\` (fora de qualquer pasta
  sincronizada). No repo escreve-se "documento X enviado".
- O agente nunca escreve IBAN/NIF/senhas em formulários: prepara o resto, deixa a página
  aberta e o clique/colagem é do Danilo (uma sentada, um passo de cada vez, pelo Telegram).
- Logout de contas de prova é `scope=local`, nunca global.

## 8. Segurança da conta
- "Palavra-passe reposta" com código enviado ao próprio Gmail e concluída em 85 s = alguém
  com o Gmail aberto. Cruzar com o histórico do Chrome do PC (perfil, hora, `authResult=FAILED`
  → logout → login) antes de gritar "intrusão". A 13/09 foi o perfil Bora deste PC.

## 9. Morada da inscrição, anexos por email e o W-8BEN (18/09)
- **A morada da inscrição corrige-se por pedido escrito, não pela Apple sozinha:**
  `developer.apple.com/account` → Membership details → "Update your information" → modal
  "Change contact details" → "Provide updates" → formulário
  `developer.apple.com/contact/request/update-individual-information/` (Região, tipo
  Nome/Endereço/Ambos, novo endereço, informações adicionais; **sem campo de ficheiro**). Abre
  um caso próprio (18/09: 102967621679) e a Apple pede documentação depois. O campo "New
  address in Roman character" **apaga acentos, vírgulas e "º"** no `keyup`/`blur` (só letras,
  dígitos, espaço, `.`, `-`, `#`, `&`): escreve-se em ASCII e a grafia exacta vai nas
  informações adicionais (que aceitam acentos). Fonte: ajuda "Updating your account
  information" ("go to the membership details section … to submit a request").
- **Responder a um caso com anexo:** o suporte responde de `emea_appsen_support@apple.com`
  (Genesys; o `[caseId]` no assunto liga a resposta ao caso). O `reply`/`create_draft` do Gmail
  MCP só levam anexos em base64 — 170 KB escritos à mão corrompem o PDF. Receita segura:
  rascunho pelo MCP (`create_draft` com `replyToMessageId`) → Gmail web no Chrome perfil Bora
  → `find` "file input Filedata" → `file_upload` (ficheiro copiado para o scratchpad; apagar
  depois) → chip com nome e tamanho → Send → `get_message` do SENT mostra `attachments`.
- **"Informações fiscais em falta" nas duas linhas de impostos** = questionário guardado,
  W-8BEN por preencher. O W-8BEN é do Danilo (juramento; data de nascimento, NIF, tratado,
  certificação; Enviar é irreversível): o agente deixa a aba aberta e escreve o mapa dos
  campos no CONTINUAR. "A processar" na conta bancária = IBAN colado, 24 h para processar.

## 📊 Telemetria (obrigatório no fim de cada execução)
1. Actualizar o frontmatter: `execucoes`, `sucessos` ou `falhas`, `ultima_execucao`.
2. Uma linha em `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
