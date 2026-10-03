-- ═══════════════════════════════════════════════════════════════════════════
-- TODO 3 FIX (close-TODOs 2026-05-11) — Migrar triggers da sessão mega
-- 2026-05-11 para usar vault em vez de current_setting (alinhar com
-- _notify_admin_urgent_trigger 5F-β-α).
--
-- Achado: pg_settings (`app.supabase_url`, `app.service_role_key`) não
-- estão definidas a nível DB. Padrão correcto é ler `project_url` +
-- `service_role_key` do vault. Sem isto, triggers silenciosamente skip os
-- pushes/OCR.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_chat_message_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $trg$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NEW.sender_type IS NULL OR NEW.sender_type NOT IN ('client','driver') THEN
    RETURN NEW;
  END IF;
  IF NEW.order_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE '5G: vault secrets MISSING — skipping notify-chat-message for message %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/notify-chat-message',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_key,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object('message_id', NEW.id)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '5G: notify-chat-message trigger error: %', SQLERRM;
  RETURN NEW;
END;
$trg$;

COMMENT ON FUNCTION public._notify_chat_message_trigger() IS
  '5G v2 (close-TODOs 2026-05-11): vault-based (project_url + service_role_key). NUNCA bloqueia INSERT.';

-- RPC finalize_storeshopping_purchase_v2 — mesma migração para vault
-- (corpo completo aplicado via apply_migration MCP; ver migration name
-- 2026_05_11_migrate_v2_triggers_to_vault no schema_migrations da DB).
-- Mudança chave: substitui
--   v_url := current_setting('app.supabase_url', true);
--   v_key := current_setting('app.service_role_key', true);
-- por
--   SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
--   SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
-- v1 NÃO foi tocada. Status flow inalterado.
