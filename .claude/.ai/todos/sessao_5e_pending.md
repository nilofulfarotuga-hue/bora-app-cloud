# 5E TODOs adiados

## Técnicos imediatos

- **Histórico real de playbooks**: criar `support_skills_history` com
  versioning monotonic. Rollback recria entry em vez de decrementar.
  UI timeline de versões. (Hoje: `version = GREATEST(version-1, 1)`
  é frágil se houver múltiplos updates intercalados.)
- **Diff visual proper**: biblioteca diff em Flutter (ex.
  `diff_match_patch`) substitui o split anterior/novo actual em
  caixas vermelha/verde.
- **Auto-approve para SAFE com threshold confiança**: Danilo configura
  ex. `>0.85 confidence → auto-aprovar`. Requer Gemini retornar score.
- **Rollback `new_skill`**: confirmar com Danilo, DELETE skill +
  marcar `rolled_back`. Hoje requer SQL manual.
- **Auditoria histórica**: dashboard de approvals/rejections com
  user_id, timestamp, taxa por tipo/zona. `reviewed_by` já capturado.
- **Métricas**: rate aprovação por `proposal_type`, `zone_type`,
  tempo médio até aprovação, % que sofrem rollback.
- **Edge Fn truncate detection**: avisar UI quando playbook >8K tokens
  for truncado por Gemini `maxOutputTokens=8192`.
- **Settings `support_email` / `whatsapp_number`**: hoje CRITICAL.
  Considerar whitelist controlada com confirmação dupla (re-type).

## Próximas sessões

- **5F** — Comunicação Robô A ↔ Robô B (~4h)
- **5G** — Painel admin inbox propostas avançado (~3h)
- **Sessão 6 ORIGINAL** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor BUG 39 (~6-8h)

## Limitações conhecidas (5E v1)

- `version` decrement em rollback não monotonic
- `TextField` simples para diff (sem syntax highlight)
- `new_skill` rollback via DELETE manual
- Token output Gemini = 8192 (playbooks >8K truncados)
- Sem auto-approve threshold
- Sem dashboard de métricas

## Notas decisão

- `OTP_RESEND` mantido em `CRITICAL_SKILLS` array hardcode mesmo
  não existindo na DB — defensivo, futureproof se for criada.
- `chatbot_welcome_text` é o nome real (não `welcome_text` do plano).
- `whatsapp_number`/`support_email` classificados CRITICAL (canais
  contacto cliente — mudança equivale a quebrar suporte).
- Retorno RPC `admin_approve_skill_suggestion` mudou de `uuid`→`jsonb`
  (BREAKING, mas Flutter 5D ignorava retorno → sem regressão).
