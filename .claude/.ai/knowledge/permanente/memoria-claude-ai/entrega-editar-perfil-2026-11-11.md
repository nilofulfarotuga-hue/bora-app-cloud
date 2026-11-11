---
id: memoria-claude-ai-entrega-editar-perfil-2026-11-11
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Entrega: Editar perfil do cliente — migrações por aplicar e ordem de publicação

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `entrega-editar-perfil-2026-11-11`, origem `claude-code`, atualizada em 2026-11-11T18:17:55.283252+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: entrega editar perfil 2026 11 11 · memoria claude.ai · claude_ai_memoria

Missão editar-perfil-2026-11-11 (Claude Code no PC, 11/11/2026). A bora-tranca recusou aplicar DDL ("migration é publicar: publica o Claude.ai"), também em prova com rollback. Nada de estrutura foi aplicado em produção.

O QUE APLICAR, POR ESTA ORDEM (ficheiros no ramo ai/2026-11-11-editar-perfil, commit 0a7764fa, PR #12 https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/12):
1) supabase/migrations/20261111180000_editar_perfil_cliente.sql — md5 99ce60a83b0b1984629096d83b75338f, 14135 bytes. Cria user_profile_changes (RLS sem políticas), _apply_user_profile_change (núcleo; grava users + auth.users.raw_user_meta_data bora_name/bora_phone + auditoria), _notify_profile_changed (sino + push notify-admin-message), client_update_my_profile (só auth.uid(), recusa convidado, limite 10/dia), substitui admin_update_client_contact (mesma assinatura; tira o exception when undefined_table que desfazia o UPDATE e dizia ok), cria admin_get_profile_changes.
2) supabase/migrations/20261111180100_aprovar_account_update_pelo_nucleo.sql — md5 29e4a8b30b8adad9cf4c7151a8083a0e, 3794 bytes. Remendo por âncoras do ramo ACCOUNT_UPDATE de admin_approve_action (guarda a definição antiga em bkp_fn_admin_approve_action_20261111; idempotente). Só aceita chaves name/full_name/phone.
3) Só depois: juntar ai/2026-11-11-editar-perfil a autonomous-night-2026-04-29 (app: botão Editar perfil + EditProfileScreen + AuthStore.editClientProfile/syncClientContactFromServer; painel: Histórico de mudanças do perfil). Sem as migrações o botão Guardar falha.
4) Depois de publicado nas 3: Bloco 4 — GENERAL_FAQ (support_skills c5f57484…) linha "Mudar nome ou telemóvel" passa a "Perfil → Editar perfil", mantendo o ACCOUNT_UPDATE.

PROVAS: PGlite 25 cenários verdes (.claude/.ai/reports/editar-perfil-2026-11-11/prova_sql_pglite.saida.json); flutter test editar_perfil_cliente 4/4, l10n_cobertura verde; analyze sem avisos novos. Depois de aplicar, conferir: select proname from pg_proc where proname in ('client_update_my_profile','_apply_user_profile_change','admin_get_profile_changes'); e strpos(pg_get_functiondef('public.admin_approve_action(uuid)'::regprocedure),'_apply_user_profile_change')>0.

FEITO EM PRODUÇÃO (dados, com backup): GENERAL_FAQ v1->v2 (bkp_support_skills_general_faq_20261111), DRIVER_FAQ v1->v2 (bkp_support_skills_driver_faq_20261111), chunk e925387a (bkp_support_knowledge_chunks_nav_20261111).

ARMADILHA: a app lê o nome do cliente do metadata do login (bora_name), não de public.users. A mudança à mão de hoje (ACCOUNT_UPDATE 3687d72f) só mexeu em users — a cliente ainda vê o nome antigo na app. Não se mexeu na conta dela (ordem do Danilo). A versão nova sincroniza ao abrir.

Relatório: .claude/.ai/reports/editar-perfil-2026-11-11.md
