-- BUG 1 (cadastro parceiro, 2026-07-14): restaurants_public_read só deixa o
-- dono ler o próprio restaurante quando approval_status='approved'. Um
-- parceiro com candidatura 'pending' (ou 'rejected') que faça logout/login
-- nunca via a própria linha, então PartnerEntryScreen caía sempre no wizard
-- do zero em vez de reconhecer a candidatura em curso (risco de duplicar
-- linhas 'pending' em restaurants a cada nova submissão).
--
-- Policy adicional e permissiva (Postgres faz OR entre policies permissivas
-- do mesmo comando) — não altera restaurants_public_read, só soma acesso
-- para o próprio dono independente do status.
CREATE POLICY restaurants_owner_read ON public.restaurants
  FOR SELECT
  USING (auth.uid() = user_id);

COMMENT ON POLICY restaurants_owner_read ON public.restaurants IS
  'Dono (auth.uid() = user_id) vê a própria linha mesmo pending/rejected; leitura pública continua approved-only via restaurants_public_read.';
