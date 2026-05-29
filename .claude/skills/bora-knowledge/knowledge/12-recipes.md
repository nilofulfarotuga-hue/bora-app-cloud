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

## Fontes adicionais
- `.claude/.ai/knowledge/decisions/` (formato ADR das decisões).
- CEO-AI `SKILL.md` §6 (protocolo de orquestração) e §9 (auto-atualização de contexto).
