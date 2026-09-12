# PLANO — Crawler de Preços Oficiais continente.pt (PVPR, sem promoções)

> **Estado:** PLANO PARA APROVAÇÃO — **NADA foi escrito na BD.** Só queries SELECT read-only.
> **Data:** 2026-06-14 · **Autor:** CEO-AI (Claude Code) · **Branch:** `autonomous-night-2026-04-29`
> **Objetivo:** Atualizar o `price` base dos 11.884 produtos da loja Continente com o **PVPR/preço estrutural** do continente.pt, **ignorando promoções**.

---

## 0. FACTOS VERIFICADOS VIA MCP (não suposições)

| Facto | Valor confirmado | Query |
|---|---|---|
| Loja | `restaurant_id='continente-guarda'`, `is_partner=false`, `category=supermarket` | ✅ |
| Total produtos | **11.884** | ✅ |
| Com ID SFCC na `photo_url` (regex `/col/[0-9]+/[0-9]+-`) | **926** | ✅ |
| `source='continente_sfcc_bestsellers_2026-06-08'` | **934** (avg €23,60) | ✅ |
| `source='glovo_cont_rebuild_2026_06_07'` | **10.950** (avg €4,97) | ✅ |
| `is_on_sale=true` | **0** | ✅ |
| `needs_review=true` | 3 · `photo_url IS NULL` | 16 | ✅ |
| **Preços atuais dos 10.950 Glovo** | TODOS = `glovo ÷ 1,15` (`_continente_price_sources_2026_06_07`, `price_source='glovo_minus15'`, `pid=NULL`) | ✅ |

### Descobertas-chave (alteram a arquitetura proposta no brief)

1. **O ID Continente está no próprio campo `id`, não só na `photo_url`:**
   - SFCC (934): `id = 'cnt-<PID>'` → ex. `cnt-2003367`, e a `photo_url` confirma `2003367`.
   - Glovo (10.950): `id = 'cont-<N>'` → ex. `cont-7795050`, `cont-8496351`, `cont-2001144`.
   - O `<N>` dos `cont-` tem o formato exato de um **artigo Continente (PID 7 dígitos)**. **Hipótese forte:** `cont-<N>` → `Product-Show?pid=<N>` resolve diretamente. **Se confirmado (Fase 0), elimina o name-matching para a esmagadora maioria dos 10.950.**

2. **A capacidade está NO NOME, não em `unit`** (`unit` é NULL em 100% da amostra): ex. `"...Sanex (emb. 600 ml)"`, `"...Vaseline (emb. 1 lt)"`. O `search_normalized` já contém `"...emb 600 ml..."`. → O matching de capacidade da Fase 2 tem de fazer **parse do nome**, não do campo `unit`.

3. **O "rebuild" de 7-jun é exatamente a fonte errada que queremos substituir:** os 10.950 estão a `glovo ÷ 1,15`. Prova ao cêntimo na amostra de validação (ver §6).

4. **Método SFCC já provado sem anti-bot** (relatório `continente-price-updater-phase1-final.md`, 22-abr): 2.844 produtos, **90,3% cobertura, 0× 429/403** a 4,5s/req. Scripts reaproveitáveis: `.claude/.ai/scripts/phase1_full.py` (+resume/checkpoint), `phase1_summarize.py`.

5. **Tooling já existente a reaproveitar:** skill `weekly-market-prices` (Product-Show + JSON-LD, 3,5s/req, só Continente — método confirmado), skill `market-data-sync`, tabela `product_update_runs` (auditoria run-level), `platform_settings` (kill switches, padrão `key`+`value JSONB`+`category`).

---

## 1. ESTRATÉGIA DE ACESSO AO continente.pt

### 1.1 Endpoint primário (provado)
```
GET https://www.continente.pt/on/demandware.store/Sites-continente-Site/pt_PT/Product-Show?pid=<PID>
```
- Devolve a página SFCC (Demandware) do produto. **Não há bloqueio Cloudflare** a este endpoint (provado abril + probe hoje: a página carrega, 0 CAPTCHA).
- ⚠️ **WebFetch é insuficiente** — a conversão para markdown perde o bloco de preço (testado hoje). É **obrigatório** um parser HTTP que lê o **HTML cru** e extrai o preço de forma estruturada.

### 1.2 Fonte do preço dentro do HTML (ordem de fiabilidade)
1. **Data layer SFCC / JSON embebido** — bloco `data-analytics`/`dataLayer`/`ct-pdp` com objeto de preço estruturado contendo **`list` (PVPR) e `sales` (preço atual)**. Esta é a fonte fiável para distinguir PVPR de promo.
2. **JSON-LD** `<script type="application/ld+json">` (`Product.offers.price`) — fallback; dá o preço atual mas nem sempre o PVPR.
3. **DOM** (`.ct-price-formatted`, `.pvp-recomendado`, classes de preço) — último recurso.

### 1.3 Anti-bloqueio (parâmetros provados)
- **Rate:** 3,5–4,5 s por request **+ jitter ±1 s** (abril: 0 bloqueios). Manter 1 worker sequencial por defeito.
- `User-Agent` de browser real; `Accept-Language: pt-PT`.
- **Checkpoint/resume** a cada N produtos (já implementado no `phase1_full.py`) — uma corrida de ~15 h tem de sobreviver a falhas.
- Em `net_error` → sleep 30–60 s e retry isolado no fim.
- **Runtime:** Node script (`scripts/scraper/continente_pvpr.js`) ou Python (reusar `phase1_full.py`). **NÃO** Edge Function (timeout incompatível com 15 h). Corre local/CI, escreve na staging via `SERVICE_ROLE_KEY` (já em `scripts/scraper/.env`, gitignored).

---

## 2. PARSING: PVPR vs PROMOÇÃO (regra determinística)

Para cada produto, extrair dois números do data layer SFCC:
- `pvpr` = preço de lista / PVP recomendado (`prices.list`)
- `atual` = preço de venda exibido (`prices.sales`)

**Árvore de decisão (= regra do brief):**
```
se pvpr existe E pvpr > atual:        → tinha_promocao = true  ; preco_base = pvpr
senão se atual existe:                 → tinha_promocao = false ; preco_base = atual
senão (nenhum preço fiável):           → SKIP (não toca) ; status = 'no_price'
```
- **Nunca** usar `atual` quando há promoção. **Nunca** usar preço "Cartão Continente"/"Desconto Imediato" como base.
- Marcadores textuais (`Desconto Imediato`, `Poupe`, `Menos X% que PVPR`, preço riscado) usados só como **sinal de confirmação** de `tinha_promocao`, não como fonte do número.
- **Sanity guards** (flag, não aplica automático): `preco_base > 200€`, `preco_base < 0,20€`, ou `|preco_base − price_atual_BD| / price_atual_BD > 30%` → `needs_review=true` na staging (sinal de erro do Glovo ou de parse).
- **NÃO capturar** páginas de categoria/campanha/sazonais: se `Product-Show` faz `redirect_home` ou cai numa listagem → `status='redirect_home'`, não extrai preço.

---

## 3. ESTRUTURA DA STAGING

**Run-level:** reutilizar `product_update_runs` (já existe: `run_at, market, source, scraped, inserted, updated, failed, duration_ms, status, error`).

**Per-produto:** nova tabela `continente_price_staging` (modelada na `_continente_price_sources_*` existente, + campos do brief):
```sql
CREATE TABLE continente_price_staging (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  run_id          uuid REFERENCES product_update_runs(id),
  product_id      text NOT NULL,          -- products.id (cnt-/cont-)
  name            text,
  pid             text,                   -- PID Continente usado
  continente_url  text,
  old_price       numeric,               -- products.price atual (snapshot)
  pvpr            numeric,               -- PVP recomendado extraído
  site_current    numeric,               -- preço atual no site (promo incl.)
  new_price       numeric,               -- = preco_base decidido (§2)
  had_promo       boolean DEFAULT false,
  method          text,                  -- sfcc_id_from_id | sfcc_pid_from_cont | name_match | skipped
  confidence      text,                  -- high | medium | low
  status          text,                  -- ok | 404 | redirect_home | no_price | net_error | ambiguous
  needs_review    boolean DEFAULT false, -- diff>30% / sanity / ambíguo
  applied         boolean DEFAULT false,
  applied_at      timestamptz,
  reviewer_action text,                  -- approved | rejected | NULL
  created_at      timestamptz DEFAULT now()
);
```
**Princípio:** o crawler escreve SÓ na staging. A `products` só é tocada na Fase 3 após aprovação (ou auto-apply de alta confiança, ver §7).

---

## 4. FASES DE EXECUÇÃO

### Fase 0 — Preparação + verificação de hipótese (≈ 5 min, ~25 requests)
1. **Confirmar hipótese `cont-<N>` = PID:** sortear ~20 produtos `cont-` e bater `Product-Show?pid=<N>`. Medir taxa de hit (nome do site ≈ nome BD). **Gate de decisão:**
   - hit ≥ 80% → Fase 2 usa PID direto (rápido, fiável). 
   - hit < 80% → cair para name-match (§Fase 2b).
2. Criar `continente_price_staging` + kill switch `platform_settings('continente_price_crawler_enabled'=true, category='scraping')`.
3. Backup defensivo: `CREATE TABLE _backup_continente_price_pre_pvpr_2026_06_14 AS SELECT id, price, source, last_updated FROM products WHERE restaurant_id='continente-guarda';`

### Fase 1 — 934 produtos SFCC (alta confiança) (`method=sfcc_id_from_id`)
- PID = parte numérica de `cnt-<PID>` (cross-check com regex da `photo_url`).
- Crawl → parse §2 → staging. `confidence=high`.
- ⚠️ Estes vieram do site a 8-jun mas avg €23,60 é alto → **podem ter capturado preço promo**; re-crawl reaplica a regra PVPR e corrige.

### Fase 2 — 10.950 produtos Glovo (`method=sfcc_pid_from_cont`)
- **2a (caminho feliz, se Fase 0 confirmar):** PID = parte numérica de `cont-<N>` → Product-Show. `confidence=high`. Esperado ~90% ok (padrão abril).
- **2b (fallback p/ 404 / redirect_home / hipótese falhada):** pesquisa `Search-Show?q=<nome limpo>` → 1º resultado.
  - **Match só aceite se:** tokens do nome batem **E capacidade bate exatamente** (capacidade parseada de `(emb. X ml/lt/gr/kg)` no nome BD vs site). `1 L` nunca casa com `500 ml` nem `6×1L`.
  - Ambíguo / capacidade diferente / múltiplos candidatos → `status='ambiguous'`, `needs_review=true`, **não escreve preço**. `confidence=low`.

### Fase 3 — Aplicação (após aprovação)
- Relatório: total, atualizados, pulados (promo/no_price/404/redirect), divergências >30% (sinal de erro Glovo anterior).
- `UPDATE products SET price=s.new_price, last_updated=<ISO>, source='continente_pt_official_2026-06-14' FROM continente_price_staging s WHERE products.id=s.product_id AND s.status='ok' AND (s.applied=false) AND (<filtro aprovação>)`. (`last_updated` é **TEXT** → gravar ISO-8601 string.)
- Nunca toca `name`, `photo_url`, `category`, `unit`. Só `price`, `last_updated`, `source`.

---

## 5. ESTIMATIVA DE TEMPO / REQUESTS

| Cenário | Requests | Rate | Wall-clock |
|---|---|---|---|
| 11.884 × 1 worker | 11.884 | 3,5 s | **≈ 11,6 h** |
| 11.884 × 1 worker | 11.884 | 4,5 s | ≈ 14,9 h |
| 11.884 × 2 workers | 11.884 | 5 s | ≈ 8,2 h (risco↑ bloqueio) |
| Fallback 2b (só misses) | ~1.100 extra | 4,5 s | +1,4 h |

**Recomendação:** 1 worker, 3,5–4,5 s + jitter, checkpoint, correr de noite. ~15 h cobre tudo + retries. (Abril fez 2.844 em ~3,5 h coerente com isto.)

---

## 6. VALIDAÇÃO OBRIGATÓRIA (gate antes de massa)

Correr o crawler só sobre estes 5 e **bater exatamente** antes de prosseguir. Estado atual na BD confirma o problema:

| Produto | Cap. | Esperado (PVPR) | Na BD agora | Encontrado |
|---|---|---|---|---|
| Leite UHT Magro Gresso | 1 L | **0,87€** (PVPR 0,91) | — | (verificar) |
| Leite UHT Magro S/ Lactose Gresso | 1 L | **1,06€** (PVPR 1,12) | — | (verificar) |
| Gel Banho Cuidado Experto Protector Sanex | 600 ml | **PVPR 5,99€** (promo 2,99) | `cont-7795050` = **3,05€** ❌ | (verificar) |
| Gel Banho Manteiga Karité Vaseline | 700 ml | **PVPR 4,99€** | — | (verificar) |
| Gel Banho Zero% Pele Seca Sanex | 600 ml | **PVPR 5,99€** | — | (verificar) |

Parser tem de devolver **5,99** (não 2,99) no Sanex. **Se a amostra não bater → PARAR e reportar, não aplicar em massa.**

---

## 7. PAINEL ADMIN (PT-BR — obrigatório, mexe em preços)

Novo ecrã `admin_continente_prices_screen.dart` + RPCs admin (padrão dos ecrãs admin existentes):
1. **Botão "Atualizar Preços Continente"** → marca um run (`product_update_runs`) e sinaliza o script/cron (o crawl pesado corre fora da app; a app não bloqueia 15 h).
2. **Tela de revisão da staging:** lista `nome | preço antigo | preço novo | PVPR | tinha promoção | método | confiança | status`. Filtros: só divergências >30%, só `name_match`/`ambiguous`, só `had_promo`, só `needs_review`.
3. **Ações:** aprovar tudo (alta confiança) · aprovar linha · rejeitar linha · aplicar selecionados → chama RPC que faz o UPDATE da Fase 3 com `admin_audit_log`.
4. **Auditoria:** quem correu, quando, quantos alterados (em `admin_audit_log` + `product_update_runs`).
5. **Kill switch:** `platform_settings.continente_price_crawler_enabled` (toggle no painel, via skill `update-platform-setting`).
6. **Política auto-apply (a confirmar §8):** `status='ok' AND method∈{sfcc_*} AND NOT needs_review AND diff≤30%` → auto-aplicável; resto → revisão manual.

---

## 8. DECISÕES A CONFIRMAR (Danilo)

1. **934 SFCC (8-jun):** re-crawl também (corrige possível promo capturada, recomendado) ou deixar como está?
2. **Auto-apply:** aplicar automaticamente alta confiança (`sfcc_*`, sem promo, diff≤30%) e mandar só o resto para revisão manual? Ou **tudo** passa por aprovação no painel?
3. **Limiar de divergência** para flag manual: 30% (proposto) ok?
4. **Workers:** 1 (seguro, ~15 h) ou 2 (~8 h, risco ligeiro)?
5. **Produtos sem PVPR fiável / 404 / ambíguos:** deixar `price` como está (proposto) — confirmar que NÃO se marca `is_available=false` (seriam ~5-10% do catálogo a desaparecer).
6. **Cron semanal:** integrar como o job de Terça (§27.1) via `weekly-market-prices`?

---

## 9. RISCOS & MITIGAÇÃO

| Risco | Mitigação |
|---|---|
| Hipótese `cont-<N>`=PID falsa | Fase 0 mede antes; fallback name-match 2b |
| Site muda layout do data layer | Validação §6 falha cedo → PARA |
| Preço "Cartão" confundido com base | Regra `list vs sales`; validação Sanex (5,99≠2,99) |
| Corrida 15 h interrompida | Checkpoint/resume (`phase1_full.py` já tem) |
| Escrita acidental na `products` | Crawler só escreve staging; UPDATE só na Fase 3 c/ aprovação |
| Bloqueio anti-bot | 3,5–4,5 s+jitter (0 bloqueios em abril); 1 worker |

---

## 10. ZONAS PROTEGIDAS — CONFIRMADO INTACTO

- **NÃO** altera `pricing_service.dart` nem a fórmula markup +15% (aplicada em runtime por `pricing_calculate`). Guardamos **preço base puro** em `price`, como todos os mercados.
- **NÃO** toca Stripe, dispatch, `bora_tokens`, RLS.
- Só colunas `price`, `last_updated`, `source` da `products` (loja Continente) + tabela staging nova + 1 setting + 1 ecrã admin.
