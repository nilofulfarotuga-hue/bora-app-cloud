---
name: notify-broadcast
description: Envia notificação push em massa segmentada (all/clients/drivers/partners) via push_broadcasts + Edge Fn execute-broadcast. Dry-run preview da audiência+mensagem; --commit exige --confirm. Regista em admin_audit_log. PT-PT.
metadata:
  type: operacoes
  category: notifications
  depends_on: bora-knowledge
  uses_edge_fns: [execute-broadcast]
  version: 1.0.0
---

# Notify Broadcast

Push em massa segmentada. Insere uma linha em **`push_broadcasts`** (status `pending`) e
dispara a Edge Fn **`execute-broadcast`** (que lê tokens ativos de `*_push_tokens` e envia via FCM).

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/06-flows.md` / `08-edge-functions.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Segmentos (confirmados no código da Edge Fn)
`all` · `clients` · `drivers` · `partners`. (⚠️ `city:Guarda` **não** é suportado pela
`execute-broadcast` atual → pendência; usar um dos 4.)

## Uso
```bash
python scripts/preview_audience.py --segment clients          # conta destinatários
python scripts/send.py --segment clients --title "..." --body "..."             # dry-run
python scripts/send.py --segment clients --title "..." --body "..." --commit --confirm
```

## Modos
- **DEFAULT (dry-run)**: mostra segmento + nº destinatários + título/corpo. NÃO insere/envia.
- **`--commit --confirm`** (ambos): INSERT `push_broadcasts(status='pending')` → POST
  `execute-broadcast {broadcast_id}` → `admin_audit_log` (quem + segmento + nº).

## Salvaguardas
- `--commit` **exige também `--confirm`** (dupla confirmação) — push em massa é irreversível.
- Mensagens **PT-PT**; não enviar conteúdo $ enganoso (o operador é responsável pelo texto).
- Rate/lotes geridos pela Edge Fn (batches de 50). Não recria infra de push.
- **Admin UI**: idealmente o Danilo compõe/agenda broadcasts num ecrã admin — **pendência** anotada.
