---
name: market-harvester
description: Use this skill when the user says "SKILL: market-harvester", or when work needs to find or fix product images across the 6 Portuguese markets (Mercadona, Continente, Pingo Doce, Lidl, Auchan, Intermarché). Handles the 4-level image cascade (L1 market CDN → L2 inter-market library → L3 brand site → L4 Bing/Google Images) with budget enforcement (€50/mês). Complements `market-scraper` (per-market fetch) and `products-updater` (weekly cron). Triggers on "fix fotos", "imagens mercados", "cascata L1 L2 L3 L4", "harvester imagens", "fotos fictícias".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill é descritiva — planeia e orquestra recuperação de imagens reais de produtos aplicando cascata L1→L4. Nunca executa scrapers, nunca escreve na DB nesta sessão. Cascata e orçamento vêm da BR v2 §27.2. Match inter-market por `(nome_normalizado, marca, unidade)`.

# MARKET HARVESTER

## ROLE
Especialista transversal em recuperação de imagens de produtos para os 6 mercados portugueses. Aplica a cascata canónica de 4 níveis (BR §27.2), reutiliza imagens legítimas entre mercados (mesmo produto = mesma imagem) e preserva sempre o preço específico de cada mercado. Responsável por eliminar imagens fictícias sem nunca introduzir novas.

Corre DEPOIS de `market-scraper` (que preenche L1 por mercado) e ANTES de `system_validator`.

---

## CASCATA CANÓNICA (BR §27.2)

Para cada linha em `products` sem imagem válida:

| Nível | Fonte | Custo | Quando usar | Prova de hit |
|---|---|---|---|---|
| **L1** | Site oficial do próprio mercado (CDN do mercado) | Grátis | Preferencial. Corrido por `market-scraper`. | URL começa pelo CDN do mercado + HTTP 200 + content-type image/* |
| **L2** | Biblioteca partilhada inter-market (Mercadona primeiro, depois Continente, Lidl, Pingo Doce, Auchan, Intermarché) | Grátis | Match `(nome_normalizado, marca, unidade)` existente com imagem L1 noutro mercado. | Linha `source` da library marcada como L1 legítima |
| **L3** | Site oficial da marca (derivado de `brand_low` / `brand_mid` / `brand_premium`) | Grátis | Produto de marca global (Coca-Cola, Nestlé, Unilever). Seguir sitemap / open graph image. | HTTP 200 + og:image ou JSON-LD `image` |
| **L4** | API de imagens: Bing Image Search (1.000/mês grátis) **primeiro**, Google Custom Search (3.000/mês grátis) como fallback | Meta gratuito; tecto €50/mês | Só se L1–L3 falharem. Query = `"{brand} {name} {unit} PT"`. | Primeiro resultado com content-type image/* e pelo menos 200×200 |
| **Fallback** | `photo_url = NULL` + `needs_photo = true` | — | Todos os níveis falharam. | — |

Cascata para de descer no primeiro hit válido.

---

## INPUTS / OUTPUTS

### Input
```
{
  market: "continente-guarda" | "pingodoce-guarda" | ... | "mercadona-guarda",
  dry_run: true|false,
  rows: [ { id, name, brand_low, brand_mid, brand_premium, unit, current_photo_url } ]
}
```

### Output
```
{
  rows_total: N,
  images_l1: n,
  images_l2: n,
  images_l3: n,
  images_l4_bing: n,
  images_l4_google: n,
  no_image: n,
  fictitious_cleared: n,
  budget_spent_eur: x.xx,
  budget_cap_hit: true|false,
  errors: [...]
}
```

---

## NORMALIZAÇÃO DE MATCH (L2)

Chave canónica usada para partilhar imagens entre mercados:

```
normalize(name)   -> lowercase + sem acentos + trim + colapsar espaços + remover pontuação
normalize(brand)  -> lowercase + sem acentos + trim
normalize(unit)   -> parse "500ml" / "1L" / "200g" / "6x33cl" → {value, unit_base}
```

Match obrigatório nos três campos. Se `brand_*` estiverem todos NULL, cai para L3/L4 sem tentar L2.

---

## DETECÇÃO DE IMAGENS FICTÍCIAS

Candidatos a fictício (suspeita — ver auditoria Fase 1 do plano):

- `photo_url` repetida em ≥ 50 linhas do mesmo mercado → suspeita de placeholder em lote.
- `photo_url` aponta para CDN de outro mercado mas o match `(nome_normalizado, marca, unidade)` falha → fictícia certa.
- `photo_url` HTTP 404 / 403 / content-type diferente de `image/*` → fictícia.

Acção: `photo_url = NULL` + `needs_photo = true`. **Nunca** substituir por outra foto fictícia.

---

## ORÇAMENTO L4 (BR §27.2)

- Tecto absoluto: **€50/mês** somando Bing + Google.
- Alerta admin aos **€30** (80 %).
- Paragem obrigatória aos **€50** → restante produtos caem para fallback `needs_photo = true`.
- Contador mensal vive em `product_image_budget` (tabela a criar em sessão dedicada).
- Reset na primeira corrida do mês.
- Alertas via `notifications-engineer`.

---

## EXEMPLOS WORKED

### Exemplo 1 — Coca-Cola 1.5L aparece em 4 mercados

**Input:** `rows = [ {id:'ct-001', name:'Coca-Cola 1.5L', brand_low:'Coca-Cola', unit:'1.5L', current_photo_url: 'cdn.mercadona.es/fake.jpg'} ]` em Continente.

**Processo:**
1. Detectar que `cdn.mercadona.es/fake.jpg` não existe em `mercadona-guarda` com a mesma chave → fictícia.
2. L1 Continente: tentar `cdnd.continente.pt/.../coca-cola-1-5l.jpg` → hit ✅ → usar.
3. Caso L1 falhe: L2 — procurar em `mercadona-guarda WHERE (nome_normalizado, marca, unidade) == (coca-cola, coca-cola, 1.5L)` → hit ✅ → reutilizar URL Mercadona (agora legítimo, BR §27.2 permite).
4. Preço da Continente mantém-se intacto (nunca partilhado).

**Output esperado:**
```
✅ HARVEST COCA-COLA 1.5L — BR §27.2
Continente: L1 hit (cdnd.continente.pt)
Fallback possível: L2 Mercadona (mesma chave)
Preço: preservado (NUNCA partilhado)
Delegar a: executor em sessão dedicada
```

**Failure mode:** Falha se gravar URL Mercadona por cima do preço da Continente. Falha se marcar fictícia a url Mercadona onde o match `(nome_normalizado, marca, unidade)` é real.

---

### Exemplo 2 — Produto Lidl sem marca global (marca branca "Freeway Cola")

**Input:** `rows = [ {id:'lidl-123', name:'Freeway Cola 1.5L', brand_low:'Freeway', unit:'1.5L', current_photo_url: NULL} ]`.

**Processo:**
1. L1 Lidl: tentar `lidl.pt/.../freeway-cola-1-5l.jpg`.
2. Se L1 falhar: L2 — marca branca Lidl não existe noutros mercados → skip.
3. L3: `freeway` não é site de marca global → skip.
4. L4: Bing `"Freeway Cola 1.5L PT"` → tentar primeiro (quota 1.000/mês).
5. Se Bing sem orçamento: Google CSE.
6. Se ambos falharem: `photo_url = NULL` + `needs_photo = true`.

**Output esperado:**
```
✅ HARVEST FREEWAY COLA — BR §27.2 cascata completa
L1 Lidl: miss
L2 inter-market: skip (marca branca)
L3 brand: skip (sem site oficial)
L4 Bing: hit ✅ custo €0.001
Budget mensal: 2.34 / 50.00 EUR
```

**Failure mode:** Falha se Bing devolver imagem de Coca-Cola (produto diferente) e o harvester aceitar. Mitigação: verificação mínima de similaridade textual no alt-text da imagem.

---

### Exemplo 3 — Orçamento L4 bate em €50

**Input:** mid-run do Lidl, budget chegou a €50.

**Processo:**
1. Paragem imediata das chamadas L4.
2. Linhas restantes: `photo_url = NULL` + `needs_photo = true`.
3. Alerta crítico via `notifications-engineer` (email + FCM admin).
4. Log em `product_update_log` com `budget_cap_hit = true`.
5. Retomar no mês seguinte.

**Output esperado:**
```
🔴 BUDGET L4 CAP — BR §27.2
Custo mês: 50.00 / 50.00 EUR
Linhas restantes marcadas needs_photo=true
Alerta admin enviado
Retomar no reset do mês
```

**Failure mode:** Falha se continuar a consumir API depois do cap. Falha se apagar linhas em vez de marcar needs_photo.

---

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Fetch L1 por mercado (HTML/API do próprio site) | `market-scraper` |
| Cascata L2 (inter-market) + L3 (marca) + L4 (Bing/Google) | **market-harvester** (eu) |
| Orquestração semanal cross-market + pg_cron | `products-updater` |
| Análise legal ToS de cada fonte | — (externa / Danilo) |
| Alertas admin em budget cap / falha | `notifications-engineer` |
| Observação em produção | `monitoring-engineer` |
| Validação schema pós-mudança | `system_validator` |
| Proteger pricing / dispatch / Stripe | `guardian` · `flow_guard` |

---

## NÃO PODE FAZER

- ❌ Criar edge functions nesta sessão (pertence a sessão dedicada via `executor`).
- ❌ Criar pg_cron nesta sessão.
- ❌ Escrever na DB nesta sessão (read-only spec).
- ❌ Substituir foto fictícia por outra foto fictícia.
- ❌ Partilhar preço entre mercados (BR §27.2 proíbe).
- ❌ Tocar em zonas protegidas BR §25.3 (pricing_service, driver_capacity_service, finalizePurchase, bora_tokens triggers, Stripe, dispatch-engine).
- ❌ Exceder 1 req/s por host (BR §27.5).
- ❌ Exceder €50/mês em L4.

---

## RESPONSABILIDADES

- ✅ Aplicar cascata L1→L4 sem saltar níveis (BR §27.2).
- ✅ Validar que imagem L2 corresponde ao mesmo produto (match chave canónica).
- ✅ Detectar e limpar fotos fictícias sem introduzir novas.
- ✅ Respeitar orçamento mensal €50 com alertas aos €30/€50.
- ✅ Preservar preços de cada mercado.
- ✅ Logar em `product_update_log` a contagem por nível.
- ✅ Alertar admin em falhas e cap.

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §27.2 · §27.5 (revisto 2026-04-18).
- Cascata L1→L4 canónica. Parar no primeiro hit válido.
- Match L2 obrigatório em `(nome_normalizado, marca, unidade)`.
- Preços **NUNCA** partilhados entre mercados.
- Foto fictícia detectada → `photo_url = NULL` + `needs_photo = true`.
- Orçamento L4 €50/mês com alerta aos €30.
- Rate limit 1 req/s por host.
- Ordem canónica: `decision_engine` → `market-scraper` (L1) → **market-harvester** (L2→L4) → `system_validator` → `executor` (em sessão dedicada).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/business_rules.md` §27.2 | Cascata canónica + orçamento L4 |
| `.claude/.ai/business_rules.md` §27.5 | Regras anti-falha |
| `.claude/.ai/business_rules.md` §27.6 | Estado actual por mercado |
| `supabase/functions/update-products/` | Host eventual das chamadas L4 (sessão dedicada) |
| `scripts/scraper/` | Scripts de scraping existentes (L1) |
| skill `market-scraper` | L1 por mercado |
| skill `products-updater` | Orquestração semanal |
| skill `notifications-engineer` | Alertas budget/falha |
| skill `monitoring-engineer` | Observação produção |
| skill `system_validator` | Smoke tests pós-mudança |
| skill `guardian` | Barreira zonas protegidas §25.3 |

---

## BENCHMARK

> **iFood Catalog Sync** — imagens vêm do POS do parceiro (menu API). Sem cascata cross-vendor.
>
> **Uber Eats** — cada integração POS (Clover, Square, Toast) entrega imagem própria. Sem harvesting externo.
>
> **Glovo / Deliveroo** — catálogos partilhados entre parceiros com mesmo GTIN/EAN. Reutilização de imagem por GTIN é prática standard — equivalente ao nosso match por `(nome_normalizado, marca, unidade)` (sem GTIN disponível publicamente em PT).
>
> **Bora equivalente:** BR §27.2 com cascata de 4 níveis e orçamento L4 explícito. Diferenciador: budget rígido €50/mês + fallback `needs_photo` antes de arriscar foto fictícia.
