# Quality Rules — Market Data Cleaner

Critérios de qualidade aplicados na auditoria e limpeza. Qualquer decisão
"APAGAR" = soft-delete (`is_active = false`), NUNCA DELETE físico.

---

## Critério (a) — Produto sem imagem

**Detecção:**
- `photo_url IS NULL`
- `photo_url = ''`
- `photo_url` não começa com `http://` ou `https://`
- (Opcional futuro) URL devolve 404 — não verificar em audit.py por custo

**Decisão:**
- Default: **marcar `needs_review`** + manter activo (não apagar cegamente)
- Se >70% de um mercado sem imagem: escalar ao Danilo (provável bug de scraping)
- Placeholder só se aprovado explicitamente (cinza neutro #F5F5F5)

---

## Critério (b) — Produto sem marca detectável

**Detecção (heurística refinada 2026-04-19, aprovada por Danilo):**
- `has_brand = true` se QUALQUER uma das condições:
  1. `brand_low IS NOT NULL OR brand_mid IS NOT NULL OR brand_premium IS NOT NULL`
  2. `name ~* (allowlist_pattern)` (marcas conhecidas — ver abaixo)
  3. `name` contém pelo menos uma palavra capitalizada ≥3 letras (regex `\m[A-ZÀ-Þ][a-zà-ÿ]{2,}\M`) QUE NÃO esteja na lista de fillers

**Filler words (excluídas da detecção por capitalização):**
- Adjectivos: bio, eco, fresco/a, original, novo/a, natural, grande, pequeno, clássico, especial, premium, regular, light, diet, zero, intenso, suave, doce, salgado, picante
- Unidades: kilo, litro, litros
- Dias semana: segunda, terça, quarta, quinta, sexta, sábado, domingo
- Meses: janeiro–dezembro
- Preposições ES: con, sin, para, enero, febrero

**Allowlist de marcas (PT + PT-marcas próprias + PT-populares):**
```
hacendado, deliplus, bosque verde, milbona, saskia, compal, nestlé,
milaneza, knorr, delta, nescafé, mimosa, vigor, matinal, agros, pleno,
yoplait, danone, activia, parmalat, continente, pingo doce, auchan,
lidl, intermarché, mercadona, coca-cola, pepsi, sumol, luso, pedras,
sagres, super bock, heineken, lipton, maggi, calvé, heinz, hellmann,
barilla, nacional, cerelac, chocapic, tulicreme, bimbo, colgate,
oral-b, sensodyne, pantene, dove, nivea, axe, rexona, gillette, ariel,
skip, persil, finish, fairy, cif, sanex, dodot, pampers, huggies,
nutella, kit kat, snickers, mars, twix, bounty, ferrero, milka, oreo,
toblerone
```

**Decisão:**
- `has_brand = false` → `is_available = false` (soft-delete)
- Adicionar à allowlist marcas >20 ocorrências que fiquem como falsos positivos

**Nota Mercadona (encoding):** o catálogo Mercadona tem caracteres mal codificados
(`Ã` em vez de `á`/`í`/`ó`). Produtos como "ArÃndanos" não são apanhados como tendo
marca porque "Ar" tem <3 letras. São ~60 falsos positivos — aceitáveis como ruído
nesta passagem; 2ª passagem futura com normalização de encoding.

---

## Critério (c) — Preço inválido

**Detecção:**
- `price IS NULL` → sem preço
- `price = 0` → gratuito (suspeito)
- `price > 500` → provável erro de scraping (€ vs cêntimos)
- `price < 0.05` → muito barato (suspeito)

**Decisão:**
- Sem preço ou preço 0 → **soft-delete (`is_active = false`)** — não dá para vender sem preço
- Preço >€500 → **soft-delete** + flag `needs_review` (pode ser real mas precisa revisão)
- Preço <€0.05 → **soft-delete** + flag `needs_review`

---

## Critério (d) — Produto não-supermercado (Pingo Doce)

**Detecção (regex case-insensitive no nome):**
- Electrónica: `\y(tv|televis[ãa]o|smartphone|telem[óo]vel|computador|laptop|notebook|tablet|auscultador|headphone|colun[aã]o\s+bluetooth)\y`
- Automóvel: `\y(pneu|jante|bateria\s+carro)\y`
- Ourivesaria: `\y(ourivesaria|joia|pulseira\s+ouro|brinco\s+ouro|colar\s+ouro|rel[óo]gio\s+pulso)\y`
- Mobília: `\y(sof[áa]|cadeira\s+escrit|secret[áa]ria|mob[íi]lia|cama\s+de\s+casal)\y`
- Livros de lazer: `\y(livro\s+romance|banda\s+desenhada|comic)\y`

**Decisão:**
- Aplicar APENAS a produtos com `market_id` do Pingo Doce (validar primeiro)
- **Soft-delete** (is_active=false)
- Reportar contagem por keyword para permitir expansão da lista

**Exclusões (NÃO apagar mesmo que match):**
- "Pilhas" (supermercado vende)
- "Lâmpada" (supermercado vende)
- Produtos com preço < €20 (provável acessório legítimo de supermercado)

---

## Critério (e) — Tradução ES→PT (Mercadona)

**Detecção:**
- `market_id` da Mercadona
- Nome contém palavras-chave ES: `\y(con|de|para|sin|leche|aceite|carne|pescado|queso|huevo|huevos|pollo|agua|verdura|pan|mantequilla|galleta|zumo|arroz|az[úu]car)\y`

**Decisão:**
- **Traduzir `name`** (não apagar) via dicionário PT-ES hardcoded
- Dicionário mínimo inicial (em `translate.py`):
  ```
  leche → leite
  aceite → azeite
  carne → carne (igual)
  pescado → peixe
  queso → queijo
  huevo → ovo
  huevos → ovos
  pollo → frango
  agua → água
  verdura → vegetais
  pan → pão
  mantequilla → manteiga
  galleta → bolacha
  zumo → sumo
  arroz → arroz (igual)
  azúcar → açúcar
  con → com
  de → de (igual)
  para → para (igual)
  sin → sem
  ```
- Preservar `name` original em coluna `original_name_es` (se não existir, adicionar)
- `deep-translator` apenas se aprovado (requer rede + chave)

---

## Thresholds Globais

| Métrica | Limite | Acção se ultrapassar |
|---|---|---|
| % produtos sem marca num mercado | >80% | PARAR auditoria, reportar |
| % produtos afectados num batch | >50% | PARAR batch, reportar |
| Produtos activos projectados após limpeza | <100 por mercado | Reconsiderar estratégia |
| Tempo de query | >60s | Abortar |
| Tamanho de batch UPDATE | 1.000 linhas | Hard limit |

---

## Ordem de Execução Sugerida

1. **Lidl** (mais limpo historicamente) — piloto para validar processo
2. **Continente** — mercado grande, auditoria detalhada
3. **Auchan** — semelhante a Continente
4. **Intermarché** — normalmente pequeno
5. **Pingo Doce** — requer filtro adicional (critério d)
6. **Mercadona** — tradução em passo dedicado (critério e)
