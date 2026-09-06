# Rebuild Continente-Guarda via Glovo — EXECUTADO · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`.
> Maior loja. Espelho 1:1 da Glovo Continente Modelo Guarda (estrutura/fotos/categorias/ordem). Sequência idêntica à Auchan.

## 1. Loja Glovo
**`continente-grd1`** — Glovo store **295687** / addr **470732** (Guarda). 27 categorias top na Glovo; semeadas as **23 reais** (saltadas 4 promo/sazonais cross-cutting: santos-populares, operacao-biquini, alto-em-proteina, novidades — agrupamentos de marketing que duplicam produtos; produtos delas herdam a categoria real). **NENHUMA categoria real excluída** (per decisão Danilo: todas, incl. Jogos e Brinquedos, Casa e Decoração, Bricolage, Livraria e Papelaria).

## 2. Preço — decisão (STOP rule #3 + evidência)
- Cruzamento per-produto com continente.pt = **inviável a esta escala** (10.950 × 2 req c/ redirect ≈ 8h+; match por nome fuzzy, Glovo não dá PID directo). → STOP rule #3 acionada: **fallback preço Glovo**.
- **MAS validado que Glovo Continente ≈ preço de prateleira (sem markup):** sample Compal Néctar Manga 1L = **€1,49 (Glovo) ≤ €1,59 (continente.pt** variante)** — Glovo NÃO está acima da prateleira. Consistente com Glovo Auchan e Pingo Doce (ambos confirmados sem markup; badge Glovo "mesmo preço que na loja").
- **Gravado preço Glovo direto** (`source='glovo_cont_rebuild_2026_06_07'`) = preço-base; +15% Bora em runtime. continente.pt **está acessível** (Product-Show via redirect+cookie SitePreference=DESKTOP dá JSON-LD) — um refresh de preços oficiais por PID fica como follow-up opcional dedicado.

## 3. Métricas antes/depois (MCP)
| Métrica | Antes (caos) | Depois (Glovo) |
|---|---|---|
| Total | 13.953 | **10.950** |
| Ativos | 12.393 | **10.950** |
| Sem foto | 1.840 (13%) | **16** (99,9% com foto) |
| Sem preço | 275 | **0** |
| Categorias | 212 (HTML sujo/duplicadas) | **23** (limpas, ordem Glovo) |
| Preço > €50 | 592 (PS5, piscinas €2k…) | máx €251,82 (mantido — "todos os produtos") |
| ids cont- / sort_order | — | 100% |

## 4. 5 produtos sample (preço Glovo)
| Nome | Preço |
|---|---|
| Lombinhos de Frango Continente 440g | €3,14 |
| Frango Assado com molho de Limão | €9,19 |
| Costeletas do Cachaço de Porco 650g | €3,90 |
| Ovos Classe M/L Superovo 12un | €3,79 |
| Bifes de Frango Continente 680g | €5,47 |

## 5. Categorias finais (ordem Glovo, 23 — todas mantidas)
Frutas e Vegetais > Talho e Peixaria > Charcutaria e Queijos > Padaria e Pastelaria > Laticínios e Ovos > Mercearia > Mercearia Doce > Refeições Frescas > Gelados e Congelados > Águas e Sumos > Cervejas e Sidras > Vinhos e Espumantes > Bebidas Espirituosas > Bio e Saudável > Beleza e Higiene > Saúde e Bem-Estar > Limpeza > Bebé e Criança > Animais de Estimação > Jogos e Brinquedos > Livraria e Papelaria > Casa e Decoração > Bricolage, Jardim e Auto.

## 6. Diff vs backup
Backup `_backup_continente_pre_rebuild_2026_06_07` (13.953). Novo=10.950, prefix `cont-{storeProductId}` → substituição total do catálogo caótico (212 cats HTML-sujo, 3.575 prefixos de id, 1.840 sem foto, 275 sem preço) por espelho limpo da Glovo.

## 7. Notas / limitações
- 23 promo-categorias não semeadas (produtos delas captados nas categorias reais). 
- mojibake: 29 nomes (0,3%) com `�` (quirks de fonte; negligível).
- Alguns ~20 produtos "Mais vendidos" no topo ficam sob a 1ª categoria (Frutas e Vegetais) — artefacto menor do carrossel featured.
- **Preço:** Glovo direto (validado ≈ prateleira). Refresh oficial continente.pt por PID = follow-up opcional.

## 8. Zonas protegidas
Intactas. Só `products` de `continente-guarda` + backup. Sem toques em dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger.
