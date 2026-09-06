# Lição — Observabilidade E2E em tempo real (o Claude.ai ganha OLHOS)

**Data:** 2026-07-11
**Zona:** 🟢 verde (observabilidade pura — não financeira, não produção)

## O problema (custou 2 dias)

O Claude.ai ficava **cego** ao progresso ao vivo dos testes E2E. Tinha de
confiar na palavra do executor — que já provou não ser fiável. Resultado: 2 dias
perdidos a debater um estado que ninguém conseguia verificar de forma independente.

## A regra (daqui em diante, para SEMPRE)

**Todo teste E2E escreve o seu progresso na tabela Supabase `e2e_log`.**
O Claude.ai faz `SELECT` a qualquer momento e vê EM TEMPO REAL exatamente o que
está a acontecer — sem depender de ninguém contar.

## Como funciona

- **Tabela** `public.e2e_log` — colunas: `id, created_at, fluxo, passo, estado`
  (`iniciou`/`passou`/`falhou`), `detalhe` (erro literal), `device` (serial adb ou
  `vps`/`host`), `run_id` (agrupa uma execução). RLS aberta a `anon` (é só diário
  de teste, sem dados sensíveis).
- **Módulo** `.claude/testes-e2e/e2e_diario.py` — expõe
  `registar(fluxo, passo, estado, detalhe, device)`. Faz um INSERT PostgREST
  **best-effort** (timeout 8s, nunca lança — observabilidade jamais afunda o teste).
  Sem `SUPABASE_URL/KEY` no `.env` → no-op silencioso.
- **`runner.py`** escreve os passos finos: início/fim de cada fluxo, cada `maestro:`
  (start + passou/falhou com o `tail` do erro), cada `poll_db` (start + passou/timeout).
- **`loop-noturno.py`** escreve os eventos de alto nível: arranque de cada ciclo e a
  **classificação** (BUG DO TESTE → YAML afinado / BUG DO APP → BLOQUEADO/REGISTADO).

## Como o Claude.ai vê ao vivo

```sql
-- últimos eventos, mais recente primeiro
SELECT to_char(created_at,'HH24:MI:SS') t, fluxo, passo, estado, detalhe, device
FROM public.e2e_log ORDER BY created_at DESC LIMIT 30;

-- só uma execução
SELECT * FROM public.e2e_log WHERE run_id = '<run_id>' ORDER BY created_at;

-- caçar um passo que falha repetido (decisão na hora)
SELECT fluxo, passo, count(*) FILTER (WHERE estado='falhou') falhas
FROM public.e2e_log WHERE created_at > now() - interval '2 hours'
GROUP BY fluxo, passo HAVING count(*) FILTER (WHERE estado='falhou') >= 3;
```

Se um fluxo falha 3× no mesmo passo, o Claude.ai **vê** e corrige — já não precisa
de acreditar em ninguém.

## Detalhes que importam

- `run_id` = `YYYYMMDD-HHMMSS-<pid>` do processo (ou `E2E_RUN_ID` do ambiente).
- Escrita usa a MESMA credencial `.env` do runner (SERVICE_ROLE ou ANON) — se só
  houver ANON, a RLS `e2e_log_insert_any` deixa escrever na mesma.
- Nunca imprime segredos; `detalhe` é truncado (≤4000 chars).
- Migration: `e2e_log_observabilidade` (aplicada 2026-07-11 no projeto
  `ojykpzwqrtusfeakzrna`).
