# BLOCO D5 — Dois quadros novos no painel admin (2026-09-05)

Agente: `admin`. Missão: adicionar dois quadros PT-BR ao painel admin —
(1) avisos push que falharam nas últimas 24h, (2) marcações presas com botão
"libertar" que nunca mexe em dinheiro.

## Resumo do que ficou feito

Ambos os quadros foram **implementados e ligados ao banco em produção**
(`ojykpzwqrtusfeakzrna`), não apenas propostos — a MCP Supabase, que no
arranque da sessão parecia offline, respondeu normalmente assim que testada.

## 1) Quadro "Avisos que falharam"

- **Fonte de dados:** tabela `notification_failures` — **já existia**
  (criada em `20260718003000_cleaning_notifications_and_equipment.sql`),
  já usada por `_cleaning_notify_user()` (limpeza doméstica) e pelas funções
  do carwash (`20260827101000`, `20260827103000`). Não foi preciso criar
  tabela nova.
- **Achado de segurança corrigido (bónus, fora do pedido original mas
  bloqueava o quadro):** a tabela tinha **RLS desligada** e **GRANT total**
  (SELECT/INSERT/UPDATE/DELETE/TRUNCATE) a `anon` **e** `authenticated` desde
  a criação — qualquer pedido não autenticado conseguia ler, escrever ou
  **apagar a tabela inteira**. As funções que lá gravam são
  `SECURITY DEFINER` (correm com o privilégio do dono, não do chamador), por
  isso não precisavam desse grant. Corrigido na migration
  `20260904230000`: RLS ligada, grants revogados de `anon`/`authenticated`,
  só fica `SELECT` para `authenticated` sob a policy
  `notification_failures_select_admin` (`USING (public.is_admin())`).
- **Ecrã:** `lib/screens/admin/admin_notification_failures_screen.dart`.
  Lista as últimas 24h por defeito (pedido explícito), com seletor para
  7 dias / tudo. Mostra `source` (função que falhou), `kind`, `user_id`,
  `erro` (mensagem) e hora. Estado vazio explica a cobertura actual.
- **Gap documentado (não coberto ainda):** as Edge Functions `notify-client`,
  `notify-driver`, `notify-partner`, `notify-tvde-client`,
  `notify-tvde-driver`, `notify-service-provider`, `notify-washer`,
  `notify-chat-message`, `notify-purchase-finalized`,
  `notify-partner-low-rating`, `notify-admin-*` (13 funções em
  `supabase/functions/`) hoje só fazem `console.error(...)` quando o FCM
  falha — **não gravam em `notification_failures`**. Só limpeza e lavagem
  auto gravam. Ligar as 13 funções exigiria editar + fazer deploy de cada
  uma (trabalho maior, fora do orçamento deste bloco) — o ecrã já assume
  isso e avisa no estado vazio. Próximo passo sugerido: escolher 2–3 canais
  de maior volume (`notify-client`, `notify-driver`) e replicar o padrão
  `INSERT INTO notification_failures` já usado em `_cleaning_notify_user`.

## 2) Quadro "Marcações presas"

- **Fonte de dados:** tabela `reservations` já existente (Reservas PRO F1).
  Hoje está **vazia em produção** (0 linhas) — por isso o ecrã mostra
  "nenhuma marcação presa" ao vivo, o que é o comportamento correcto, não
  um bug.
- **Achado corrigido (bónus):** `reservations` tinha RLS ligada mas **só**
  policies de dono-cliente e de parceiro — **faltava policy de leitura para
  admin**. `admin_reservations_screen.dart` (ecrã pré-existente, não criado
  por mim) já fazia `.from('reservations').select()` directo e
  provavelmente devolvia vazio para o admin por causa disso. Corrigido com a
  policy `reservations_admin_read` (`USING (public.is_admin())`).
- **RPC de listagem:** `admin_stuck_reservations(p_minutes int default 60)`
  — devolve reservas em `pending`/`pending_payment` há mais de N minutos,
  com nome do restaurante via JOIN. `SECURITY DEFINER`, gated por
  `public.is_admin()`.
- **RPC de libertar — trava de dinheiro embutida na função, não só na UI:**
  `admin_release_stuck_reservation(p_reservation_id uuid, p_reason text)`.
  Só muda o estado para `cancelled_by_admin` quando
  **`prepayment_pi IS NULL`** (nenhum PaymentIntent Stripe associado à
  reserva — ou seja, nenhum dinheiro pode ter sido cobrado). Se a reserva
  já tiver um `prepayment_pi`, a função **recusa** com
  `requires_refund_manual_review` em vez de decidir sozinha. Toda chamada
  bem-sucedida grava em `admin_audit_log` via `log_admin_action`.
- **Ecrã:** `lib/screens/admin/admin_stuck_reservations_screen.dart`.
  Selector de janela (15min/1h/6h/1dia), cartão por reserva com estado do
  pagamento visível. Botão muda para "Ver aviso" quando há pagamento
  associado; ao clicar mostra diálogo **"⚠️ Confirmação necessária"**
  explicando que é dinheiro real e que a Trava não deixa decidir sozinho —
  exactamente o comportamento pedido na tarefa em vez de implementar
  reembolso.
- **Por que não usei a RPC `admin_cancel_reservation_on_behalf_of` já
  existente:** essa função (viva em produção, não documentada em nenhuma
  migration local — gap pré-existente do repo) marca o estado como
  `cancelled_refunded` com base numa janela de horas, mas **não chama a
  Stripe** — só promete o reembolso via texto de notificação. Reutilizá-la
  para "libertar" teria zona cinzenta de dinheiro sem eu saber quem
  realmente processa esse reembolso depois. Preferi escrever uma RPC nova,
  estreita, que só actua onde é matematicamente impossível haver cobrança
  (sem PaymentIntent).

## Ficheiros tocados/criados

- `supabase/migrations/20260904230000_admin_notif_failures_and_stuck_reservations.sql`
  (novo, **aplicado em produção** via MCP `apply_migration`, verificado com
  `execute_sql` depois — grants, policies e `security_type=DEFINER`
  confirmados).
- `lib/screens/admin/admin_notification_failures_screen.dart` (novo).
- `lib/screens/admin/admin_stuck_reservations_screen.dart` (novo).
- `lib/screens/admin/admin_dashboard_screen.dart` (editado): 2 imports +
  2 `_NavCard` novos — "Avisos que falharam" (secção notificações) e
  "Marcações presas" (secção reservas).

## Prova — `flutter analyze`

RAM disponível antes do analyze (portão pesado, 800 MB): **2016 MB** — acima
do portão, sem necessidade de libertar nada.

```
flutter analyze
...
215 issues found. (ran in 32.5s)
```

Todos os 215 são pré-existentes (outros ficheiros não tocados nesta missão —
`deprecated_member_use`, `use_build_context_synchronously`, etc.).
Confirmação isolada:

```
$ flutter analyze 2>&1 | grep -ci "error -"
0
```

Análise isolada aos 3 ficheiros tocados/criados, depois de um ajuste de
`const`:

```
flutter analyze lib/screens/admin/admin_notification_failures_screen.dart \
  lib/screens/admin/admin_stuck_reservations_screen.dart \
  lib/screens/admin/admin_dashboard_screen.dart
...
   info - Use 'const' with the constructor... admin_dashboard_screen.dart:258:14
1 issue found.
```

Esse único item (linha 258) é o `Scaffold` de "Acesso negado" — código
pré-existente, não tocado por esta missão (confirmado por leitura directa).
**0 erros, 0 warnings, 0 infos nos 2 ecrãs novos.**

## Verificação directa no banco (não confio no "devia estar aplicado")

```sql
-- grants de notification_failures depois da migration:
anon: apenas REFERENCES, TRIGGER (sem select/insert/update/delete/truncate)
authenticated: SELECT, TRIGGER, REFERENCES (sem insert/update/delete/truncate)
service_role/postgres: mantêm tudo (as SECURITY DEFINER continuam a gravar)

-- policies confirmadas:
notification_failures_select_admin | notification_failures | SELECT
reservations_admin_read            | reservations           | SELECT

-- RPCs confirmadas SECURITY DEFINER:
admin_stuck_reservations           | DEFINER
admin_release_stuck_reservation    | DEFINER
```

## Pendências / próximos passos sugeridos

1. Ligar `notify-client` e `notify-driver` (maior volume) a
   `notification_failures` — replicar o padrão já provado em
   `_cleaning_notify_user`. Não feito aqui por ser trabalho de edição +
   deploy de Edge Functions, fora do orçamento deste bloco.
2. `reservations` está vazia em produção agora — o quadro "Marcações presas"
   só mostra dados reais quando houver reservas paradas; testável
   criando uma reserva de teste com `admin_force_create_reservation`
   (`p_status='pending'`) e aguardando a janela.
3. Investigar por que `admin_cancel_reservation_on_behalf_of` marca
   `cancelled_refunded` sem chamar a Stripe — gap fora do escopo desta
   missão, mas relevante para `pagamentos-wallet`.

## PARA O DANILO

Nenhuma decisão de dinheiro pendente — a trava de "libertar" está na própria
função do banco, não só na tela, então nem o robô nem eu conseguimos
acidentalmente mexer em pagamento por aqui. Só um aviso: achei uma tabela
(`notification_failures`) que estava aberta a qualquer pessoa da internet
ler/escrever/apagar desde julho — já fechei (RLS + policy admin-only), mas
se quiser que eu faça uma varredura geral procurando outras tabelas com o
mesmo problema, é só pedir.
