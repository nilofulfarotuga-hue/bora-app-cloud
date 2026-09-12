# Sessão 5F-α — Pendentes (5F-β + 5F-α manuais)

**Data 5F-α:** 2026-05-06
**Branch base:** `autonomous-night-2026-04-29`

---

## 5F-β — Push real automático + reply UI

### pg_net settings (BLOQUEANTE)

```sql
-- Antes de criar a Edge Fn notify-admin-urgent + trigger, configurar:
ALTER DATABASE postgres SET app.supabase_url = '<service URL>';
ALTER DATABASE postgres SET app.service_role_key = '<service_role JWT>';
```

Sem isto o trigger AFTER INSERT não consegue chamar a Edge Fn.

### Tabela `admin_push_tokens`

```
admin_user_id uuid FK -> auth.users
fcm_token     text
device_label  text   ('iPhone Danilo', 'Android Danilo')
created_at    timestamptz
revoked_at    timestamptz NULL
```

RLS: admin_self (admin vê os seus tokens) + service_role_all.

### Edge Fn `notify-admin-urgent`

- verify_jwt=false (chamada do trigger via service_role no body)
- Param: `crosstalk_id` + `urgency`
- Para cada `admin_push_tokens` activo: send FCM
- Email Resend para admins hardcoded
  (`nilofulfarotuga@gmail.com` + `nilofulfaro@gmail.com`)
- Rate limit: 1 push por crosstalk_id (evita duplicação)
- Logs em `support_audit_log` (ou tabela equivalente)
- Sem PII no payload (só `crosstalk_id` + `urgency`)

### Trigger AFTER INSERT em `robot_crosstalk`

```sql
CREATE OR REPLACE FUNCTION robot_crosstalk_notify_critical()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.urgency = 'critical' AND NEW.status = 'pending'
     AND NEW.direction = 'a_to_b' THEN
    PERFORM net.http_post(
      url := current_setting('app.supabase_url') || '/functions/v1/notify-admin-urgent',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      ),
      body := jsonb_build_object(
        'crosstalk_id', NEW.id,
        'urgency', NEW.urgency
      )
    );
  END IF;
  RETURN NEW;
END;
$$;
```

### Configurar Resend API key

`supabase secrets set RESEND_API_KEY=<key>` (uma vez).

### `admin_respond_to_crosstalk` RPC + UI reply

- RPC `admin_respond_to_crosstalk(p_crosstalk_id, p_answer)`
  GRANT authenticated + check `is_admin()`.
- Botão "Responder" em `AdminCrosstalkScreen` para rows pending
  → modal textarea → submit RPC → row muda para `answered`
  com `answered_by='admin'`.
- Sair do "modo observador" actual (banner observador 5F).

### Auto-resposta Claude Code

- Skill `ask-knowledge-base` corre em loop scheduled
  (`/loop` slash command ou cron skill).
- Lê `a_to_b` pending → `query_knowledge.ts` → `respond.ts`
  automático se `min_similarity > 0.7` em ≥2 chunks.
- Threshold + override admin via flag em `support_settings`.

### Métricas

- View `crosstalk_metrics`: rate respondido / ignored, tempo
  médio resposta por urgência, top skills accionadas, top RAG
  chunks reutilizados.
- Card no `AdminDashboardScreen` ou nova página
  `AdminCrosstalkStatsScreen`.

### Anonymization JS fix

- `analyze-conversations` (5D, JS) tem mesmo bug ordem UUID que
  foi corrigido em PG na hotfix 5F-B1.
- Replicar ordem `email → phone PT → UUID → phone genérico → dígitos 4+`
  no `_anonymizePII()` JS.

### Webhook receiver para confirmar entrega push

(opcional) callback FCM para invalidar tokens mortos.

### Auto-fechamento

Crosstalks com `status='pending'` + `created_at` há >7 dias
sem resposta → auto-update `status='ignored'` (pode ser
reaberto manualmente).

---

## 5F-α — pendentes manuais

- **S15 functional smoke**: testar em-app uma frase tipo
  "paguei mas não recebi pedido" e confirmar que:
  - Robô A escolhe `ASK_ROBOT_B` skill
  - chama `agent_ask_robot_b(p_urgency='critical')`
  - row entra em `robot_crosstalk` com `urgency='critical'`
  - `AdminCrosstalkScreen` mostra banner vermelho + badge
- **Versioning support_skills history**: tabela
  `support_skills_history` (audit trail playbook updates) —
  considerar em 5F-β ou 5G. `updated_at` já existe; `version`
  é monotonic via `version+1`.

---

## Notas de implementação

- 5F-α deve preceder 5F-β: realtime via app aberta é o mínimo
  viável. 5F-β acrescenta push push push.
- Push admin deve ser opt-in via `profiles.notif_admin_crosstalk`
  (default `true` para admins hardcoded; configurável).
- Manter regra **sem WhatsApp** — Danilo decisão 2026-05-06.

---

*Pendentes Sessão 5F-α — actualizar quando 5F-β for iniciada.*
