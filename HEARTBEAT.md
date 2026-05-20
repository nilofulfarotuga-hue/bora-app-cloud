# HEARTBEAT

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
