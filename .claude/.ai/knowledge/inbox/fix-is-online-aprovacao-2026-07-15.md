---
data: 2026-07-15
tema: parceiro-restaurante / admin
estado: atual
---

# Fix: parceiro aprovado ficava sempre "Indisponível" (is_online=false)

## Causa raiz
`supabase/functions/register-partner/index.ts:242` cria o parceiro com
`is_online: false` explicitamente. A RPC `approve_partner` (definida em
`supabase/migrations/20260503030000_partner_approval_workflow.sql`) só mudava
`approval_status='approved'` — nunca tocava `is_online`. Resultado: parceiro
aprovado continuava com `is_online=false` para sempre, e
`RestaurantModel.statusLabel` (lib/models/restaurant_model.dart:231) mostra
"Indisponível" sempre que `isOnline=false`, mesmo com `business_hours`
configurado e dentro do horário.

Não havia nenhum ecrã admin que editasse `is_online` — só existia
`RestaurantStore.toggleRestaurantOnline` (chamado a partir do app do
**parceiro**, com efeito colateral de foreground service que não faz
sentido disparar a partir do admin).

## Correção

1. **`supabase/migrations/20260715120000_approve_partner_sets_online.sql`**
   — `CREATE OR REPLACE FUNCTION public.approve_partner`: adiciona
   `is_online = true` ao mesmo UPDATE que já define `approval_status =
   'approved'`. Loja aprovada passa a ficar automaticamente disponível.
   Mesma lógica de permissão/auditoria da função original, só o UPDATE
   mudou.

2. **`lib/screens/admin/admin_partner_detail_screen.dart`** — aba "Estado"
   ganhou um `SwitchListTile.adaptive` "Loja Online/Offline" no topo,
   independente do estado de aprovação, chamando o novo método
   `_setAdminIsOnline(bool)` (update directo em `restaurants.is_online`,
   mesmo padrão dos toggles já existentes `takeaway_enabled` /
   `curbside_enabled` no mesmo ficheiro — não reusa
   `RestaurantStore.toggleRestaurantOnline` para evitar disparar o
   foreground service do lado errado).

## Nota
`flutter analyze` / `flutter test` não puderam ser executados neste
ambiente (binário `flutter` não instalado no container headless). A
mudança segue exatamente o padrão de código já em produção no mesmo
ficheiro (`_setAdminTakeawayEnabled` / `_setAdminCurbsideEnabled`), pelo
que o risco de erro de compilação é baixo — recomenda-se `flutter analyze`
antes do próximo build de release.

Migration ainda **não aplicada em produção** (Supabase remoto) — só
commitada. Precisa de `supabase db push` (ou equivalente) para entrar em
vigor.
