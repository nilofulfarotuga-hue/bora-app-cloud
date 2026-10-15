#!/bin/bash
: "${SUPABASE_SERVICE_ROLE_KEY:?defina SUPABASE_SERVICE_ROLE_KEY no ambiente (nunca no repo)}"
# Create demo@bora.app account
curl -s -X POST 'https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/admin/users' \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo@bora.app","password":"BoraDemo2026!","email_confirm":true,"app_metadata":{"bora_role":"client"}}'
echo ""
echo "DONE"
