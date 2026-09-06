---
id: fix-parceiro-gerir-loja-reconfirmacao-2026-08-01
data: 2026-08-01
tipo: reconfirmacao
dominio: parceiro-servicos
estado: atual
---

# Reconfirmação: bug "parceiro-serviços preso em Submetido para Análise" — JÁ RESOLVIDO

## Tarefa recebida
Prompt idêntico (mesmo salão de teste `022bf907-c433-467d-a883-c5b74c25e00f`,
mesma descrição, mesma exigência de relatório em
`fix-parceiro-gerir-loja-2026-07-18.md`) ao já executado em 2026-07-18.
Padrão conhecido de tarefa duplicada no loop autónomo (ver memória
`project_cadastro_parceiro_senha_ja_resolvido_5x`,
`project_juiz_hash_texto_caminho_ja_resolvido`).

## Verificação feita nesta sessão (não reinvestiguei do zero)
1. `git log --oneline --follow -- lib/screens/pending_approval_screen.dart`
   → topo é `e36495a fix(parceiro-servicos): reconsulta approval_status
   fresco antes de navegar`.
2. `git branch -a --contains e36495a` → aparece em `autonomous-night-2026-04-29`
   (local) **e** em `remotes/origin/autonomous-night-2026-04-29` — o fix está
   publicado, não só local.
3. `git status --short` nos 3 ficheiros envolvidos
   (`pending_approval_screen.dart`, `partner_entry_screen.dart`,
   `partner_appointments_store.dart`) → vazio, sem alterações pendentes.
4. Li o código atual dos 3 ficheiros e confirmei que a lógica descrita no
   relatório de 2026-07-18 está intacta em HEAD (`aeed47f`, muitos commits
   depois de `e36495a`):
   - `_PartnerNoRestaurantRouter.initState()` chama sempre
     `loadMyProvider(force: true)`.
   - `loadMyProvider(force: true)` ignora o cache (`_provider`) e faz sempre
     um `SELECT` fresco em `service_providers WHERE user_id = auth.uid()`.
   - O gate decide por `provider.approvalStatus` (`approved`→
     `PartnerServicesHubScreen`, `pending`→`PendingApprovalScreen`,
     `rejected`/outro → cai para o fluxo de `restaurants`).
   - `PendingApprovalScreen._handleManageStore` reconsulta
     `PartnerAppointmentsStore.loadMyProvider(force: true)` (ou
     `RestaurantStore.ownRestaurantApprovalStatus` para categoria
     restaurante) antes de navegar; só avança para o hub se `approved`.

## Conclusão
Nada para corrigir — o bug já não existe em HEAD. Não fiz commit nem push
(sem alterações de código; commitar/push vazio seria ruído). O relatório
original (`fix-parceiro-gerir-loja-2026-07-18.md`) mantém-se válido e
completo — não foi reescrito.

## Nota para o próximo agente
Se este mesmo pedido chegar uma terceira vez, repetir só os 4 passos de
verificação acima (grep/git log) em vez de reler todo o código — já foi
confirmado 2x sem drift.
