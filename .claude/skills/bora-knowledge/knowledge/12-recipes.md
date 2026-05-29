# 12 — Receitas (passo-a-passo)

> Operações comuns. Cada receita assume leitura prévia de [10-protected-zones](10-protected-zones.md).

## Receita 1 — Adicionar categoria à home
Ver detalhe em [02-home-categories.md](02-home-categories.md). Resumo:
1. PNG em `assets/images/categories/` (+ pubspec se preciso).
2. Gradient novo em `app_colors.dart` (se preciso; respeitar 1 laranja/ecrã).
3. Garantir Screen de destino.
4. Adicionar descritor (`label`/`gradient`/`imageAsset`/`onTap`) em `client_home_screen.dart`.
5. `flutter analyze` + smoke visual.

## Receita 2 — Criar widget `bora/` novo
1. Ficheiro `bora_app/lib/widgets/bora/bora_xxx.dart`; classe `BoraXxx extends StatelessWidget`.
2. Consumir tokens `AppColors.*` / `AppTheme.*` (zero hex).
3. Construtor com `required` mínimos + defaults sensatos.
4. Exportar no barrel `bora.dart`.
5. Documentar em [04-widgets-bora.md](04-widgets-bora.md).

## Receita 3 — Alterar um design token global
1. Editar **só** `app_theme.dart` (base) ou `app_colors.dart` (semântico).
2. Propagar é automático (ecrãs usam tokens). Verificar contraste/regra 1 laranja.
3. `flutter analyze`. Atualizar [01-design-system.md](01-design-system.md).
4. Mudança visual ampla → confirmar com Danilo (estrutural).

## Receita 4 — Banir / reativar entidade (driver/parceiro/cliente)
- Driver: colunas `is_banned`, `banned_at/by`, `banned_until`, `ban_reason_code`, `ban_reason`.
  Reativar = limpar `is_banned=false` + `banned_until=NULL`. Forçar logout: Edge Fn `admin-force-driver-logout`.
- Parceiro/restaurante: `approval_status` + `is_active_admin`. Soft-disable via `is_active_admin=false`.
- ⚠️ Operação admin/segurança → confirmar (Validation Gate). Preferir RPC/Edge Fn admin a SQL cru.

## Receita 5 — Rever candidatura de estafeta
1. Listar `drivers WHERE approval_status='pending'`.
2. Conferir documentos (`document_photo_url`, `vehicle_doc_url`, `registration_selfie_url`, `iban`, `nif`, `license_plate`).
3. Aprovar: `approval_status='approved'`, `approved_at/by`. Rejeitar: `'rejected'` + `rejection_reason`.
4. Fazer via painel admin / RPC dedicada (não SQL cru em prod). Push ao estafeta conforme decisão.

## Receita 6 — Atualizar um platform_setting
1. Ler atual: `SELECT key, value, description FROM platform_settings WHERE key='<key>'`.
2. **Confirmar com Danilo** (é regra de negócio).
3. Atualizar: `UPDATE platform_settings SET value='<jsonb>'::jsonb, updated_at=now() WHERE key='<key>'`.
4. Validar que `PricingService`/Edge Fns leem o novo valor (sem cache stale).
5. Registar a decisão em `.claude/.ai/knowledge/decisions/{data}-{slug}.md`.

## Receita 7 (bónus) — Onboardar parceiro
Usar a skill apropriada:
- Restaurante → `onboard-partner-restaurant`
- Loja → `onboard-partner-store`
- Farmácia → `onboard-partner-pharmacy`
Todas: dry-run default, leem esta bora-knowledge, chamam `register-partner` + `upload-restaurant-asset`.

## Receita 8 — Banir/reativar um CLIENTE (vive no Auth, não em `users`)
Descoberta S2 (MCP): a tabela `users` **não tem** colunas de ban (`is_banned`, etc.).
O ban de cliente vive no **Supabase Auth**:
1. Banir: `PUT {SUPABASE_URL}/auth/v1/admin/users/{user_id}` com `{"ban_duration":"<Nh>"}`
   (service_role no `Authorization`+`apikey`). Permanente ≈ `"876000h"`; temporário = horas até à data.
2. Reativar: mesmo endpoint com `{"ban_duration":"none"}`.
3. **Listar banidos**: consultar `GET /auth/v1/admin/users` (campo `banned_until`) — **não** a tabela `users`.
4. Registar sempre em `admin_audit_log` (a app pode não refletir o ban, pois não há coluna).
- Skill: `ban-or-reactivate-entity --type client`. ⚠️ Pendência: considerar coluna `is_banned` em `users`.

## Receita 9 — Banir/reativar um PARCEIRO (via `is_active_admin`)
`restaurants` **não tem** colunas de ban — só `is_active_admin` (descoberta S2):
1. Banir/desativar: `UPDATE restaurants SET is_active_admin=false WHERE id=:id`.
2. Reativar: `is_active_admin=true`.
3. Razão/código/until **não têm coluna** → guardar em `admin_audit_log.details` (JSONB).
4. Bloquear se houver pedidos em curso (`orders.status IN preparing/callingDriver/driverAccepted/pickedUp/onTheWay` por `restaurant_id`).
- Skill: `ban-or-reactivate-entity --type partner`. ⚠️ Pendência pré-launch: migration p/ colunas
  `is_banned/banned_at/banned_by/ban_reason_code/ban_reason/banned_until` em `restaurants`.
- Driver, por contraste, **tem** todas as colunas + enum `ban_reason_code` (fraud, misconduct,
  documents_invalid, inactivity, safety, other).

## Receita 10 — Padrão de audit log (`admin_audit_log`)
Toda ação administrativa destrutiva (aprovar/rejeitar/banir/reativar/force-logout) regista 1 linha:
- Colunas: `admin_id`(uuid), `admin_email`, `action`, `entity_type`, `entity_id`(uuid) **ou**
  `entity_id_text`(TEXT — usar p/ `restaurants`/`orders`), `details`(jsonb), `ip_address`, `created_at`.
- `admin_id`/`admin_email` vêm do env `BORA_ADMIN_USER_ID`/`BORA_ADMIN_EMAIL` (escrita via service_role).
- Pôr **contexto rico** em `details` (reason, reason_code, until, previous_status, mechanism).
- Edge Fns admin (ex.: `admin-force-driver-logout`) já escrevem a sua própria linha — não duplicar.
- Helper de referência: `_shared.audit_log(ctx, action, entity_type, entity_id, details, text_id=…)`
  nas skills S2.

## Fontes adicionais
- `.claude/.ai/knowledge/decisions/` (formato ADR das decisões).
- CEO-AI `SKILL.md` §6 (protocolo de orquestração) e §9 (auto-atualização de contexto).
