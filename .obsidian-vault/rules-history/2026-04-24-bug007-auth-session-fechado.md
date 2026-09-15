---
date: 2026-04-24
type: tech-rule
files_affected:
  - lib/auth/auth_store.dart
commit: manual (sem alteração de código)
ceo_ai_section: Current System State / PRONTO
approved_by: Danilo
tags: [rules, auth, bug-close]
---

# BUG-007 — Auth/session persistence: fechado como resolvido

## Antes
BUG-007 marcado como "funcional mas com edge cases não resolvidos" e "Current Focus" no CLAUDE.md.

## Depois
Análise completa de `auth_store.dart` confirma que todos os edge cases críticos estão tratados. Fechado como ✅ RESOLVIDO sem alteração de código.

## Motivo
- `_onAuthStateChange(session=null)` → retorno early é **intencional** (token hiccup protection, não sign-out real)
- `_initFromPrefs` → re-autentica driver via `signInWithPassword` antes de usar UID (fix crítico já aplicado)
- Guard `roleStr != 'driver'` → driver nunca recebe guest UID
- Edge case "client sem password" → probabilidade nula em produção (registo sempre exige password)
- Edge case "non-demo client não em memória" → workaround automático via `_onAuthStateChange` quando `signInWithPassword` dispara

## Impacto
- Nenhuma alteração de código necessária
- SKILL.md PRONTO: Auth actualizado para reflectir BUG-007 fechado
- PARCIAL: "Realtime sync" removido (era BUG-002, já resolvido em commit e4b3596)
