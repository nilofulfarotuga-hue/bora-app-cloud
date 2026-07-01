-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 5 — Seed do /goal "Paridade Admin 360°" + backlog (20 domínios)
-- ═══════════════════════════════════════════════════════════════════════════
-- Idempotente (ON CONFLICT). O placar começa 1/20 (só Parceiros restaurante/loja
-- tem paridade completa — baseline da auditoria 2026-07-01). Ver docs/fase5/.
-- Nenhuma escrita de dinheiro: os itens 🔴 (vermelha, N3) são só entradas de
-- backlog para PROPOR — a Trava bloqueia aplicar.
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.autonomy_goals (slug, titulo, descricao, metrica_alvo, metrica_atual, unidade, itens_por_ciclo, teto_max_turns)
VALUES ('paridade-admin-360',
  'Paridade Admin 360°',
  'Para cada domínio SEM gestão no admin (auditoria 2026-07-01), construir o ecrã de gestão (ver/editar/criar/banir/configurar/exportar/auditar), um de cada vez, Juiz-gated, até a paridade admin chegar a 20/20.',
  20, 1, 'dominios', 1, 40)
ON CONFLICT (slug) DO NOTHING;

WITH g AS (SELECT id FROM public.autonomy_goals WHERE slug='paridade-admin-360')
INSERT INTO public.autonomy_backlog_items (goal_id, dominio, descricao, nivel, zona, prioridade, estado, juiz_veredito, ordem)
SELECT g.id, x.dominio, x.descricao, x.nivel, x.zona, x.prioridade, x.estado, x.juiz, x.ordem FROM g, (VALUES
  ('Parceiros restaurante/loja', 'Paridade admin JÁ completa (baseline da auditoria).', 2::smallint, 'verde', 'P1', 'feito', 'aprovado', 0),
  ('Visualizador de auditoria (admin_audit_log)', 'Ecrã read-only do admin_audit_log com filtros. Puro SELECT.', 1::smallint, 'verde', 'P2', 'pendente', NULL, 10),
  ('Exportar CSV (multi-domínio)', 'Exportar CSV em pedidos/clientes/parceiros. Read-only.', 1::smallint, 'verde', 'P1', 'pendente', NULL, 20),
  ('Filtros de descoberta (config cliente)', 'Config admin de filtros (aberto agora, dietético). Não-financeiro.', 1::smallint, 'verde', 'P2', 'pendente', NULL, 30),
  ('Gestão de Serviços/agendamentos (admin)', 'Pausar/ver providers + horário de loja.', 2::smallint, 'verde', 'P1', 'pendente', NULL, 40),
  ('Config Reservas Pro (admin)', 'Pacing/turn times/waitlist das reservas Pro.', 2::smallint, 'verde', 'P1', 'pendente', NULL, 50),
  ('Gestão de Favores/errand (admin)', 'Catálogo/consentimento de favores.', 2::smallint, 'verde', 'P2', 'pendente', NULL, 60),
  ('Revisão KYC estafeta (admin)', 'Admin revê KYC do estafeta (bloqueante). Compliance.', 2::smallint, 'amarela', 'P0', 'pendente', NULL, 70),
  ('Revisão KYC/documentos TVDE (admin)', 'Admin revê docs TVDE (IMT/DL 45/2018).', 2::smallint, 'amarela', 'P0', 'pendente', NULL, 80),
  ('Bucket driver-documents privado (SEC)', 'Forçar driver-documents privado + rever 3 buckets públicos.', 2::smallint, 'amarela', 'P0', 'pendente', NULL, 90),
  ('GDPR export / privacidade (admin)', 'Export/eliminação GDPR por utilizador.', 2::smallint, 'amarela', 'P1', 'pendente', NULL, 100),
  ('Zonas de entrega (admin)', 'CRUD de zonas. Toca taxa por zona. DINHEIRO — propose-only.', 3::smallint, 'vermelha', 'P0', 'pendente', NULL, 200),
  ('Taxa por zona (admin)', 'Taxa de entrega por zona. DINHEIRO — propose-only.', 3::smallint, 'vermelha', 'P0', 'pendente', NULL, 210),
  ('Pedido mínimo por zona (admin)', 'Pedido mínimo por zona. DINHEIRO — propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 220),
  ('Surge / preço dinâmico (admin)', 'Surge/pricing — propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 230),
  ('Gestão de cupões/promo codes (admin)', 'CRUD promo (afeta margem). Propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 240),
  ('Config de tokens (token_config)', 'Config de tokens (token_* = vermelha). Propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 250),
  ('Gestão de reclamações + refund (admin)', 'Reclamações com decisão de refund. Propose-only.', 3::smallint, 'vermelha', 'P0', 'pendente', NULL, 260),
  ('Idempotency de refund (config)', 'orders.refund_idempotency_key (BR §8.4.3 TODO). Propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 270),
  ('Acertos/settlements override (admin)', 'Override manual de settlements. DINHEIRO — propose-only.', 3::smallint, 'vermelha', 'P1', 'pendente', NULL, 280)
) AS x(dominio, descricao, nivel, zona, prioridade, estado, juiz, ordem)
ON CONFLICT (goal_id, dominio) DO NOTHING;
