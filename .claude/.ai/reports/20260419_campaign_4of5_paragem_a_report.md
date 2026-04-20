# Campanha 4/5 — Paragem A (Auditoria Read-Only)

**Data:** 2026-04-19
**Skill criada:** `.claude/skills/market-data-cleaner/` (5 ficheiros)
**Queries executadas:** 6 (A-F) + 2 cross-checks
**Writes à DB:** 0 (read-only absoluto)

---

## 🚨 ESCALAÇÕES CRÍTICAS (2)

### 1. Lidl — 67% do catálogo com preço €0 (6 083 / 9 085)
Amostras confirmam produtos reais com nomes **alemães**: "Saskia", "Kaugummi" (pastilha), "Bratwurst" (salsicha), "Milbona" (marca Lidl DE), "Malzina".
**Hipótese:** o scraping apanhou o catálogo **Lidl Alemanha** (não Portugal). Preços não foram extraídos porque a página DE tem estrutura diferente.
**Não é dado a limpar — é bug de ingestão.** Apagar 67% destruiria o catálogo.

### 2. Intermarché — 54% do catálogo com preço €0 (3 500 / 6 504)
Amostras confirmam produtos com nomes **franceses**: "Crème Caramel", "Comté Affiné 6 Mois", "Reblochon De Savoie", "Cacao Maigre En Poudre".
**Hipótese:** scraping apanhou **Intermarché França**.
**Mesma conclusão:** bug de origem do scrape, não dados a limpar.

**Acção recomendada:** antes de qualquer soft-delete destes dois mercados, reingestar com fonte PT. Esta campanha deve **saltá-los** e deixar em `needs_review` massivo até reingestão.

---

## 📊 Sumário por Mercado (supermercados)

| Mercado | Total | Sem imagem | % | Preço €0 | Preço >€500 | Outros (tax) | Estado |
|---|---:|---:|---:|---:|---:|---:|---|
| **Auchan** | 6 333 | 2 998 | 47.3% | 0 | 20 | 5.8% | Normal |
| **Continente** | 6 334 | 2 028 | 32.0% | 0 | 3 | 12.9% | Normal |
| **Intermarché** | 6 504 | 2 999 | 46.1% | **3 500** | 0 | 3.0% | 🚨 Escalar |
| **Lidl** | 9 085 | 3 002 | 33.0% | **6 083** | 0 | 2.2% | 🚨 Escalar |
| **Mercadona** | 5 011 | **0** | 0.0% | 2 | 2 | 22.0% | Tradução ES→PT |
| **Pingo Doce** | 9 542 | 3 037 | 31.8% | 0 | 0 | 22.0% | Normal |

Fast-food (McDonald's, KFC, Burger King, Pizza Hut, pizzaria paulista) com `total < 110` — fora do âmbito desta campanha.

---

## 📋 Detalhe por Critério

### (a) Sem imagem
- **Auchan**: 2 998 (47.3%) — mais alto
- **Intermarché**: 2 999 (46.1%)
- **Lidl**: 3 002 (33.0%)
- **Continente**: 2 028 (32.0%)
- **Pingo Doce**: 3 037 (31.8%)
- **Mercadona**: 0 (0%) — impecável
- Nenhum ultrapassa o threshold 70%.

### (b) Nomes curtos (proxy para "sem marca clara")
- Máximo: Lidl com 315 nomes <10 chars (3.5% do seu catálogo) → amostras são **marcas próprias alemãs** ("Milbona", "Saskia")
- Restantes <110 nomes curtos cada — residual
- **Nenhum mercado ultrapassa 80% sem marca**. Critério de escalação do Danilo não dispara por este motivo.

### (c) Preço inválido
- Sem preço (NULL): 0 em todos os mercados
- Preço = 0: **Lidl 6083**, **Intermarché 3500**, Mercadona 2, restantes 0 → tratar Lidl/Intermarché como escalação (acima); Mercadona 2 = soft-delete trivial
- Preço >€500: Auchan 20 (max €1649.99), Continente 3 (max €1498), Mercadona 2 (max €4875) → soft-delete + `needs_review`
- Preço <€0.05: Mercadona 31 (min €0.01) → soft-delete + `needs_review`

### (d) Não-supermercado no Pingo Doce
- Regex original (TV, smartphone, ourivesaria…): **0 matches**
- Regex alternativo (aspiradores, preço >€100): **8 matches** — "Aspirador Sem Saco", "Desumidificador", fraldas ("Pampers Tam.5"), tripas.
- **Conclusão:** o problema reportado pelo Danilo existe mas é muito menor que o esperado (8 produtos, não centenas). Fraldas são legítimas de supermercado. Candidatos reais a remover: ~2 (aspirador, desumidificador). **Critério (d) é marginal.**

### (e) Mercadona em espanhol
- **868 produtos** confirmados com vocabulário ES ("Queso lonchas", "Agua mineral", "Hacendado", "Ventresca de atún")
- 17% do catálogo Mercadona — tradução ES→PT é útil
- Dicionário PT-ES com 60 entradas já em `translate.py`

### (f) Taxonomy "Outros"
- Supermercados: Mercadona 22%, Pingo Doce 22%, Continente 13%, Auchan 6%, Intermarché 3%, Lidl 2%
- Fast-food com 46-100% "Outros" é **esperado** (18 secções são de supermercado, não restauração)
- **Não bloqueia esta campanha**. Potencial 2ª passagem do taxonomy-mapper só para Mercadona + Pingo Doce (~3 200 produtos) se quiseres.

---

## ✅ Invariantes Respeitadas

- Zero writes à DB
- Zero toques em zonas protegidas
- Backups `products_backup_2026_04_18` (22 264 rows) e `products_taxonomy_backup_20260419` (43 121 rows) intactos
- Escalações disparadas antes de qualquer DELETE/UPDATE

---

## 📋 Plano de Limpeza Proposto (aguarda aprovação em Paragem B)

### Estratégia revista (divergente do plano original)

| Ordem | Mercado | Acção | Volume | Confiança |
|---|---|---|---:|---|
| 1 | **Mercadona** | Soft-delete preços inválidos (35) + tradução ES→PT (868) | 903 | Alta — catálogo limpo de base |
| 2 | **Continente** | Soft-delete preços >€500 (3) + flag needs_review sem imagem (2 028) | 2 031 | Alta |
| 3 | **Auchan** | Soft-delete preços >€500 (20) + flag needs_review sem imagem (2 998) | 3 018 | Alta |
| 4 | **Pingo Doce** | Flag needs_review sem imagem (3 037) + soft-delete 2 electrónicos | 3 039 | Alta |
| 5 | **Lidl** | ⚠️ **ADIAR** — reingestar de fonte PT antes de limpar | — | Bloqueado |
| 6 | **Intermarché** | ⚠️ **ADIAR** — reingestar de fonte PT antes de limpar | — | Bloqueado |

### Totais projectados
- Soft-deletes reais (is_active=false): **62** (Mercadona 35 + Continente 3 + Auchan 20 + Pingo Doce 2 + Mercadona 2 preço 0)
- Updates tradução (Mercadona name): **868**
- Flags `needs_review = true` (sem imagem): **~11 128** (não removidos, apenas sinalizados)
- Totais activos após limpeza (mercados limpáveis): Mercadona 4 976, Continente 6 331, Auchan 6 313, Pingo Doce 9 540 — todos bem acima do threshold 100.

### Setup one-time necessário antes de Parte 4
1. Criar `products_cleanup_backup_20260419` (snapshot id/photo_url/name/price/is_active)
2. **Usar coluna existente `is_available` em vez de criar `is_active`** (evita migração nova — `is_available` já existe e tem o mesmo significado semântico)
3. `ALTER TABLE products ADD COLUMN IF NOT EXISTS original_name_es text` — só para Mercadona
4. Verificar queries Flutter: filtram `WHERE is_available = true`? (reportar em Paragem B)

---

## 🔍 Decisões pendentes para Paragem B

1. **Usar `is_available` (já existe) ou criar `is_active`?** → recomendo reutilizar `is_available`.
2. **Lidl/Intermarché:** adiar inteiramente ou marcar os 9 583 com `needs_review=true` até reingestão?
3. **Tradução Mercadona:** dicionário hardcoded (offline, já pronto) ou `deep-translator` (requer instalar + rede)?
4. **Placeholder de imagem:** usar nos 11 128 sem imagem ou só flag needs_review?
5. **2ª passagem taxonomy-mapper** para Mercadona + Pingo Doce "Outros" (~3 200 produtos): nesta campanha ou Campanha 5/5?

---

## Próximo passo

Aguardar aprovação explícita do Danilo sobre:
- As 5 decisões pendentes acima
- Escalação Lidl/Intermarché (adiar vs marcar needs_review)
- Ordem de execução revista

**Não avançar à Parte 4 sem resposta.**
