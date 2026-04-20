# PLANO ESTRATÉGICO — 6 MERCADOS (Bora App)

Gerado por: `ceo-ai` (orchestrator)
Data: 2026-04-18
Estado: **PROPOSTA — aguarda aprovação do Danilo**
Modo sessão: read-only (nenhuma mutação executada)

---

## 1. ESTADO ACTUAL (verificado via Supabase MCP)

Query: `SELECT restaurant_id, COUNT(*), COUNT(DISTINCT photo_url), COUNT(*) FILTER (WHERE photo_url ILIKE '%mercadona%') FROM products GROUP BY restaurant_id`

| Mercado             | Produtos | Fotos únicas | % únicas | Com CDN Mercadona | Sem preço |
|---------------------|---------:|-------------:|---------:|------------------:|----------:|
| mercadona-guarda    | 5.011    | 3.805        | 76 %     | 5.011 (legítimo)  | 2         |
| continente-guarda   | 4.832    | 2.519        | 52 %     | 589 (12 %)        | 0         |
| pingodoce-guarda    | 3.101    | 558          | 18 %     | 1.062 (34 %)      | 0         |
| lidl-guarda         | 3.002    | 406          | 13 %     | 674 (22 %)        | 0         |
| auchan-guarda       | 3.003    | 505          | 17 %     | 1.121 (37 %)      | 0         |
| intermarche-guarda  | 3.004    | 504          | 17 %     | 1.114 (37 %)      | 0         |

**Factos**
- 5 mercados violam BR §27.2 (fotos CDN Mercadona nos ficheiros) → 4.560 linhas contaminadas.
- 4 mercados abaixo do mínimo 5.000 (BR §27.2) → défice total ≈ 6.890 produtos.
- Duplicação massiva de fotos (Lidl 13 % únicas) sugere fallback fictício repetido.
- Preços OK (não-nulos quase sempre) — não precisam de recuperação urgente.
- Escopo geográfico actual: `-guarda` (cidade Guarda) — o resto do pipeline assume este sufixo.

---

## 2. DECISÕES DE NEGÓCIO FIXADAS (Danilo, 2026-04-18)

1. **Imagens partilháveis entre mercados** (Coca-Cola = Coca-Cola). Invalida a leitura original de BR §27.2; ver ponto 6.
2. **Preços nunca partilhados** — cada mercado guarda o seu.
3. **Apagar imagens fictícias/duplicadas** autorizado.
4. **Cascata de 4 níveis para imagens**
   - L1 site do mercado
   - L2 biblioteca partilhada (Mercadona primeiro como fallback inter-market)
   - L3 site oficial da marca
   - L4 Google/Bing Image Search
   - Fallback final → marcador "sem imagem" (nunca fictícia).

---

## 3. SKILLS ENVOLVIDAS (canónicas + 1 nova)

| Skill                  | Papel nesta tarefa                                                                 | Estado        |
|------------------------|------------------------------------------------------------------------------------|---------------|
| `ceo-ai`               | Orquestra + aprova plano com Danilo (esta sessão).                                 | ✅ activo      |
| `products-updater`     | Calendário pg_cron, quality gates semanais, log `product_update_log`.              | ✅ existe      |
| `market-scraper`       | Estratégia por mercado, backoff, rotação User-Agent.                               | ✅ existe      |
| `guardian`             | Verifica impacto nas zonas protegidas BR §25.3 antes de `executor`.                | ✅ existe      |
| `flow_guard`           | Bloqueia mudanças estruturais no core (não deve ser tocado por este plano).        | ✅ existe      |
| `system_validator`     | Corre `dart analyze` + smoke tests após mudança.                                   | ✅ existe      |
| `market-harvester`     | **NOVA** — cascata L1→L4 de imagens + merge com biblioteca partilhada.             | 🆕 a criar     |
| `notifications-engineer` | Alerta admin em falha de job.                                                    | ✅ existe      |

**Nova skill proposta:** `.claude/.ai/skills/market-harvester.md` (read-only spec). Motivo: `market-scraper` é por mercado; falta um colector transversal que aplique a cascata de 4 níveis em bulk e cruze com a library inter-market.

---

## 4. PLANO FASEADO

### FASE 0 — Correcção da BR §27.2 (governança)
- Reescrever §27.2: fotos podem ser partilhadas; o que é **proibido** é foto fictícia (ex.: placeholder recoloriado) ou foto manifestamente errada (imagem de outro produto).
- Registar em `business_rules.md` a cascata de 4 níveis como canónica.
- Sem código. Apenas documentação.

### FASE 1 — Auditoria de imagens fictícias (read-only)
- SQL de classificação: marcar como "suspeita" toda linha onde `photo_url` aparece em ≥ N produtos do mesmo mercado (candidato a fictício repetido). Gerar relatório.
- Cruzar com biblioteca Mercadona: linhas cuja URL Mercadona **não existe** em `mercadona-guarda` → fictícias certas.
- Output: `reports/audit_images_2026-04-XX.csv`.
- Não apaga nada. Apenas lista.

### FASE 2 — Skill `market-harvester` (spec)
- Ficheiro `.claude/.ai/skills/market-harvester.md` descrevendo:
  - Input: `{market, product_rows}`
  - Cascata L1 (site mercado) → L2 (library Mercadona/outros) → L3 (site marca via `brand_low/mid/premium`) → L4 (Google Images API ou Bing).
  - Match inter-market por chave `(normalized_name, brand, unit)`.
  - Rate limit 1 req/s por host (BR §27.5).
  - Output: `{rows_updated, images_l1, images_l2, images_l3, images_l4, no_image}`.

### FASE 3 — Limpeza da DB (sessão dedicada, com `guardian`)
- Apagar campo `photo_url` (setar NULL) em linhas fictícias identificadas na Fase 1.
- Marcar `is_available=false` em linhas com nome/preço inválidos.
- Deletar linhas órfãs sem identidade (name NULL/ vazio).

### FASE 4 — Harvest por mercado (sessão dedicada por mercado)
Ordem canónica BR §27.1 (Segunda→Sábado). Para cada mercado:
1. `market-scraper` corre L1 (site oficial) → fill produtos até 5.000.
2. `market-harvester` corre L2→L4 apenas sobre linhas ainda sem foto.
3. Fallback final: `photo_url = NULL` + flag `needs_photo=true`.
4. `system_validator` confirma quality gate.

### FASE 5 — Automação semanal
- Edge function `update-products` + pg_cron (ver BR §25.1) — **sessão própria**.
- 1 mercado por dia, domingo = retry (BR §27.5).

---

## 5. RISCOS / ZONAS PROTEGIDAS BR §25.3

Este plano **não toca** em:
- `lib/services/pricing_service.dart`
- `lib/dispatch/driver_capacity_service.dart`
- `lib/stores/order_store.dart::finalizePurchase`
- Triggers `bora_tokens`, `trg_award_tokens_on_delivery`
- Qualquer código Stripe
- `supabase/functions/dispatch-engine/index.ts`

Guardian deve correr antes de QUALQUER execução real (Fase 3+).

---

## 6. DECISÕES PENDENTES (Danilo, aprovar antes da Fase 1)

1. ✅/❌ Reescrever BR §27.2 conforme Fase 0.
2. ✅/❌ Criar skill `market-harvester` (Fase 2).
3. Provider para L4 (Google Custom Search API vs Bing Search API vs SerpAPI)? Tem custo.
4. Escopo geográfico: manter `-guarda` ou generalizar (`mercadona` sem cidade)?
5. Limite de orçamento para API de imagens (L4).

---

## 7. CRITÉRIO DE FEITO GLOBAL

- 6 mercados com ≥ 5.000 produtos.
- 0 linhas com `photo_url` fictícia (zero duplicação cruzada inter-market).
- Todas as fotos obedecem à cascata L1→L4 (ou `NULL` + `needs_photo`).
- pg_cron a rodar 6×/semana + domingo retry.
- `dart analyze` 0 erros após cada sessão.

---

*Proposta gerada pelo `ceo-ai`. Nenhuma acção executada. Aguarda confirmação explícita do Danilo por fase.*
