#!/bin/bash
# Create demo@bora.app account
curl -s -X POST 'https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/admin/users' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzAwMDcyOCwiZXhwIjoyMDg4NTc2NzI4fQ.TFbiYG1SQEB5gNpUb1721mvkL5JU7hJaSsrru4KkE8A' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzAwMDcyOCwiZXhwIjoyMDg4NTc2NzI4fQ.TFbiYG1SQEB5gNpUb1721mvkL5JU7hJaSsrru4KkE8A' \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo@bora.app","password":"BoraDemo2026!","email_confirm":true,"app_metadata":{"bora_role":"client"}}'
echo ""
echo "DONE"
