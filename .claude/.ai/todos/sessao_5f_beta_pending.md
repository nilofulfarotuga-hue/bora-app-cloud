# TODOs Pendentes — Sessão 5F-β

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Estado infra:** Deploy completo. Activação real depende de configs manuais Danilo.

---

## ⚠️ ACTIVAÇÃO REAL — Acções manuais Danilo

### 1. `pg_net` settings (BLOQUEANTE — trigger inactivo)

`ALTER DATABASE` via MCP falhou por privilege (esperado). Trigger
`trg_robot_crosstalk_notify_urgent` está registado mas faz silent skip
até estes settings serem configurados.

**No Supabase Dashboard → SQL editor:**

```sql
ALTER DATABASE postgres
  SET app.supabase_url = 'https://ojykpzwqrtusfeakzrna.supabase.co';

ALTER DATABASE postgres
  SET app.service_role_key = '<service_role_key do dashboard>';

SELECT pg_reload_conf();
```

**Activa simultaneamente:**
- 5D cron auto-suggest (`analyze-conversations` schedule)
- 5B-β1 trigger (`shadow → live` automation)
- `PASSWORD_RESET` real
- **5F-β `notify-admin-urgent` trigger**

**Validar pós-config:**

```sql
SELECT current_setting('app.supabase_url', true) AS url,
       CASE WHEN current_setting('app.service_role_key', true) IS NULL
            THEN 'MISSING' ELSE 'CONFIGURED' END AS key_status;
-- Esperado: url=https://...; key_status=CONFIGURED
```

### 2. `RESEND_API_KEY` (opcional — só email)

```bash
supabase secrets set RESEND_API_KEY=<chave_resend> \
  --project-ref ojykpzwqrtusfeakzrna
```

**Sem isto:** push FCM funciona; email skip silent (log:
`[notify-admin-urgent] RESEND_API_KEY missing — email skipped`).

**Verificar:**

```bash
supabase secrets list --project-ref ojykpzwqrtusfeakzrna | grep RESEND
```

### 3. Domínio email Resend

Confirmar `noreply@boraapp.com` verificado no Resend Dashboard
(SPF/DKIM ok). Se domínio for outro, editar
`supabase/functions/notify-admin-urgent/index.ts` linha `EMAIL_FROM`
e re-deploy.

### 4. Admin abrir admin app uma vez

`AdminPushService.registerForAdmin()` corre em
`AdminDashboardScreen.initState` (post-frame callback). Sem isto:
0 tokens em `admin_push_tokens` → push_attempted=0.

**Validar pós-abertura:**

```sql
SELECT id, admin_id, fcm_token, device_label, platform, last_used_at
FROM admin_push_tokens
ORDER BY last_used_at DESC;
```

---

## Smoke teste manual pós-config completo

Para confirmar que push funciona end-to-end (depois de #1 + #4):

### Cenário: simular pergunta crítica via cliente

```sql
-- INSERT manual de teste (substituir auth admin context)
INSERT INTO robot_crosstalk (
  asked_by, direction, urgency, status, question, question_context, rag_chunks_used
) VALUES (
  'a', 'a_to_b', 'critical', 'pending',
  '🧪 5F-β smoke — admin push test (delete after)',
  '{"smoke": true}'::jsonb,
  '[]'::jsonb
);
```

**Esperado:**
1. Trigger dispara → `net.http_post` para `notify-admin-urgent`
2. Edge Fn busca tokens → envia FCM v1 push para todos admins
3. Push aparece em admin app(s) com título "🔴 URGENTE — Bora App"
4. Tap no push abre `/admin/crosstalk`
5. Card visível com botão Responder
6. Resposta via UI grava `answered_by='admin'`

**Cleanup:**

```sql
DELETE FROM robot_crosstalk WHERE question LIKE '%🧪 5F-β smoke%';
```

---

## Próximas sessões

- **5G** — Painel admin inbox propostas avançado (~3h)
- **Sessão 6** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor (~6-8h)

---

## Arquivos referência

- `bora_app/.claude/.ai/reports/20260502_megafinal/05f_beta_audit.md` — audit pré-execução
- `bora_app/.claude/.ai/reports/20260502_megafinal/05f_beta_report.md` — relatório final
- `bora_app/.obsidian-vault/sessões/05f_beta_prompt.md` — sync Obsidian
- `bora_app/.claude/.ai/business_rules.md` §41 — regras canónicas
