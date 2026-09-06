# Pré-5A — Obsidian Vault Migration — Fase A (Audit)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ⛔ STOP após A6 — aguarda luz verde Danilo
**Modo:** PROTECÇÃO TOTAL (read-only, zero mutações)

---

## Resumo executivo

> ⚠️ **Anomalia maior:** spec assumia sync scripts existentes em
> `.claude/.ai/knowledge/`. **NÃO EXISTEM.** Sub-tarefa B4 (actualizar
> scripts) tem de ser repensada — opções na §A2.

| Eixo | Estado | Implicação Fase B |
|---|---|---|
| Source vault | OK, intacto, 51 .md | Copiar |
| Destino `.obsidian-vault/` | NÃO existe | B1+B2 limpos, sem conflito |
| Sync scripts | **NÃO EXISTEM** | B4 muda — decisão Danilo |
| Git root | `bora_app/` | `.gitignore` vai aqui |
| `.gitignore` actual | Existe, sem regras Obsidian | B5 só append |
| `.obsidian/` config | 1 stub vazio + jsons | Migrar config inteiro |
| `.trash/` | Não existe | B2 sem exclusão necessária |

---

## A0 — Raiz git (TRAP T4)

```
git rev-parse --show-toplevel
→ C:/Users/danil/Desktop/projetosflutter/bora_app
```

**Decisão B5:** `.gitignore` aplicado é
`bora_app/.gitignore` (já existe). Paths nas novas regras são
**relativos a `bora_app/`** (e.g. `.obsidian-vault/.obsidian/...`),
não `bora_app/.obsidian-vault/...`.

---

## A1 — Inventário vault source

**Path:** `C:\Users\danil\Desktop\Bora`
**Total .md:** **51** (spec disse ~49 — ligeira divergência, OK)

### Distribuição por subpasta

| Count | Subpasta |
|---:|---|
| 16 | `bugs/` |
| 11 | `rules-history/` |
| 6 | `negocios/` |
| 5 | `arquitetura/` |
| 4 | `entregas/` |
| 4 | `ideias/` |
| 2 | `equipe/` |
| 1 | `.obsidian/2026-04-24.md` ← **stub vazio (0 bytes)** |
| 1 | `Bem-vindo.md` (root) |
| 1 | `RELATORIO-NOCTURNO-2026-04-24.md` (root) |
| **51** | **TOTAL** |

### Pastas de configuração (não são .md, mas existem)
- `.obsidian/` — config Obsidian (app.json, appearance.json,
  workspace.json, graph.json, plugins/, core-plugins.json,
  community-plugins.json, text-generator.json, `.obsidian/.obsidian/`
  recursivo (parece bug do plugin — replicado), `.obsidian/.smart-env/`)
- `.smart-env/` — Smart Connections plugin cache (embeddings, multi/,
  smart_components/, smart_contexts/, event_logs/, embedding_models/)
- `arquitetura/`, `bugs/`, `entregas/`, `equipe/`, `ideias/`,
  `negocios/`, `rules-history/` — conteúdo

### `.trash/` — **NÃO EXISTE** (não precisa exclusão)

### SHA256 CSV gerado
`vault_source_hashes.csv` (51 linhas, UTF-8, NoTypeInformation) com
colunas Path | Hash | Size. Método: `Get-FileHash -Algorithm SHA256`
(byte-level, não Get-Content).

### Anomalia A1.1 — `.obsidian/2026-04-24.md` é stub vazio
Ficheiro 0 bytes, criado 24 Apr. Decisão recomendada: **migrar mesmo
assim** (preservar bytes para SHA256 match). Não filtrar.

### Anomalia A1.2 — `.obsidian/.obsidian/` recursivo
Existe `Bora/.obsidian/.obsidian/plugins/...` (config dentro de
config). Provável artefacto de plugin (smart-connections + mcp-tools
referenciam cwd interno). Migrar tal qual; **não tentar limpar**.

---

## A2 — Inventário sync scripts existentes

⚠️ **CRÍTICO — divergência total com spec:**

`bora_app/.claude/.ai/knowledge/` contém **apenas 3 ficheiros** (zero
scripts):

```
INDEX.md                                       2094 B
business-rules/wallet.md                       4712 B
sessions/2026-04-28-admin-panel-overhaul.md   15995 B
```

**Não há `.ps1`, não há `.sh`, não há sync de qualquer tipo.**

Procura alargada (`grep` em `.claude/`, `scripts/`, `supabase/`,
`backend/` por `Desktop/Bora`):
- 1 hit: `.claude/.ai/reports/20260502_megafinal/05a1_agente_backend_audit.md`
  (ficheiro de relatório de outra sessão — referência documental, não
  script).

Procura por `obsidian-vault`: **0 hits** em qualquer ficheiro.

Procura por `from-obsidian` (mencionado no INDEX.md como subfolder
planeado): só o próprio INDEX.md menciona. Subfolder `from-obsidian/`
**não existe** — foi planeamento futuro nunca implementado.

### Implicação para B4

A premissa "actualizar scripts existentes" desaparece. Opções:

**Opção α (recomendada — minimal):** **NÃO criar scripts.**
Após migração, `.obsidian-vault/` vive dentro do repo. Não há
necessidade de sync entre dois locais. Obsidian abre o folder
directamente. Git é o backup. **B4 vira no-op; B6/B7 (smoke tests)
caiem juntos** (não há script para testar).

**Opção β:** Criar **um** script de **backup** de `.obsidian-vault/`
para um path externo (ex. OneDrive/Dropbox), unidireccional
projeto→externo. Fora do scope desta sessão; eventual sessão futura.

**Opção γ:** Criar script de export `.obsidian-vault/` →
`.claude/.ai/knowledge/from-obsidian/` (concretizar o que INDEX.md
prometeu). Assumiria que CEO-AI quer ler conteúdo do vault
indirectamente. Discutir antes.

> ⛔ **Pedido decisão Danilo:** Opção α, β ou γ?

---

## A2b — Path resolution analysis (TRAP T1)

**N/A** — não há scripts para analisar. Quando houver (Opção β/γ),
recomendação fica registada:

- PowerShell: `$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path`
- Bash: `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"`
- `$VAULT = Join-Path $root ".obsidian-vault"`

Depois resolve relativo à própria localização do script.

---

## A3 — Conflitos destino + `.gitignore` (TRAP T5)

### `bora_app/.obsidian-vault/`
**NÃO existe.** Sem conflito. B1+B2 são copy clean.

### `bora_app/.gitignore` — existe, completo (Flutter + secrets)
Sem regras Obsidian.

**Para B5, append-only:**

```gitignore
# ── Obsidian vault — config local não vai para git ─────────────
.obsidian-vault/.obsidian/workspace*
.obsidian-vault/.obsidian/cache
.obsidian-vault/.obsidian/app.json
.obsidian-vault/.obsidian/appearance.json
.obsidian-vault/.obsidian/graph.json
.obsidian-vault/.obsidian/community-plugins.json
.obsidian-vault/.obsidian/core-plugins.json
.obsidian-vault/.obsidian/text-generator.json
.obsidian-vault/.smart-env/
.obsidian-vault/.trash/

# Plugin recursivo .obsidian/.obsidian/ (artefacto)
.obsidian-vault/.obsidian/.obsidian/

# Plugins binários (re-instalados localmente)
.obsidian-vault/.obsidian/plugins/*/main.js
.obsidian-vault/.obsidian/plugins/*/data.json
.obsidian-vault/.obsidian/plugins/*/manifest.json
.obsidian-vault/.obsidian/plugins/*/styles.css
.obsidian-vault/.obsidian/plugins/*/bin/
```

> ⛔ **Pedido decisão Danilo:** queres ignorar o `.obsidian/` inteiro
> (paths individuais acima), ou prefere granular (workspace.json e
> caches mas guardar `app.json`/`appearance.json` para que outros
> dispositivos abram com o mesmo theme)?
>
> Recomendação: granular como acima. `app.json`/`appearance.json` no
> source actual ficheiros são triviais (2 bytes cada, basicamente
> `{}`) — não vale guardar. Apenas guardar plugins **lista**
> (`community-plugins.json` no source tem 104 B = lista de IDs); **mas
> mesmo essa fica per-machine** (algumas plugins não funcionam em
> todos os SOs). Recomendação final: ignorar `.obsidian/*` quase tudo,
> excepto `plugins/*/manifest.json` que é versionável (curto, descreve
> qual plugin).

---

## A4 — Direcção sync actual (TRAP T3)

**N/A** — não há scripts (ver A2). Logo, **não há direcção a
preservar**. Ponto morto.

Após decisão Danilo (Opção α/β/γ em §A2), B4 reformula-se conforme
escolha.

---

## A5 — Análise impacto

| Item | Quantidade | Risco |
|---|---|---|
| Ficheiros a criar (.md) | 51 | Zero |
| Ficheiros config a copiar | ~25 (`.obsidian/*`, `.smart-env/*` excluído por gitignore) | Zero (binary copy) |
| Ficheiros a editar | 1 (`.gitignore`, append) | Zero |
| Sync scripts a criar | 0 (Opção α) ou 1-2 (β/γ) | Zero local; β/γ adicional ~30min |
| Source intactus | sim, garantido (Copy-Item, não Move) | — |

### Plano rollback (se algo correr mal em Fase B)
1. `Remove-Item bora_app\.obsidian-vault -Recurse -Force`
2. `git checkout -- bora_app/.gitignore`
3. (se tiver criado scripts) `Remove-Item bora_app\.claude\.ai\knowledge\sync-*.ps1 -Force`
4. Source `C:\Users\danil\Desktop\Bora` permanece intacto (nunca foi
   tocado).

### Riscos identificados (todos baixos)
- **R1 — CRLF/LF (TRAP T2):** mitigado por `Copy-Item` (binary copy).
  Nunca usar `Get-Content` + `Set-Content` para mover .md. Smoke S2
  valida via SHA256 byte-level.
- **R2 — Smart Connections cache (~30 MB?):** medir antes de copiar.
  Se >50 MB, recomendar **excluir** `.smart-env/` da migração (é
  re-gerado automaticamente pelo plugin).
- **R3 — Plugins binários:** alguns plugins (mcp-tools tem `bin/`)
  trazem binários compilados. Versionar isso é mau. **Excluir
  `.obsidian/plugins/*/bin/`** no `.gitignore`. Plugin re-instala em
  cada máquina.
- **R4 — Sessões existentes podem referenciar `C:\Users\danil\Desktop\Bora`:**
  encontrei 1 ocorrência em `reports/20260502_megafinal/05a1_agente_backend_audit.md`.
  É documento histórico de outra sessão; **não actualizar** (é
  registo do estado em tempo da escrita; renomear distorce histórico).

---

## A6 — Decisões pendentes Danilo (responder antes de B)

1. **Sync scripts (§A2):** α (não criar) | β (backup externo) | γ (export para `.claude/.ai/knowledge/from-obsidian/`)?
2. **`.smart-env/` (§A5 R2):** medir tamanho primeiro; se >50 MB, excluir da migração?
3. **`.obsidian/` granularidade (§A3):** granular como proposto, ou ignorar tudo?
4. **`.obsidian/2026-04-24.md` stub vazio (§A1.1):** migrar tal qual (preservar SHA256)? Ou apagar antes de copiar?
5. **`.obsidian/.obsidian/` recursivo (§A1.2):** migrar tal qual (lixo do plugin)? Ou normalizar fora do scope desta sessão?

### Após luz verde, ordem proposta para Fase B
1. B1 — `mkdir -p bora_app/.obsidian-vault` + replicar 7 subpastas conteúdo
2. B2 — `Copy-Item -Recurse -Force` (incl. `.obsidian/`, excl. `.smart-env/` se R2 confirmar)
3. B3 — SHA256 CSV destino → diff vs source CSV → 100% match obrigatório
4. (B4 condicional Opção β/γ)
5. B5 — `.gitignore` append (granularidade aprovada em A6.3)
6. (B6/B7 só se Opção β/γ)
7. B8 — doc migração + critério apagar source

---

## Anexo

- `vault_source_hashes.csv` — 51 linhas, SHA256 + Size (este folder)
- Skills identificadas para criar: nenhuma (sessão filesystem trivial)
- Próxima acção: ⛔ STOP, aguardar resposta às 5 perguntas A6.
