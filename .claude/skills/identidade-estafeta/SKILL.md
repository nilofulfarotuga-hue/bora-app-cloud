---
name: identidade-estafeta
description: Regra fixa da identidade do estafeta (e dos outros papéis) — user_id manda em tudo, drivers.id só para tried_driver_ids e matching interno — com um verificador que falha se aparecer `.eq('id', <auth uid>)` ou `on_conflict=id` numa tabela de papéis. Usar antes de qualquer commit que toque em drivers/cleaners/washers/restaurants no Flutter, e ao rever migrações que escrevam nessas tabelas.
metadata:
  type: guardrail
  zona: verde
  execucoes: 1
  sucessos: 1
  falhas: 0
  ultima_execucao: 2026-09-16
---

# identidade-estafeta — `user_id` manda; `drivers.id` só para `tried_driver_ids`

## A regra (fixada 16/08/2026, reafirmada 16/09/2026)

- **`user_id` manda em tudo o que a app vê e aceita**: `orders.assigned_driver_id`,
  `orders.current_driver_offer_id`, `orders.driver_id`, `orders.preassigned_driver_id`,
  créditos, tokens, saldo, `driver_push_tokens.user_id`, RLS (`drivers_update_own` é
  `user_id = auth.uid()`).
- **`drivers.id` só serve para `tried_driver_ids` e matching interno do motor.**
- No Flutter, TODA a escrita/leitura do próprio estafeta é por `user_id = auth.uid()`:
  `from('drivers').update(...).eq('user_id', uid)` e upsert com `onConflict: 'user_id'`.
  **Nunca** `.eq('id', <auth uid>)` nem `onConflict: 'id'` numa tabela de papéis
  (`drivers`, `cleaners`, `washers`, `restaurants`).
- Ao ler um estafeta a partir de um id que veio de um pedido (`assigned_driver_id`), usar
  `.or('user_id.eq.$id,id.eq.$id')` — aceita as contas antigas em que `id = user_id`.
- No SQL, quem recebe "um estafeta" resolve sempre `where d.user_id::text = p or d.id::text = p`
  e grava `coalesce(d.user_id, d.id)`.

## As cicatrizes (porque isto é skill e não nota)

- **16/08 — Valdemir (TVDE):** `vehicle_type` lido por `id` vinha NULL → não roteava para o modo
  passageiros; créditos/tokens iam para uma linha que não existia.
- **16/09 — Ney (web):** `PATCH drivers?id=eq.<uid>` ×8 → 0 linhas (nunca ficou online no
  servidor); `POST drivers?on_conflict=id` → 409 ×8 (o INSERT batia no UNIQUE(user_id)); sem
  token; heartbeat nunca chamado. Um pedido da Goola ficou 10 min preso no nome dele.
- Há **7 contas** com `drivers.id ≠ user_id` em produção (todas as registadas pela app). As contas
  demo e as antigas têm `id = user_id` e por isso os testes com elas **não apanham** o bug — é por
  isso que existe o verificador.

## O verificador

```bash
python .claude/skills/identidade-estafeta/verificar.py            # varre lib/
python .claude/skills/identidade-estafeta/verificar.py --json     # saída para CI
python .claude/skills/identidade-estafeta/verificar.py lib/stores # pasta específica
```

Falha (exit 2) se encontrar, numa cadeia `from('<tabela de papel>')`:
- `.eq('id', <variável de auth uid>)` — nomes considerados uid: `uid`, `userId`, `user.id`,
  `authUser.id`, `authUserId`, `currentUser.id`, `currentUser!.id`, `auth.uid`, `driverId`,
  `_primaryDriverId`, `currentDriverId`, `myId`, `_uid`;
- `onConflict: 'id'` / `on_conflict=id` num upsert.

Excepções declaradas na mesma linha com `// identidade: id-ok <motivo>` (ex.: ecrã admin que
recebe `drivers.id` de uma lista). O painel admin que lista por `drivers.id` (`widget.driverId`)
não é apanhado porque o nome não é de auth uid.

## Como se corrige

1. Escrita do próprio: `.eq('user_id', uid)`; upsert `onConflict: 'user_id'` (mantém `'id': uid`
   no payload para contas novas nascerem com `id = user_id`).
2. Leitura por id vindo de um pedido: `.or('user_id.eq.$id,id.eq.$id').limit(1)`.
3. SQL: `where d.user_id::text = p or d.id::text = p`.
4. Depois: `flutter analyze` + este verificador + prova com uma conta em que `id ≠ user_id`
   (Erika, Valdemir ou Ney — só leitura; nunca mudar a palavra-passe de uma conta real).

## Telemetria (obrigatório no fim de cada execução)

1. Actualizar o frontmatter (`execucoes`, `sucessos`/`falhas`, `ultima_execucao`).
2. Uma linha em `.claude/.ai/knowledge/wiki/skills-metrics.md`.
