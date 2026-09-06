# Missão Completa — 2026-07-12 (loop autónomo)

Executor headless. Ordem: 1→2→3→4→5. Cada parte fecha antes da próxima.

---

## PARTE 1 — DISCO CHEIO ✅ CONCLUÍDA

**Problema:** Claude falhava com `Not enough disk space`. C: só tinha 14.39 GB livres.

**Limpeza executada (nada de código/config/dados apagado):**
| Alvo | Libertado |
|---|---|
| Gradle caches (`C:\Users\danil\.gradle\caches`) — re-descarrega sozinho | 4.36 GB |
| Gravações E2E >2 dias (`.claude/testes-e2e/gravacoes/`) — 12 ficheiros | 0.48 GB |
| TEMP do utilizador danil | 0.16 GB |
| Reciclagem | 0 (já vazia) |
| **TOTAL** | **~5.03 GB** |

**Resultado:** Free C: **14.39 GB → 19.42 GB**. Daemons gradle parados antes da limpeza para libertar locks. `build/` e `.dart_tool/` do bora_app já estavam ausentes (n/a). Android SDK (4.51 GB) e Pub Cache (0.32 GB) preservados (necessários / re-download caro).

---

## PARTE 2 — ESTABILIDADE ADB ✅ CONCLUÍDA

**Causa real:** device `N75LTG5X5DSKDMV4` desconectava a meio (`was requested but not connected`) → falso "reset-role-screen falha".

**(a) OS-level — a causa-raiz:** `powercfg` desativou **USB selective suspend** (AC+DC) no esquema ativo (`48e6b7a6…` sob `2a737441…`). Exit 0. Isto impede o Windows de suspender a porta USB do telemóvel a meio do teste.

**(b)/(c) Runner (`.claude/testes-e2e/runner.py`):** já implementados pelos commits de hoje (9d78935 gate boot_completed, 1878466). Antes de cada Maestro corre `garante_serial_autorizado()` → `adb reconnect` + escalada `kill/start-server` (reusa `~/.android/adbkey`) + `espera_device_pronto()` que só liberta o Maestro quando `sys.boot_completed==1`. Se o device cai **a meio** (assinatura `DESLIGADO_SIG`), recupera e repete.

**Reforço aplicado nesta missão:** retentativas mid-flow **1 → 2** (`MAX_TENT=3`) — device muito flaky recupera mesmo com 2 quedas antes de contar falha. `runner.py` compila OK (`py_compile`).

---
