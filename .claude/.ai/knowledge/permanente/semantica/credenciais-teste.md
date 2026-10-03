---
tema: credenciais-teste · escopo: projeto · estado: atual · atualizado: 2026-07-10
id: credenciais-teste
tipo: referencia
origem: [Tarefa 1 missão 3-em-1 2026-07-10 — sync banco↔runner]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado
---

# 🔑 Credenciais de TESTE (E2E) — fonte da verdade

> ⚠️ SÓ contas de TESTE (isoladas, marcadas "nao usar"). NUNCA produção. NUNCA Stripe real.

## Regra única (para nunca mais divergir)
**A fonte da verdade da password é `.claude/testes-e2e/.env`** (gitignored). Quem mudar a
password no banco TEM de atualizar o `.env` no mesmo ato — e vice-versa (o
`criar-contas-teste.py` sincroniza banco←.env). Antes de qualquer suite Maestro, o runner
valida por REST `signInWithPassword` (a validação falha = parar antes de gastar Maestro).

## Contas
| Conta | Email | Password | Papel |
|---|---|---|---|
| Cliente E2E | `teste-cliente@bora.app` | ver `E2E_CLIENT_PASSWORD` no `.env` (13 chars, "Bora…", sincronizada banco↔runner 2026-07-10 ~17:40, REST 200 ✅) | client (bora_role) |
| Estafeta E2E | `teste-estafeta@bora.app` | `E2E_DRIVER_PASSWORD` no `.env` — ⚠️ conta NÃO existe no Auth como email direto (drivers usam `{phone}@driver.bora.app`); validar/criar no 1.º ciclo da suite | driver |
| Parceiro E2E | `teste-parceiro@bora.app` | `E2E_PARTNER_PASSWORD` no `.env` | partner |

## Histórico de divergências (lição)
2026-07-10: password do banco rodada fora do fluxo (sem atualizar `.env`) → smoke E2E falhou
horas com `invalid_credentials 400` enquanto REST validava a password antiga. Diagnóstico
custou: logcat + debug-flow + suspeita errada de char-dropping. **Se o smoke der
invalid_credentials: 1.º verificar sync banco↔.env, só depois culpar o Maestro.**
