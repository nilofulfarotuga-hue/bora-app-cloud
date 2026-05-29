---
name: reservation-ops
description: Operações sobre reservas — listar (por restaurante/data/estado) e marcar chegada via RPC partner_mark_arrival (que aplica o desconto €2 internamente). Dry-run default; --commit chama a RPC. NÃO reimplementa lógica de pré-pagamento.
metadata:
  type: operacoes
  category: reservations
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Reservation Ops

Lista e atualiza reservas usando **RPCs existentes**. O pré-pagamento €3 e o desconto €2 na
chegada são geridos pela RPC — esta skill **não recalcula** nada disso.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/06-flows.md` (reservas) / `05-business-rules.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` + **JWT** com permissão p/ a RPC
(`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`).

## RPCs (confirmadas via MCP)
- `partner_mark_arrival(p_reservation_id uuid)` — marca chegada (aplica €2 internamente).
- (`client_arrived(p_reservation_id)` existe — variante do lado do cliente.)
- **no_show**: não há RPC single dedicada; o mecanismo existente é o cron
  `auto_close_no_show_reservations` (após grace) / painel admin → esta skill **não fabrica** no_show.

## Uso
```bash
python scripts/list_reservations.py --restaurant <id> --status confirmed --date 2026-05-30
python scripts/mark_status.py --reservation-id <uuid> --status arrived           # dry-run
python scripts/mark_status.py --reservation-id <uuid> --status arrived --commit  # chama partner_mark_arrival
```

## Modos
- **list_reservations**: read-only (SELECT reservations com filtros).
- **mark_status DEFAULT (dry-run)**: mostra a RPC que seria chamada. NÃO executa.
- **mark_status `--commit`**: `arrived` → `partner_mark_arrival(p_reservation_id)`.
  `no_show` → **não executa** (sem RPC single); imprime orientação (cron/admin).

## Salvaguardas
- Usa RPCs existentes; **não reimplementa** pré-pagamento/€2/€3 (geridos pela RPC).
- `no_show` single não suportado por RPC → guidance, sem ação destrutiva.
- Não toca Stripe/`bora_tokens`.
