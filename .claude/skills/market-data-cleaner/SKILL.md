---
name: market-data-cleaner
description: >
  Limpa o catálogo de produtos por mercado (Continente, Lidl, Auchan, Pingo Doce,
  Intermarché, Mercadona). Trata 5 critérios de qualidade: (a) produtos sem
  imagem, (b) produtos sem marca detectável, (c) preços inválidos/NULL/zero/>€500,
  (d) produtos não-supermercado (electrónicos, bijuteria, moda) a remover do
  scraping do Pingo Doce, (e) tradução ES→PT de nomes da Mercadona. Usa SEMPRE
  soft-delete (is_active=false) — NUNCA DELETE físico. Exige backup antes de
  qualquer mutação e dry-run obrigatório em clean.py.

  Triggers:
    - "limpar catálogo do Lidl" / "limpar catálogo do Continente" / etc.
    - "auditar produtos sem marca/imagem/preço"
    - "traduzir produtos Mercadona"
    - "remover electrónicos do Pingo Doce"
    - "auditoria global de qualidade de produtos"
---

# Market Data Cleaner — Bora App

## Propósito

Melhorar a qualidade do catálogo de produtos visível ao cliente final. O scraping
inicial trouxe ruído: imagens em falta, nomes sem marca, preços inválidos, idioma
espanhol (Mercadona), e categorias fora de âmbito (TVs no Pingo Doce). Esta skill
remove esse ruído de forma reversível e auditável.

## Quando usar

- Ao detectar quadrados cinza (imagem em falta) no ecrã de produtos
- Quando um mercado específico precisa de revisão de qualidade
- Antes de lançamento, para garantir primeira impressão sólida ao utilizador
- Após cada scrape novo de um parceiro

## Quando NÃO usar

- Não apagar produtos fisicamente (DELETE) — sempre `UPDATE is_active = false`
- Não alterar `name`/`category_root`/`category` sem backup (excepto tradução ES→PT da Mercadona com passo dedicado)
- Não tocar em zonas protegidas:
  - `lib/services/pricing_service.dart`
  - `supabase/functions/dispatch-engine/`
  - Stripe / `create-payment-intent` / `stripe-webhook` / `confirm-mbway-payment`
  - Triggers `bora_tokens` / `driver_balances`
  - `lib/services/driver_capacity_service.dart`
  - `lib/auth/auth_store.dart`
  - `products_backup_2026_04_18` (preservar)
  - `products_taxonomy_backup_20260419` (preservar)

## Estrutura

```
market-data-cleaner/
├── SKILL.md                    # este ficheiro
├── references/
│   └── quality_rules.md        # 5 critérios de qualidade + thresholds
└── scripts/
    ├── audit.py                # read-only: conta problemas por mercado
    ├── clean.py                # soft-delete com dry-run obrigatório
    └── translate.py            # tradução ES→PT Mercadona (dicionário local)
```

## Fluxo de Execução (obrigatório)

1. **Paragem A — Auditoria read-only**
   - Correr `audit.py` ou queries A-F via MCP Supabase
   - Reportar números por mercado ao Danilo
   - NÃO executar limpeza

2. **Paragem B — Plano aprovado**
   - Apresentar estimativa: quantos produtos por critério por mercado
   - Propor ordem de execução (mercado mais limpo primeiro)
   - Aguardar aprovação explícita

3. **Paragem C — Pós-primeiro-mercado**
   - Executar limpeza num só mercado (ex: Lidl)
   - Reportar resultados reais (diff vs estimado)
   - Aguardar luz verde antes de avançar aos outros

## Regras Duras

1. **Backup obrigatório** antes de qualquer UPDATE:
   - Tabela `products_cleanup_backup_20260419` = snapshot de `id, photo_url, name, price, is_active` ANTES de mutar
2. **Soft-delete apenas**: `UPDATE products SET is_active = false`
   - Se coluna `is_active` não existir, adicionar com `DEFAULT true` primeiro
3. **Batches transaccionais** de ~1.000 produtos
4. **Circuit breakers**:
   - Se >50% de produtos de um mercado afectados → PARAR e reportar
   - Se query demora >60s → PARAR
5. **Tradução Mercadona**:
   - Passo dedicado, revisível
   - Dicionário PT-ES hardcoded (agua→água, leche→leite, aceite→azeite…) por defeito
   - `deep-translator` só se aprovado (requer rede)
6. **Flutter queries** devem filtrar `WHERE is_active = true` (reportar se já existe ou falta adicionar)

## Critérios de Qualidade

Ver `references/quality_rules.md` para detalhe dos 5 critérios (a-e) com thresholds, keywords e decisões (APAGAR vs needs_review vs traduzir).

## Saídas Esperadas

- Relatório de auditoria em `.claude/.ai/reports/YYYYMMDD_campaign_4of5_*.md`
- Diff por mercado (antes/depois)
- Lista de produtos marcados `needs_review` (para revisão manual)
- Contagem de produtos activos finais por mercado

## Identidade da Marca (para placeholders)

Se se decidir usar placeholders em vez de apagar:
- Cor de fundo: #F5F5F5 (cinza claro neutro)
- Ícone: genérico da secção taxonómica (ex: garrafa para Bebidas)
- NUNCA usar logo Bora (#2E7D32 + #E65100) num placeholder de produto
