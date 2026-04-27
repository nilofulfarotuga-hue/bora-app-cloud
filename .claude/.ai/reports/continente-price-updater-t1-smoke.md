# Continente Price Updater — T1 Smoke Test (50 PIDs)

Data: 2026-04-21
Método: M3 (Product-Show?pid=) + follow redirects → `/produto/<slug>-<pid>.html`
Execução: 267,1 s (~4m27s) · rate 4,5s ±0,8s jitter · User-Agent Chrome real · 0 DB writes
Dataset completo: `.claude/.ai/tmp/continente_smoke.json`

## Resumo

| Status | N.º | % |
|---|---|---|
| igual (|Δ|≤0,01€) | 35 | 70% |
| diferente (mesmo produto, preço mudou) | 9 | 18% |
| **⚠️ diferente-NOME_DIFERENTE** (PID na BD aponta para outro produto) | 4 | 8% |
| não encontrado (sem JSON-LD Product) | 2 | 4% |
| erro HTTP / bloqueio | 0 | 0% |

Cobertura: 48/50 (96%) com preço extraído. **Zero 429, zero 5xx, zero bloqueios.**

## Findings críticos

### 1. Rate-limit 4,5s ±0,8s é seguro
50 requests consecutivos sem qualquer sinal de throttling. Podemos manter este rate para a Fase 1 inteira (4.577 × 4,5s ≈ 5h43m).

### 2. ⚠️ PID errado em 4 produtos (8%) — todos com `id` tipo `prod_XXXX`
Os 4 mismatches vêm **todos** de seed data (`20260415000000_seed_restaurants.sql`). A `photo_url` nesses rows tem um PID que não pertence ao produto descrito no `name`. Se fizermos UPDATE cego pelo PID, **escrevemos preço errado em 8% do catálogo**.

| id BD | nome BD | nome SITE | preço site |
|---|---|---|---|
| prod_0977 | Ervilhas Congeladas 750g | Delícias do Mar Ultracongeladas Continente | 1,29€ |
| prod_0683 | Curcuma + Pimenta Preta 60un | Pimenta Branca com Moínho em Frasco Continente | 1,79€ |
| prod_0313 | Tabasco 60ml | Mostarda Dijon com Mel em Vidro Maille | 3,99€ |
| prod_0035 | Atum em Lata 120g | Salsichas Frankfurt Lata 10 un Continente | 1,19€ |

**Amostragem por tipo de id:**
- 6 `prod_*` → 4 com PID errado (67%!)
- 19 `cnt-*` → 0 com PID errado (0%)
- 25 uuid → 0 com PID errado (0%)

**Conclusão:** o campo `photo_url` dos rows `prod_*` não é fonte fiável de PID. Ou excluímos `prod_*` da Fase 1, ou **forçamos verificação de nome antes do UPDATE**.

### 3. 9 diferenças reais de preço (mesmo produto)
Confirmam que a BD está desactualizada. Amostragem:

| PID | Produto | BD | Site | Δ |
|---|---|---|---|---|
| 7163487 | Tamboril Fresco kg | 9,26 | 1,79 | **-7,47€** |
| 2604857 | Lasanha de Legumes Congelada 400g | 5,44 | 0,74 | -4,70€ |
| 8195596 | Body Mist Exotic Love Womensecret | 12,99 | 9,74 | -3,25€ |
| 7305458 | Café em Grão Qualitá Oro Int 5 Lavazza | 17,99 | 14,99 | -3,00€ |
| 7801750 | Creme Corpo Soft&Co | 9,99 | 7,49 | -2,50€ |
| 2053281 | Champô Cabelo Normal | 2,99 | 4,99 | **+2,00€** |
| 8519065 | Creme Balsâmico Romã Bio Cristal | 3,89 | 2,52 | -1,37€ |
| 7329389 | Queijo Curado Fatiado Castelões | 4,99 | 3,99 | -1,00€ |
| 4999431 | Bolachas Cracker Tuc | 3,19 | 2,49 | -0,70€ |

Nota: `Tamboril Fresco kg` (9,26→1,79) é suspeito — provavelmente o site devolveu o preço por unidade em vez de por kg. **Rever antes de actualizar**.

### 4. 2 não encontrados
PIDs 8147037 (Broas d'Avó) e 7071906 (Strogonoff de Peru) — página carrega mas sem JSON-LD Product. Podem estar descontinuados. Aceitável em Fase 1 como skip.

## Recomendações para Fase 1 (antes de arrancar)

1. **Obrigatório: validação de nome.** UPDATE só se `name_match ≥ 0,3` (ratio de palavras partilhadas, primeiros 4 chars, sem acentos). Na amostra, este critério apanhou 100% dos 4 mismatches sem falsos positivos.
2. **Considerar excluir rows `prod_*` da Fase 1**, ou correr apenas validação read-only e reportar. São 6/50 = ~12% do catálogo mas têm fiabilidade de PID muito baixa.
3. **Seguir redirects** — obrigatório (sem isto, 100% dos requests falham com 301).
4. **Cookie jar** — manter entre redirects (sem isto, algumas páginas devolvem cookie-wall).
5. **Tratar Tamboril/unidade de venda** — se `site_price` < 30% do `bd_price` em produtos frescos (kg), **marcar para revisão manual**, não fazer UPDATE automático.
6. **Rate 4,5s ±0,8s confirmado seguro.** Pode manter-se.

## Números esperados para Fase 1 completa (4.577 produtos)

Extrapolando a amostra:
- ~3.200 iguais (70%)
- ~820 diferenças reais de preço (18%) → **UPDATEs úteis**
- ~370 PID errado (8%) → **skip via name-guard**
- ~180 não encontrados (4%) → **skip**
- Duração estimada: ~5h43m

## STOP

T1 concluído. Zero DB writes. Método validado com ajustes obrigatórios identificados.

**A aguardar OK do Danilo para T2 (Fase 1 completa).** Se OK, aplico as 5 recomendações acima antes de arrancar.
