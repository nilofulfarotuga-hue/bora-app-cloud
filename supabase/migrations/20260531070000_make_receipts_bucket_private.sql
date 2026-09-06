-- Alinha repo↔produção: o bucket `receipts` está PRIVADO em produção (public=false),
-- corrigido por UPDATE manual em 2026-05-31, mas SEM migration no repo.
-- Reverte 20260522183406_make_receipts_bucket_public: `receipts` contém PII financeira
-- (talões com valores/identificadores) e NÃO pode ser público.
-- Idempotente: correr de novo não causa dano.
-- As políticas RLS do bucket já existem e estão corretas — NÃO são tocadas aqui.

UPDATE storage.buckets SET public = false WHERE id = 'receipts';
