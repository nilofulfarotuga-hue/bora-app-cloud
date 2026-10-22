# Provas — limpeza semanal só chama depois de pago (19/10/2026)

Missão `limpeza-semanal-pagamento-19-10`. Autorização do Danilo (19/10/2026, literal):
"autorizo arrumar as limpezas semanais" + "Pode" + "o divã tem que fazer o pagamento do MBA.
E aí tem que chegar a notificação no telemóvel dele, no MBA dele, para ele fazer o pagamento."
Sem dados pessoais neste ficheiro (sem telefone, sem email): só ids.

RAM medida antes de começar: 2326 MB disponíveis (leve). Antes do `flutter analyze`: 3727 MB.

## Bloco 1 — Supabase (migração `20261019100000_limpeza_semanal_so_chama_depois_de_pago.sql`)

Aplicada pelo MCP (`apply_migration` → `{"success":true}`). Leitura de volta:

```
colunas=3  gate_oferta=true
gatilho="CREATE TRIGGER trg_cleaning_paid_offer AFTER UPDATE OF payment_status ON public.cleaning_bookings FOR EACH ROW EXECUTE FUNCTION _trg_cleaning_paid_offer()"
cron="20 * * * * SELECT public._cleaning_cron_unpaid_retry(); active=true"
anon_pode(cleaning_request_payment)=false   authenticated_pode(_cleaning_cron_unpaid_retry)=false
```

Prova do gatilho em transação desfeita (DO + RAISE — nada ficou gravado, ninguém foi chamado):

```
ROLLBACK_PROVA | mbway por pagar -> offer=NULL oferecidas=0
               | depois de held -> offer=8b4c0aa9-ca16-4bc1-b88f-a071a8468dd9 oferecidas=1
               | dinheiro -> offer=8b4c0aa9-ca16-4bc1-b88f-a071a8468dd9
sobras da prova na tabela (stripe_payment_intent_id='pi_teste_rollback'): 0
```

Conta da série (âncora = 1.ª reserva, sáb 10/10 13:30 Lisboa):

```
hoje: ultima=seg 19/10 08:45, 2 reservas          k=2 -> Sat 24/10 13:30 (12:30 UTC, hora de verão)
depois do fix: ultima=sab 24/10 13:30, 3 reservas k=3 -> Sat 31/10 13:30 (13:30 UTC, hora de inverno)
reagendada p/ tras: sex 16/10, 2 reservas         k=2 -> Sat 24/10 13:30 (sem repetir 17/10)
reagendada p/ quarta 21/10, 2 reservas            k=2 -> Sat 24/10 13:30
```

## Bloco 2 — Edge `cleaning-request-payment` (v1, verify_jwt=true, só servidor)

```
chave do servidor (cofre), reserva em dinheiro -> 200 {"ok":false,"error":"not_mbway"}   (não tocou na Stripe)
sem Authorization                              -> 401 UNAUTHORIZED_NO_AUTH_HEADER
chave anon (JWT legado)                        -> 403 {"ok":false,"error":"forbidden"}
```

## Bloco 3 — dados do Divan

Cópia antes: `public.bkp_cleaning_bookings_divan_20261019` (2 linhas, RLS ligada).

```
UPDATE df044ec2 -> status=scheduled, scheduled_at=2026-10-24 12:30:00+00 (24/10 13:30 Lisboa),
                   cleaner_id=null, offer_cleaner_id=null, requested_cleaner_id=8b4c0aa9…, unpaid
cleaning_request_payment(e7cc0ba4) -> {"ok":true,"tentativa":1,"request_id":49983}
  Edge -> 200 {"ok":true,"paymentIntentId":"pi_3USC8aGlT3R2jCYp123HfcbM","status":"requires_action","amountCents":3240,"tentativa":1,"telefone":"stripe"}
cleaning_request_payment(df044ec2) -> {"ok":true,"tentativa":1,"request_id":49985}
  Edge -> 200 {"ok":true,"paymentIntentId":"pi_3USC8nGlT3R2jCYp0WaYAcjP","status":"requires_action","amountCents":3240,"tentativa":1,"telefone":"stripe"}
logs da Edge (08:41:45 / 08:41:58 UTC):
  [cleaning-request-payment] e7cc0ba4… tentativa=1 amount=€32.40 status=requires_action pi=pi_3USC8aGlT3R2jCYp123HfcbM telefone=stripe mode=live
  [cleaning-request-payment] df044ec2… tentativa=1 amount=€32.40 status=requires_action pi=pi_3USC8nGlT3R2jCYp0WaYAcjP telefone=stripe mode=live
```

Avisos na app: Mayra (a de 26/10 08:45 voltou a sáb 24/10 13:30, recebe o pedido quando o
pagamento entrar) e Divan (2 pedidos MB Way de 32,40 €).

Resultado na Stripe (lido com a Edge só-leitura `diag-pagamento-limpeza`, 08:50 UTC):

```
pi_3USC8aGlT3R2jCYp123HfcbM  requires_payment_method  3240  kind=cleaning booking=e7cc0ba4… origem=pedido_automatico
   last_payment_error: payment_method_customer_decline / generic_decline
   "The customer did not approve the PaymentIntent."
pi_3USC8nGlT3R2jCYp0WaYAcjP  requires_payment_method  3240  kind=cleaning booking=df044ec2… origem=pedido_automatico
   last_payment_error: payment_method_customer_decline / generic_decline
pi_3UOcSJGlT3R2jCYp0vPMImzB  succeeded  3240  kind=cleaning booking=d70666d1… (a de 10/10, a única paga)
stripe-webhook: 2x payment_intent.payment_failed às 08:46:35 UTC — "booking fica unpaid (retry possível)"
```

Ou seja: o pedido chegou à Stripe e ao MB Way; o Divan não aprovou (recusou ou deixou expirar —
a Stripe dá o mesmo código aos dois casos). As duas reservas continuam `unpaid`; a de sábado volta
a ser pedida pelo cron (12 h depois, até 4 vezes) e o admin é avisado a menos de 24 h.

## Bloco 4 — painel e app

- `flutter analyze` aos 3 ficheiros: só 2 avisos antigos (Radio `groupValue`/`onChanged`, linhas
  141/143, código anterior). Nenhum erro.
- `flutter test --no-pub test/l10n_cobertura_test.dart`: `All tests passed!` (13).
- Juiz, chão anti-trapaça (`--base HEAD`): `✅ CLEAN`.

## Revisor de contexto limpo (maker/checker)

Confirmou: nenhum caminho chama a profissional antes de pago; série e mudança da hora certas
(31/10 13:30 Lisboa = 13:30 UTC); `anon` não chama; utilizador sem ser admin leva 42501; a Edge
só aceita o servidor. Achados e o que se fez:

| Achado | Feito? |
|---|---|
| Cron/painel podiam juntar 2 pedidos no telemóvel | **Sim** — Edge v2 recusa se a Stripe já tem um `requires_action` (ou pago) dessa reserva |
| Telefone escolhido pelos tipos aceites, não pelo tipo usado | **Sim** — v2 usa `payment_method.type === 'mb_way'` |
| Mensagem de erro da Stripe podia levar o telefone aos logs | **Sim** — v2 mascara sequências de 6+ dígitos |
| Nome do ficheiro ≠ versão aplicada | **Sim** — ficheiro renomeado para `20261019083907_…` |
| Painel dizia "chega ao celular" antes de se saber | **Sim** — passa a dizer "disparado" |
| Aviso ao admin quando a oferta falha depois de pago | **Não** — 2.ª migração bloqueada pela tranca |
| Série de teste podia mandar MB Way real (não copia `is_test_order`) | **Não** — idem |
| Séries com cartão: nascem por pagar e ninguém cobra | **Não** — idem (aviso ao admin); cobrança automática do cartão nem estava pedida |
| Pedidos MB Way do cron de noite | **Não** — idem (proposta: só 09:00–21:00 Lisboa) |
| Botão "Pagar com MB Way" do cliente cria pedido em paralelo ao automático | **Reportado** — `cleaning-checkout` é lista vermelha |
| Pagamento aprovado depois de cancelar fica `held` e sem estorno | **Reportado** — webhook/`confirm_cleaning_payment_webhook` são zona de pagamento |
| Reagendar a 1.ª reserva da série arrasta as seguintes | **Reportado** — âncora pedida pela ordem; corrigir pede coluna própria |
| `20261010073000_limpeza_duas_voltas_de_ofertas.sql` nunca foi aplicada (sem `offer_rounds` em produção) e substitui `_cleaning_next_offer` | **Reportado** — se alguém a aplicar, apaga a trava do pagamento e o `aceita_papel` |

Edge v2 no ar (versão 2) — testes sem tocar em dinheiro:

```
servidor + reserva em dinheiro (46eba5a8)  -> 200 {"ok":false,"error":"not_mbway"}
servidor + reserva já paga (d70666d1)      -> 200 {"ok":false,"error":"not_unpaid","payment_status":"released"}
chave anon                                 -> 403 {"ok":false,"error":"forbidden"}
```

O caminho "já há um pedido à espera → não cria outro" foi verificado por leitura e `deno check`,
não ao vivo (só há reservas reais por pagar; testar criava um MB Way real).

## Tranca

`bora-tranca: BLOQUEADO Write — migration que toca tokens/wallet/pagamentos/ledger` na 2.ª
migração. O padrão de conteúdo (`zonas-vermelhas.json` → `migracoes.padrao_conteudo`) apanhou a
palavra *Stripe* nos comentários; o SQL só mexe em `cleaning_bookings` e em funções de limpeza.
Não foi contornado. Proposta para o Danilo: o padrão ignorar comentários SQL (`--` e
`COMMENT ON … IS '…'`) antes de procurar as palavras.
