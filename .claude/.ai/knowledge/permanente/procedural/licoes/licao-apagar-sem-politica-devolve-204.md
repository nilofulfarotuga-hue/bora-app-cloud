---
tema: licao-apagar-sem-politica-devolve-204 · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-apagar-sem-politica-devolve-204
tipo: licao
origem: [commit 5efd2d96, lib/screens/admin/admin_orphan_payments_screen.dart, supabase/migrations/20260430260000_payment_drafts_gating.sql]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — DELETE sem política de apagar devolve 204 e apaga ZERO linhas

- **Contexto:** painel admin, ecrã de pagamentos órfãos — botão "Excluir draft" sobre a tabela
  `payment_drafts` (rascunhos de pagamento).
- **A descoberta:** um DELETE pelo PostgREST numa tabela com RLS ligada e **sem política de
  apagar** devolve `204` (sucesso, sem corpo) e apaga **zero** linhas, sem erro nenhum. O cliente
  Dart não distingue isso de um apagar verdadeiro. `payment_drafts` só tem a política de leitura
  `payment_drafts_owner_read`: o botão existe desde 2026-05-01 (commit `21b419d8`) e nunca apagou
  nenhum rascunho — o ecrã dizia "Draft apagado." na mesma.
- **Regra a aplicar:** nunca dizer "apagado" (nem registar na auditoria) pelo código de resposta.
  Pedir sempre de volta o que saiu — `.delete().eq(...).select('id')` — e tratar a lista vazia
  como "o servidor não deixou". Vale o mesmo para UPDATE (ver "mesma família").
- **O que ficou feito (2026-10-05, commit `5efd2d96`, publicado):** o ecrã pede confirmação, pede
  de volta as linhas e só diz "apagado" e só regista na auditoria (`log_admin_action`) o que saiu
  mesmo (`admin_orphan_payments_screen.dart:46-122`). **Por decidir:** o botão continua sem
  conseguir apagar — ou se tira, ou ganha função própria de admin
  (`.claude/.ai/missoes/ronda-04-10/pronto/LEIA.md` §5).
- **Mesma família, já vista:** 2026-04-28 — a política `drivers_update_own` bloqueava em silêncio
  os UPDATE do admin e o PostgREST devolvia `204` com 0 linhas afectadas
  (`inbox/2026-04-28-admin-panel-overhaul.md`, BUG 1).
- **Evidência:**
  - produção, 2026-10-05: `payment_drafts` com RLS ligada e uma única política,
    `payment_drafts_owner_read` (SELECT, `authenticated`) — lido em `pg_policies`;
  - `supabase/migrations/20260430260000_payment_drafts_gating.sql:39-42` (liga a RLS e cria só
    essa política);
  - `git show 5efd2d96 -- lib/screens/admin/admin_orphan_payments_screen.dart`: antes era
    `.from('payment_drafts').delete().eq('id', draftId)` seguido de "Draft apagado.".

`estado: atual`
