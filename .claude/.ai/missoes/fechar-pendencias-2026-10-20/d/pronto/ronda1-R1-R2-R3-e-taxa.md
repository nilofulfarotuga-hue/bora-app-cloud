# Bloco D · ronda 1 — R1, R2, R3 e a taxa de serviço do prémio (21/10/2026)

Nada disto está aplicado. O orquestrador transmitiu o "Vai" do Danilo (21/10 06:15Z, MISSAO.md e e2e_log 4087)
para R1, R2 e R3 "só se for mesmo preciso", com a ordem de **não aplicar ainda**: o revisor vê primeiro.
A taxa de serviço do prémio e o acerto da loja **não** estão no "Vai": continuam proposta.

Saídas literais das provas: `../prova_rollback_resultado.txt` (secções "Ronda 1").

---

## R1 — `create_order` aceita o `user_id` de outra pessoa

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

**O buraco (provado hoje, desfeito):** o cliente demo A chama `create_order` com `user_id` = cliente demo V e o
pedido fica no nome de V (`C_R1_hoje_pedido_normal_em_nome_de_V: dono_e_V true`). Pelo mesmo caminho desconta-se
a carteira de V (`wallet_debit_for_order(v_user_id…)`). Para os vales do check-in já está tapado pelo gatilho da
ronda 1 (`B_A_usa_vale_de_V: checkin_premio_de_outra_pessoa`, vale de V continua `por_usar`).

**A mudança:** 1 linha da `create_order` (linha 70), mesma assinatura:

```sql
-- antes
  v_user_id := COALESCE((p_input->>'user_id')::UUID, auth.uid());
-- depois
  v_user_id := CASE
                 WHEN auth.uid() IS NULL
                   OR public.is_admin()
                   OR COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
                 THEN COALESCE((p_input->>'user_id')::UUID, auth.uid())
                 ELSE auth.uid()
               END;
```

**Quem chama `create_order` (procurado no repo e na base, 21/10):**

| Quem | Sessão | Manda `user_id`? | Com o R1 |
|---|---|---|---|
| App (cliente, `order_store.dart:994`) | cliente | não (o `rpcInput` não tem `user_id`) | igual: dono = quem está ligado |
| Edge `finalize-order-from-intent` (cartão) | `service_role` | sim, o do rascunho de pagamento | igual: dono = o do rascunho |
| Testes e2e (`scripts/e2e/helpers/orders.py`) | `service_role` | sim | igual |
| Painel, robôs, favores, TVDE | ninguém chama `create_order` (0 funções na base, 0 no painel) | — | — |

As versões instaladas da app não mandam `user_id`, por isso não mudam.

**Prova (desfeita), a linha nova numa função temporária, em cada tipo de sessão:**
cliente A manda V → fica A; A sem `user_id` → fica A; A manda o próprio → fica A; admin manda V → fica V;
servidor (`service_role`) manda V → fica V; sem sessão manda V → fica V.

**Porque não provei a função inteira trocada:** a Trava deste PC (`protege-banco.sh`, regra 4) recusa qualquer SQL
que tenha DDL e o nome `create_order` no mesmo texto. Não se contorna. A prova de ponta a ponta está pronta em
`R1_prova_para_quem_aplica.sql` (troca a linha dentro da transação, faz os 5 pedidos demo e desfaz tudo).

**Ficheiros:**

| Ficheiro | md5 |
|---|---|
| `R1_aplicar.sql` (cópia em `bkp_fn_create_order_20261021`, confere o md5 de antes, troca a linha, confere que o resto ficou igual byte a byte) | d05fcbda3394c4c18886621b13ba816c |
| `R1_reversao.sql` (repõe a cópia e confere o md5) | 066ee8848b1f4ab1e052d724b3a9e5c2 |
| `R1_prova_para_quem_aplica.sql` | 583d11d24b9e10c39190369d3222cfe7 |

md5 de `create_order` ANTES (21/10): `8688fcf8b22429246079ec873d076fd8` (33 257 caracteres; a linha-âncora aparece 1 vez).

---

## R2 — o cliente muda o estado do seu pedido diretamente

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

(Mexe em quem pode mudar o estado de um pedido, zona protegida; é o que abriu a F1.)

**O que a app faz de facto (lido no código e medido na base):** a app do cliente só faz 2 mudanças, e nunca num
pedido de restaurante parceiro: `created → preparing` e `preparing → callingDriver`
(`order_store.dart`, `_simulateRestaurantFlow`). Em `order_status_events` (21/10), as únicas mudanças feitas pelo
próprio cliente foram exatamente estas 2 (restaurante não-parceiro, compras, favores; 6+6+4+4+4+4 vezes).
Cancelar vai pela Edge `client-cancel-order` (servidor); aceitar, recolher e entregar são da loja e do estafeta.

**A mudança:** um gatilho `BEFORE UPDATE OF status` em `orders` que só olha para escritas diretas pela API
(`current_user` = `authenticated`/`anon`) feitas pelo dono do pedido, sem ser admin, estafeta ou loja desse
pedido; deixa só as 2 mudanças da app. Não mexe em políticas, colunas nem dados. As funções e as Edge do
servidor, o admin, a loja e o estafeta ficam como estão.

**Prova (desfeita), as funções e o gatilho criados dentro da transação, decisão testada com linhas em memória:**

| Caso | Recusa? |
|---|---|
| cliente, não-parceiro, created→preparing / preparing→callingDriver | não |
| cliente, favor e compras de loja parceira, created→preparing | não |
| **ataque** cliente delivered→rejected / delivered→cancelled / created→delivered | **sim** |
| **ataque** cliente, restaurante parceiro, created→preparing (isso é da loja) | **sim** |
| cliente cancela direto (a app usa a Edge) | sim |
| mesmo estado | não |
| estafeta do pedido (mesmo sendo o cliente) pickedUp→onTheWay, onTheWay→delivered | não |
| loja do pedido (mesmo sendo a cliente) created→preparing | não |
| admin; servidor (`service_role`) | não |

Permissões: sem sessão não chama nada; o gatilho só corre dentro do `UPDATE`.

**Porque não fiz o `UPDATE orders` de verdade:** a bora-tranca não deixa um agente escrever `UPDATE` em `orders`.
A prova de ponta a ponta (estafeta recolhe → 1 linha; cliente põe `rejected`/`delivered` → 42501; cliente muda as
notas → 1 linha; admin cancela → `cancelled`) está pronta em `R2_prova_para_quem_aplica.sql`.

**Ficheiros:**

| Ficheiro | md5 |
|---|---|
| `R2_aplicar.sql` | 4609f433caa9378ed011e6e0928f17f9 |
| `R2_reversao.sql` (desligar já numa linha, ou tirar de vez) | 561c8c4972e82119131d58e6ca238c88 |
| `R2_prova_para_quem_aplica.sql` | 62c4290748dd237f8dfab4eaf6cdd44c |

ANTES (21/10): não existe `trg_pedido_estado_cliente_guarda` nem as 3 funções (`r2_no_ar 0`, `r2_funcoes 0`).

**Outro buraco que vi pelo caminho (não está no "Vai", fica reportado):** o cliente também pode escrever
diretamente `payment_status` e `cash_total_due` no seu pedido (a guarda `enforce_financial_immutability` não as
protege). Ex.: pôr `paid` num MB Way por pagar, ou baixar o valor a cobrar em dinheiro. A app do cliente não
escreve nenhuma das duas. Proposta para outra ronda: congelar essas 2 colunas para escritas diretas do cliente,
como o R2 faz ao estado.

---

## R3 — a loja vê "2 Salgados Grandes" num pedido a 0 €

**Afeta o prémio?** Já não. Desde a ronda 1, qualquer artigo que mencione `premio-checkin-` (em qualquer campo)
exige um vale válido do próprio cliente (provado: `A_sem_vale_product_id → checkin_premio_sem_vale`), e os artigos
de um pedido já criado não ganham prémios novos. A loja vê o nome do prémio ("Prémio Bora Todo Dia: 2 Salgados
Grandes") a 0 €, que é o que deve ver: entrega os salgados e a Bora paga-lhe pela lista "A pagar às lojas".

**O buraco geral continua (não é do prémio):** a `create_order` cobra pelas `product_lines` e guarda os `items` à
parte; se o id da linha não existir, usa o preço que o cliente manda. Mandando `items` verdadeiros e
`product_lines` com um id inventado a 0 €, a loja vê o artigo e o pedido sai a 0 €.

**Medido a 21/10:** nos 48 pedidos reais dos últimos 120 dias (restaurante e compras), 0 artigos sem id e 0 ids que
não existam em `products`. Isto quer dizer que uma regra "id de linha tem de existir no catálogo da loja e bater
com os artigos" não partiria nenhum pedido real.

**Não preparei a migração:** não é preciso para o prémio, e mexe na conta do preço da `create_order` (o ciclo das
`product_lines`), que é maior e mais arriscada que o R1. Fica como próximo passo, com estes números.

---

## Taxa de serviço do prémio (NÃO está no "Vai")

**⚠️ Isto mexe em pagamento/dinheiro, e ainda NÃO está pronto a aplicar:** só o desenho. O SQL escreve-se
depois de o Danilo decidir, porque mexe na conta que cobra.

Hoje o cliente não paga taxa de serviço sobre o prémio: a taxa é 5 % do produto e o produto conta 0 €.
Com a regra "como num pedido normal", pagaria **0,32 €** na Keli (5 % de 6,30 €) e **0,46 €** no Goola
(5 % de 9,22 €).

Não há maneira de o fazer sem mexer na `create_order` e na `quote_order_pricing` (as duas calculam a taxa por
`pricing_calculate(tipo, subtotal…)`; o prémio entra com subtotal 0). Desenho: logo a seguir à conta
(`create_order`, depois da linha 522 `END IF;`), somar à taxa de serviço a diferença entre a taxa calculada com o
valor de balcão dos vales usados no pedido e a taxa atual; o mesmo na `quote_order_pricing`, para o carrinho
mostrar o mesmo número. Patch por âncora, como o R1, com cópia e prova.

---

## Resumo para o revisor

- Nada aplicado. `create_order` com o md5 de antes; `trg_pedido_estado_cliente_guarda` não existe.
- R1 e R2: aplicar, reverter e provar estão em ficheiros com md5. A prova de ponta a ponta de cada um corre-se
  antes de aplicar (a Trava e a tranca não me deixam a mim).
- R3: não preparado, de propósito (o prémio não precisa); números medidos acima.
- Taxa: só desenho, à espera do Danilo.
