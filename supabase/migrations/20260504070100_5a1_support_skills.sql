-- Sessão 5A-1 B2 — support_skills (playbooks markdown DB-driven)
-- Admin edita sem redeploy. Versionable. Seed em 5A-2 B17.

CREATE TABLE IF NOT EXISTS public.support_skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_name text NOT NULL UNIQUE,
  version int NOT NULL DEFAULT 1,
  category text NOT NULL,
  mode text NOT NULL CHECK (mode IN ('read_only','write','escalate')),
  requires_human_handoff bool NOT NULL DEFAULT false,
  playbook_md text NOT NULL,
  allowed_tools jsonb NOT NULL DEFAULT '[]'::jsonb,
  examples jsonb NOT NULL DEFAULT '[]'::jsonb,
  active bool NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_skills_active
  ON public.support_skills (active) WHERE active = true;

ALTER TABLE public.support_skills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_skills_select_authed ON public.support_skills;
CREATE POLICY support_skills_select_authed ON public.support_skills
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS support_skills_modify_admin ON public.support_skills;
CREATE POLICY support_skills_modify_admin ON public.support_skills
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
