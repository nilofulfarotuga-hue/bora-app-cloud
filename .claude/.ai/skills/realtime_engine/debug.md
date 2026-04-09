---
name: realtime_engine_debug
description: Debug sub-procedure for realtime_engine. Quick checklist for identifying realtime failures — no code changes, diagnosis only. For full bug investigation use fix_realtime.
version: 2.0.0
---

# REALTIME ENGINE — DEBUG CHECKLIST

## ROLE
Quick triage tool for realtime issues. Identify failure point before calling `fix_realtime` for full investigation.

---

## OBJECTIVE

Localizar rapidamente onde o fluxo realtime falha (eventos não chegam, dados inconsistentes, delay alto).

---

## CHECKLIST

### Eventos não chegam
- [ ] Subscription ativa? (`StreamSubscription` não é null)
- [ ] Canal correto? (nome + filtro)
- [ ] Dados corretos no backend? (verificar no Dashboard)
- [ ] RLS permite acesso? (testar com SQL Editor)
- [ ] ID não é null quando subscription foi criada?

### Dados inconsistentes
- [ ] Duplicação de eventos? (múltiplas subscriptions?)
- [ ] Perda de eventos? (filtro muito restritivo?)
- [ ] Race condition? (subscription criada antes de auth completar?)

### Delay alto
- [ ] Delay artificial (`Future.delayed`) no fluxo?
- [ ] `notifyListeners()` disparando rebuild desnecessário?

---

## RESPONSABILIDADES

- ✅ Triage rápido de falha realtime (diagnóstico, não fix)

## NÃO PODE FAZER

- ❌ Propor correção de código (delegar a `fix_realtime` + `executor`)
- ❌ Alterar política de sync (delegar a `realtime_engine/rules.md`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Triage rápido de falha realtime | **realtime_engine/debug.md** (eu) |
| Bug pontual com fix completo | `fix_realtime` |
| Política de realtime | `realtime_engine/rules.md` |

## RULES

- Apenas diagnostica — não corrige
- Ao identificar causa → passar para `fix_realtime`
- Source of truth: `.claude/.ai/business_rules.md`
