---
id: e2e-observabilidade-2026-07-11
tipo: relatorio
origem: [executor loop autónomo Bora]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# Olhos em tempo real para o Claude.ai sobre os testes E2E

## Porquê
O Claude.ai ficava **cego** ao progresso ao vivo dos testes E2E e tinha de
confiar na palavra do executor (que já provou não ser fiável) → 2 dias perdidos.
Agora há um **diário partilhado** no Supabase que o Claude.ai lê a qualquer momento.

## O que foi feito

1. **Tabela `public.e2e_log`** (migration `e2e_log_observabilidade`, projeto
   `ojykpzwqrtusfeakzrna`) — colunas `id, created_at, fluxo, passo, estado`
   (`iniciou`/`passou`/`falhou`), `detalhe` (erro literal), `device` (serial adb
   ou `vps`/`host`), `run_id`. **RLS aberta** a `anon`/`authenticated` (é só diário
   de teste — não-financeira, não-produção). Índices em `created_at`, `fluxo`, `run_id`.

2. **Módulo `.claude/testes-e2e/e2e_diario.py`** — `registar(fluxo, passo, estado,
   detalhe, device)` faz um INSERT PostgREST **best-effort** (timeout 8s, **nunca
   lança** — observabilidade jamais afunda o teste). Sem `.env` → no-op silencioso.
   Usa a mesma credencial do runner (SERVICE_ROLE ou ANON; a RLS deixa ANON escrever).

3. **`runner.py`** passa a escrever cada passo importante: início/fim de fluxo,
   cada `maestro:` (start + passou/falhou com o `tail` do erro), cada `poll_db`
   (start + passou/timeout).

4. **`loop-noturno.py`** escreve os eventos de alto nível: arranque de cada ciclo e
   a **classificação** (BUG DO TESTE → YAML afinado / BUG DO APP → BLOQUEADO/REGISTADO).

## Prova real (tempo real, confirmado)
- Smoke do módulo: 3 linhas apareceram na tabela em <2s (depois limpas).
- Corri `runner.py --fluxo smoke-login-cliente` com um telemóvel real ligado
  (`RZGYB1XQD2P`) → a tabela recebeu **ao vivo**:
  - `início do fluxo | iniciou | single=True`
  - `maestro: comum/reset-role-screen.yaml | iniciou`
  Cada passo seguinte (passou/falhou) é escrito à medida que acontece.

## Como o Claude.ai vê ao vivo
```sql
SELECT to_char(created_at,'HH24:MI:SS') t, fluxo, passo, estado, detalhe, device
FROM public.e2e_log ORDER BY created_at DESC LIMIT 30;
```
Se um fluxo falha 3× no mesmo passo → visível e acionável na hora (sem depender de ninguém).

## Regra gravada
`wiki/licoes/observabilidade-e2e-tempo-real.md` — daqui em diante **todo teste
E2E escreve o seu progresso em `e2e_log`**.

## Ficheiros tocados
- **Novo** `supabase` (migration remota) `e2e_log_observabilidade`
- **Novo** `.claude/testes-e2e/e2e_diario.py`
- **Editado** `.claude/testes-e2e/runner.py` (import + 6 pontos de `registar`)
- **Editado** `.claude/testes-e2e/loop-noturno.py` (import + ciclo + classificação)
- **Novo** `wiki/licoes/observabilidade-e2e-tempo-real.md`
- **Novo** `.claude/.ai/knowledge/inbox/e2e-observabilidade-2026-07-11.md` (este)

## Re-verificação independente (executor headless, 2026-07-11)
Confirmado do zero (sem confiar no relatório anterior):
- Tabela `public.e2e_log` existe com as **8 colunas** exatas (`id,created_at,fluxo,
  passo,estado,detalhe,device,run_id`); RLS **ON** com políticas `e2e_log_insert_any`
  + `e2e_log_select_any` para `anon`/`authenticated` → o Claude.ai **lê via anon**.
- Smoke ao vivo (`python e2e_diario.py`) → 3 linhas na tabela em <2s (depois limpas).
- **`runner.py --todos` a correr AGORA** no device real `RZGYB1XQD2P` (2 devices
  ligados: `RZGYB1XQD2P`, `N75LTG5X5DSKDMV4`). A tabela recebeu **ao vivo**:
  - nível runner: `smoke-login-cliente → início → maestro reset iniciou → falhou
    (rc=1 + tail literal do erro) → fim falhou (79.7s)` e depois `login-estafeta → início`;
  - nível Maestro dentro do flow (`diario.yaml`, device=`maestro`): "abriu
    Supermercados", "abriu loja Continente", "loja carregou produtos".
- Erro literal é gravado no `detalhe` (ex.: `rc=1 · Running on RZGYB1XQD2P…`).

## Nota
Não foi committado (política do loop). Teste completo (`runner.py --todos`) deixado
a correr em background com o diário ligado — o Claude.ai pode acompanhar ao vivo com o
SELECT acima.
