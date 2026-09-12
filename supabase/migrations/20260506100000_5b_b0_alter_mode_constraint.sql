-- Sessão 5B-α B0 — Alter support_skills.mode CHECK to include write_shadow/write_auto
ALTER TABLE public.support_skills
  DROP CONSTRAINT IF EXISTS support_skills_mode_check;

ALTER TABLE public.support_skills
  ADD CONSTRAINT support_skills_mode_check
  CHECK (mode = ANY (ARRAY[
    'read_only'::text,
    'write'::text,
    'write_shadow'::text,
    'write_auto'::text,
    'escalate'::text
  ]));
