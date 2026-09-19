# Intermarché-Guarda — Relatório de Sessão · 2026-06-05

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`
> Validado via `prompt-blindado-validator` (BLOCO 1–6 ✅). Loja `intermarche-guarda` (mercado = não-parceiro).

## 1. Acesso à fonte — ❌ BLOQUEADO
| Fonte | Resultado |
|---|---|
| Uber Eats (`ubereats.com`) | ❌ não carrega (timeout/bloqueio do browser tool) |
| `intermarche.pt` | ❌ **"Navigation to this domain is not allowed"** |
| Glovo | N/A — Glovo não tem Intermarché na Guarda |

**Consequência (regra do Passo 0):** não foi possível fazer **fotos** nem **validação cruzada** (Passos 3–4). Estes exigem a fonte e ficam para a skill `market-data-sync` (Playwright) numa sessão dedicada. A correção de preços foi feita na mesma, com a regra de fallback (soft-delete quando o preço é absurdo e não confirmável).

## 2. Erros de preço — investigados e tratados
Os 8 produtos sinalizados eram o **conjunto completo** de anomalias (confirmado por varrimento: só existem 3 produtos a exatamente €65,40 e mais 5 acima de €60; sem extras escondidos).

Como nenhuma fonte web está acessível, apliquei a distinção do prompt **absurdo vs suspeito**:

### Soft-deleted (`is_available=false` + `removal_reason='price_error_unconfirmed'`) — 5 produtos
| Nome | Categoria | Preço | Porquê |
|---|---|---|---|
| Lombo de Porco Curado 100g | Charcutaria & Queijos | €65,40 | €654/kg — impossível |
| Lombo de Peru Fatiado 150g | Charcutaria & Queijos | €65,40 | €436/kg — impossível |
| Lombo de Vitela 500g | Mercearia | €65,40 | €130/kg — absurdo (parte do bug €65,40) |
| Contorno de Olhos 15ml | Higiene Pessoal | €300 | creme de olhos normal €5–30 |
| Pá de Jardinagem | Mercearia | €300 | preço absurdo **+** mal categorizada (ver §3) |

> O padrão **€65,40 idêntico em 3 carnes não relacionadas** confirma bug do scraper anterior. Todos reversíveis (soft, não DELETE).

### Mantidos ativos mas FLAGADOS para verificação na fonte — 3 perfumes
O prompt classifica-os como "suspeitos", não "absurdos"; €80–120 é **plausível** para Eau de Parfum 100ml de marca. Sem fonte para confirmar, deixei-os ativos e registo aqui os IDs para o scraper reconciliar:
| Nome | Preço | ID |
|---|---|---|
| Eau de Parfum Masculino 100ml | €120 | 5b2b98a2-d287-4de5-8fd3-ffc9a1fc7977 |
| Eau de Parfum Feminino 100ml | €80 | 28124300-b799-4829-b614-6b8009f269ff |
| Eau de Toilette Natura 100ml | €80 | 7c38a86f-18d6-444a-97d3-c3b0001fe5bc |

**Nenhum preço foi inventado** (regra "Uber bloqueada → não inventar").

## 3. Pá de Jardinagem — decisão
Estava em "Mercearia" a €300. Não pude confirmar contra a fonte (bloqueada). Como o preço é absurdo, foi **soft-deleted** (`price_error_unconfirmed`) — sai da vista do cliente já. A correção de categoria (→ Jardim) ou remoção definitiva fica para a sessão com fonte: se existir no Uber Intermarché Guarda, recolocar com preço/categoria reais; se não, manter removida.

## 4. Fotos — ❌ não executado
1.864 sem foto (62%) **inalterado**. Requer a fonte Uber (bloqueada). **Não** usei backfill cross-loja por doadores (lição da sessão Auchan: gera placeholders genéricos). 0 placeholders introduzidos.

## 5. Validação cruzada — ❌ não executado
Requer o catálogo Uber completo. Adiado para `market-data-sync`.

## 6. Métricas — inicial vs final (MCP)
| Métrica | Inicial | Final |
|---|---|---|
| Total | 3.004 | 3.004 |
| Ativos | 2.967 | **2.962** (−5) |
| Sem preço | 0 ✅ | 0 ✅ |
| Sem foto | 1.864 | 1.864 (inalterado) |
| HTML quebrado | 0 ✅ | 0 ✅ |
| Categorias | 13 | 13 |
| Preço máx (ativo) | €300 | **€120** |
| Removidos (price_error) | — | 5 |

Busca validada (`ban`/`agu`/`iogur`/`detergent`) → resultados relevantes, nomes acentuados corretos.

## 7. Limitações (honestidade)
- **Uber Eats e intermarche.pt bloqueados** pelo browser tool → sem fotos, sem cross-validation, sem confirmação de preços reais.
- Os 5 soft-deletes são por preço absurdo não-confirmável (reversíveis); os 3 perfumes ficam por verificar.
- O grosso do trabalho (fotos reais + add/remove product-level + confirmar perfumes) depende de uma sessão `market-data-sync` Playwright com a fonte Uber.

## Regra admin
A edição de preço individual e a remoção produto-a-produto por loja já existem no painel admin (gestão de produtos). Não foi identificada lacuna nova.

## Zonas protegidas
Intactas. Apenas dados de catálogo (`products`) de `intermarche-guarda` e a coluna aditiva `removal_reason` (já existente). Nenhuma alteração a dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger.
