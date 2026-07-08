---
tema: multipapel · escopo: projeto · estado: atual · atualizado: 2026-07-06
id: multipapel
tipo: conceito
origem: [tabelas drivers/cleaners (Supabase), driver_signup_screen.dart, branch autonomous-night-2026-04-29]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Vertical MULTIPAPEL (duplo-papel estafeta ⇄ limpeza)

> A **ponte** entre a vertical do estafeta/motorista (`drivers`) e a da limpeza doméstica
> (`cleaners`). LIVE e pushed na sessão de 2026-07-06 (branch `autonomous-night-2026-04-29`).
> Fechada por uma sessão que retomou um diagnóstico interrompido a meio da finalização.
> Ligações: `vertical-limpeza.md` (a outra ponta), registo de estafeta (fluxo único
> `driver_signup_screen`).

## O que É (regra) — `estado: atual`

- Um utilizador pode ter **DOIS papéis ao mesmo tempo** — estafeta/motorista (tabela `drivers`)
  **E** profissional de limpeza (tabela `cleaners`) — **SEM criar conta nova**.
- As duas tabelas são **independentes**, ambas ligadas por `user_id` ao **MESMO** auth user.
  **NÃO há exclusividade** entre papéis.
- O 2.º papel ganha-se com a **mesma conta autenticada**: `cleaner_apply` e
  `driver_register_or_update` já usam `auth.uid()`.

## Backend — migration `multirole_bridge` (APLICADA em prod) — `estado: atual`

- Ficheiro local: `supabase/migrations/20260706130000_multirole_bridge.sql`.
- Confirmada em prod via MCP `list_migrations` — registada como version **`20260706112654`**
  (nome `multirole_bridge`). ⚠️ O timestamp do ficheiro local (`...130000`) **difere** do version
  aplicado (`...112654`) — drift de naming menor; a migration **está aplicada**.
- Duas funções `SECURITY DEFINER`, **só leitura/derivação — NÃO toca dinheiro**
  (nada de tokens/pricing/Stripe). Verificado no ficheiro (2026-07-06):
  - `public.my_roles_summary()` → jsonb com `has_driver`, `driver_status`, `has_cleaner`,
    `cleaner_status`, `driver_profile`, `cleaner_profile` (name/phone/email/nif/photo_url).
    **`GRANT EXECUTE` a `authenticated`.** Usada nos cards de convite/troca e no **PREFILL**
    da candidatura ao 2.º papel.
  - `public.admin_user_role_flags(p_user_id uuid)` → jsonb `driver_status`/`cleaner_status`
    (**NULL = não tem esse papel**). Guarda `public._admin_op_guard()`. Usada como **BADGE**
    nas telas de aprovação admin (candidatura de estafeta / de limpeza).

## Camada Flutter — `estado: atual`

- `lib/services/roles_service.dart`:
  - classe `RolesSummary` — `fromJson`/`empty`, getters `driverApproved`/`cleanerApproved`/
    `cleanerPending`, campos `hasDriver`/`hasCleaner`/`driverStatus`/`cleanerStatus`/
    `driverProfile`/`cleanerProfile`.
  - função **pura** `crossRoleStateFor(String?)` → enum
    `CrossRoleCardState { invite, pending, active }`
    (null/rejected/desconhecido → `invite`; pending → `pending`; approved → `active`).
- Widgets: `lib/widgets/multirole_switch_card.dart`, `lib/widgets/admin_other_role_badge.dart`.
- Ecrã novo: `lib/screens/driver/driver_role_apply_screen.dart` (candidatura cross-role com
  prefill do **outro** perfil).
- Entradas/pré-preenchimento em: `cleaner_apply_screen.dart`, `cleaner_home_screen.dart`,
  `profile_screen.dart`.
- **Badges admin** em: `admin_driver_approval_screen.dart`, `admin_cleaning_cleaners_screen.dart`.
  **Paridade admin já coberta — PT-BR.**

## Cobertura de teste — `estado: atual`

- `test/multirole_test.dart` — **9 testes de lógica pura** (sem rede): 5 de `crossRoleStateFor`
  + 4 de `RolesSummary.fromJson`/`empty()`. Todos verdes (`flutter test` +9).

## Rasto git / gate — `estado: atual`

- Branch `autonomous-night-2026-04-29`, **PUSHED**. Após rebase por cima do CI
  `42b5472` (versionCode 366), os 4 commits (confirmados em `git log`):
  - `71acf43` — multipapel/1 (ponte cleaner→estafeta + prefill; "aplicado em prod").
  - `d47263b` — multipapel/2 (entrada de Limpeza ciente do papel no perfil).
  - `3fce028` — multipapel/3 (badge de duplo-papel nas telas admin, PT-BR).
  - `1e82434` — test(multipapel) (9 testes).
- **Gate do Juiz passou:** chão anti-trapaça CLEAN · `flutter analyze` 0 erros (0 novos nos
  ficheiros tocados) · `flutter test` +9.

## Ligações

- **`vertical-limpeza.md`** — a outra ponta da ponte (cadastro/KYC do `cleaner_apply`, tokens via
  `_cleaning_complete`, chat cliente↔profissional).
- **Registo de estafeta** — fluxo único `driver_signup_screen` (`AuthStore.registerDriverAsync`
  @Deprecated); `driver_register_or_update` usa `auth.uid()`, o que torna o 2.º papel possível.
