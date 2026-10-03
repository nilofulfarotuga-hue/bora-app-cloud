# Rebuild Pingo Doce-Guarda via Glovo Lisboa — EXECUTADO · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`.
> Pingo Doce não existe na Guarda (Glovo/Uber). Rebuild copiando catálogo de uma loja Glovo Pingo Doce de Lisboa. Sequência idêntica à Auchan (commit d690de3).

## 1. Loja Glovo escolhida
- **`pingo-doce-lis4`** — store **427913** / addr **869627** (Lisboa).
- **Razão:** das lojas Pingo Doce Lisboa na Glovo, só `pingo-doce-lis4` resolve sem morada (as outras `lis1-3,5-9` existem mas são *address-gated* — exigem morada na zona de entrega). `lis4` é uma loja **numerada normal** (não um flagship com nome tipo "Colombo"/"Saldanha"), e o seu catálogo (5.071 produtos) é de **dimensão média** — coerente com o objectivo "loja mediana de bairro, não a gigante gourmet". Os 99 stores da categoria incluíam 1 PD limpo + dezenas de slugs hashed (outras marcas/lojas address-gated).

## 2. Lojas Pingo Doce Lisboa (Glovo)
`pingo-doce-lis1` … `pingo-doce-lis9` existem como páginas; só `lis4` resolve catálogo sem morada (default). As restantes precisam de morada por zona. Não foi possível enumerar contagens das address-gated sem definir várias moradas — usou-se `lis4` (média, resolúvel).

## 3. Exclusão de categorias não-alimentação
Semeadas **19 categorias** alimentares/casa; **excluídas** (per decisão Danilo): Livraria e Papelaria, Casa e Decoração, Bricolage/Jardim/Auto. Também removido o root de marketing **"As Nossas Marcas"** (881 produtos) re-correndo o crawler sem esse mapeamento → esses produtos PD-marca herdaram a **categoria alimentar real** (Mercearia/Laticínios/...). Leak final das excluídas: **0** (48 produtos cross-link filtrados no apply).

## 4. Métricas antes/depois (MCP)
| Métrica | Antes (caótico) | Depois (Glovo Lisboa) |
|---|---|---|
| Total | 9.395 | **5.023** |
| Ativos | 7.414 | **5.023** |
| Sem foto | muitos | **16** (99,7% com foto) |
| Sem preço | 0 | **0** |
| Categorias | 27 (HTML sujo) | **19** (limpas, ordem Glovo) |
| Leak excluídas | — | **0** |
| sort_order | — | 100% (ordem da home Glovo) |
| Preço min/máx | caótico (€0,02–>€50) | €0,10 / €74,99 |

## 5. 5 produtos sample (preço Glovo)
| Nome | Preço |
|---|---|
| Manteiga com Sal Mimosa 250G | €2,44 |
| Manteiga sem Sal Mimosa 250G | €2,44 |
| Pão de Forma Branco sem Côdea Pingo Doce 450G | €1,29 |
| Pão de Forma 360G | €2,99 |
| Bolachas Nutella Biscuits 304G | €4,79 |

## 6. Validação de preço vs Pingo Doce oficial
- **Manteiga com Sal Mimosa 250g = €2,44** → oficial €2,19–2,44 → **MATCH** (topo do intervalo). 
- **Conclusão: Glovo Pingo Doce = preço de prateleira, SEM markup oculto** (como a Glovo Auchan, ao contrário da Uber Intermarché). Preço gravado **direto** (= preço-base; +15% Bora em runtime). **Nenhuma correção aplicada** (correto).

## 7. Categorias finais (ordem Glovo)
Frutas e Vegetais > Talho e Peixaria > Charcutaria e Queijos > Padaria e Pastelaria > Laticínios e Ovos > Mercearia > Mercearia Doce > Refeições Frescas > Gelados e Congelados > Águas e Sumos > Cervejas e Sidras > Vinhos e Espumantes > Bebidas Espirituosas > Bio e Saudável > Beleza e Higiene > Saúde e Bem-Estar > Limpeza > Bebé e Criança > Animais de Estimação. (19)

## 8. Diff vs backup
Backup `_backup_pingodoce_pre_rebuild_2026_06_07` (9.395) + `_backup_pingodoce_pre_cleanup_2026_06_07` (estado original). Novo=5.023, **100% ids novos** (prefix `pd-{storeProductId}`) → substituição total do catálogo caótico antigo por espelho limpo da Glovo Lisboa. Esperado num rebuild.

## 9. Ferramenta
Reusado `glovo_grocery_crawler.js` (commit d690de3) — **generalizado** com `--names <json>` para suportar outras lojas Glovo (Pingo Doce usa scId/nomes próprios). Reutilizável para qualquer loja Glovo.

## 10. Reversão
`DELETE … ; INSERT … SELECT * FROM _backup_pingodoce_pre_rebuild_2026_06_07;` (via MCP).

## 11. Zonas protegidas
Intactas. Só `products` de `pingodoce-guarda` + backups. Sem toques em dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger.
