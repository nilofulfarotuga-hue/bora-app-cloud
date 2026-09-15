---
id: licao-onde-vive-a-trava
tipo: licao
origem: [Fase 0: procurar "engine --selftest" no VPS; a Trava é hook PreToolUse no repo]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — mapear **onde** vive um guard antes de o testar

**Problema.** O prompt pedia "rodar `engine --selftest`" para provar que a Trava do banco dispara.

**Tentativas que falharam.** Procurar `engine` e `protege-banco.sh` **no VPS** → não existiam lá.

**Porquê.** A "Trava" **não** é um binário do Hermes no VPS. É um **hook `PreToolUse` no repo (PC)**:
`.claude/settings.json` liga `.claude/hooks/protege-banco.sh` (matcher Bash|Supabase|execute_sql|
apply_migration|deploy_edge_function) e `protege-dinheiro.sh` (matcher Edit|Write|MultiEdit).

**Solução (regra generalizável).** Antes de testar um guard, **localizar onde ele está declarado**
(procurar em `settings.json`/hooks/CI, não presumir a plataforma). O selftest correto era
`bash .claude/scripts/selftest_protege_banco.sh` → **12/12** (bloqueia 7 destrutivas, passa 5 seguras).
