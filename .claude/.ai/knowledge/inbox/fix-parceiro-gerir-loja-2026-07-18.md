---
id: fix-parceiro-gerir-loja-2026-07-18
data: 2026-07-18
tipo: fix
dominio: parceiro-servicos
estado: atual
---

# Fix: parceiro de serviços preso em "Submetido para Análise" pós-aprovação

## Sintoma reportado
Prestador de serviços (`service_providers` — beleza, barbearia, etc.) aprovado
pelo admin (`approval_status='approved'`, `is_active_admin=true`, `approved_at`
preenchido — confirmado via MCP no salão "corte teste",
`022bf907-c433-467d-a883-c5b74c25e00f`) continuava preso no ecrã "Submetido
para Análise" no app, e o botão "Gerir a Minha Loja" não levava à gestão da
loja. Acontecia para todas as categorias de prestador de serviços.

## Ficheiros tocados
- `lib/screens/partner_entry_screen.dart`
- `lib/screens/pending_approval_screen.dart`

## Causa exata
Duas causas, ambas no lado do app (o dado em `service_providers` já estava
correto):

1. **`PartnerEntryScreen` / `_PartnerNoRestaurantRouter`** — o router que
   decide entre mostrar o hub de gestão ou o ecrã de análise chamava
   `loadMyProvider()` (cache idempotente do `PartnerAppointmentsStore`) **sem
   `force: true`**, e a decisão original só verificava "existe uma linha em
   `service_providers`" — nunca o `approval_status` dessa linha. Se o
   provider tivesse sido lido uma vez (ex.: pré-aquecido no login) antes da
   aprovação do admin, ficava cacheado como `pending` para sempre na sessão,
   ou pior: qualquer linha existente (mesmo `pending`/`rejected`) dava acesso
   direto ao hub.
2. **`PendingApprovalScreen._handleManageStore`** (o botão "Gerir a Minha
   Loja") não fazia *nenhuma* consulta ao Supabase — apenas navegava sempre
   para `PartnerLoginScreen`/voltava atrás, sem nunca reconsultar se o
   parceiro já tinha sido aprovado.

## O que mudou
1. `_PartnerNoRestaurantRouter.initState()` agora chama sempre
   `PartnerAppointmentsStore.loadMyProvider(force: true)` — nunca confia em
   cache. O gate passou a decidir pelo `provider.approvalStatus` real:
   `approved` → `PartnerServicesHubScreen`; `pending` → `PendingApprovalScreen`
   (com a categoria certa); `rejected`/desconhecido → cai para a verificação
   equivalente em `restaurants` (mesmo padrão já existente para restaurantes),
   deixando o parceiro refazer candidatura em vez de lhe dar acesso.
2. `PendingApprovalScreen` passou a ser `StatefulWidget`. O botão "Gerir a
   Minha Loja" (`_handleManageStore`) agora:
   - Reconsulta o estado fresco: `RestaurantStore.ownRestaurantApprovalStatus`
     para categoria `restaurant`/null, ou
     `PartnerAppointmentsStore.loadMyProvider(force: true)` para as restantes
     categorias (beleza, loja, farmácia, supermercado).
   - Se `approved` → `SessionStore.setRole(UserRole.partner)` e
     `Navigator.popUntil(isFirst)`, deixando o `_RootNavigator`
     (`main.dart`) reconstruir e o `PartnerEntryScreen` entrar já no hub.
   - Se `rejected` ou ainda `pending` → mostra `SnackBar` em PT-PT explicando
     o estado, sem navegar.
   - Erro de rede → `SnackBar` genérico, sem travar o botão.

Confirmado via RLS (`supabase/migrations/20260608000002_appointments_rls.sql`,
policy `sp_select`) que o dono (`user_id = auth.uid()`) pode sempre ler a
própria linha em `service_providers` independentemente do `approval_status`,
por isso o `force: true` funciona mesmo antes da aprovação.

## O painel de gestão do prestador — já existia, só não era alcançado
`PartnerServicesHubScreen` (`lib/screens/partner/services/partner_services_hub_screen.dart`,
270 linhas) **já estava implementado e completo** antes deste fix — não foi
criado agora. Tem: Agenda, Gerir Serviços, Gerir Equipa, Financeiro,
fecho semanal, adicionar walk-in, bloquear horário, registo de push token,
logout quando é ecrã raiz. O bug nunca foi "painel em falta" — era só o gate
de navegação que nunca lá chegava.

## Verificação (fluxo mental)
Prestador `corte teste` com `approval_status='approved'`, `is_active_admin=true`:
1. Login → `PartnerEntryScreen` → `authStore.currentPartner != null`,
   `partnerRestaurant == null` (é prestador de serviços, não restaurante) →
   `_PartnerNoRestaurantRouter`.
2. `initState` dispara `loadMyProvider(force:true)` → SELECT fresco em
   `service_providers` (RLS `sp_select` permite via `user_id=auth.uid()`) →
   devolve a linha com `approval_status='approved'`.
3. `FutureBuilder` recebe `provider.approvalStatus == 'approved'` →
   `PartnerServicesHubScreen` — entra direto na gestão da loja.
4. Se o parceiro já estivesse preso no `PendingApprovalScreen` de uma sessão
   anterior (cache antigo) e carregar "Gerir a Minha Loja": reconsulta
   `loadMyProvider(force:true)` → `approved` → `setRole(partner)` +
   `popUntil(isFirst)` → `_RootNavigator` reconstrói → mesmo caminho acima.

`flutter analyze` nos dois ficheiros: **0 issues** (133.1s).

## Commit
```
99a5220 fix(parceiro-servicos): reconsulta approval_status fresco antes de navegar
2 files changed, 97 insertions(+), 15 deletions(-)
```
(branch `autonomous-night-2026-04-29`)

## Notas
- Não mexeu em dinheiro, pricing, dispatch nem admin (o fluxo de aprovação
  do admin já funcionava e não foi alterado).
- Estas alterações já estavam presentes na working tree (não commitadas) no
  arranque desta sessão — provavelmente de uma ronda anterior do loop
  autónomo interrompida antes do commit. Esta sessão verificou a lógica
  (RLS, stores, painel de destino), correu `flutter analyze` e fez o commit.
