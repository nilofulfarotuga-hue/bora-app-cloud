# CÓRTEX BORA — FASE 0: Auditoria + Blueprint (100% READ-ONLY)

> Gerado por: Claude Code (Opus 4.8) · Orquestração: CEO-AI · Data: **2026-07-08**
> Modo: **PROTECÇÃO TOTAL** · **Nada foi migrado, escrito no cérebro ou alterado.**
> Único ficheiro criado nesta fase: **este relatório.**
> VPS tocado apenas com `ls` / `cat` / `docker exec ... bash -lc 'ls|head|grep'` + 1 `SELECT` Supabase.

---

## 0. TL;DR (5 vereditos que importam)

1. **"O Obsidian sumiu"? → NÃO SUMIU.** Mudou de sítio. O vault canónico está no repo
   (`bora_app/.obsidian-vault/`, **117 .md, 643 KB**). O antigo `C:\Users\danil\Desktop\Bora`
   **ainda existe** (89 .md) e é o que a app Obsidian provavelmente abre → dá a sensação de "sumiu".
2. **O Córtex lado-código JÁ EXISTE em 80%.** `.claude/.ai/knowledge/` já é um cérebro Karpathy
   (INDEX + PROTOCOLO + `permanente/{semantica,episodica,procedural}` + `sessao` + `_arquivo`, **46 .md**).
   A Fase 1 deve **evoluir isto**, não construir um `.cortex/` paralelo do zero (decisão do Danilo — §Ambiguidades).
3. **Sócio-AI Fase A está VIVO e a funcionar.** NORTE preenchido (0 `AJUSTA`), SOUL com anéis A/B/C/D,
   `daily_pulse.py` correu hoje (07:00) e escreveu KPIs reais. A **anon key foi persistida hoje**
   (`.env.bak_preSocioCred_20260708`) — a memória "aguarda vai / não persistida" está **desatualizada**.
4. **As 4 views KPI: ✅✅✅✅.** `socio_kpi_daily/cancelamentos/tvde/saude` existem e foram lidas com
   sucesso pela credencial actual do Hermes (o pulso de hoje mostra dados reais das 4).
5. **A Trava (protege-banco) está ATIVA e passa selftest 12/12.** Bloqueia (exit 2) as 7 operações
   destrutivas e deixa passar (exit 0) as 5 seguras. Pré-requisito de segurança **cumprido**.

---

## 📋 A) LADO CÓDIGO (repo local)

### A1 — Vault Obsidian · VEREDITO: **não sumiu, migrou para o repo**
| Local | Existe? | Nº .md | Notas |
|---|---|---|---|
| `bora_app/.obsidian-vault/` (**canónico**) | ✅ | **117** (643 KB) | subpastas: arquitetura, backups, bugs, entregas, equipe, ideias, negocios, rules-history, `sessoes`, **`sessões`** |
| `C:\Users\danil\Desktop\Bora` (**deprecated**) | ✅ ainda em disco | 89 (188 ficheiros) | `00_BORA_DNA.md`, audits, benchmarks, `auditoria-2026-05-31`… |

- O `.gitignore` confirma a migração: *"Vault canónico vive em bora_app/.obsidian-vault/ (commit 2026-05-04)"* —
  só ignora config/cache (`.obsidian/workspace*`, `.smart-env`), os `.md` **estão versionados**.
- **Divergência real:** repo tem 117 .md, o antigo tem 89 → o repo é superset mais recente, mas o antigo
  **não foi apagado** e (pior) **é o que a sync do VPS puxa** (ver B4). Órfãos prováveis: a comparação
  não é 1:1; alguns `.md` antigos podem não ter par no repo (auditar na Fase 1 antes de apagar o antigo).
- 🐞 **Bug de acentos:** existem **duas** pastas `sessoes` **e** `sessões` dentro do vault → notas partidas em dois sítios.

### A2 — Fontes brutas candidatas a `raw/`
| Fonte | Local | Tamanho / nº | mtime |
|---|---|---|---|
| `business_rules.md` | `.claude/.ai/business_rules.md` | **190 KB · 57 cabeçalhos** (não "27 secções") | 2026-07-06 |
| Relatórios de sessão | `.claude/.ai/reports/**` | **170 .md** | 2026-04-18 → 2026-07-08 |
| `NORTE.md` (repo) | `docs/estrategia/NORTE.md` | estrutura c/ `<<DANILO PREENCHE>>` | — |
| Vault Obsidian | `.obsidian-vault/` | 117 .md | — |
| `SOUL.md` | **só no VPS** (não no repo) | — | — |

- `business_rules.md` tem **numeração colidida** (dois `## 18.`: LIMPEZA e RESERVAS; secções `§28…§38`
  em paralelo com `## 27`). É o maior RAW e precisa de ser **chunked** para caber no invariante ~24 KB.

### A3 — Schema existente (Camada 3 = "como trabalhar")
- `.claude/skills/ceo-ai/` — **3 ficheiros:** `SKILL.md` + `references/PROJECT_CONTEXT.md` + `references/FONTES_DADOS_MERCADOS.md`.
- **`CLAUDE.md`** — **1 só**, na raiz (22.5 KB). **Não existe `AGENTS.md`.**
- **Cérebro já estruturado:** `.claude/.ai/knowledge/` — **46 .md**, `INDEX.md` (4.8 KB) + `PROTOCOLO.md` (2 KB).
  Subpastas: `benchmarks, business-rules, permanente/{episodica,procedural,procedural/licoes,semantica}, security, sessao, sessions, _arquivo`.
  🐞 duplicado de acentos/idioma: **`sessao` e `sessions`** (duas pastas para a mesma ideia).

### A4 — Git / `.cortex` / `.gitignore`
- Branch: **`autonomous-night-2026-04-29`** ✅ · working tree: **sujo (13 entradas)** — nada de Córtex, é trabalho em curso.
- **`.cortex/` NÃO existe** ✅ (como esperado).
- `.gitignore` **tem** regras Obsidian (ignora só workspace/cache/`.smart-env`) e `knowledge/sessao/*` (efémero) — correto.

---

## 📋 B) LADO NEGÓCIO (VPS Hermes — container `hermes-agent-fvnc-hermes-agent-1`)

> `/opt/data` **não existe no host** — vive **dentro do container** (volume). Imagem `ghcr.io/hostinger/hvps-hermes-agent`, Up 2 dias.

### B1 — Sócio-AI Fase A · VEREDITO: **presente e a correr**
| Artefacto | Estado |
|---|---|
| `/opt/data/NORTE.md` | ✅ 2214 B, `AJUSTA`=**0** (totalmente preenchido), rev. 2026-07-08 |
| `/opt/data/daily-pulse/` | ✅ `2026-07-08.md` + `_pulse-log.jsonl` |
| `daily_pulse.py` | ✅ `/opt/data/hermes/socio-ai/daily_pulse.py` (py3.13) |
| `/opt/data/SOUL.md` | ✅ 31 KB — **anéis A/B/C/D registados** (linhas 280-286) |
| **Cron** | ✅ `hermes-daily-pulse.sh` **07:00 Europe/Lisbon** (memória dizia "sob demanda sem cron" → **stale**) |

- Anéis no SOUL: **A** autónomo (bug/refactor/dados/paridade) · **B** autónomo c/ aviso (copy, ordem, push<50, tokens-UI, e-mail/WhatsApp) ·
  **C** proponho (features, campanhas massa, mudança de fluxo) · **D** 🔴 Lista Vermelha (dinheiro/RLS/auth/migrations destrutivas/build prod = PROPOSE-ONLY).

### B2 — 4 Views KPI · **✅ TODAS LIDAS COM SUCESSO**
| View | Existe (SQL) | Lida pelo Hermes (pulso 2026-07-08) |
|---|---|---|
| `socio_kpi_daily` | ✅ | ✅ (tabela de pedidos/GMV renderizada) |
| `socio_kpi_cancelamentos` | ✅ | ✅ (motivos: dispatch_safety_timeout ×4…) |
| `socio_kpi_tvde` | ✅ | ✅ (corridas por dia) |
| `socio_kpi_saude` | ✅ | ✅ (78 crashes/7d) |

- Credencial: `.env` tem `SUPABASE_ANON_KEY` **não-vazia** (=1) + `SUPABASE_URL=https://ojykpzwqrtusfeakzrna`. **Persistida hoje.**
- Também existem (usadas pela skill `daily-pulse`, doc drift): `v_kpis_diarios`, `v_funil_checkout`, `v_drivers_online_agora`.
- ⚠️ Os erros em `errors.log` (`Permission denied: /opt/data/cron/jobs.json`) são de **outro** subsistema (cron interno do Hermes),
  **não** das views KPI. Fora do escopo do Córtex, mas registado (regra "reportar tudo").

### B3 — Trava (protege-banco) · VEREDITO: **SIM, dispara — selftest 12/12**
- **Correção de escopo:** não há `engine` no VPS nem `protege-banco.sh` lá. A Trava é um **hook PreToolUse no repo (PC)**:
  - `settings.json` liga **`.claude/hooks/protege-dinheiro.sh`** (matcher `Edit|Write|MultiEdit`) e
    **`.claude/hooks/protege-banco.sh`** (matcher `Bash|mcp__*Supabase*|execute_sql|apply_migration|deploy_edge_function`).
- `bash .claude/scripts/selftest_protege_banco.sh` → **pass=12 fail=0**:
  bloqueia (exit 2) git reset hard, git push force, `supabase db reset`, deploy edge protegida, DROP tabela fin, DDL money fn, DISABLE RLS fin;
  passa (exit 0) deploy edge não-protegida, SELECT, git push normal, commit c/ palavra "drop", migration normal.
- ⚠️ Pendência: existe `.claude/scripts/protege-banco.FIXED.sh` (fix p/ caso "python ausente" na deteção de deploy) **não aplicado**
  + `settings.json.bak_preApply_20260708` — reconciliar (o hook LIVE funciona; o FIXED é um upgrade proposto).

### B4 — Sync repo↔VPS · o que existe hoje
- **Ponte = Tailscale** (`/root/bora-bridge-up.sh`, estado em volume `/opt/data/tailscale`). Container alcança o PC como `bora-pc`.
  Instala comandos-ponte (`pc, readpage, websearch, vault, browse, vps_render, claude-shim`).
- **Sync de notas = one-way PC→VPS** (`/root/obsidian-sync.sh`, cron **04:30**): `tar` do vault do PC → container `/opt/data/obsidian-bora`.
  🐞 **BUG IMPORTANTE:** puxa `C:/Users/danil/Desktop/**Bora**` (o vault **DEPRECATED**, 89 .md), **não** o canónico
  `.obsidian-vault/` (117 .md). O Hermes está a ler notas velhas.
- **Não existe** qualquer sync de código repo↔VPS. `/opt/data/cortex/` **ainda não existe** no container.

---

## 🗺️ C) BLUEPRINT DO CÓRTEX (proposta — NÃO executar na Fase 0)

> **Princípio-mestre:** *reaproveitar, não duplicar.* O lado-código do Córtex **é** o
> `.claude/.ai/knowledge/` que já existe. Recomendação forte: **adotar/renomear/evoluir** essa árvore
> (ou tratar `.cortex/` como o seu novo nome) em vez de criar um terceiro cérebro paralelo. (Decisão em §Ambiguidades Q1.)

### C1 — Estrutura de pastas (dois lados)
```
# LADO CÓDIGO (repo, git) — evolução do actual .claude/.ai/knowledge/  → .cortex/
.cortex/
  index.md                 # entry point (herda o INDEX.md actual)
  log.md                   # NOVO: quem/quando/de-que-lado escreveu (proveniência)
  schema.md                # NOVO: as regras de trabalho = destilado de CLAUDE.md + ceo-ai/SKILL.md + PROTOCOLO.md
  raw/                     # NOVO: fontes brutas versionadas (chunk do business_rules.md 190KB, reports índice)
  wiki/
    codigo/                # ← dono: Claude Code (backend-map, zonas-protegidas, dispatch, pricing…)
    negocio/               # ← espelho do lado VPS (pulso, funil, KPIs, cancelamentos)
    conceitos/             # ← atemporal (DNA, glossário, benchmarks)
  _arquivo/                # histórico bruto + mapas de migração (nunca apagar) — já existe

# LADO NEGÓCIO (VPS, volume do container) — NOVO
/opt/data/cortex/
  index.md   log.md   schema.md   (espelhos sincronizados)
  wiki/negocio/          # ← dono: Hermes (daily-pulse consolidado, sinais, autolog)
  wiki/codigo/           # ← RÉPLICA read-only vinda do repo (Hermes lê, não escreve)
```
`index.md` e `log.md` são **lógicos partilhados** (mesmo conteúdo, sincronizado); `raw/` fica só no lado-código.

### C2 — Governança por zona (dono de escrita × anel)
| Tipo de página | Dono de escrita | Anel | Porquê |
|---|---|---|---|
| `wiki/codigo/zonas-protegidas`, `dispatch`, `pricing`, `finalizePurchase`, `bora_tokens`, `stripe-webhook`, RLS orders/wallets/ledger | Claude Code **propõe** | **D 🔴** | descreve dinheiro/segurança → aprovação Danilo (a Trava bloqueia) |
| `wiki/codigo/backend-map`, migrations não-financeiras, arquitetura | Claude Code | **A** (não-$) / **D** se tocar $ | factos de código verificáveis |
| `wiki/negocio/*` (pulso, KPIs, funil, cancelamentos, saúde) | Hermes | **A** | só leitura de views → reporta |
| `wiki/negocio/` sinais que sugiram mudança de fluxo/campanha | Hermes **propõe** | **C** | 1 toque do Danilo |
| `wiki/conceitos/*` (DNA, glossário, FAQ, traduções, benchmarks) | qualquer | **A** | atemporal, sem risco |
| `raw/*` (fontes brutas imutáveis) | append-only | **A** | nunca reescrever, só anexar |
| `schema.md` (regras de trabalho) | Claude Code **propõe** | **C/D** | muda o comportamento do agente |

Regra herdada do SOUL: **qualquer página que descreva zona 🔴 = Anel D (PROPOSE-ONLY)**, exatamente como a Lista Vermelha do CEO-AI.

### C3 — Plano de migração faseado (ordem da Fase 1, "aos poucos")
1. **Batch 0 (esqueleto):** criar `.cortex/` (ou renomear `knowledge/`) + `index.md` + `log.md` + `schema.md` (1 página cada). Ligar nada.
2. **Batch 1 (piloto, 1 de cada tipo):** 1 página `wiki/codigo/` (ex.: `zonas-protegidas`), 1 `wiki/negocio/` (pulso de hoje),
   1 `wiki/conceitos/` (DNA), 1 `raw/` (1º chunk do `business_rules.md`). Validar formato + invariante ~24 KB.
3. **Batch 2:** migrar o resto do `knowledge/permanente/` → `wiki/codigo/` e `wiki/conceitos/` (já são pequenos).
4. **Batch 3:** chunk completo do `business_rules.md` (57 cabeçalhos → N páginas ≤24 KB) para `raw/` + índice.
5. **Batch 4:** indexar os 170 relatórios como `raw/` (só metadados/ponteiros, não corpo inteiro).
6. **Batch 5:** ligar o `log.md` de proveniência e o sync (C4). **Só então** ativar escrita autónoma por anel.

### C4 — Sync bidirecional repo↔VPS (fonte de verdade por lado)
- **Código manda no repo:** `wiki/codigo/` + `schema.md` + `raw/` → repo é fonte; VPS recebe **réplica read-only** (Hermes nunca escreve aqui).
- **Negócio manda no VPS:** `wiki/negocio/` → VPS é fonte; repo recebe réplica read-only (Claude Code nunca reescreve pulso).
- **`index.md`/`log.md`:** partilhados; cada escrita **anexa** ao `log.md` uma linha `{ts, lado (repo|vps), autor (claude|hermes), página, anel}`.
- **Anti-conflito:** partição por dono elimina escrita simultânea no mesmo ficheiro (ninguém escreve na zona do outro).
  Transporte reutiliza a ponte Tailscale já existente (`bora-pc` ↔ container). **Pré-fix:** corrigir a sync para o vault canónico (ver Riscos).

### C5 — Consolidação cruzada noturna (a inovação)
Estender `daily_pulse.py` (anel A, read-only) para, **além** do pulso:
1. Ler os últimos commits que tocaram `wiki/codigo/` (via a réplica do repo no container).
2. Cruzar com o pulso de negócio do dia.
3. **Sinalizar contradições** — ex.: *"commit mexeu no fluxo de cancelamento (§12) E cancelamentos subiram 50% em 2026-07-07"*.
4. Escrever o sinal em `wiki/negocio/` + anexar ao `log.md`; **nunca corrige, só assinala** (Anel A → reporta; ação fica com o Danilo).
   Já há base para isto: o pulso de hoje **já** emitiu 3 sinais (cancelamento 50%, crashes). Falta o cruzamento com commits.

---

## 🖥️ D) PAINEL ADMIN — "Central do Córtex" (só listar)
Pontos de UI que o painel admin precisará para dar autoridade total ao Danilo:
1. **Ver `index.md` + `log.md`** do cérebro (feed de proveniência: quem/quando/de-que-lado escreveu cada página).
2. **Fila de aprovação "zona vermelha"** — páginas Anel C/D pendentes (o que o Claude/Hermes propôs escrever e ainda não aplicou).
3. **Aprovar / Rejeitar** uma escrita proposta (1 toque) — espelha o inbox `robot_suggestions` da Fase 5.
4. **Auditoria por autor** — filtrar por `claude` vs `hermes`, por anel, por data.
5. **Diff viewer** — ver o antes/depois da página proposta.
6. **Kill switch do Córtex** — suspender escrita autónoma (herda `robot_b_enabled` / dial de confiança da Fase 5).
7. **Estado do sync** — última sincronização repo↔VPS por lado, e alerta se divergir.
> Guardrail (herdado da Fase 5): a Central do Córtex deve ser **o cabeçalho da mesma caixa** de aprovação
> já existente, **não** um segundo inbox.

---

## ⚠️ E) BUGS / RISCOS ENCONTRADOS (mesmo fora de escopo)
1. 🔴 **Sync do VPS puxa o vault ERRADO** — `obsidian-sync.sh` sincroniza `Desktop\Bora` (deprecated, 89 .md), não o canónico `.obsidian-vault/` (117 .md). Corrigir **antes** de qualquer consolidação de negócio.
2. 🟠 **Vault antigo `Desktop\Bora` ainda em disco** — causa a ilusão "Obsidian sumiu". Auditar órfãos e só depois deprecar/arquivar.
3. 🟠 **Pastas duplicadas por acento/idioma:** `.obsidian-vault/{sessoes, sessões}` e `knowledge/{sessao, sessions}` — notas partidas.
4. 🟠 **`protege-banco.FIXED.sh` não aplicado** + `settings.json.bak_preApply_20260708` — reconciliar (hook LIVE ok, FIXED é upgrade).
5. 🟡 **`business_rules.md` 190 KB com numeração colidida** (dois `## 18.`, `§28…§38` vs `## 27`) — precisa de chunk + renumeração no `raw/`.
6. 🟡 **Doc drift KPI** — skill `daily-pulse` cita `v_kpis_diarios/v_funil_checkout/v_drivers_online_agora`, mas o pulso lê `socio_kpi_*`. Ambos existem; alinhar doc.
7. 🟡 **Cron interno do Hermes falha** — `Permission denied: /opt/data/cron/jobs.json` (repete em `errors.log`). Fora do Córtex, mas a corrigir.
8. 🟢 **Housekeeping no container:** ~30 `SOUL.md.bak*`, ~10 `.env.bak*`, ~10 `bora-bridge-up.sh.bak*`, e uma pasta literal `%APPDATA%\npm` (env var Windows vazada como nome de pasta).
9. 🟢 **Memória local desatualizada:** (a) anon key "não persistida" → **já persistida** (2026-07-08); (b) daily-pulse "sem cron" → **tem cron 07:00**. Atualizar no fim (handoff ao bibliotecario-cerebro).

---

## ❓ F) AMBIGUIDADES — decisão do Danilo antes da Fase 1
- **Q1 (a grande):** `.cortex/` novo **OU** adotar/renomear o `.claude/.ai/knowledge/` que já é o cérebro?
  → *Recomendação:* **evoluir o existente** (menos retrabalho, menos duplicação, invariante ~24 KB já respeitado). Confirmar.
- **Q2:** Podemos **corrigir a sync do VPS** para o vault canónico `.obsidian-vault/` e **arquivar** o `Desktop\Bora` (após auditar órfãos)?
- **Q3:** Padronizar as views em **`socio_kpi_*`** e atualizar a doc da skill `daily-pulse` (que ainda cita `v_*`)?
- **Q4:** Local exato do lado-negócio: confirmar `/opt/data/cortex/` (volume, sobrevive a `docker recreate`) como destino.
- **Q5:** `schema.md` do Córtex = destilado de **CLAUDE.md + ceo-ai/SKILL.md + PROTOCOLO.md**. Concordas com esta fusão como fonte da Camada 3?

---
*Fim da Fase 0. Nenhuma escrita no cérebro, nenhuma migração, VPS intacto. Próximo passo aguarda decisão do Danilo (§F).*
