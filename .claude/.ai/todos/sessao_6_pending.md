# Sessão 6 — Pendências 6-α

Lista de TODOs adiados durante a Sessão 6 (Avaliações por Estrelas, 2026-05-07).
Não-críticos para lançamento — não bloqueiam BR §44.

## DB / Backend

- **Trigger AVG running average** — actual recalc full em cada INSERT/UPDATE/DELETE.
  Para volume > 100k ratings considerar increment-only via `delta_sum + delta_count` no trigger
  e divisão lazy. Risco actual: scan O(N) por evento.
- **Tags configurable via `support_settings`** — actualmente hardcoded em
  `lib/models/rating_model.dart` (`RatingTags.positive` + `negative`). Considerar
  mover para JSON em `support_settings` por `subject_type` para A/B testing
  e i18n futura.
- **Moderação automática resposta partner** — `restaurant_respond_to_rating`
  apenas valida ownership + comprimento. Adicionar verificação de palavrões
  via lista DB (`badwords_pt`) ou Gemini moderation API.
- **Audit trail completo flagging** — gravar histórico de flag/unflag em
  `admin_audit_log` (já existe a tabela). Hoje só guarda último flagged_at/by.
- **Reply admin a rating** (suporte) — RPC `admin_respond_to_rating` análogo a
  `restaurant_respond_to_rating` mas com origem visível ("Resposta da equipa Bora").

## Flutter / UI

- **PartnerPushService** — registar `restaurants.fcm_token` via FCM no parceiro:
  - Refactor `RestaurantDashboardScreen` de `StatelessWidget` para `StatefulWidget`
  - `WidgetsBinding.instance.addPostFrameCallback` no `initState`
  - `FirebaseMessaging.instance.getToken()` → UPDATE em `restaurants` para o
    `email` do partner logado
  - Setup deep-link tap (`onMessage` + `onMessageOpenedApp`) → `Navigator.pushNamed('/partner/ratings', arguments: { restaurant_id, restaurant_name })`
  - Pattern: copiar `lib/services/admin_push_service.dart` (5F-β)
- **Upload foto opcional rating** — coluna `photo_url` em ratings + storage bucket
  `rating-photos` + RLS (rater write own; público read se `is_private=false`)
- **Filtro categoria em `RestaurantRatingsListScreen`** — chips Top/Recente/
  "Comida boa"/"Embalagem"/etc. (queries client-side aos `recent[]` retornados)
- **Diff lado-a-lado para resposta partner** (admin flagging) — mostrar comentário
  original + resposta lado-a-lado em AlertDialog
- **Estrelas em RestaurantsScreen card** — usar widget `RatingStarsBadge` criado
  e mostrar mesmo quando `avgRatingFor()` é null (placeholder "Sem avaliações")

## Documentação

- Atualizar `bora_app/.obsidian-vault/regras/§44_avaliacoes.md` (cópia de §44 do
  business_rules.md) — fonte secundária para CEO-AI/skills

## Próxima sessão

- **Sessão 7** — Validações finais + UUID refactor (BUG 39) — ~6-8h
- **5F-β-β** — Refactor 7 cron jobs scrapers BROKEN (decisão pendente)
