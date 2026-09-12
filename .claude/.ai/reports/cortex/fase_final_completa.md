# CÓRTEX BORA — Relatório Final (Blocos 0–6, autónomo)

> Sessão Claude Code (Opus 4.8) · 2026-07-08 · Branch `autonomous-night-2026-04-29`.
> **Zona verde, aditivo e reversível. Zero tocou dinheiro/Stripe/pricing/tokens/RLS → zero paragens 🔴.**
> Nada apagado (só **movido** para `_arquivo`/`_descartado`/`inbox`). Fecho de 1A + Blocos 1–6.

## ✅ BLOCO 0 — pendências da 1A fechadas
| Item | Estado | Detalhe |
|---|---|---|
| 0.1 Repontar Obsidian | ⚠️ **manual (1 clique)** | Não há `obsidian.json` (Roaming/Local) nem tool de automação **desktop** → deixei breadcrumb `C:\Users\danil\Desktop\_LEIA_vault_Bora_mudou.txt` com os passos exatos. É o único item que depende de ti. |
| 0.2 Arquivar velho | ✅ | `Desktop\Bora` (188 ficheiros) → `Desktop\_Bora_arquivo_2026-07-08` (188 ✅). **Movido, não apagado.** |
| 0.3 Duplicados de acento | ✅ | VPS: `obsidian-bora/sessoes` (5 stale) → `_vault_velho_arquivo/…_stale_20260708`. Repo: `knowledge/{sessions}` (9 tracked) → `inbox/`; `sessao/` fica como o único dir efémero. |
| 0.4 Hash drift | ✅ | `fase1a_consolidacao.md`: `0c623cc→0b44734`, `0f7e0e0→ffe08c5`. |
| 0.5 git push | ✅ | Feito no fim (ver §Commits). A branch já seguia origin; empurrei os novos commits. |

## ✅ BLOCO 1 — frontmatter de identidade (via `bibliotecario-cerebro`)
- **22/22 páginas** de `permanente/**` carimbadas (merge — preservou `tema/escopo/estado/atualizado`).
- **10 `zona: vermelha`** · **0 `NAO_VERIFICADO`** (cada `origem` veio de fonte real citada no corpo).
- Âmbito honesto: só `permanente/**`. O **vault** (117) e `_importado-velho/` (33) são **arquivo** — ficam como histórico (não pagam identidade de página viva). Reversível batch a batch.

## ✅ BLOCO 2 — camada inbox
`inbox/` + `inbox/_descartado/` + **regra dos 14 dias** (não promovido → movido, recuperável 30 dias, nunca apagado). Semeado com **9 registos** re-alojados. Promotor/descartador = `cortex_nightly` (não o humano).

## ✅ BLOCO 3 — confiança derivada + knowledge debt
`confianca` é **derivada** (100% na `ultima_confirmacao`, −1%/semana; `NAO_VERIFICADO`=40%; `validade_dias` expirado=0%) — nunca chutada pela IA (documentado em `schema.md` §9). `_debt.md` auto-gerado. **1ª corrida: 0 páginas em dívida** (tudo carimbado fresco).

## ✅ BLOCO 4 — decisões (ADR) + lições
- `wiki/decisoes/` (**2 ADR**): evoluir `knowledge/` como Córtex; manutenção do cérebro repo-side.
- `wiki/licoes/` (**5 lições** reais da saga): `docker exec -u`, verificar-fonte-de-sync, verificar-estado-antes-de-reexecutar, onde-vive-a-trava, confirmar-ferramenta-antes-de-prometer. Regra anti-lixo aplicada (só regras generalizáveis).

## ✅ BLOCO 5 — consolidação noturna (`_tools/cortex_nightly.py`)
**Validado (dry-run correu):** 0 dívida · 9 propostas de inbox aging · 10 zona:vermelha listadas (só proposta) · contradiction scan em modo parcial (degrada com graça). Relatório: `inbox/_reports/nightly-2026-07-08.md`.
- **DRY-RUN por defeito** (só propõe; `--apply` para agir). **Nunca** toca 🔴.
- **Decisão arquitetural (ver ADR):** corre **repo-side** (é onde o cérebro vive), **não** no `daily_pulse.py` do VPS — o VPS não tem o `knowledge/` sincronizado. O VPS continua dono do pulso de negócio.
- 🟡 **Dependência aberta:** a *contradiction engine* precisa dos **sinais de negócio** do VPS (`inbox/_signals.json`). Sem eles corre parcial. Ponte fica **staged** (ver §Bugs).

## 🖥️ BLOCO 6 — Central do Córtex (spec PR-ready, NÃO construído)
`reports/cortex/central_cortex_admin_spec.md`. Implementar toca **app Flutter de produção** → por regra **propõe-se** (não é 🔴 de dinheiro; não precisa "vai", precisa do teu build). Reusa `AdminRobotSuggestionsScreen` como cabeçalho (não 2º inbox). Ponte de dados: tabela `cortex_status`/`cortex_queue` (verde) publicada pelo `cortex_nightly`. Convocar `admin` + `backend-supabase` para construir.

## 🔴 FILA DE APROVAÇÃO (zona vermelha à espera do teu OK)
Estas **10 páginas** descrevem zonas protegidas → marcadas `zona: vermelha` = **PROPOSE-ONLY** (futuras edições a elas exigem o teu OK; o **conteúdo atual não muda** nada de dinheiro — é só a etiqueta de governança):
`decisoes.md`, `backend-map.md`, `backend-map-tabelas.md`, `backend-map-rpcs.md`, `backend-map-edge-functions.md`, `backend-map-triggers-rls.md`, `business-rules.md`, `pricing.md`, `zonas-protegidas.md`, `vertical-limpeza.md`.
> Nada aqui é uma alteração de dinheiro pendente — é o rótulo que faz a Trava proteger estas páginas daqui para a frente. As *revisões* da contradiction engine cairão nesta mesma fila quando a ponte de sinais existir.

## ⚠️ BUGS / RISCOS / REFINAMENTOS
1. 🟡 **Repoint Obsidian é manual** — sem `obsidian.json` nem automação desktop. Breadcrumb deixado; 1 clique teu (Open folder as vault → `.obsidian-vault`).
2. 🟡 **`cortex_nightly` aging usa mtime do ficheiro** → os 9 registos re-alojados hoje aparecem "71/28/15 dias" e seriam DESCARTADOS num `--apply`. **Seguro agora** (dry-run nunca age). Refinar antes de ligar `--apply`: contar idade desde a **entrada no inbox**, não desde o mtime original.
3. 🟡 **Contradiction engine parcial** — falta a ponte de sinais VPS→repo (`_signals.json`). Staged.
4. 🟢 **`auditoria-360.md`** tinha uma modificação **pré-existente** (anterior à sessão) que ficou agrupada no commit do Bloco 1 (o Bibliotecário carimbou o mesmo ficheiro). Sem perda; só nota de proveniência.
5. 🟢 **`INDEX.md` (~linha 78)** ainda aponta o vault velho `Desktop\Bora` (agora arquivado) — modificação pré-existente por rever; handoff ao `bibliotecario-cerebro` (não editei — respeitei o dono). 
6. 🟢 **Avisos LF→CRLF** do git no Windows — cosméticos.

## 📦 Commits desta sessão (`[skip ci]`)
- `40e8f36` — Bloco 0: re-home sessions→inbox + fix hash drift.
- `56bb475` — Blocos 2–6: inbox/debt/decisoes/licoes/tools/log/schema + admin-spec.
- `db438e5` — Bloco 1: frontmatter identidade em `permanente/**` (22 pág, 10 🔴).
- `<este>` — relatório final + 1ª corrida `cortex_nightly`.
*(push → `origin/autonomous-night-2026-04-29`.)*
