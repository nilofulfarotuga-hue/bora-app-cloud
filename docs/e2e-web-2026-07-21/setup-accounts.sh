#!/bin/bash
set -e

SUPABASE_URL="https://ojykpzwqrtusfeakzrna.supabase.co"
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzAwMDcyOCwiZXhwIjoyMDg4NTc2NzI4fQ.TFbiYG1SQEB5gNpUb1721mvkL5JU7hJaSsrru4KkE8A"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

admin() {
  curl -s -X "$1" "$SUPABASE_URL$2" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"}
}

echo "=== CHECKING EXISTING ACCOUNTS ==="
EXISTING=$(admin GET "/auth/v1/admin/users?select=email" | python3 -c "import sys,json; [print(u['email']) for u in json.load(sys.stdin).get('users',[])]" 2>/dev/null || echo "")
echo "$EXISTING"

create_user() {
  local email="$1" password="$2" role="$3"
  if echo "$EXISTING" | grep -q "^${email}$"; then
    echo "EXISTS: $email"
    return 0
  fi
  echo "CREATING: $email (role=$role)"
  RESULT=$(admin POST "/auth/v1/admin/users" "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true,\"app_metadata\":{\"bora_role\":\"$role\"}}")
  echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK id='+d.get('id','?')[:8])" 2>/dev/null || echo "$RESULT"
}

create_user "cliente1@swarm.bora.test" "SwarmBora2026!" "client"
create_user "motorista1@swarm.bora.test" "SwarmBora2026!" "driver"
create_user "estafeta1@swarm.bora.test" "SwarmBora2026!" "driver"
create_user "limpador1@swarm.bora.test" "SwarmBora2026!" "driver"

echo ""
echo "=== VERIFYING EXISTING ACCOUNTS ==="
for email in "demo@bora.app" "ouro.prata@bora.app"; do
  if echo "$EXISTING" | grep -q "$email"; then
    echo "OK: $email exists"
  else
    echo "MISSING: $email"
  fi
done

echo ""
echo "=== INSERTING E2E_LOG INIT ==="
curl -s -o /dev/null -w '%{http_code}' -X POST "$SUPABASE_URL/rest/v1/e2e_log" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d '{"fluxo":"swarm_init","passo":"setup","estado":"passou","detalhe":"Setup accounts completed","device":"vps-chromium","run_id":"WEB-E2E-2026-07-21"}'
echo ""

echo "=== APPROVING DRIVER DOCUMENTS ==="
for email in "motorista1@swarm.bora.test" "estafeta1@swarm.bora.test" "limpador1@swarm.bora.test"; do
  USER_ID=$(admin GET "/auth/v1/admin/users?select=id&email=eq.$email" | python3 -c "import sys,json; print(json.load(sys.stdin)['users'][0]['id'])" 2>/dev/null || echo "")
  if [ -n "$USER_ID" ]; then
    # Check if driver record exists
    EXISTING_DRIVER=$(curl -s "https://ojykpzwqrtusfeakzrna.supabase.co/rest/v1/drivers?user_id=eq.$USER_ID&select=id" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")
    DRIVER_ID=$(echo "$EXISTING_DRIVER" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    if [ -n "$DRIVER_ID" ]; then
      echo "Driver record exists for $email (id=$DRIVER_ID), approving documents..."
      curl -s -o /dev/null -w '' -X PATCH "https://ojykpzwqrtusfeakzrna.supabase.co/rest/v1/drivers?id=eq.$DRIVER_ID" \
        -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "Content-Type: application/json" \
        -d '{"documents_verified":true}'
      echo "approved $email"
    else
      echo "No driver record for $email yet (will be created on first login)"
    fi
  fi
done

echo ""
echo "=== ALL DONE ==="
