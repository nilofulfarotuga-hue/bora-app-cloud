# Sessão 4C/7 — productId Flutter Fix Completo (prompt)

**Data**: 2026-05-04
**Branch**: `autonomous-night-2026-04-29`
**Modelo**: Opus 4.7
**Estimativa**: 3-4h
**Modo**: PROTECÇÃO TOTAL (aprovação per task)

## Pré-requisitos
Sessões 1, 2, 3, 3B-NOVA, 4, 5A-1, 5A-2, 5A-2-β fechadas (último commit `0de7228`).

## Problema
Flutter envia `productId = NOME` (ex: "Comida Gato Auchan Adulto 400g") em vez do ID real (ex: "cnt-3847648") em call sites específicos. RPC `create_order` lookup falha → subtotal NULL → erro Flutter + ordens órfãs cobradas €5-6.50 (7 órfãs históricas conhecidas).

Sessão 4 B5 mitigou via fallback `unit_price` na RPC SQL (defesa server-side, ACTIVA) + asserts dev/debug em `cart_item.dart`. Asserts em Dart strip em release → produção vulnerável.

## Decisão estratégica
Single source of truth: `productId` vem do `ProductModel.id` da DB. Validação run-time em release (`if-throw` explícito, NÃO asserts).

## Estrutura
- **Fase A**: audit read-only (A0→A10) — STOP em A10
- **Fase B**: execução (B1→B5 + smokes + commit) — só após luz verde Danilo

## Output Fase A
- `.claude/.ai/reports/20260502_megafinal/04c_productid_audit.md`
- Cópia em `.obsidian-vault/entregas/04c_productid_audit.md`
- Cópia prompt em `.obsidian-vault/sessões/04c_prompt.md` (este ficheiro)

## Resumo findings Fase A (final)
- **3 call sites com bug** (não 30+, não 107):
  - `product_detail_screen.dart:28` — `_variantKey` embute nome
  - `store_products_screen.dart:872, 1149` — `_variantKey` embute nome
  - `restaurant_menu_screen.dart:188` — fallback `?? item.name`
- **1 único ponto RPC `create_order`** (`order_store.dart:714`) + 1 alternativo via Edge Fn (`:474`)
- **Decisão**: HÍBRIDA (CartItem validation + 4 edits cirúrgicos + validateOrderPayload helper)
- **Split α/β NÃO necessário**
- **4-5 ficheiros tocados na Fase B**

Ver `04c_productid_audit.md` para detalhes completos.
