-- ════════════════════════════════════════════════════════════
-- BUG A (sessão exec 2026-05-12) — Sync repo de bucket 'receipts'
--
-- Bucket já criado em prod via MCP em 2026-05-11. Esta migration
-- garante criação idempotente em dev/staging para que esses
-- ambientes não tenham uploads 400 ao iniciar fresh.
--
-- RLS policies já existem no repo via migration anterior
-- 20260511120000_receipts_storage_rls_applied.sql — NÃO duplicar.
-- ════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'receipts',
  'receipts',
  false,
  10485760,  -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;
