-- Sessão 2026-05-26 — Partner approval workflow schema
-- Adiciona colunas obrigatórias para fluxo de aprovação de parceiros:
-- nif, iban, owner_doc_url, activity_doc_url, approval_status, rejection_reason,
-- submitted_at, reviewed_at, approved_at.
--
-- Documentos (owner_doc_url, activity_doc_url) agora OPCIONAIS no signup.
-- Admin panel mostra docs para review; admin pode aprovar ou rejeitar c/ motivo.

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS nif TEXT,
  ADD COLUMN IF NOT EXISTS iban TEXT,
  ADD COLUMN IF NOT EXISTS owner_doc_url TEXT,
  ADD COLUMN IF NOT EXISTS activity_doc_url TEXT,
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

-- Índice para filtragem comum em admin panels
CREATE INDEX IF NOT EXISTS idx_restaurants_approval_status
  ON public.restaurants(approval_status)
  WHERE approval_status IN ('pending', 'approved', 'rejected');
