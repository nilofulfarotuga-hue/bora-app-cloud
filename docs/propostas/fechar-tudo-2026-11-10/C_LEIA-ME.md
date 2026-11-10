# Bloco C — prova sem dinheiro real da diferença de peso no cartão

Missão fechar-tudo-2026-11-10. Autorizações do Danilo para esta funcionalidade: "Autorizo" de 26/10 e de 02/11 (cobrar a diferença do peso no cartão) e 10/11 ("8 tem que fazer"). Pedido literal: "Prova ponta a ponta em teste: melancia a mais → cobra a diferença; a menos → devolve; cartão recusado → pedido não trava e fica dívida visível no painel. Com as provas verdes, liga o interruptor."

Ramo `ai/2026-11-10-fechar-tudo-c`. Nada foi publicado nem aplicado em produção por este agente.

## 1. O que se descobriu: "a menos" vai para a carteira, não para o cartão

Lido em produção a 10/11/2026 (`pg_get_functiondef` de `finalizar_talao_nao_parceiro`): quando o pedido foi pago com cartão ou MB Way e o peso real sai mais barato, o talão credita a diferença na **carteira Bora** do cliente (`wallet_transactions`, `kind = refund_credit_free`, motivo `storeshopping_v2_peso_variavel`, chave de idempotência `v2_peso_<pedido>`) e marca os ajustes como `carteira`. **Não há devolução parcial na Stripe** em nenhum sítio do código (nem na função, nem nas Edge). É a regra de 26/10 (`docs/contexto/03-regras-de-negocio.md`, peso variável: "cartão/MB Way mais barato → carteira"), e o aviso ao cliente já diz "Saiu mais barato: a diferença vai para a tua carteira Bora no fim".

O mesmo mecanismo (crédito na carteira dentro do talão) já correu em produção para produtos em falta: 1 linha `storeshopping_v2_unavailable_items` em `wallet_transactions`. Ajustes de peso em produção até hoje: 0 (`order_weight_adjustments` vazia).

Por isso, no ensaio, o caso "a menos" prova que o cartão **não é mexido** e que a decisão do talão é "carteira". Se o Danilo quiser que o "devolve" seja no cartão (devolução parcial na Stripe) em vez da carteira, é uma decisão nova de dinheiro — ver "PARA O DANILO" no fim.

## 2. O que este bloco faz

- `supabase/functions/_shared/peso_cartao.ts` (novo): o código da cobrança passou para aqui — ler o cartão e o cliente do pagamento original e cobrar off_session; sem cartão, banco a pedir autenticação ou cartão recusado → "a Bora assume". Tem também a decisão do talão (cópia fiel do ramo do SQL). O pedido real e o ensaio usam **o mesmo código**.
- `supabase/functions/cobrar-diferenca-peso/index.ts`: o pedido real passa a usar esse código (as mesmas mensagens e respostas de antes). Uma melhoria pequena: se a Stripe já cobrou e depois o banco falhar a gravar, já não se marca "a Bora assume" por engano — fica registado no `e2e_log` (`gravar_pedido`) para o admin acertar.
- `supabase/functions/cobrar-diferenca-peso/ensaio.ts` (novo): o **modo ensaio**. Pedido `{ "ensaio": true, "caso": ... }`, só com a chave de servidor. Usa **só** `STRIPE_TEST_SECRET_KEY_EMPRESA`; se faltar, grava "falta a chave de teste" e pára; se a chave lá dentro não começar por `sk_test_`/`rk_test_`, recusa-a. Funciona com o interruptor desligado. Não lê nem escreve `orders`, carteiras nem dinheiro: grava o resultado em `ensaio_peso_cartao`.
- `supabase/migrations/20261110220000_ensaio_peso_cartao.sql` (novo): a tabela `ensaio_peso_cartao` (RLS ligada, só admin lê) e a RPC `admin_ensaio_peso_cartao(p_caso)` (só admin; manda o pedido à Edge com a chave do cofre `service_role_key`, a mesma porta que o talão usa para a cobrança real).
- Painel admin (PT-BR), ecrã **Ajustes de peso**: secção "Ensaio do cartão (modo de teste da Stripe)" com 4 botões e a lista dos resultados (OK / FALHOU / ERRO). No **detalhe do pedido**, a secção "Ajustes de peso" mostra agora em vermelho "Ficou por cobrar: X € — a Bora assumiu" quando a diferença não foi cobrada.

Os casos do ensaio (melancia de 10,00 €):

| caso | cartão de teste da Stripe | tem de dar |
|---|---|---|
| `a_mais` | `pm_card_visa` (4242…), guardado para off_session como no checkout real | `cartao_cobrado` (2,50 € cobrados off_session no mesmo cartão) |
| `a_menos` | `pm_card_visa` | `carteira` (1,80 €; o pagamento original fica intacto, nada cobrado nem devolvido no cartão) |
| `recusado` | `pm_card_chargeCustomerFail` (4000 0000 0000 0341: guarda-se no cliente, recusa qualquer cobrança) | `bora_assume` |
| `pede_autenticacao` | `pm_card_authenticationRequired` (4000 0027 6000 3184: o banco pede sempre autenticação) | `bora_assume` |

Nos dois cartões que recusam, o pagamento original de teste fica criado sem confirmar (esses cartões recusam qualquer cobrança, até a primeira): serve só para o código real ler dele o cartão e o cliente, como faz com um pedido.

## 3. Ordem para publicar (o líder, numa janela)

1. **SQL**: aplicar `supabase/migrations/20261110220000_ensaio_peso_cartao.sql` com o mesmo nome (`apply_migration` nome `ensaio_peso_cartao`, versão 20261110220000). Prova: as 3 linhas comentadas no fim do ficheiro (`relrowsecurity = true`; `anon` sem `execute`; tabela vazia).
2. **Edge `cobrar-diferenca-peso`** (hoje versão 8, `verify_jwt = true`, publicada a 02/11 06:35 a partir do commit 171733e8 — o repo não está atrás do ar). Publicar a pasta inteira com os partilhados: `index.ts`, `ensaio.ts`, `../_shared/peso_cartao.ts` (novo), `../_shared/keys.ts`, `../_shared/chaves.ts`, `../_shared/stripe_contas.ts` (estes três sem mudanças). Manter `verify_jwt = true`. Prova logo a seguir: o vigia das chaves (`{"ping":true}` com a chave de servidor) tem de responder `{"pong":true}`, e um pedido real com o interruptor desligado continua a dar `{"ok":false,"error":"desligado"}`.
3. **App** (só o painel admin muda): vai na publicação normal (web do painel + as lojas, como sempre). Ficheiros: `lib/screens/admin/admin_ensaio_cartao_peso_section.dart` (novo), `lib/screens/admin/admin_ajustes_peso_screen.dart`, teste `test/admin_ensaio_cartao_peso_test.dart`.

## 4. Como o Danilo põe a chave de teste (um passo, com a página aberta)

Stripe da **EMPRESA** ("Bora", Unipessoal Lda, `acct_1UX67LGWwQxC9wR2`) → ligar o **modo de teste / sandbox** (interruptor no topo) → **Programadores** → **Chaves de API** → copiar a **chave secreta de teste** (começa por `sk_test_`) → Supabase do projeto `ojykpzwqrtusfeakzrna` → **Edge Functions** → **Secrets** → novo segredo com o nome exato `STRIPE_TEST_SECRET_KEY_EMPRESA` e o valor copiado → guardar.

Nunca a chave `sk_live_`: o ensaio recusa-a e grava "a chave não é de teste". Nunca colar a chave no chat nem em ficheiros. Não é preciso republicar a Edge depois de pôr o segredo.

Enquanto a chave não existir, carregar num botão grava uma linha **ERRO — "Falta a chave de teste: STRIPE_TEST_SECRET_KEY_EMPRESA…"**. Isto já prova a porta (RPC → cofre → Edge → tabela) antes de haver chave.

## 5. As provas (todas sem dinheiro real)

Pelo painel: **Ajustes de peso → Ensaio do cartão** → carregar nos 4 botões, um de cada vez; o resultado aparece em poucos segundos. Têm de ficar os 4 a **OK**:

- Melancia a mais → "Esperado: cartão cobrado · Deu: cartão cobrado", com `pi_… → pi_…`.
- Melancia a menos → "Deu: carteira Bora (cartão não mexido)".
- Cartão recusado → "Deu: a Bora assume (pedido segue)".
- Banco pede autenticação → "Deu: a Bora assume (pedido segue)".

Pelo SQL (o líder, sem o painel), simulando o admin só dentro da transação:

```sql
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'nilofulfarotuga@gmail.com'), 'role', 'authenticated',
                    'email', 'nilofulfarotuga@gmail.com', 'app_metadata', json_build_object('role', 'admin'))::text, true);
select public.admin_ensaio_peso_cartao('a_mais');
select public.admin_ensaio_peso_cartao('a_menos');
select public.admin_ensaio_peso_cartao('recusado');
select public.admin_ensaio_peso_cartao('pede_autenticacao');
commit;
-- uns 20 segundos depois:
select caso, estado, esperado, resultado, pi_original, pi_extra, erro, detalhe->>'erro_codigo' as codigo
  from public.ensaio_peso_cartao order by criado_em desc limit 4;
-- e a resposta crua da Edge, se alguma não aparecer:
select id, status_code, left(content::text, 300) from net._http_response order by created desc limit 4;
```

Tem de dar: `a_mais ok cartao_cobrado` (com `pi_extra`), `a_menos ok carteira` (sem `pi_extra`), `recusado ok bora_assume` (código `card_declined`), `pede_autenticacao ok bora_assume` (código `authentication_required`). Prova extra: no painel da Stripe da empresa **em modo de teste** → Pagamentos, aparecem os pagamentos de 10,00 € e o de 2,50 € com a descrição "Bora — diferença de peso do pedido ensaio-…" e metadata `ensaio = peso_cartao`. No modo real não aparece nada.

**"O pedido não trava"** (prova pelo código, não pelo ensaio): no talão (`finalizar_talao_nao_parceiro`, produção), a cobrança é um `net.http_post` sem esperar resposta, e logo a seguir o pedido passa a `onTheWay` ("6) Segue direto para a entrega"). Quando a cobrança falha, a Edge só mexe em `order_weight_adjustments.settled_via = 'bora_assume'`, manda o aviso URGENTE ao porteiro e escreve no `e2e_log`; nunca toca no estado do pedido. **"Dívida visível no painel"**: o detalhe do pedido mostra "Ficou por cobrar: X € — a Bora assumiu" (teste de widget `detalhe do pedido: a diferença que a Bora assumiu fica à vista`), e o ecrã Ajustes de peso já somava "Bora assumiu X € (n)".

## 6. Só depois das 4 provas a OK: ligar o interruptor

Pelo painel: **Configurações da plataforma → `weight_adjust_card_charge_enabled` → ligado** (é a RPC `admin_update_setting`, que regista no log de admin). Pelo SQL, a mesma RPC como admin (nunca UPDATE direto):

```sql
begin;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'nilofulfarotuga@gmail.com'), 'role', 'authenticated',
                    'email', 'nilofulfarotuga@gmail.com', 'app_metadata', json_build_object('role', 'admin'))::text, true);
select key, value from public.admin_update_setting('weight_adjust_card_charge_enabled', 'true'::jsonb);
commit;
select value from public.platform_settings where key = 'weight_adjust_card_charge_enabled';  -- true
```

Desligar é o mesmo com `'false'::jsonb`. Dinheiro e MB Way ficam como estão (o MB Way nunca é cobrado outra vez; a menos vai sempre para a carteira).

Vigiar nos primeiros pedidos ao quilo pagos com cartão:

```sql
select order_id, settled_via, sum(delta_client_cents) from public.order_weight_adjustments
 where settled_at > now() - interval '7 days' group by 1, 2 order by 1;
select fluxo, passo, estado, detalhe, created_at from public.e2e_log
 where fluxo = 'cobrar-diferenca-peso' order by created_at desc limit 20;
```

## 7. Testes corridos neste PC

- `deno test --allow-read supabase/functions/_shared/peso_cartao_test.ts supabase/functions/cobrar-diferenca-peso/ensaio_test.ts` → **16 passed, 0 failed** (decisão do talão; a mais; sem cartão; requires_action; recusado; os 4 casos do ensaio; falta chave; chave real recusada; o ramo do ensaio não usa a chave real nem `orders`; defeito plantado: se o cartão que devia recusar for cobrado, o ensaio dá FALHOU).
- `deno check supabase/functions/cobrar-diferenca-peso/index.ts` → sem erros.
- `test/admin_ensaio_cartao_peso_test.dart` (Flutter) **não foi corrido**: pouca memória no PC (ordem da missão: não correr flutter). Tem de passar no Juiz/CI antes de publicar.

## PARA O DANILO

"A menos → devolve": hoje devolve-se para a **carteira Bora** (regra de 26/10), nunca para o cartão. Se quiseres que volte ao cartão, é uma mudança de dinheiro nova e precisa do teu "autorizo".
