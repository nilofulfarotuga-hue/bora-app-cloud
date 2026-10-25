# Aprovada não é publicada — releaseType e lookup sem cache
> Referência de `apple-conta-e-loja`; carregar só quando o SKILL.md mandar.

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
