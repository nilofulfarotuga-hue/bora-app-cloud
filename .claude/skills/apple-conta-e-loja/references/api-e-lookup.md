# Lookup por país, contentStatuses e o que a API faz
> Referência de `apple-conta-e-loja`; carregar só quando o SKILL.md mandar.

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
