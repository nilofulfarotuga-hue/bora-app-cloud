-- Sessão 5E B1 — Estender skill_suggestions p/ 3 tipos proposta + zonas SAFE/CRITICAL
-- Adiciona: proposal_type, zone_type, target_skill_id, target_setting_key,
--          target_setting_value, previous_value
-- Estende: status CHECK (+rolled_back), UNIQUE pattern_hash (incluir proposal_type)

-- 6 colunas novas (todas com default coerente; 0 rows existentes em prod)
ALTER TABLE public.skill_suggestions
  ADD COLUMN IF NOT EXISTS proposal_type text
    NOT NULL DEFAULT 'new_skill'
    CHECK (proposal_type IN ('new_skill','playbook_update','settings_update')),
  ADD COLUMN IF NOT EXISTS zone_type text
    NOT NULL DEFAULT 'safe'
    CHECK (zone_type IN ('safe','critical')),
  ADD COLUMN IF NOT EXISTS target_skill_id uuid
    REFERENCES public.support_skills(id),
  ADD COLUMN IF NOT EXISTS target_setting_key text
    CHECK (target_setting_key IS NULL OR target_setting_key ~ '^[a-z_]+$'),
  ADD COLUMN IF NOT EXISTS target_setting_value text,
  ADD COLUMN IF NOT EXISTS previous_value text;

-- Coerência type ↔ target fields obrigatórios
ALTER TABLE public.skill_suggestions
  DROP CONSTRAINT IF EXISTS skill_suggestions_type_coherence;
ALTER TABLE public.skill_suggestions
  ADD CONSTRAINT skill_suggestions_type_coherence
  CHECK (
    (proposal_type = 'new_skill') OR
    (proposal_type = 'playbook_update'
       AND target_skill_id IS NOT NULL) OR
    (proposal_type = 'settings_update'
       AND target_setting_key IS NOT NULL
       AND target_setting_value IS NOT NULL)
  );

-- Status CHECK +rolled_back
ALTER TABLE public.skill_suggestions
  DROP CONSTRAINT IF EXISTS skill_suggestions_status_check;
ALTER TABLE public.skill_suggestions
  ADD CONSTRAINT skill_suggestions_status_check
  CHECK (status IN ('pending','approved','rejected','implemented','rolled_back'));

-- UNIQUE pattern_hash inclui proposal_type
-- (mesmo pattern com proposal_type diferente é distinct e permitido)
ALTER TABLE public.skill_suggestions
  DROP CONSTRAINT IF EXISTS skill_suggestions_pattern_hash_status_key;
ALTER TABLE public.skill_suggestions
  DROP CONSTRAINT IF EXISTS skill_suggestions_pattern_hash_unique;
ALTER TABLE public.skill_suggestions
  ADD CONSTRAINT skill_suggestions_pattern_hash_unique
  UNIQUE (pattern_hash, proposal_type, status);

-- Indexes parciais (apenas pending — onde se filtra mais)
CREATE INDEX IF NOT EXISTS idx_skill_suggestions_proposal_type
  ON public.skill_suggestions (proposal_type)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_skill_suggestions_zone_pending
  ON public.skill_suggestions (zone_type, status)
  WHERE status = 'pending';
