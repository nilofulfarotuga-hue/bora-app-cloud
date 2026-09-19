# 🧠 PLANO — LOTE D: Reparar o "cérebro" (Knowledge + Obsidian)
> Data: 2026-05-31 · Modo: PROTECÇÃO TOTAL · **NADA editado / NENHUM sync corrido / Obsidian intocado** (só análise read-only + DB read-only).
> Aprovação do Danilo antes de qualquer passo. Ordem segura: 1) corrigir factos → 2) reconciliar stores → 3) registar no Obsidian → 4) religar sync.

---

## ⚠️ CORREÇÃO DE FACTO IMPORTANTE (honestidade)
O prompt assume que **hoje fechei 3 blockers via MCP**. A verdade verificada agora na DB de produção:

| Fix | Estado na DB (verificado) | Quem nesta sessão |
|---|---|---|
| (a) `admin_list_orphans` guarded (anon revogado) | ✅ live (`authenticated/service_role/postgres`) | **Eu apliquei** (migration `20260518200000`) |
| (b) bucket `receipts` privado | ✅ live (`public=false`) | **NÃO fui eu** — já estava feito |
| (c) cron `bora_dispatch_maintenance` usa `net.http_post` | ✅ live (corrigido) | **NÃO fui eu** — já estava feito |

→ Os 3 estão **mesmo live**. Mas **nesta sessão só apliquei o (a)**; (b) e (c) foram feitos fora desta sessão (presumo que pelo Danilo, direto na DB). Para o registo no Obsidian isto é o mesmo resultado, **mas a atribuição correta importa** e a **dívida de repo é real** (ver abaixo).

**Dívida de repo confirmada:** não existe nenhuma migration no repo a captar (b) bucket-privado nem (c) cron-fix — o repo ainda tem a versão **antiga** (cron com `extensions.net.http_post`, bucket público). Buckets públicos atuais: `avatars, product-images, products, restaurant-assets` (receipts já fora).

---

## 1. MAPA DOS DOIS CÉREBROS

### Store A — CURADO (congelado)
- **Local:** `projetosflutter/.claude/.ai/knowledge/` — **83 ficheiros**.
- **INDEX `last_synced`: 2026-04-25T23:40:00Z** · `.sync-state.json` de 25/04.
- Estrutura: `business-rules/`, `architecture/`, `roadmap/`, `decisions/`, `references/`, `from-obsidian/` (destino do sync).
- **Estratégico** (roadmap, decisões, regras) + factos técnicos que **envelheceram mal**.

### Store B — VIVO
- **Local:** `bora_app/.claude/skills/bora-knowledge/knowledge/` — **14 ficheiros** (`00-auto-facts.md` auto-gerado + `01-design-system` … `12-recipes` curados).
- Atualizado até maio (mas `08-edge-functions.md` ainda diz "38" vs 43 real).
- **Técnico/operacional**, lido por TODAS as outras skills (via skill `bora-knowledge`).

### Os dois `.claude` (fonte de confusão)
- O harness carregou **`projetosflutter/.claude/skills/ceo-ai/SKILL.md`** (raiz) como skill ativa — logo a **raiz** está em uso.
- As 45 skills "filhas" vivem em **`bora_app/.claude/skills/`**.
- → Há **ceo-ai/SKILL.md em DOIS sítios** (raiz + bora_app). **Decisão pendente:** qual é o canónico? (Recomendo: bora_app como canónico do projeto; confirmar qual o harness lê em produção.)

### Os dois VAULTS Obsidian (ambos existem em disco)
- `C:\Users\danil\Desktop\Bora` (B maiúsculo) — usado pelo `sync-obsidian-knowledge.ps1` (vault→knowledge).
- `C:\Users\danil\Desktop\bora\rules-history` (b minúsculo) — usado pela skill `auto-rules-sync` (regras de negócio).
- 🔴 **Dúvida bloqueante:** qual é o "cérebro verdadeiro"? Só o Danilo confirma. **Não avançar sem isto.**

### Scripts de sync (e PORQUÊ congelou)
- `.claude/scripts/sync-obsidian-knowledge.ps1` (+ `.sh`): **UNIDIRECIONAL** (vault → `.claude/.ai/knowledge/from-obsidian/`), idempotente (SHA256), **manual** (precisa `-VaultPath`).
- **Porque congelou (2 razões):**
  1. **Manual, sem hook/cron** → ninguém o correu desde 25/04.
  2. **Unidirecional** → a direção *trabalho-em-código → Obsidian* **nunca existiu**. Logo, mesmo correndo, nada do que o Claude faz chega ao vault.
- `auto-rules-sync` é outro mecanismo (regras → vault `rules-history`), com aprovação manual.

---

## 2. LISTA EXATA DE FACTOS ERRADOS A CORRIGIR

### `projetosflutter/.claude/skills/ceo-ai/SKILL.md` (raiz, ativo)
| Linha | Errado | Certo |
|---|---|---|
| 12 | Paleta `#2E7D32` + `#E65100` | `#16A34A` (primary) + `#F97316` (accent) |
| 13 | "5 Edge Functions" | **43 deployed / 38 locais** |
| 138-139 (PARCIAL) | "Firebase push falta deploy"; "Foto perfil cliente bug não salva" | Firebase push (FCM heads-up/FGS/CallKit) **feito**; foto perfil **persiste** (Sessão 2.3) |
| 142 (#1 blocker) | Firebase push CRÍTICO | **resolvido** |
| 143 (#2 blocker) | BUG-PT-006 parceiro sem som | **resolvido** (notify-partner/chat) |
| 145 (#4 blocker) | Foto perfil cliente | **resolvido** |
| 150-156 (scores) | Cliente 52 / Parceiro 52 / TOTAL 55/100 | obsoletos — recomputar ou remover |
| 241 | "5 Edge Functions: …" (lista) | 43 (lista real via MCP `list_edge_functions`) |

### `projetosflutter/.claude/.ai/knowledge/architecture/stack.md`
- Linhas ~19-25 + 32-33: lista de "5 Edge Functions" + paleta `#2E7D32/#E65100` → atualizar (ou apontar para o store vivo `08-edge-functions.md`).

### `projetosflutter/.claude/.ai/knowledge/INDEX.md`
- `last_synced: 2026-04-25` → data atual após reconciliação.

### `projetosflutter/.claude/.ai/knowledge/roadmap/tier1-blockers.md`
- Marcar resolvidos: Firebase push, foto perfil, BUG-PT-006. Rever os restantes.

### `bora_app/.claude/skills/bora-knowledge/knowledge/08-edge-functions.md`
- "38 em supabase/functions" → **43 deployed / 38 locais** + nota das **6 deployed-sem-fonte** (admin-cancel-reservation, execute-broadcast, gemini-diagnostic, robot-b, upload-driver-document, upload-order-photo) e **1 local-sem-deploy** (confirm-mbway-payment).

### Tabelas
- Vários docs dizem "75 tabelas" → realidade **78** (confirmar contagem no momento da edição).

> **Nota:** as edições aos docs **curados** (01-12 do store vivo) são bloqueadas pelo Knowledge Protocol — só `00-auto-facts.md` é auto-editável. Os factos técnicos contáveis (edge fns, tabelas, skills) devem ir para **`00-auto-facts.md`** via a skill `update-bora-knowledge` (MODO A), **não** editados à mão nos 01-12.

---

## 3. PLANO DE RECONCILIAÇÃO (fonte única)

**Recomendação de papéis (sem perder informação):**
- **Store VIVO (`bora-knowledge`) = fonte técnica única** (edge fns, tabelas, design tokens, fluxos, zonas protegidas). É o que as skills leem.
- **Store CURADO (`.ai/knowledge`) = só estratégia/roadmap/decisions** (ADRs, tier-blockers, competitors). **Remover dele os factos técnicos duplicados** que envelhecem mal (edge fns, paleta) → passam a apontar para o store vivo.
- **Não apagar nada** sem backup: arquivar o que sair para `.ai/knowledge/_archive/`.

**Mecânica segura:**
1. Correr `update-bora-knowledge` em **`detect_drift`** (read-only) → relatório do drift atual.
2. Correr em **`apply_updates` (MODO A)** → só reescreve `00-auto-facts.md` (edge fns 38→43, contagem skills, tabelas). **Nunca toca 01-12.**
3. Os factos do **store curado** + `ceo-ai/SKILL.md` (paleta, scores, blockers) → **edição manual proposta como diff** ao Danilo (tocam SKILL.md = zona "pergunta antes").
4. Decidir o `ceo-ai/SKILL.md` canónico (raiz vs bora_app) e **eliminar o duplicado** (após confirmação de qual o harness lê).

**Skill responsável:** `update-bora-knowledge` (técnico, MODO A) + edição curada manual para estratégia.

---

## 4. O QUE REGISTAR NO OBSIDIAN (trabalho de hoje 31/05)

Estrutura proposta no vault verdadeiro (ex. `Desktop\Bora\Bora App\2026-05-31\`):
1. **Relatório:** copiar `AUDITORIA_GERAL_2026-05-31.md` + os 3 planos (`PLANO_DISTANCIA_ESTRADA`, `PLANO_C4_C5_DETALHADO`, este `PLANO_LOTE_D`).
2. **Fixes de segurança/infra (live na DB):**
   - (a) `admin_list_orphans` fechada (guard `app_metadata.role='admin'` + REVOKE anon) — **aplicado nesta sessão**.
   - (b) bucket `receipts` privado — **já estava feito** (não nesta sessão).
   - (c) cron `bora_dispatch_maintenance` `net.http_post` — **já estava feito** (não nesta sessão).
3. **Lotes implementados:** A (transparência preço + cancelamento via platform_settings), B (limpeza/dead code: bora_bottom_nav v1, @Deprecated/apagar store_shopping_purchase, rótulos comissão 10/90, gitignore housekeeping), C (nota estafeta no checkout, pesquisa/ordenação lojas, reorder 1-toque).
4. **Planos guardados:** distância de estrada (server-authoritative), C4 substituição, C5 entrega agendada.
5. **🔴 DÍVIDA A RECONCILIAR (destacar no vault):** o **repo NÃO reflete** (b) bucket-privado nem (c) cron-fix — só vivem na DB. Criar migrations no repo para capturá-los (senão um `db reset`/redeploy reintroduz o bug). E os commits dos Lotes A-C **ainda não foram push** (ficam para o fim).

> Como é **escrita manual no vault** (o sync não faz esta direção), isto é uma sessão de "backfill Obsidian" — o Claude Code pode **gerar os .md prontos** numa pasta de staging para o Danilo arrastar para o vault, OU escrever direto no vault **só após o Danilo confirmar o path verdadeiro**.

---

## 5. RELIGAR O SYNC AUTOMÁTICO (último passo)

**Problema:** o sync atual é unidirecional (vault→knowledge) e manual. Para "tudo passar ao Obsidian" é preciso a direção **inversa** (knowledge/relatórios → vault), que não existe.

**Proposta (mais robusta, por fases):**
1. **Curto prazo (fiável já):** um script novo `export-to-obsidian.ps1` que copia `relatorios/*.md` + `.ai/knowledge/**` → `<vault>/Bora App/` (idempotente SHA256, igual ao existente mas ao contrário). Mantém o sync atual (vault→knowledge) para o que o Danilo escreve à mão.
2. **Automação (não voltar a congelar):** ligar ambos os scripts a um **hook `Stop`/`SessionEnd`** do Claude Code (corre no fim de cada sessão) — via skill `update-config` (settings.json). Alternativa: pg_cron/Task Scheduler diário. **Hook = mais robusto** (corre sempre que há trabalho, sem depender de memória humana).
3. **Bidirecional real:** documentar que `export-to-obsidian` (saída) + `sync-obsidian-knowledge` (entrada) juntos = bidirecional. Guardas anti-conflito por SHA256 já existem.
4. **Validação:** criar um ficheiro-teste `__sync_test_31mai.md` num lado → correr → confirmar que aparece no outro → apagar.

**Garantia anti-congelamento:** o **hook de sessão** é a chave — remove a dependência de "alguém lembrar-se de correr".

---

## 6. DIVISÃO DE TRABALHO E RISCO

| Tarefa | Quem | Risco |
|---|---|---|
| Confirmar vault verdadeiro (`Desktop\Bora` vs `Desktop\bora\rules-history`) | **Danilo** | — (bloqueante) |
| Confirmar `ceo-ai/SKILL.md` canónico (raiz vs bora_app) | **Danilo** | — |
| `update-bora-knowledge` detect_drift + MODO A (00-auto-facts) | Claude Code | BAIXO (só toca ficheiro auto) |
| Corrigir factos curados (paleta/scores/blockers) — diff proposto | Claude Code → aprova Danilo | BAIXO (docs; SKILL.md pede confirmação) |
| Reconciliar stores (arquivar duplicados técnicos do curado) | Claude Code | **MÉDIO** — *fundir mal pode perder info* → **sempre backup em `_archive/` antes** |
| `export-to-obsidian.ps1` + hook de sessão | Claude Code | BAIXO (escreve só no vault/staging; nunca apaga) |
| Migrations de repo para bucket-privado + cron-fix (capturar a dívida) | Claude.ai (MCP) / Claude Code | ⚠️ cron = zona dispatch → **só documentar a migration, aplicar com aprovação** |
| Arrastar ficheiros para o vault / backfill | **Danilo** (ou Claude após path confirmado) | BAIXO |

**Riscos-chave:**
- 🔴 Fundir os 2 stores **sem backup** pode perder informação válida → regra: **arquivar, nunca apagar**.
- 🔴 Religar o sync **antes** de corrigir os factos **espalha os erros** → respeitar a ordem (1→2→3→4).
- 🔴 A migration do cron toca dispatch (zona proibida) → documentar, aplicar só com OK explícito.

---

## RECOMENDAÇÃO FINAL
Seguir a ordem segura **estritamente**: (1) corrigir factos no original → (2) reconciliar com backup → (3) backfill manual do Obsidian → (4) religar sync com **hook de sessão** (a peça que impede voltar a congelar). **Decisões bloqueantes para o Danilo:** qual o vault verdadeiro e qual o `ceo-ai/SKILL.md` canónico. Até isso, não escrever no vault.

## FECHO
- ✅ **Não editei / não corri sync / não toquei no Obsidian.** Só leitura (filesystem + DB read-only) + este plano.
