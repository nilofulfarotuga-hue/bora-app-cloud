# Fase 2 — Copiar Opções Glovo → Bora · DRY-RUN + GATE
### 2026-06-09 · MODO PROTECÇÃO TOTAL · **ainda SEM escrita na DB**

> Estado: **EXECUTADO ✅** — Decisões: Q1 = `×0,8261` em TODOS os extras fast-food (Danilo manteve a regra); Açaí = preço exacto. Q2 = wipe + reinserir só os 2 copos da Glovo. Backups feitos, inserção/colapso/wipe concluídos, validação MCP OK. **Aguarda apenas go-ahead para commit/push + versionCode** (Validation Gate pré-commit).

---

## 1. Infra / método
- **Parser SSR corrigido:** o `unesc` da Fase 1 (regex) partia em descrições com `\\n` (duplo-escape) — os 4 "Copo" do Açaí e vários produtos BK/KFC não eram lidos. Substituído por `jsUnescape` single-pass. Resultado: **parseFails=0**, McD continua 107/333/1379, e agora apanha tudo (BK subiu de 168→186 produtos, KFC 174→181 — a Fase 1 tinha sub-contado).
- **Credenciais:** `backend/.env` → `SUPABASE_SERVICE_ROLE_KEY` + `SUPABASE_URL`. Padrão de insert = `.ai_4lojas_apply.js` (POST `/rest/v1` lotes 150, `Prefer: resolution=merge-duplicates`).
- **Slugs Glovo confirmadas:** `mcdonalds-grd`, `burger-king-grd`, `kfc-grd`, **`sabores-de-casa-acai-grd`** (✅ Açaí EXISTE em Guarda — stop rule #8 não dispara).

## 2. Contagens reais (dry-run, matched only)
| Loja | Glovo c/opção | Match Bora | Grupos a inserir | Items a inserir | Glovo sem match |
|---|---:|---:|---:|---:|---:|
| McDonald's | 92 | 88 | 322 | 1 330 | 4 |
| Burger King | 139 | 127 | 479 | 2 675 | 12 |
| KFC | 150 | 145 | 705 | 6 292 | 5 |
| **TOTAL fast-food** | **381** | **360** | **1 506** | **10 297** | **21** |

- **21 produtos Glovo com opções sem equivalente na Bora** (stop rule #6 → reporto, NÃO crio sem aprovação). Ex.: McD `Menu Salada Atum & Pasta`, `Snack Wrap Chicken Cheese/Mayo`; BK `2 Whopper + 2 batatas + Nuggets x5`, `Double Cowboy Menu`, vários combos família; KFC `Menu Duplo Coronel/Clássica`, `Bucket For One ...`. → Por defeito **ficam sem opções** (não existem na Bora). Posso criá-los numa fase futura se quiseres.

## 3. McDonald's — Colapso de tamanhos (Decisão B já aprovada)
- **27 produtos "(Grande)" a APAGAR**, todos com produto-base (médio, sem sufixo) existente → **0 órfãos** (nenhum se perde).
- O produto-base recebe o grupo Glovo **"Selecione o Tamanho"** (Médio +€0 · Grande +€1,57 = 1,90×0,8261). As diferenças de preço Bora Grande−Médio batem certo (≈€1,57). Backup `_backup_products_pre_fase2_2026_06_09` antes do DELETE.
- Exemplos: `McMenu® Big Mac® (Grande)` €8,10 → apaga, mantém `McMenu® Big Mac®` €6,53 (Tamanho Grande +€1,57); idem Big Tasty Double/Single, Big Arch, 2 Snack Wraps (diff €1,78), etc.

## 4. 💰 PREÇO DOS EXTRAS — descoberta crítica
A regra do prompt era `price_add = priceImpact_Glovo × 0,8261` para os 3. **Verifiquei o `pricing_service` + os preços-base reais:**
- `CartStore.addItem()` **NÃO aplica markup em runtime** — o preço guardado na DB já é o preço final ao cliente (base + extras somados).
- **Preço-base McD na Bora = mediana 0,826× Glovo** → a regra ×0,8261 **bate certo** para o McD. ✅
- **Preço-base BK e KFC na Bora = mediana 0,718× Glovo** (≠ 0,826!). Se aplicar ×0,8261 aos extras de BK/KFC, os extras ficam ~15% mais caros que os próprios produtos da loja (incoerente).
- → **DECISÃO necessária** (ver §6, Q1). Recomendo **×0,7182** para BK/KFC (igual à base da loja).

## 5. 🍨 Sabores Açaí — já está IGUAL à Glovo
- Glovo Guarda só tem **2 tamanhos** (Copo Mega: *Acompanhamentos OBRIG 5-5 de 10* + *Extras 0-10 @+€1*; Copo Pequeno: OBRIG 2-2).
- **A Bora já tem isto** — e melhor: **4 copos** (Peq=2 / Méd=3 / Grd=4 / Mega=5), mesma lista de 10 toppings (Leite Condensado, Amendoim, Leite em Pó, Granola, Mel, Creme de Avelã, Paçoca, Banana, Morango, Kiwi), extras a +€1.
- Apagar+reinserir do Glovo (como o prompt pedia) **REDUZIRIA a 2 tamanhos** e perderia Médio/Grande. Preços Glovo são mais altos (Mega €13,9 vs €12) mas Açaí é **parceiro** → preços são do dono, não derivados do Glovo.
- → **DECISÃO** (ver §6, Q2). Recomendo **manter como está**.

## 6. Decisões pendentes (gate)
- **Q1 — multiplicador extras BK/KFC:** ×0,7182 (igual base, recomendado) · ×0,8261 (regra original) · ×1,0 (cru Glovo).
- **Q2 — Açaí:** manter (recomendado) · refrescar toppings dos 4 copos · apagar+reinserir 2 do Glovo.

## 7. Plano de execução (após decisões)
1. Backups: `_backup_pog/_poi/_products_pre_fase2_2026_06_09` (CREATE TABLE AS).
2. Inserir grupos+items McD/BK/KFC (lotes 150, IDs legíveis `{rid}-{slug}-gN/-iN`, nomes limpos, `price_add` arredondado 2dp).
3. McD: DELETE 27 "(Grande)".
4. Açaí: conforme Q2.
5. Validação MCP (tabela contagens) + sample 5 produtos/loja.
6. Relatório final + Validation Gate pré-commit → commit + push + versionCode + /ctx.

---

## 8. EXECUÇÃO — CONCLUÍDA (2026-06-09)

**Backups** (antes de qualquer DELETE): `_backup_pog_pre_fase2_2026_06_09` (8), `_backup_poi_pre_fase2_2026_06_09` (80), `_backup_products_pre_fase2_2026_06_09` (498). ✅

**Script:** `.ai_opcoes_glovo_apply.js` (dry-run default, `--commit`, `--store=`). Parser SSR jsUnescape. `price_add` = `ROUND(priceImpact × mult, 2)` (fast-food mult=0,8261; Açaí mult=1,0).

**Inserções (0 falhas):**
| Loja | Grupos | Items | Notas |
|---|---:|---:|---|
| McDonald's | 330 | 1 337 | + 27 produtos "(Grande)" APAGADOS (colapso) |
| Burger King | 488 | 2 691 | |
| KFC | 705 | 6 292 | |
| Sabores Açaí | 4 | 40 | wipe 8/80 antigos → 2 copos Glovo (Pequeno 2-2 · Mega 5-5) |
| **TOTAL** | **1 527** | **10 360** | |

**Validação MCP (estado final):** McD 111 prod / 330 grp / 1337 it / 88 c-opções · BK 173/488/2691/127 · KFC 176/705/6292/145 · **Açaí 11 / 8 grp / 80 it / 4 c-opções** (Danilo estendeu Médio+Grande via MCP — ver §9).
**Sanity:** grupos_sem_nome=0 · min>max=0 · items_sem_nome=0 · **price_add<0 = 0** · items_órfãos=0 · McD "(Grande)" restantes=0. ✅

**Amostra validada (igualzinho à Glovo):**
- **McMenu® Big Mac®** → Tamanho (Médio · Grande +€1,57) · Bebida (9) · Acompanhamento (4) · Molho (Ketchup +€0,08 · FIFA +€0,95…) · Complemento (Cheeseburger +€2,48…) · Sem Big Mac · Extra Queijo +€0,91.
- **Menu Whopper®** → Carne · Acompanhamentos (9) · Bebidas (15, Coca +€0,08, Monster +€0,50) · Remover ingredientes · Adiciona extras (Bacon+Queijo +€1,65…).
- **Box Meal Coronel (KFC)** → Sanduíche · Ingredientes Extra · Acompanhamento · Complemento · Bebida · Molho · Sobremesa (26) · Ainda tem espaço · Talheres.
- **Copo Mega 500ml (Açaí)** → Escolha os Acompanhamentos (OBRIG 5 de 10) + Deseja Extras? (0-10 a +€1). ✅ exactamente como pedido.

## 9. Notas / pendências
- **21 produtos Glovo com opções sem equivalente Bora** → ficaram sem opções (stop rule #6, não criados). Lista no §2.
- **✅ Açaí Copo Médio/Grande — RESOLVIDO** pelo Danilo via MCP (2026-06-09): os 4 copos ficaram com estrutura (Pequeno=2 · Médio=3 · Grande=4 · Mega=5 acompanhamentos de 10 + extras 0-10 a +€1). Estado final Açaí = **4 produtos / 8 grupos / 80 items**. Backup `_backup_acai_4copos_2026_06_09_grupos` + `_items`.
- **Preço extras BK/KFC** a ×0,8261 (tua regra). FYI: a base de BK/KFC mede-se a 0,718×Glovo, logo os extras ficam proporcionalmente ~13% acima da base — documentado, mantido por tua instrução.
- **Reversão:** `INSERT INTO product_option_groups SELECT * FROM _backup_pog...` etc. + restaurar 27 produtos McD do backup, se necessário.

## 10. Pendente (FIM) — após go-ahead
Commit (`relatorios/` + `.ai_opcoes_glovo_apply.js` + bump versionCode `pubspec.yaml`) → `git push origin autonomous-night-2026-04-29` → `/ctx doctor` + `/ctx stats`.
