# README — smoke-test-critical-paths (read-only)

Health-check dos caminhos críticos. **Zero escrita, zero pagamentos, zero pedidos.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/smoke.py          # relatório PT-BR + _preview/smoke.md
python scripts/smoke.py --json   # JSON para CI
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) |
| `smoke.py` | OPTIONS a Edge Fns + RPCs via information_schema + counts; ✅/⚠️/❌ |

## Notas
- Edge Fns: só **OPTIONS** (preflight CORS) — confirma que estão deployed/alcançáveis sem
  executar a lógica (não cria pedido nem cobra).
- pg_cron não é verificável via REST → o relatório indica como ver via MCP.
- Exit 1 se algum check crítico (Edge Fn / RPC) falhar.
