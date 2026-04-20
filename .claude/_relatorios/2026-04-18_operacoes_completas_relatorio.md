# RELATÓRIO — 3 OPERAÇÕES COMPLETAS

**Data:** 2026-04-18
**Modo:** Protecção Total (aprovação por tarefa)
**Executor:** Claude Opus 4.7 (1M context)
**Âmbito:** só markdown em `.claude/.ai/` e `.claude/_backups/`. Zero toques em código Flutter.

---

## Operação 1 — `business_rules.md` actualizado

- **§14.10 adicionado** (linha 548) — toggle `reservations_enabled`:
  - Reservas são OPCIONAIS (por defeito OFF)
  - Parceiro activa/desactiva no dashboard
  - Coluna DB: `restaurants.reservations_enabled` (boolean, default false)
  - Guard cliente: botão "Reservar mesa" só aparece se flag = true
- **Secção 27 adicionada** (linha 918) — actualização automática de produtos dos mercados:
  - §27.1 Calendário semanal pg_cron (Mercadona seg → Intermarché sáb, domingo = retry)
  - §27.2 Requisitos qualidade (5.000+ produtos, fotos REAIS, PT)
  - §27.3 Mercadona (API pública, 5.011 produtos ✅)
  - §27.4 Estratégia por mercado (SFCC / scraping)
  - §27.5 Regras anti-falha (log, retry domingo, 1 req/s)
  - §27.6 Estado actual (tabela — 5 mercados com fotos da Mercadona a corrigir)
- **§26.1 actualizado** — 10 features novas marcadas como feitas:
  - Avaliações com etiquetas (BR §13) ✅
  - Gorjetas/Tips widget + DB (BR §4.5) ✅
  - Fotos obrigatórias sendPackage/carryGroceries (BR §7.5/7.6) ✅
  - Takeaway em parceiros (BR §14.9) ✅
  - Reservas de mesa — fluxo base (BR §14) ✅
  - Driver Help — botão + DB + RPC (BR §5.2) ✅
  - Painel admin — reservas + avaliações (BR §16) ✅
  - GDPR — checkbox registo, apagar conta, banner cookies (BR §20) ✅
  - Cancelamento pelo cliente com taxas (BR §8.3) ✅
  - Bugs corrigidos: botão voltar Android, foto perfil, checkbox estafeta ✅
- **§26.2 actualizado** — 6 itens pendentes para lançamento:
  - Ecrã avaliação abrir automaticamente após entrega
  - Botão "Reservar mesa" com guard `reservations_enabled` (§14.10)
  - Takeaway bypass no dispatch
  - Gorjeta no checkout
  - Pré-pagamento €3 nas reservas (Stripe)
  - Toggle `reservations_enabled` no painel do parceiro
- **Footer** date bump 2026-04-17 → 2026-04-18

**Backup:** `.claude/_backups/2026-04-18_br_update/business_rules_v2.md` (30.252 bytes, original intacto)

**Verificação:** ✅ 27 secções (§1…§27) confirmadas via Grep

---

## Operação 2 — 14 skills criadas

Directório: `.claude/.ai/skills/`
Todas com `protection_mode: read-only`, frontmatter completo, ROLE, 2 EXEMPLOS WORKED, REFERÊNCIAS BORA APP, BENCHMARK UBER/IFOOD/GLOVO, RESPONSABILIDADES, FRONTEIRAS, NÃO PODE FAZER, RULES.

| # | Ficheiro | Linhas | BR principal |
|---|---|---|---|
| 1 | `cancellation-engineer.md` | 132 | §8.3 · §12 |
| 2 | `gdpr-compliance.md` | 151 | §20 |
| 3 | `partner-dashboard-engineer.md` | 147 | §14 · §14.10 · §15 |
| 4 | `admin-panel-engineer.md` | 148 | §16 · §9 · §4 |
| 5 | `testing-engineer.md` | 146 | §25.3 |
| 6 | `qa-engineer.md` | 177 | §1.3 · §7 · §8 · §14 · §26.2 |
| 7 | `notifications-engineer.md` | 151 | §22 · §14.6 · §7.1 |
| 8 | `partner-onboarding.md` | 152 | §15 |
| 9 | `products-updater.md` | 164 | §24 · §27 |
| 10 | `market-scraper.md` | 158 | §27.4 |
| 11 | `deployment-engineer.md` | 159 | §26 |
| 12 | `security-engineer.md` | 168 | §21 · §25.3 · §3.2 |
| 13 | `monitoring-engineer.md` | 167 | §9 · §22 · §25.1 |
| 14 | `ui-designer.md` | 192 | identidade visual |
| — | **Total** | **2.212** | — |

**Backup:** `.claude/_backups/2026-04-18_fase3_14skills/` (25 ficheiros originais)

**Notas:**
- Skills 9 e 10 (`products-updater`, `market-scraper`) são apenas `.md` descritivas — sem edge functions nem pg_cron criados nesta sessão (confirmado na aprovação OP2).
- Skill 3 (`partner-dashboard-engineer`) NÃO criou migration para `restaurants.reservations_enabled` — confirmado na aprovação OP1 (será criada em sessão dedicada).

---

## Operação 3 — `rules.md` actualizado

- Version: `2.1.0` → `2.2.0`
- Header: `FASE 2.B.2 COMPLETA — 36 SKILLS` → `FASE 3 COMPLETA — 50 SKILLS`
- **Camada 4** (Validação Pós + QA): 3 → 5 (+testing-engineer, +qa-engineer)
- **Camada 5** (Domínio): 8 → 15 (+cancellation, gdpr, partner-dashboard, admin-panel, partner-onboarding, notifications, ui-designer)
- **Camada 6** (Backend + Extras): 8 → 10 (+products-updater, +market-scraper)
- **Camada 7** (Release + Ops): **nova camada** — 3 skills (deployment, security, monitoring)
- Cada skill nova marcada `⭐ NOVO (Fase 3)` com referência BR

---

## Verificação global

- [x] BR tem 27 secções
- [x] §14.10 presente (`reservations_enabled`)
- [x] §26.1 com 10 features novas marcadas ✅
- [x] §26.2 com 6 itens pendentes
- [x] §27 presente com tabela de estado
- [x] 14 skills criadas com formato correcto (frontmatter + 9 secções obrigatórias)
- [x] `rules.md` com 50 skills, 7 camadas, versão 2.2.0
- [x] Código Flutter NÃO tocado (`lib/` zero modificações)
- [x] `dispatch-engine`, `pricing_service.dart`, Stripe, triggers `bora_tokens` NÃO tocados
- [x] Sem migrations, edge functions, pg_cron criados nesta sessão
- [x] Backups íntegros (BR 30.252 bytes + pasta skills com 25 originais)

---

## Entregas vs. âmbito pedido

| Pedido | Estado |
|---|---|
| OP1: BR §14.10 + §27 + §26 checklist | ✅ |
| OP2: 14 skills com formato uniforme | ✅ |
| OP3: rules.md passa a 50 skills + versão bump | ✅ |
| Backups antes de cada OP | ✅ (2 pastas) |
| Zonas protegidas intactas | ✅ |
| Relatório final | ✅ (este ficheiro) |

---

## Próximos passos sugeridos (fora do âmbito desta sessão)

1. **Sessão dedicada**: criar migration `ALTER TABLE restaurants ADD COLUMN reservations_enabled BOOLEAN NOT NULL DEFAULT false` + UI toggle no dashboard parceiro (pertence a `partner-dashboard-engineer`)
2. **Sessão dedicada**: implementar scrapers reais para Continente/Pingo Doce/Lidl/Auchan/Intermarché (pertence a `market-scraper` + revisão legal ToS)
3. **Fase 4 (não aprovada)**: criar as 3 skills de Release + Ops como workflows de CI/CD concretos (hoje estão descritas mas sem automação)
4. Ligar os 6 itens de BR §26.2 (escopo do próximo lançamento)
