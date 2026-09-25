-- 5G B1: schema extend + indexes + ALTER CHECK status (preserva TODOS 5E values)

-- 1. Coluna admin_notes
ALTER TABLE public.skill_suggestions
  ADD COLUMN IF NOT EXISTS admin_notes text DEFAULT NULL;

-- 2. CHECK status preserva 5E values + adiciona auto_archived
ALTER TABLE public.skill_suggestions
  DROP CONSTRAINT IF EXISTS skill_suggestions_status_check;

ALTER TABLE public.skill_suggestions
  ADD CONSTRAINT skill_suggestions_status_check
  CHECK (status IN (
    'pending',
    'approved',
    'rejected',
    'implemented',
    'rolled_back',
    'auto_archived'
  ));

-- 3. Indexes para filtros eficientes
CREATE INDEX IF NOT EXISTS idx_skill_suggestions_status_type
  ON public.skill_suggestions
  (status, proposal_type, suggested_at DESC);

CREATE INDEX IF NOT EXISTS idx_skill_suggestions_zone
  ON public.skill_suggestions (zone_type)
  WHERE zone_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_skill_suggestions_category
  ON public.skill_suggestions (suggested_category);

CREATE INDEX IF NOT EXISTS idx_skill_suggestions_search
  ON public.skill_suggestions
  USING gin(to_tsvector('portuguese', coalesce(pattern_summary, '')));
