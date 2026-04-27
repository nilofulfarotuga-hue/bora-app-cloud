# Continente Price Updater — Fase 0 Dry-Run (50 produtos)

**Data:** 2026-04-21
**Fonte:** `products WHERE source='glovo-continente-guarda-2026-04-21' AND price IS NULL`
**Universo:** 2.844 produtos · **Amostra:** 50 aleatórios
**Método:** M3 — `continente.pt/.../Product-Show?pid=<PID>` (PID extraído de `id` `glv-<N>`)
**Rate:** 4,5 s ± 1,0 s jitter · **ZERO writes na BD**
**Resultado run:** 50/50 processados, sem stop, sem 429/403

---

## Resumo

| Estado | Qtd | % |
|---|---:|---:|
| ✅ Preço extraído OK | **45** | **90 %** |
| ⚠️ 404 (produto inexistente em continente.pt) | 4 | 8 % |
| ⚠️ Redirect para homepage (PID inválido / fora de stock) | 1 | 2 % |
| 🛑 Bloqueio (429 / 403) | 0 | 0 % |
| 🛑 Erro de rede | 0 | 0 % |

**Coverage estimado para 2.844 produtos:** ~2.560 com preço, ~284 sem preço (`needs_review=true`, `is_available=false`).

---

## Tabela completa (50 produtos)

| # | PID | Nome (Glovo) | Preço €  | Status |
|---:|---|---|---:|---|
| 1 | 8206496 | Detergente Máquina Roupa Líquido Frutos Exóticos Surf (84 doses) | **9.99** | ok |
| 2 | 5311121 | Ravioli Fresco de Bolonhesa Rana (emb. 250 gr) | **3.69** | ok |
| 3 | 7600952 | Carvão Vegetal Especial Continente (emb. 3 kg) | — | redirect → home |
| 4 | 8549514 | Iogurte Sólido +Proteína Baunilha Continente (emb. 200 gr) | **0.75** | ok |
| 5 | 7756663 | INNOCENT Smoothie Maçã, Kiwi e Lima 250 ml | **2.19** | ok |
| 6 | 6837237 | Gel de Banho Ice Chill Axe 400ML | **3.59** | ok |
| 7 | 3605242 | Whisky Grant's (garrafa 1 lt) | **18.65** | ok |
| 8 | 3051007 | Sumo Multi-Vitaminas Capri-Sun Pack 10x20CL | — | **404** |
| 9 | 7069752 | Frango Completo aos Pedaços Continente (1,3 kg) | **3.19** | ok |
| 10 | 8506612 | Proteína Whey Concentrada Baunilha Way Up (900 gr) | **26.99** | ok |
| 11 | 8502739 | Ambientador Recarga Difusor Air Wick Flor de Cerejeira | **5.99** | ok |
| 12 | 5940300 | REF C/GÁS LIMA LIMAO ZERO 7UP LATA 33CL | — | **404** |
| 13 | 8696645 | Tre Marie AncoraUno Frolla de Cacau (315 g) | — | **404** |
| 14 | 7003018 | Tablete Chocolate Negro Excellence Framboesa Lindt (100 gr) | **4.84** | ok |
| 15 | 8282803 | Peito de Perú Forno a Lenha Campofrio (200 gr) | **4.59** | ok |
| 16 | 8206497 | GilletteLabs Máquina De Barbear Edição Neon Night | **19.59** | ok |
| 17 | 7414788 | Creme de Legumes sem Batata Continente Equilíbrio (800 gr) | **2.89** | ok |
| 18 | 5060932 | Tortellini Fresco de Ricotta e Espinafres Rana (250 gr) | **2.99** | ok |
| 19 | 4970162 | Mostarda Top Down Heinz (240 gr) | **2.99** | ok |
| 20 | 5981228 | Iogurte Líquido Manga Continente (640 gr / 4 un) | **1.35** | ok |
| 21 | 2837405 | Ice Tea Pêssego Lipton (1 lt) | **2.44** | ok |
| 22 | 8385622 | Pasta Dentífrica Oral-B Advanced Branqueamento 75ml | **3.29** | ok |
| 23 | 7081813 | 7 kg Purina One Active Frango (cão) | **23.99** | ok |
| 24 | 8296722 | Tablete de Chocolate de Leite Milka, 90 gr | **2.49** | ok |
| 25 | 2214727 | Mimosa Leite Magro Uht 200 Ml | — | **404** |
| 26 | 6231759 | Cápsulas de Café Suave Int 8 Continente (10 un) | **2.09** | ok |
| 27 | 4211946 | Aftershave Bálsamo Men Sensitive Nivea (100 ml) | **5.91** | ok |
| 28 | 5406727 | Cerveja com Álcool Mini Super Bock (15 x 20 cl) | **7.29** | ok |
| 29 | 7186733 | Cápsulas Café Ristretto Robusto Int 13 Continente (16 un) | **3.85** | ok |
| 30 | 7059072 | Champô Seco Original Batiste (200 ml) | **3.21** | ok |
| 31 | 8013806 | Ambientador Stick Perfumado Baunilha Continente | **2.79** | ok |
| 32 | 2918065 | Pastilhas Elásticas Frutos Silvestres Trident (14,5 gr) | **0.99** | ok |
| 33 | 6085644 | Ambientador Recarga Difusor Lavanda Continente | **1.89** | ok |
| 34 | 3706104 | Preservativos Fínissimo Senso Control (12 un) | **7.75** | ok |
| 35 | 7457883 | Gel de Banho Kids Pera Corine de Farme (500 ml) | **5.49** | ok |
| 36 | 8752703 | Nivea Sun Stick Facial UV SPF50+ Toque Sedoso 15 g | **11.03** | ok |
| 37 | 3733734 | Mostarda Original Savora 190 G | **2.22** | ok |
| 38 | 8675983 | Champô Hidrata Coco Herbal Essences (650 ml) | **6.96** | ok |
| 39 | 8172746 | Lipton Chá Preto e Laranja 20 saquetas | **3.32** | ok |
| 40 | 8610219 | Sacos Lixo Elastic+ 30 lt Vileda (12 un) | **3.89** | ok |
| 41 | 8145317 | A LEITEIRA Creme Sublime Chocolate Caramelo Salgado 4×65 g | **2.09** | ok |
| 42 | 4621952 | Pasta de Dentes Max White One Colgate (75 ml) | **2.68** | ok |
| 43 | 8365941 | Sumo 100% Tropical e Kale Continente Equilíbrio (75 cl) | **1.99** | ok |
| 44 | 7410576 | Adoçante com Doseador Neodoce (1200 un) | **1.45** | ok |
| 45 | 6552955 | Pastilhas Elásticas de Morango Bubbaloo (38 gr) | **0.65** | ok |
| 46 | 2050182 | Espumante Raposeira Reserva DOC Távora-Varosa Branco (75 cl) | **9.99** | ok |
| 47 | 7758400 | Champô Anti-Caspa Linic Men Controlo Oleosidade 610ml | **6.74** | ok |
| 48 | 8448534 | SOFLAN Detergente Roupa Manual Delicado 22 doses 900 ml | **4.49** | ok |
| 49 | 6929963 | Sidra com Álcool Maçã Somersby (50 cl) | **1.29** | ok |
| 50 | 7889400 | Bebida Energética sem Açúcar Guapa (25 cl) | **0.49** | ok |

---

## Falhas (5 produtos)

| PID | Nome | Tipo | Acção sugerida |
|---|---|---|---|
| 7600952 | Carvão Vegetal Especial Continente (3 kg) | redirect homepage | sazonal? marcar `is_available=false`, retry no Verão |
| 3051007 | Capri-Sun Multi-Vitaminas Pack 10x20cl | 404 | descontinuado / re-PID — marcar `needs_review=true` |
| 5940300 | 7UP Zero Lima-Limão lata 33cl | 404 | mesmo |
| 8696645 | Tre Marie AncoraUno Frolla 315g | 404 | mesmo |
| 2214727 | Mimosa Leite Magro UHT 200ml | 404 | mesmo |

**Padrão dos 404:** parecem ser PIDs antigos/descontinuados que o Glovo mantém em catálogo mas o Continente já removeu. Não são erros do método.

---

## Tempos

- Tempo total run: ~3 min 30 s
- Fetch médio: 1,5 s (HTTP + parse)
- Sleep médio entre requests: 4,5 s ± jitter
- **Sem 429, sem 403, sem CAPTCHA** — o site aceita tranquilamente neste ritmo.

---

## Estimativa para Fase 1 (todos os 2.844)

| Métrica | Valor |
|---|---|
| Tempo de execução | **~3 h 30 min** (4,5 s × 2.844 + ~1,5 s fetch) |
| Coverage esperado | ~2.560 com preço (90%) |
| Falhas esperadas | ~284 (`needs_review=true`, `is_available=false`) |
| Risco de bloqueio | Baixo — confirmado a 4,5 s ± jitter |

---

## Próximos passos (a aguardar OK do Danilo)

1. ✅ **Aprovar amostra** — preços razoáveis, sem aberrações
2. 🔜 **Backup BD** — `CREATE TABLE products_backup_glovo_continente_guarda_20260421 AS SELECT ...`
3. 🔜 **Fase 1** — correr todos os 2.844 com mesmo rate, com checkpoint cada 200, gerar JSON `phase1_prices.json`
4. 🔜 **Fase 2** — gerar SQL UPDATE (ainda em dry-run, mostrar diff antes de aplicar)
5. 🔜 **Fase 3** — aplicar UPDATE com transacção, marcar 404s como `needs_review=true, is_available=false`

---

## Ficheiros gerados

- `.claude/.ai/scripts/phase0_dryrun50.py` — scraper
- `.claude/.ai/scripts/phase0_test_one.py` — validador 1 fetch
- `.claude/.ai/tmp/phase0_products_2026-04-21.json` — amostra de input (50)
- `.claude/.ai/tmp/phase0_prices_2026-04-21.json` — output bruto (50 resultados)
- `.claude/.ai/reports/continente-price-updater-phase0-dryrun50.md` — este relatório

**STOP.** Aguardar aprovação do Danilo para Fase 1.
