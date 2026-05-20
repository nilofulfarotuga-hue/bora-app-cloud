# HEARTBEAT

## 2026-05-20 14:00 UTC — SATURAÇÃO 4 PASSADAS (1173 produtos)

- Wells 476 · Worten 254 · Leroy 217 · Kiwoko 145 · Zippy 81
- Returns 4ª passada: Worten 0, Leroy +29, Kiwoko 0, Zippy 0 → saturação
- "Promoções" excluído conforme decisão Danilo (duplicados sale-priced de outras cats)
- Walker amplificado + scroll deep 4× dentro de cada sub-cat foi a chave

## 2026-05-20 12:30 UTC — 5 LOJAS OPERACIONAIS (889 produtos)

- ✅ Wells 476 · Worten 168 · Leroy 105 · Kiwoko 88 · Zippy 52
- Solução: cdp_click_subcats.js — click cada sub-cat React button → wait → intercept
  (root cause anterior: produtos só carregam quando se clica numa sub-cat, não no landing)
- StoreIds: Worten=124378 · Leroy=539720 · Kiwoko=529912 · Zippy=123602
- Schema confirmed: produtos têm { name, priceInfo.amount, imageUrl }
- Cobertura ainda parcial vs metas brief (Worten 168/500, Leroy 105/400, etc) — segunda passada
  pode apanhar mais via "Mostrar tudo" navigation

## 2026-05-20 11:00 UTC — Desbloqueio CDP parcial

- ✅ CDP funcionou (Chrome real session + Glovo address pré-confirmado)
- ✅ Worten: 3 produtos · Kiwoko: 36 produtos · primeira leva inserida
- ⚠ Leroy / Zippy: 200+ API calls feitas mas intercept walker retorna 0 produtos
  (JSON schema diferente — Worten/Leroy/Zippy não usam `{name, price}` em sub-objects)
- Total non-grocery actual: **Wells 476 + Worten 3 + Kiwoko 36 = 515 produtos**
- Próximo: debug walker (dump responses JSON crú) para Worten/Leroy/Zippy
- URLs canónicas Glovo: `https://glovoapp.com/pt/pt/guarda/stores/<slug>` (com `/stores/`)

## 2026-05-20 08:00 UTC — Worten/Leroy/Kiwoko/Zippy BLOQUEADAS

- 4 lojas Glovo Guarda confirmadas (slugs reais: worten-vivaci-guarda-grd, leroy-merlin-grd, kiwoko-grd, zippy-grd)
- Tentativas: glovo_multi_import.js (sub-cat clicks) + glovo_deep_scroll.js (60× scrolls + intercept) → 0 produtos cada
- Root cause: address gating + Glovo-Perseus-Session-Id missing + sub-cats sem URL pattern + React state-only navigation
- Wells continua 476 produtos ✅
- Status detalhado: `WORTEN_LEROY_KIWOKO_ZIPPY_STATUS.md`
- **Próxima sessão precisa de Opção A (address persistence)** OU Opção B (sites oficiais) OU Opção C (manual seed)

## 2026-05-19 22:00 UTC — Wells fechada

- **Loja actual:** Wells ✅ → Worten 🟡 (próxima)
- **Fase Wells:** H (commit + push) em curso
- **Progresso:** 1/5 lojas concluídas (Wells)
- **Stats Wells:** 292 produtos · 100% fotos · 78.4% preços · 0 duplicados · 0 falhas
- **Tempo scrape Wells:** 17.6 min (300 URLs, ~3.5s/produto, JSON-LD)
- **DEFERIDO Wells:** pg_cron Edge Function · validação visual vs Glovo (503) · smoke test Flutter manual
- **Próximo:** commit + push, depois Worten Fase A

## 2026-05-19 — Início sessão autónoma

- **Loja actual:** Wells (a iniciar)
- **Fase:** Setup global (docs + restaurants rows + tile UI)
- **Progresso:** 0/5 lojas concluídas
- **Branch:** `autonomous-night-2026-04-29`
- **Próximo:** Editar business_rules §27, SKILL.md §3, inserir restaurants rows, adicionar tile Lojas, investigar Wells (Glovo + Uber + wells.pt + robots.txt)
- **Bloqueios:** 0
- **Notas:**
  - Validation Gate (CLAUDE.md) accionado e aprovado (resposta AskUserQuestion)
  - CEO-AI orchestrator carregado
  - 41101 produtos já no DB (14 restaurants existentes)
  - Skills relevantes existentes: market-data-sync, taxonomy-mapper, category-mapper-v2, market-data-cleaner — não usadas (brief manda Playwright bespoke)

---

<!-- Append novas entradas no topo. Update a cada 60min ou mudança de fase. -->
