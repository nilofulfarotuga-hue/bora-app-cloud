# Rebuild Intermarché-Guarda — Uber Eats 100% cracked, gate de horário · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · **DB NÃO tocada** (ver §3).
> Danilo entregou o cURL do `getCatalogPresentationV2`. Com isso, a API Uber ficou **totalmente decifrada**.

## 1. Estratégia que funcionou: Uber Eats API (cURL do Danilo)
O body que faltava desbloqueou o catálogo. **Tudo confirmado a funcionar via Node:**
- **Header-overflow** resolvido: `maxHeaderSize:131072`.
- **Localização**: cookie `uev2.loc` com place_id REAL do Google (`ChIJU8b2j8T6PA0RADWQ5L3rAAQ`) + headers `x-uber-target-location-*`.
- **catV2 FUNCIONA** (path `/api/` e `/_p/api/`, header `x-csrf-token:x`), body:
  `{storeFilters:{storeUuid,sectionUuids:[SEC],subsectionUuids:null,sectionTypes:["COLLECTION"],shouldReturnSegmentedControlData:true},pagingInfo:{enabled:true,offset:null}}`
  → testado na secção `255a3220-…` → **200, 134 produtos**. Item = `{uuid,title,price(CÊNTIMOS),imageUrl}`.
- Loja: Intermarché Guarda `storeUuid a0fe1ff9-4042-55a3-9a28-ae1d84b93576`.

## 2. O ÚNICO gate que resta: horário da loja
`getStoreV1` devolve a **lista das ~44 sections** (categorias: Charcutaria, Frutas e Legumes, Mercearia, Álcool…) **apenas durante o horário da loja: 09:00–19:30 PT** (campo `hours`: 540–1170 min, "Todos os dias"). Fora disso `sections=[]`.
Esta sessão correu **~00:30 PT** → `getStoreV1.sections = 0`. Sem a lista de sections não dá para iterar o catálogo (o catV2 precisa do uuid de cada secção; testado: sem section devolve vazio, e o HTML da loja **não** embede a nav — carrega client-side).

→ **Não inventei nada. Não usei placeholders. Não toquei na DB.**

## 3. Porque NÃO fiz o rebuild esta noite
- Só consigo enumerar 1 secção (a do cURL) = 134 produtos. Um catálogo de 1 secção (<<1500) **degradaria** os 2962 ativos atuais. Regra: *"não deixar a DB num estado pior"*.
- Portanto: **zero escritas, sem backup, sem DELETE**. Intermarché intacta (3004 total / 2962 ativos).

## 4. Toolkit PRONTO (corre durante o horário → rebuild completo num passo)
- `scripts/uber_eats_intermarche_crawler.js` — getStoreV1 → 44 sections → catV2 por secção (com paginação `pagingInfo.offset`) → `[{id:'int-'+uuid,name,price(€),img,root,sort_order}]`. **Aborta com mensagem clara se sections<5** (fora de horário).
- `scripts/uber_apply_rebuild.js` — upsert PostgREST lotes 200 + guarda anti-placeholder (img>5×).
- `scripts/uber_eats_probe.js` — acesso base (já existia).

### Sequência a correr entre 09:00–19:30 PT (idêntica à Auchan)
1. `node scripts/uber_eats_intermarche_crawler.js --out uber_int.json` → validar ≥1500 produtos, 0 sem foto/preço.
2. Sample: 3 produtos vs Glovo p/ confirmar regra de preço (§6).
3. `CREATE TABLE _backup_intermarche_pre_rebuild_2026_06_06 AS SELECT * FROM products WHERE restaurant_id='intermarche-guarda';`
4. `DELETE FROM products WHERE restaurant_id='intermarche-guarda';`
5. `node scripts/uber_apply_rebuild.js uber_int.json intermarche-guarda`
6. Validar (sem_foto=0, sem_preco=0, cats>10, total 2000–5000).

## 5. Métricas (inalteradas — DB intacta)
`intermarche-guarda`: total=3004, ativos=2962, sem_foto=1864 — **sem alterações**.

## 6. Regra de preço (a confirmar no run diurno)
Decisão Danilo 2026-06-07: **preço = cêntimos/100 DIRETO (sem −15%)** — Uber PT grocery cobraria preço de loja, como a Glovo Auchan. O crawler já grava assim. **Validar com 3 produtos comuns vs Glovo** no run diurno; se houver markup, mudar para ×0.85 no `uber_apply_rebuild.js`.

## 7. Recomendações
1. **Re-correr este prompt entre 09:00–19:30 PT** → completo o rebuild num passo (toolkit pronto). OU agendar.
2. Admin: útil um botão "re-sync loja" no painel (corre crawler+apply) — registado como melhoria.

## 8. Zonas protegidas
Intactas. Nenhuma escrita na DB. Apenas leitura de APIs externas + 3 scripts novos + relatório.
