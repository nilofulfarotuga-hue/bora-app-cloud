# Continente PVPR — APLICAÇÃO FINAL (2026-06-15)

> Corrida completa + carregamento + aplicação parcial. Backup `_backup_continente_precos_pre_oficial_2026_06_14` (11.884) garante rollback.

## Corrida
- **11.884/11.884 (100%)** via 8 workers paralelos (`--shards 8 --sleep 2.5`, ~1,5h, keep-awake). 0 bloqueios.
- Carregado para `continente_price_staging` (run `f71e47fe-909c-4d60-b7df-78dca737f921`).
- **com preço:** 11.050 (4.148 em promoção → usaram PVPR) · **sem preço (404/redirect):** 834.

## Decisão de aplicação (Danilo): "Aplicar embalados, excluir a-peso"
Descoberta crítica: o continente.pt expõe **preço/kg** no JSON-LD para produtos a peso (Frutas e Vegetais, Talho e Peixaria), que **não** corresponde à unidade de venda da Bora (ex.: Banana 0,24→1,29 = €/kg). Aplicar cegamente poria dezenas de produtos a peso com preço errado.

| Resultado | N | Destino |
|---|---|---|
| **Aplicados** a `products` (categorias à unidade) | **9.855** | `price`+`last_updated`+`source='continente_pt_official_2026-06-14'` |
| Rejeitados — a peso (Frutas/Vegetais 986 + Talho/Peixaria 208) | 1.194 | `price` intacto + `needs_review` |
| Rejeitado — bug preço 0 (Termo Inox, revertido do backup) | 1 | `price` 9,00 restaurado |
| Sem preço (404/redirect online) | 834 | `price` intacto + `needs_review` |

## Validação (pós-aplicação, em produção)
- Gate: Sanex Protector/Zero%/Pro Hydrate = **5,99€** (eram 3,05) ✓ · Vaseline Karité = **4,99€** ✓
- Sanity: 3 preços >500€ = **legítimos** (Château Ausone 1218€, Pavie 504€, Piscina 1099€ — `old==new`). 1 a 0€ (Termo) **corrigido**.
- Audit: `admin_audit_log` action `continente_prices_applied`.
- Guard `price>0` adicionado ao crawler (previne repetição no cron).

## Pendente (próximas sessões)
1. **1.194 a peso** — converter €/kg → €/unidade (precisa do peso médio/unidade) ou manter Glovo. Estão em staging `reviewer_action='rejected'`, `needs_review=true`.
2. **834 sem preço** — descontinuados/sem stock online; manter ou re-tentar mensal.
3. **Cron de Terça** (`weekly-market-prices`) — só após este 1º ciclo validado pelo Danilo no terreno.
