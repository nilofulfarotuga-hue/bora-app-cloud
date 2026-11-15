# Parceiro rejeita reserva paga → a Bora devolve os 3 € (fechar-tudo-15-11)

Ordem: "Autorizo tudo" do Danilo (15/11 15:15), passada pela Claude.ai às 15:21. Não trava a
publicação de hoje. Feito no ramo `ai/2026-11-15-app`, sem publicar, sem SQL aplicado, sem
chamadas à Stripe.

## O que estava errado (lido no servidor, só SELECT, 15/11)

- A RPC `partner_decide_reservation(p_reservation_id, p_accept=false, p_reason)` só faz
  `status = 'rejected_refunded'` e manda ao cliente "O parceiro não pôde aceitar a sua reserva.
  Reembolso em curso." Não há devolução na Stripe, nem trigger em `reservations` que a faça
  (triggers lidos: late_cancel, noshow, finished, seated, notify_new, convidado_so_ve).
- A app do parceiro (Reservas PRO, `lib/screens/partner/reservations/partner_reservations_screen.dart`)
  dizia "O pré-pagamento de €3 será reembolsado ao cliente." e "Reserva rejeitada e reembolsada.".
  O ecrã antigo `lib/screens/partner_reservations_screen.dart` (já sem ligação no menu) dizia
  "Reserva rejeitada — reembolso automático.".
- Hoje há 0 linhas em `reservations` (SELECT por estado), portanto não há clientes por reembolsar.

## O que foi feito

| Ficheiro | O quê |
|---|---|
| `supabase/functions/partner-reject-reservation/index.ts` | Edge nova (ligação ao Supabase e à Stripe) |
| `supabase/functions/partner-reject-reservation/logica.ts` | Toda a lógica, sem rede |
| `supabase/functions/partner-reject-reservation/logica_test.ts` | 28 testes Deno com Stripe/base falsas |
| `lib/stores/partner_reservas_store.dart` | `rejectReservation(...)`, `RecusaReserva`, `RecusaReservaFalhou` |
| `lib/screens/partner/reservations/partner_reservations_screen.dart` | "Rejeitar" usa a Edge; textos verdadeiros |
| `lib/screens/partner_reservations_screen.dart` | o mesmo no ecrã antigo |
| `lib/l10n/strings_en.dart` + `tool/l10n/traducoes/pt-en-39-reserva-recusa-reembolso.json` | 11 frases novas com inglês |
| `test/reserva_recusa_reembolso_test.dart` | testes da app e da Edge lida pela fonte |

## Como a devolução funciona, passo a passo

1. A app chama a Edge com `{ reservation_id, reason }` e o token do parceiro — só quando a reserva
   tem pré-pagamento (`prepayment_cents > 0` ou `prepayment_pi`). Sem pré-pagamento continua a RPC
   de sempre (faz o mesmo e não há dinheiro).
2. A Edge confirma o token no Auth (`auth.getUser(token)`), lê a reserva com a chave do servidor e
   verifica que quem chama é o dono do restaurante (`restaurants.user_`, a mesma regra da RPC).
   Não sendo dono: 403 e nada muda.
3. Reserva `pending` → chama a mesma RPC `partner_decide_reservation(p_accept=false)` com o token
   do parceiro (muda o estado e avisa o cliente, como hoje).
4. Pagamento conferido na Stripe, na conta onde entrou (`reservations.stripe_account`,
   `stripeDaLinha`): `paymentIntents.retrieve` tem de ter `metadata.purpose =
   'reservation_prepayment'` e `metadata.reservation_id` = esta reserva, e estar `succeeded`.
5. Lista as devoluções já feitas desse pagamento e devolve só o que falta:
   `refunds.create({ payment_intent, amount, metadata }, { idempotencyKey: 'reserva-recusa-<id>' })`.
6. Regista em `admin_audit_log` (ação `reservation_partner_reject_complete`, os mesmos campos do
   `admin-cancel-reservation` + `partner_user_id`). Se a devolução não saiu, avisa a equipa no
   painel: `notify_admin_event('reservation_refund_failed', 'high', ...)`, com o que fazer.
7. Responde `{ success, idempotent, reservation_id, new_status, refund: { result, amount_cents,
   amount } }`; `result` = `succeeded` · `already_refunded` · `not_applicable` · `not_paid` ·
   `failed`. A app mostra a frase certa para cada um.

Diferenças em relação ao `admin-cancel-reservation`, de propósito: (a) dono verificado no
servidor; (b) novas tentativas seguras (abaixo); (c) o valor e o pagamento vêm da Stripe e não das
colunas da reserva, porque a RLS deixa o cliente mudá-las (achado 1); (d) aviso à equipa quando
falha, porque o parceiro não consegue refazer.

## Idempotência (nova tentativa)

- Reserva já `rejected_refunded` (resposta perdida, ou devolução que falhou): a RPC não corre outra
  vez; vê o que a Stripe já devolveu e devolve só a diferença. Se já está tudo, `already_refunded`.
- A chave `reserva-recusa-<id>` faz a Stripe responder com a mesma devolução em 24 h; depois disso,
  a lista de devoluções (passo 5) impede a segunda.
- Corrida entre duas chamadas: se a outra rejeitou, segue como nova tentativa; se aceitou, 409.
- Provado nos testes "duas chamadas seguidas: uma devolução só", "nova tentativa depois de a
  Stripe falhar", "corrida…".

## O que a Claude.ai tem de publicar

- Edge **`partner-reject-reservation`**, com os ficheiros `index.ts` e `logica.ts` (o
  `logica_test.ts` não vai) e os partilhados `../_shared/keys.ts`, `../_shared/chaves.ts`,
  `../_shared/stripe_contas.ts`. Com a CLI: `supabase functions deploy partner-reject-reservation`.
- `verify_jwt`: o mesmo da `admin-cancel-reservation` (não está no `config.toml`, portanto o
  padrão). A função valida o utilizador por dentro, funciona com `true` ou `false`.
- Segredos (só nomes; todos já existem para o `admin-cancel-reservation`): `SUPABASE_URL`,
  `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEYS` (ou `SUPABASE_SERVICE_ROLE_KEY`),
  `STRIPE_SECRET_KEY`, `STRIPE_SECRET_KEY_EMPRESA` (modo teste: `BORA_STRIPE_MODE=test` com
  `STRIPE_TEST_SECRET_KEY` e `STRIPE_TEST_SECRET_KEY_EMPRESA`).
- Nenhuma migração é precisa.
- Prova depois de publicar, sem dinheiro: POST com o token de um parceiro e
  `reservation_id` inventado → `404 {"error":"reservation_not_found"}` (a função existe e lê a
  base); sem token → `401 {"error":"missing_token"}`. Até lá, a app mostra "Esta parte ainda não
  está instalada; tenta mais tarde ou fala com a equipa Bora." e a reserva NÃO é rejeitada.

## Provas desta sessão

- `deno test --no-check --no-lock supabase/functions/partner-reject-reservation/logica_test.ts` →
  28 passed, 0 failed.
- `deno check` de `logica.ts` e `logica_test.ts` → sem erros.
- `deno lint` da pasta → só `no-import-prefix` (imports `https:`), igual a todas as outras Edges.
- Varredura igual à do `test/l10n_cobertura_test.dart` nos 3 ficheiros Dart mudados → 13 frases
  com `.tr`, 13 com inglês. Cada frase nova aparece uma só vez no `strings_en.dart`.
- `flutter analyze` / `flutter test` não corridos aqui (ordem da missão): ficam para o CI do ramo.

## Achados pelo caminho (não corrigidos — para a Claude.ai decidir)

1. **RLS de `reservations` deixa o cliente mudar dinheiro e estado da própria reserva.** A política
   `reservations_client_owner` é `FOR ALL` (`client_user_id = auth.uid()`, RLS ligada) e
   `authenticated` tem UPDATE em todas as colunas, incluindo `prepayment_pi`, `prepayment_cents`,
   `stripe_account` e `status`. Um cliente pode pôr a reserva em `pending` sem pagar, ou apontar
   `prepayment_pi` para o pagamento de um pedido. A Edge nova defende-se (confere a metadata na
   Stripe), mas o `admin-cancel-reservation` confia nessas colunas: um admin pode devolver o
   pagamento errado. Proposta: tirar o UPDATE ao cliente nessas colunas (ou passar a política a
   SELECT/INSERT e as mudanças a RPCs) e conferir a metadata também no caminho do admin.
2. **`client_confirm_reservation_payment` usa a coluna `updated_at`, que não existe em
   `reservations`.** Qualquer chamada falha; só o webhook confirma pagamentos de reserva.
3. **O aviso ao cliente da RPC diz "Reembolso em curso" mesmo sem pré-pagamento.** O texto está no
   SQL da RPC; proposta: só dizê-lo quando `prepayment_cents > 0`.
4. **Apps antigas dos parceiros continuam a rejeitar pela RPC, sem devolução,** até atualizarem.
   Para apanhar esses casos (só leitura):
   ```sql
   select r.id, r.prepayment_cents, r.decided_at
   from reservations r
   where r.status = 'rejected_refunded' and r.prepayment_pi is not null
     and not exists (select 1 from admin_audit_log a
                     where a.entity_id = r.id
                       and a.action in ('reservation_partner_reject_complete',
                                        'reservation_cancel_complete'));
   ```
   Cada linha devolve-se pelo painel de pagamentos (`admin-payments`, ação `refund`) ou chamando
   a Edge nova com a sessão do parceiro.
5. **Painel:** o tipo de aviso novo `reservation_refund_failed` aparece como "Aviso:
   reservation_refund_failed" até ter nome em `rotulosPorTipo`
   (`lib/screens/admin/admin_notifications_inbox_screen.dart`); sugestão "Reembolso de reserva
   falhou". Ficheiro fora do âmbito desta tarefa.
6. **`admin-cancel-reservation`:** numa segunda chamada sobre uma reserva já cancelada sai logo
   (`idempotent`) e não volta a tentar uma devolução que tenha falhado.
