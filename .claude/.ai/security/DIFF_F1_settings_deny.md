# DIFF F1.2 + F1.3 — Estender deny (aplicar à mão)

> **Porquê à mão:** `.claude/settings.json` e `~/.claude/settings.json` são auto-protegidos pela Trava (regra `Edit(./.claude/settings.json)` no deny). Nenhum agente pode editar a sua própria config de segurança — por design. O Danilo aplica estes diffs.

---

## F1.3 — `bora_app/.claude/settings.json` (adicionar 6 linhas ao deny)

### Encontrar (linha 43-45, antes do bloco git destrutivo):
```json
      "Edit(./.claude/settings.local.json)",
      "Write(./.claude/settings.local.json)",
      "MultiEdit(./.claude/settings.local.json)",
      "Bash(git push --force:*)",
```

### Substituir por (inserir 6 linhas novas de ficheiros multiagente):
```json
      "Edit(./.claude/settings.local.json)",
      "Write(./.claude/settings.local.json)",
      "MultiEdit(./.claude/settings.local.json)",
      "Edit(./.claude/agents/critic.md)",
      "Write(./.claude/agents/critic.md)",
      "MultiEdit(./.claude/agents/critic.md)",
      "Edit(./.claude/agents/consensus.md)",
      "Write(./.claude/agents/consensus.md)",
      "MultiEdit(./.claude/agents/consensus.md)",
      "Edit(./.claude/.ai/cortex-mcp/router.mjs)",
      "Write(./.claude/.ai/cortex-mcp/router.mjs)",
      "MultiEdit(./.claude/.ai/cortex-mcp/router.mjs)",
      "Bash(git push --force:*)",
```

**O que faz:** workers/agentes não se auto-modificam nem modificam os novos guardiões multiagente (`critic.md`, `consensus.md`, `router.mjs`). Os ficheiros ainda não existem — o deny é harmless e fica pronto para F3/F5.

---

## F1.2 — `~/.claude/settings.json` (réplica da Trava no user home — GAP crítico)

> **Problema:** o user home `~/.claude/settings.json` tem `permissions.deny` **vazio**. Uma sessão fora de `bora_app/` (ou um worker lançado noutro cwd) não carrega o deny do projeto → fica sem Trava física. Risco real.
>
> **Nota:** o settings do home atualmente usa `"defaultMode": "bypassPermissions"` (linha 70 do ficheiro). Replicar o deny é essencial porque mesmo em bypass, `deny` vence `allow` e é inbypassável.

### No `~/.claude/settings.json`, no bloco `permissions`, transformar:
```json
  "permissions": {
    "allow": [
      ...
    ],
    "defaultMode": "bypassPermissions",
    ...
  }
```

### Para (adicionar bloco `deny` ANTES de `allow`):
```json
  "permissions": {
    "deny": [
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Bash(git push --force-with-lease:*)",
      "Bash(git reset --hard:*)",
      "Bash(supabase db reset:*)"
    ],
    "allow": [
      ...
    ],
    "defaultMode": "bypassPermissions",
    ...
  }
```

> **Decisão de scope:** no user home réplica só guardamos **operacional/destrutivo global** (git destrutivo + `supabase db reset`). Os ficheiros `$` (pricing_service.dart, etc.) são relativos ao project dir e **não aplicam** fora de `bora_app/` — a sua protecção fica a cargo do deny do project (`bora_app/.claude/settings.json`) que carrega quando se trabalha dentro do repo. O home deny cobre o caso "sessão/em worker noutro cwd faz force-push/reset-hard/db-reset" que é o gap real.

### Verificação pós-aplicação (pelo Danilo)
1. Abrir `~/.claude/settings.json`, confirmar bloco `deny` com 5 entradas.
2. Testar: numa sessão Claude fora de `bora_app/`, tentar `git reset --hard <algo>` → deve ser negado.
3. Confirmar que dentro de `bora_app/` o deny do project (com ficheiros $) continua ativo.

---

## Commit sugerido (após aplicar ambos, pelo Danilo)
```
security(fase1): nega edição dos guardiões multiagente + réplica deny no user home

- project settings: deny Edit/Write/MultiEdit em agents/critic.md,
  agents/consensus.md, .ai/cortex-mcp/router.mjs (workers não se automodifiquem)
- user home settings: adiciona deny de git destrutivo + supabase db reset
  (fecha gap: sessão/worker fora de bora_app/ ficava sem Trava física)

Refs: RED_MODEL.md §2 e §5; DIFF_F1_settings_deny.md
```

---

*Aplica os 2 diffs à mão (F1.3 + F1.2). Eu já não posso — a Trava auto-protege settings.*

## Resumo do estado F1 (após aplicação manual pendente)

| Item | Estado |
|---|---|
| F1.7 RED_MODEL.md (source-of-truth) | ✅ Criado pelo agente |
| F1.5 pre-flight-multiagent.md | ✅ Criado pelo agente |
| F1.4 protege-banco.sh FINTABLE | 📝 Diff pronto (DIFF_F1_protege-banco.sh.md) — aplicação manual |
| F1.3 settings.json project deny | 📝 Diff pronto (abaixo) — aplicação manual |
| F1.2 ~ /settings.json home deny | 📝 Diff pronto (abaixo) — aplicação manual |
| F1.6 testes + auditoria | ⏳ Corre após aplicação manual |

**Achado importante da F1:** a auto-proteção da Trava impede o próprio agente de a estender (hooks + settings). Isto é correcto por design — confirma que o guardião funciona. Os diffs ficam preparados para o Danilo aplicar, e o agente pode prosseguir com as fases que **não** tocam na Trava (F2 em diante operam sobre cortex-mcp/Supabase/migrations, que não estão deny).