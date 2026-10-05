# Pronto a aplicar — o que ficou atrás da Trava (ronda 04/10, preparado a 05/10/2026)

Esta pasta guarda o que a ronda de 04/10 deixou por fazer em zonas que a Trava
proíbe a qualquer agente (`.claude/HOOKS.md`: `permissions.deny` + `protege-dinheiro.sh`
+ `protege-banco.sh`; e o plugin `bora-mods`). O Danilo deu a ordem a 05/10
("autorizo tudo"), mas a Trava foi desenhada para só abrir pela mão dele — por isso
nada aqui foi aplicado. Está tudo preparado e provado até onde se pode provar sem
publicar.

Quem aplicar precisa de uma sessão onde a Trava esteja aberta para estes caminhos
(o Danilo tira as linhas do `deny`/do gancho, ou a sessão corre onde eles não
existem, por ordem dele). Não é para contornar daqui.

---

## 1. Motor de despacho v62 — `dispatch-engine-v62/`

**O que muda (duas coisas, mais nada):**

1. **Quem pode chamar o motor.** Hoje qualquer pessoa na internet o pode acordar
   (`verify_jwt=false` e nenhuma verificação). Passa a aceitar só: a chave de
   serviço (a do ambiente ou a do cofre do banco, validada na Auth e guardada em
   memória), um admin, um estafeta aprovado, o dono do pedido, ou o dono da loja do
   pedido. É a autenticação do `notify-driver` v42 (já no ar) mais os papéis com que
   a app chama o motor. `verify_jwt` continua `false`.
2. **Quem recebe a oferta.** Os candidatos passam a vir todos de
   `public.dispatch_candidatos_entrega(order_id)` (já no ar e provada a 04/10):
   batimento **e** GPS com menos de 900 s, uma oferta viva de cada vez, favor
   sozinho, máximo 3 pedidos, raio de 20 km, já ordenados (mesma loja primeiro,
   depois o mais perto). Saem do motor as consultas directas a `drivers` e
   `tvde_rides`, o raio preferido de 10 km e o cálculo de distância em JS.

Ofertas, tempo da oferta, TTL, claim, redispatch e identidade (v59) ficam iguais.

**Ficheiros:**

- `index.v62.PROPOSTA.ts` — o ficheiro inteiro, pronto a copiar para
  `supabase/functions/dispatch-engine/index.ts`.
- `v61-para-v62.diff` — o que muda, linha a linha (+89 / −59).
- `gerar_v62.mjs` — como a proposta foi feita: a partir do ficheiro do repo, por
  âncoras exactas (cada uma tem de existir uma vez, senão aborta). Volta a gerar
  com `node gerar_v62.mjs <raiz-do-repo>`.
- `simular_v62_test.ts`, `supabase_falso.ts`, `mapa.json` — simulação: corre a
  proposta tal e qual, com base de dados falsa.
- `simulacao.saida.txt` — a saída: **14 passam, 0 falham**. O mesmo guião contra o
  v61 falha em 10 de 14 (é assim que se sabe que a prova prova alguma coisa).

**Base conferida a 05/10 07:05:** o que está no ar é a versão 61 (cabeçalho "v59"),
`updated_at` de 16/08; o ficheiro do repo tem as mesmas 338 linhas e 16 de 16
linhas distintivas do ar. A proposta parte dele.

**Quem chama o motor hoje (todos cobertos pela porta nova):**

- gatilhos e cron do banco (`invoke_dispatch_engine`, `fn_dispatch_on_calling_driver`,
  `bora_dispatch_maintenance`) — chave de serviço do cofre (`_dispatch_service_jwt()`);
- `stripe-webhook`, `finalize-order-from-intent` e o próprio motor (redispatch) —
  chave de serviço do ambiente;
- a app: estafeta ao ficar online (`driver_store.dart`), cliente/parceiro ao chegar
  a `callingDriver` (`order_store.dart`) — sessão do utilizador.

Uma chamada da app **sem sessão** (só a chave pública) passa a levar 403. Não deixa
nenhum pedido parado: o gatilho do banco chama o motor na mesma, com chave de serviço.

**Aplicar (3 passos):**

1. Copiar `index.v62.PROPOSTA.ts` para `supabase/functions/dispatch-engine/index.ts`.
2. Publicar `dispatch-engine` com **`verify_jwt=false`** (como está no ar).
3. Commit do ficheiro do repo, para o espelho ficar igual ao ar.

**Provar no ar (efeito, não invólucro):**

- sem token → 403; com a chave pública → 403;
- `select public.invoke_dispatch_engine('nao-existe');` e ler `net._http_response`:
  200 `{"ok":true}` (prova a chave do cofre pela porta nova);
- no primeiro pedido real, os registos da função mostram
  `[dispatch] N candidatos (de M, excl K)` e `SUCCESS order=… → driver=…`;
- um estafeta online com GPS parado há mais de 15 min **não** aparece nos candidatos
  (`select * from public.dispatch_candidatos_entrega('<pedido>')` como serviço).

**Voltar atrás:** publicar outra vez o ficheiro do commit `30855c27`
(`git show 30855c27:supabase/functions/dispatch-engine/index.ts`), `verify_jwt=false`.

**Risco que fica enquanto não se aplica** (do relatório do despacho): as ofertas
reais continuam com o matching antigo — estafeta com GPS parado pode receber
oferta, o mesmo estafeta pode ter várias ofertas ao mesmo tempo, e o motor
continua aberto a quem souber o endereço.

---

## 2. `lib/services/pricing_service.dart` — já não é preciso mexer

A ronda queria pôr `_nonPartnerPurchaseFee = 0.99` (está 2,50) e um ramo de
"ir buscar". Medido a 05/10:

- o cliente **já vê e paga 0,99 €**: o carrinho troca a taxa pela do servidor
  (`platform_settings.non_partner_service_fee_cents = 99`, com reserva 99 no
  `RemoteFeesService`), e o total vem do orçamento do servidor;
- o "ir buscar" já é tratado no `CartStore.pricingBreakdown`;
- o único sítio onde os 2,50 € antigos ainda contavam era a pré-verificação do
  limite de dinheiro no `createOrder`, quando o carrinho não lhe passava o total do
  servidor — passou a passar (05/10, `CartStore.finishOrder`).

Fica só como arrumação, para quando o ficheiro estiver aberto:

```diff
-  static const double _nonPartnerPurchaseFee = 2.5;
+  static const double _nonPartnerPurchaseFee = 0.99;
```

(e o comentário `// €2.50` na linha do `purchaseFee`). Não muda nada do que se cobra.

---

## 3. Favor — dinheiro da paragem em casa (`lib/widgets/errand_execution_sheet.dart`)

Hoje o telemóvel do estafeta escreve `orders.errand_home_stop_cash_cents` com um
UPDATE directo (linha ~263). É dinheiro e devia passar por uma função própria.
O ficheiro está trancado, por isso fica a proposta (POR CONFIRMAR os estados):

```sql
-- PROPOSTA — não aplicada. Mesmo efeito de hoje, com guarda.
create function public.estafeta_registar_dinheiro_paragem(p_order_id text, p_cents integer)
 returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare v_uid uuid := auth.uid(); v_n int;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_cents is null or p_cents < 0 then return jsonb_build_object('ok', false, 'error', 'valor_invalido'); end if;
  update public.orders o set errand_home_stop_cash_cents = p_cents
   where o.id = p_order_id and o.service_type = 'errand'
     and o.status in ('driverAccepted', 'pickedUp', 'onTheWay')
     and o.assigned_driver_id in (v_uid::text,
           (select d.id::text from public.drivers d where d.user_id = v_uid));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n > 0);
end $f$;
```

Na app, trocar o `.from('orders').update({...})` por
`rpc('estafeta_registar_dinheiro_paragem', params: {'p_order_id': o.id, 'p_cents': _cashReceivedCents})`.
Só depois de a app nova estar em todos os telemóveis é que se pode fechar a
escrita directa.

---

## 4. "Parceiro chama estafeta" — o fecho está errado (interruptor posto a 05/10)

**A regra (regras de negócio 2.4.1):** sempre em dinheiro. O estafeta paga à loja o
total (balcão + 10 % + 5 % + entrega) e cobra o mesmo ao cliente — fica a zeros. No
acerto, a Bora paga ao estafeta só a corrida; a loja fica com o preço de balcão e
deve à Bora os 10 % + 5 % + entrega.

**O que o fecho faz hoje** (`post_order_to_ledger`, lido a 05/10; o
`apply_order_financial_split` faz a mesma conta para a loja): trata-o como um
pedido normal de parceiro em dinheiro.

Exemplo: 10,00 € de balcão, 1 km → total 14,00 €, estafeta 4,00 €.

| | Certo | O que o fecho lança |
|---|---|---|
| Loja | fica com 10,00 (tem 14 em mão, deve 4,00 à Bora) | tem 14 em mão **e** recebe mais 8,57 → 22,57 |
| Estafeta | recebe 4,00 | ganho 4,00 e ajuste de dinheiro −10,00 → −6,00 |
| Bora | 0,00 | −2,57 |

Porquê: a parte da loja é sempre `partner_store_share(subtotal)` (aqui o subtotal
já é o balcão e a loja já recebeu tudo); e o ajuste de dinheiro do estafeta é
`−(total − ganho − adiantado)`, com `order_driver_reimbursement` a devolver 0
porque não há talão — quando ele adiantou o total à loja.

**O que tem de mudar** (missão própria, com prova em transacção desfeita antes):

- reconhecer o pedido (parceiro + `user_id` nulo + `order_type = partnerRestaurant`);
- estafeta: o que adiantou à loja = o total (o ajuste passa a dar o ganho a receber);
  ver também `apply_driver_cash_settlement`, que usa a mesma fórmula;
- loja: em vez de crédito, um débito de `total − subtotal` (10 % + 5 % + entrega);
- os extractos do parceiro (`extrato_parceiro`, `partner_my_weekly_closeout`,
  `partner_monthly_statement`, `partner_ganhos_resumo`, `partner_loja_recebe`) e o
  fecho semanal têm de mostrar essa dívida.

**O que ficou feito a 05/10:** interruptor `dispatch_parceiro_chama_estafeta_ligado`
(= `false`, visível no painel em Configurações → dispatch). Desligado, a função
`partner_chamar_estafeta` responde `indisponivel` e não cria pedido; a app nova diz
"ainda não está disponível". Zero pedidos destes existiam. Migração
`20261005061548_parceiro_chama_estafeta_interruptor.sql`; cópia da função em
`bkp_fn_partner_chamar_estafeta_20261005`. **Só ligar depois de o fecho estar certo.**

---

## 5. Achados de 05/10 que ficam para a missão do dinheiro (nada aplicado)

Vieram da revisão de contexto limpo e das provas no servidor; nenhum é da ronda de
04/10, por isso ficaram só registados.

- **Festas — o orçamento ainda conta o saco.** `quote_order_pricing` não conhece as
  festas e devolve 0,30 € de saco; o pedido perde-o no gatilho `trg_festas_no_bag`.
  Com cartão cobra-se o `payment_buffer_total` do orçamento (0,30 € a mais do que o
  pedido regista); com dinheiro e MB Way paga-se o do pedido. O carrinho e o
  pagamento mostram o do orçamento (nunca menos do que se cobra). Zero pedidos de
  festas até hoje. É a `20260825091000_festas_money_patch.sql`, por aplicar desde 25/08.
- **"Deixar à porta" com dinheiro.** O `create_order` grava o que lhe mandarem sem
  olhar ao método. A app nunca o manda com dinheiro (05/10); falta a guarda no
  servidor para pedidos forjados (um gatilho pequeno: dinheiro ⇒ `deixar_a_porta = false`).
- **Rascunhos de pagamento.** O painel nunca conseguiu excluí-los: `payment_drafts`
  só tem política de leitura. Desde 05/10 o ecrã diz a verdade e só regista o que
  saiu mesmo. Decidir: tirar o botão ou dar-lhe função própria de admin.
- **Sinal com segredo.** `driver_heartbeat_segredo` não exige `is_online` (o
  `driver_heartbeat_by_id` exige). Não mexe no despacho (o matching pede online),
  mas convém alinhar; e, quando todas as apps usarem o segredo, fechar o `_by_id` a
  quem não tem sessão.
- **Carrinho abandonado.** O aviso (desligado) não olha a quem aceitou promoções;
  a reativação olha (`reativacao_so_opt_in`). Decidir antes de ligar.
