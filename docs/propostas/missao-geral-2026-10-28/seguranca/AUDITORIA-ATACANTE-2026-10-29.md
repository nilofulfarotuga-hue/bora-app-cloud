# Auditoria de atacante ao NOSSO app e site — 29/10/2026

> Missão `final-app-2026-10-29`, bloco 6.c. Agente `seguranca`. Só o nosso: `https://app.boraguarda.com`,
> o projeto Supabase `ojykpzwqrtusfeakzrna` e o código em `C:\BoraLocal\wt-missao-geral-28-10`. Nada de terceiros.
> Só leitura e preparação: nenhum ficheiro de `lib/` tocado, nenhum DDL/DML aplicado, nenhum deploy.
> Antes disto: `docs/seguranca/AUDITORIA-2026-10-21.md` (N4). O que lá ficou corrigido não se repete aqui.

## Resumo

| Gravidade | Achados | Tocam dinheiro |
|---|---|---|
| Alta | 6 | 6 |
| Média | 7 | 3 |
| Baixa | 7 | 0 |

Segredos no site publicado: **nenhum**. Tabelas de `public` sem RLS: **3** (as três são cópias `bkp_` de ontem).
S1 (chaves secretas de `platform_settings`): preparado e provado em transação desfeita; espera o líder.

## Como se testou, e o que NÃO se fez

- Bundle público: descarreguei `index.html`, `main.dart.js` (12 MB), `flutter*.js`, `firebase-config.js`,
  `firebase-messaging-sw.js`, `version.json`, `manifest.json` e sondei 16 caminhos que nunca deviam existir. Só leitura; nada se executa.
- Atacante anónimo: HTTP real à API do nosso Supabase só com a chave publicável que vem no bundle.
- Atacante com conta: claims simulados em transação desfeita (`set local role` + `request.jwt.claims`), como o N4 fez.
  Não criei conta nem usei senhas.
- **Não fiz** nenhuma escrita em pedidos, estafetas, carteiras, tokens (regra da missão). Por isso os achados A1, A2, A3 e A6
  estão provados **por leitura do código da função, das permissões e dos gatilhos**, com números de linha, e não com um pedido
  forjado a correr. Quem decidir aplicar o conserto pode provar com defeito plantado em transação desfeita (como fez o R2/N3b).
- Nenhum SQL desta auditoria junta DDL com nome de função de dinheiro. Os consertos de dinheiro estão descritos em prosa,
  de propósito: a trava recusa texto SQL desses, mesmo em ficheiro.

## ALTA

### A1 — o cliente diz ao servidor que "o pagamento já está confirmado" (dinheiro: sim · função de dinheiro)
- **Prova.** `create_order` (corpo, linha 89): `v_payment_already_confirmed := COALESCE((p_input->>'payment_already_confirmed')::BOOLEAN, FALSE)`.
  Linhas 365 e 605-609: `WHEN v_payment_already_confirmed THEN 'paid'` — o pedido nasce `paid`. Não há nenhuma verificação de quem chama
  (a única leitura do papel é a da linha 70, que decide o `user_id`). ACL da função: `authenticated=X` (qualquer conta com sessão).
  Quem o devia pôr a `true` é só a Edge `finalize-order-from-intent` (`index.ts:87`), depois de a Stripe confirmar, e chama com a chave de serviço.
- **O que um atacante faz.** Chama `create_order` direto (sem a app) com `payment_method` `card`/`mbway`, `payment_already_confirmed: true` e um
  `payment_intent_id` inventado: pedido "pago" que o despacho aceita (`guard_dispatch_requires_payment` e `enforce_payment_before_preparing` só olham para `payment_status`, e só em `UPDATE`).
- **Sinal de abuso na base:** nenhum. Últimos 60 dias: 10 pedidos MB Way pagos, os 10 com `payment_intent_id`; 0 pagos por cartão/MB Way sem intent.
- **Conserto proposto (não aplicado).** Logo a seguir à linha 89, tratar `payment_already_confirmed` como falso quando o papel do token
  não é `service_role` (o teste já existe na linha 70). `finalize-order-from-intent` e `stripe-webhook` usam chave de serviço: continuam a passar.
  Prova a fazer por quem aplicar: antes (conta normal manda `true` → pedido `paid`) e depois (→ `pending`), em transação desfeita.
- **Zona:** `create_order` está na lista de funções de dinheiro. Só com "autorizo" do Danilo com data.

### A2 — dá para criar um pedido DIRETO na tabela, com preço e estado de pagamento à escolha (dinheiro: sim · RLS de pedidos)
- **Prova (estática, quatro peças).**
  1. Política `orders_insert_client`: `INSERT` para `authenticated` com `WITH CHECK (auth.uid() = user_id)` — nada mais.
  2. Permissões de coluna: `authenticated` tem `INSERT` em `price`, `subtotal`, `final_total`, `delivery_fee`, `driver_earnings`,
     `platform_commission`, `payment_status`, `payment_method`, `payment_intent_id`, `tokens_applied_value_cents`, `status`, `is_partner_store`
     (consultei `has_column_privilege`, todas `true`; `total` e `customer_total` são geradas a partir de `price`).
  3. Gatilhos `BEFORE INSERT` ligados em `orders`: 22. Os que olham para dinheiro só limitam dinheiro-vivo a 40 € (`enforce_cash_payment_limit`),
     somam a taxa de pedido pequeno (`fn_small_order_fee`) e reetiquetam a partilha de lojas com percentagem própria. **Nenhum valida preço, subtotal
     ou `payment_status`.** O `enforce_financial_immutability` (que protege as colunas de dinheiro) só dispara em `UPDATE`.
  4. A mesma conclusão está escrita no N3b (`supabase/migrations/20261022042551_n3b_pedido_cliente_loja_estafeta_guarda.sql`):
     "política orders_insert_client, que nenhuma app usa". A app só cria pedidos por `create_order` (`lib/stores/order_store.dart:994`);
     0 `.insert` em pedidos fora do painel.
- **O que um atacante faz.** `POST /rest/v1/orders` com a sua sessão: `price: 0.01`, `payment_status: 'paid'`, `status: 'callingDriver'`. O gatilho de despacho
  (`trg_dispatch_on_calling_driver`, `AFTER INSERT`) chama o estafeta.
- **Conserto proposto.** Tirar o `INSERT` ao papel `authenticated` na tabela de pedidos (e a política `orders_insert_client`): os pedidos nascem só por
  `create_order`, que é `SECURITY DEFINER`. Nenhuma app usa o caminho; a Edge e o webhook usam a chave de serviço. **Só endurece** (regra: RLS de pedidos nunca se afrouxa).
- **Zona:** RLS de `orders` → ordem explícita do Danilo. O líder deve confirmar com defeito plantado antes de aplicar.

### A3 — `create_order` aceita o preço que o cliente manda (dinheiro: sim · função de dinheiro)
- **Prova (corpo, números de linha).** Para `restaurant`/`storeShopping`/`takeaway` o servidor só recalcula o subtotal **se vier `product_lines`**
  (linhas 446-449). Sem `product_lines` entra o ramo `ELSE` (linhas 495-497): `v_subtotal_server := ROUND(v_subtotal_input, 2)` — o `subtotal` do cliente.
  Com `product_lines`: o preço sai de `products.price` **só se o `product_id` existir**; se não existir usa o `unit_price` do cliente (linhas 459-465).
  A quantidade (linha 466) não é validada: nenhum `RAISE` na função fala de quantidade ou de produto desconhecido
  (enumerei todos os `RAISE EXCEPTION` do corpo). Quantidade negativa abate o subtotal.
- **O que um atacante faz.** Pedido de restaurante sem `product_lines` e `subtotal: 0.01`; ou linhas com `product_id` falso e preço baixo; ou
  uma linha real mais uma falsa com quantidade negativa. O parceiro vê os `items` no pedido; a partilha dele sai do subtotal.
- **Conserto proposto.** Recusar linha cujo produto não está na base; recusar quantidade menor que 1; para estes três tipos exigir `product_lines`
  (o `subtotal` do cliente só serve para recados e encomendas sem catálogo). A app já manda `product_lines` com preço de catálogo (`cart_store.dart:778`).
- **Zona:** função de dinheiro → "autorizo" do Danilo.

### A4 — `update-products` (Edge) corre sem nenhuma autenticação (dinheiro: sim · preços de catálogo)
- **Prova.** `verify_jwt=false` e o código em produção (versão 22, lido com `get_edge_function`) não tem nenhum teste de quem chama:
  `serve(async (req) => { … market = body.market … })`. Com a chave de serviço por dentro, faz `upsert`/`insert`/`update` em `products`
  (`price`, `name`, `photo_url`, `is_available: true`). Os dois crons (`update-products-continente`, segundas 03:00; `update-products-auchan`, terças 03:00)
  chamam-na **sem cabeçalho nenhum**, por isso ninguém a protegeu.
- **O que um atacante faz.** `POST` anónimo com `{"market":"continente","pages":90,"maxUpdates":2000}`: reescreve até 2000 preços/nomes/fotos,
  volta a pôr `is_available: true` em produtos que o Danilo desativou, apanha o IP dos servidores com pedidos ao Continente/Auchan (bloqueio), gasta tempo de Edge.
  `{"market":"mercadona"}` volta a escrever o catálogo do Mercadona (que está parado até o Danilo mandar abrir).
- **Conserto proposto.** Primeira coisa do handler: `exigirServidorOuAdmin(req)` (já existe em `supabase/functions/_shared/chaves.ts:222`).
  **Ordem:** 1.º mudar os dois crons para mandarem `Authorization: Bearer` com a chave de serviço do cofre; 2.º só então publicar a função
  (senão a corrida de segunda-feira 02/11 03:00 falha). Publicar com o ficheiro inteiro.
- **Zona:** toca preços de catálogo → "autorizo" do Danilo com data.

### A5 — `platform_settings` lida por qualquer conta com sessão: 48 chaves secretas (dinheiro: sim · é o S1)
- **Prova (transação desfeita, hoje):** `ANTES cliente: 48 secretas de 463 linhas`. São o markup oculto, comissões, taxas da Stripe, o telefone MB Way da Bora,
  relatórios internos. Mais: `get_setting` devolve a chave secreta a quem a chama **sem claims** (`ANTES sem claims, papel authenticated = VALOR`).
  HTTP real (chave publicável, sem login): `get_setting` secreta → `null`; `GET /rest/v1/platform_settings` → `[]` (a API protege o anónimo; a fuga é das contas com sessão).
- **Conserto: S1 preparado** (secção abaixo) — ficheiro `docs/propostas/missao-geral-2026-10-28/janela2/S1_platform_settings_segredos.sql`.

### A6 — o desconto de tokens é dado no pedido, mas só se gasta se a app chamar a seguir (dinheiro: sim · `bora_tokens`)
- **Prova.** `create_order` (linhas 540-557) limita o desconto a metade do saldo (`get_user_tokens`) e grava `tokens_applied_value_cents`,
  mas **não gasta os tokens**: não há `consume_tokens` nem `UPDATE` de tokens nessa função. Quem gasta é a app, depois do pedido criado:
  `lib/screens/payment_method_screen.dart:1599` (`_consumeTokensAndNavigate`), com o comentário "Consumption failure is non-fatal — order already created".
  Na base só `driver_convert_tokens`, `tvde_consume_ride_tokens` e `tvde_create_roundtrip_credit_cash` chamam `consume_tokens` (TVDE e estafetas); as entregas não.
- **O que um atacante faz.** Com a app alterada (ou chamando a API), cria pedidos com `token_discount_cents` e **nunca chama** `consume_tokens`: o saldo não desce
  e o desconto (até metade do saldo e do teto %) repete-se em todos os pedidos.
- **Conserto proposto.** Gastar os tokens dentro da transação do pedido (na própria `create_order`, ou num gatilho de criação) e a app deixa de chamar `consume_tokens`.
  Até lá, uma consulta de vigia: pedidos com `tokens_applied_value_cents > 0` sem linha gasta em `bora_tokens` para o mesmo utilizador.
- **Zona:** `bora_tokens` + função de dinheiro → "autorizo" do Danilo.

## MÉDIA

### M1 — 3 tabelas `bkp_` sem RLS: o anónimo lê e escreve (dinheiro: não, mas mostra código de funções de pagamento)
- **Prova HTTP, só com a chave publicável do bundle:** `GET /rest/v1/bkp_fn_finalize_errand_purchase_20261028` → 200, 1 linha, 6381 caracteres de código;
  `bkp_fn_finalizar_talao_nao_parceiro_20261028` → 200, 17275 caracteres; `bkp_platform_settings_wallet_split_20261028` → 200 (chave não secreta).
  Permissões: `anon` tem `SELECT, INSERT, UPDATE, DELETE, TRUNCATE`. É o aviso `rls_disabled_in_public` (ERRO). Nasceram a 28/10 sem RLS.
  As outras 81 `bkp_` têm RLS ligada e sem política (fechadas), mas com `SELECT/INSERT/...` concedidos a `anon` e `authenticated` (84 no total).
- **Risco.** Ler o código de duas funções de pagamento ajuda a procurar falhas; escrever num backup estraga o ponto de restauro.
- **Conserto: S1, passo 0** (provado: 84 tabelas `bkp_`, RLS ligada nas 3, `0` com permissões para anon/authenticated). Daqui para a frente: criar backups com RLS desde o primeiro comando.

### M2 — `compute_provider_weekly_payout` deixa qualquer conta ler e gravar o acerto semanal de qualquer prestador (dinheiro: sim)
- **Prova.** Função `SECURITY DEFINER`, `authenticated=X`, corpo sem nenhuma verificação de identidade. Com `p_persist=true` faz `INSERT … ON CONFLICT DO UPDATE`
  em `appointment_payouts` para o `p_provider_id` que o chamador escolher e para a semana que escolher; devolve receita, taxa e líquido desse prestador.
  A app chama-a no ecrã de finanças do parceiro (`lib/stores/partner_appointments_store.dart`) e o painel para qualquer prestador. (O anónimo é recusado: HTTP 401.)
- **Conserto proposto.** Só aceitar `p_persist=true` a admin/serviço; para `false`, exigir que o `p_provider_id` seja de uma loja do chamador (`parceiro_minhas_lojas()`) ou admin.
  Zona: acertos de pagamento → "autorizo".

### M3 — `get_user_tokens(p_user_id)` devolve o saldo de tokens de qualquer pessoa (dinheiro: sim, leitura)
- **Prova.** `SECURITY DEFINER`, `authenticated=X`, corpo é só `SELECT SUM(amount) … WHERE user_id = p_user_id` (sem comparar com `auth.uid()`). Anónimo: HTTP 401.
  Precisa do uuid da vítima. Conserto: comparar com `auth.uid()` ou admin (a app chama com o uid do próprio, `profile_screen.dart:1820`). Zona: tokens → "autorizo".

### M4 — `driver_heartbeat_by_id` deixa o anónimo manter um estafeta "online" (dispatch)
- **Prova.** `anon` executa. O `UPDATE` de `last_heartbeat_at` tem a condição `(v_uid IS NOT NULL AND dono) OR (v_uid IS NULL AND d.is_online)`:
  sem sessão basta o uuid do estafeta, desde que ele já esteja online. Quem tem o uuid pode impedir que um estafeta "caia" por falta de sinal e deixar o despacho
  a oferecer-lhe pedidos que ele não vê. Existe a versão com segredo (`driver_heartbeat_segredo`).
- **Conserto proposto.** Tirar o ramo `v_uid IS NULL` quando a versão com segredo estiver em todas as apps instaladas. **Zona dispatch → só proposta.**

### M5 — três Edge `verify_jwt=false` aceitam qualquer conta com sessão (`exigirCallerOk`)
- `notify-purchase-finalized` (aceita `order_id` e `unavailable_credit_cents` do chamador e manda o push "Compra finalizada" ao cliente desse pedido, com o crédito à escolha),
  `notify-admin-reimbursement` (spam ao Telegram do admin com um `receipt_id`), `execute-broadcast` (só executa o que já está agendado e vencido).
  O N4 resolveu o mesmo padrão em `notify-admin-message`, `notify-cleaner` e `notify-washer`; estas três ficaram.
- **Conserto.** Trocar por `exigirServidorOuAdmin` (como as três do 21/10). `notify-purchase-finalized` toca na mensagem de crédito → verificar com o `create-payment-intent` antes.

### M6 — `register-partner` continua a confiar no JWT sem validar a assinatura
- Proposta de 21/10 (`docs/seguranca/propostas/register-partner-confirma-sessao.md`) **ainda não aplicada**: a função em produção é a versão 11, de 17/07. Conserto igual ao da proposta.

### M7 — qualquer conta com sessão pode enviar ficheiros para dois baldes públicos
- `product_images_partner_insert`: `INSERT` para `authenticated` só com `bucket_id = 'product-images'` (bucket público, 590 ficheiros, sem limite de tipo nem de tamanho).
  `restaurant_assets_owner_insert`: quem escrever numa pasta `temp-*` passa (bucket público, 500 ficheiros, 50 MB, sem limite de tipo).
  Serve para hospedar ficheiros no domínio do nosso Supabase (phishing, abuso) e gastar armazenamento.
- **Conserto.** Restringir o `INSERT` a parceiros (`parceiro_minhas_lojas()`) e pôr `allowed_mime_types` (imagens) e `file_size_limit` nos dois baldes. Não é dinheiro.

## BAIXA

- **B1 — duas tabelas internas legíveis por qualquer conta com sessão.** `missions` (1 linha: título e partes de uma missão interna) e `knowledge_digest_status`
  (resumo "estado atual consolidado", 8,7 KB com regras/lições/em aberto) têm `SELECT … USING (true)` para `authenticated`. Conserto: passar a `is_admin()`.
  (`partner_status_override` e `token_config` também são `true` para sessão, mas são dados que a app usa.)
- **B2 — `e2e_log`: política de leitura inútil.** `e2e_log_select_any` diz `true` para anon e authenticated, mas **ninguém tem `SELECT` na tabela**
  (HTTP anónimo → `401 permission denied for table e2e_log`): **não há fuga**. Fica a nota: apagar a política morta para ninguém a ligar por engano.
  O `INSERT` aberto a anon continua por desenho (o app grava lá); como `debug_crash_logs`, `link_clicks`, `site_visits`, `web_health_events`, **sem limite de ritmo** — dá para encher.
- **B3 — 49 funções `SECURITY DEFINER` executáveis pelo anónimo (aviso do Supabase).** Triagem: 22 só funcionam com chave guardada no cofre (`_caca_chave_ok`,
  `driver_heartbeat_segredo`) — corretas; 27 são públicas por desenho (inclui `get_setting` e `is_admin`) (cotações, pesquisa, avaliações, consultas por token longo). Atenção a `contadores_redes`,
  `visitas_pessoas_e_robos`, `visitas_por_origem` (estatísticas de tráfego e uso do código BEMVINDO a qualquer anónimo) e a `tvde_fiscal_consulta`/`verificar_ficha_publica`
  (protegidas só pelo comprimento do código: 12-40 e 8-40 caracteres; não vi limite de tentativas).
- **B4 — o site não manda cabeçalhos de segurança.** `app.boraguarda.com` (Cloudflare) responde sem `Strict-Transport-Security`, sem `Content-Security-Policy`, sem `X-Frame-Options`
  (a página pode ser posta dentro de uma moldura: clickjacking no login e no pagamento). Tem `nosniff` e `Referrer-Policy`. Qualquer caminho devolve a página inicial com 200
  (`/.env`, `/.git/config`… → `index.html`, sem conteúdo): não há fuga, mas também não há `robots.txt` nem `security.txt`. Conserto: regras de resposta na Cloudflare (`frame-ancestors 'self'`, HSTS).
- **B5 — Auth.** O Supabase avisa: proteção contra senhas vazadas (HaveIBeenPwned) **desligada**; validade do OTP por email acima de 1 h. São definições do painel do Supabase — decisão do Danilo.
- **B6 — chave do Google Maps no bundle** (`AIza…`, em `index.html` e `main.dart.js`, usada em `maps/api/js?key=`): a memória do projeto regista-a como **sem restrição**;
  não voltei a testá-la hoje (cada teste custa dinheiro ao Danilo). Restringir por referrer (`app.boraguarda.com`) e por pacote nas apps.
- **B7 — higiene.** Código morto do cliente que tenta escrever dinheiro (`order_store.dart:1995` `payment_status refunded`, `:2019` `paid`, `:2961` `bag_fee`): o servidor
  recusa (`orders_financial_lock`, `_pedido_cliente_recusa`) — apagar o código. 19 funções com `search_path` mutável (aviso). `is_admin()` reconhece também dois emails fixos no
  próprio código da função. O `assistant_lojas` (aviso "security definer view") só mostra id, nome, categoria e coordenadas da loja: sem dados pessoais.

## Segredos no site publicado (`app.boraguarda.com`)

Varrido: `index.html`, `main.dart.js` (12 002 305 bytes), `flutter.js`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `firebase-config.js`,
`firebase-messaging-sw.js`, `manifest.json`, `version.json`.

| Procurado | Resultado |
|---|---|
| `service_role` (palavra), `sb_secret_`, `sk_live_`, `sk_test_`, `whsec_`, `ghp_`/`github_pat_`, `-----BEGIN`, `re_` (Resend), tokens de bot, `postgres://`, `AKIA`, `xox`, `sk-` (IA) | **0** em todos |
| JWT `eyJ…` | **0** (a app usa chave nova `sb_publishable_`, não JWT) |
| `sb_publishable_` | 2 (`sb_pub…`) — pública por desenho |
| `pk_live_` | 1 (`pk_liv…`, 107 car.) — chave publicável da Stripe, pública por desenho |
| `AIza…` | 2 chaves distintas: Maps JS (`index.html` + `main.dart.js`, 11 ocorrências) e Firebase web (`firebase-config.js`) — públicas por desenho; ver B6 |
| Chave VAPID do push web | 1 (`BLH3O2…`) — pública |
| `source map` / `.env` / `.git` / `pubspec` / `service_account` / `config.toml` | não existem (a página inicial responde a tudo; nenhum ficheiro real) |
| `p_chave`, `client_secret`, `hermes`, emails | `p_chave` é a chave de um vale do check-in (`admin_checkin_premio_dar`), não um segredo; `sem_client_secret` é texto de erro; email público `boraappbora@…` |

**Chaves de produção no front: não.** Só as públicas por desenho acima.

## Base de dados

- **Tabelas de `public` sem RLS: 3** — `bkp_fn_finalizar_talao_nao_parceiro_20261028`, `bkp_fn_finalize_errand_purchase_20261028`, `bkp_platform_settings_wallet_split_20261028` (M1).
  Tabelas no total: 390. Com RLS e sem política (fechadas a anon/authenticated): 152 (aviso INFO; aceitável).
- **Políticas `using (true)`**: 25. De escrita, só 5 inserts abertos a anon (B2). De leitura: catálogos públicos por desenho (produtos, categorias, variantes, staff, disponibilidades),
  `platform_settings` (A5), `missions` e `knowledge_digest_status` (B1), `token_config` e `partner_status_override` (dados que a app usa).
- **Funções `SECURITY DEFINER` com EXECUTE para anon:** 49 (B3). Para authenticated: 888; as `admin_*` têm guarda (`_admin_op_guard`, `_carwash_require_admin`); sem guarda de identidade
  encontrei `compute_provider_weekly_payout` (M2), `get_user_tokens` (M3), `tvde_reservation_offer_to_next` (só chamada por outras funções; pode perder o EXECUTE),
  `agent_ask_robot_b` (só o chatbot), `expire_stale_driver_presence` (cron + app; inócua).
- **Advisors de segurança (8 grupos):** `rls_disabled_in_public` 3 (ERRO), `security_definer_view` 1 (ERRO, `assistant_lojas`: aceitável; o S1 acrescenta mais uma de propósito),
  `anon_security_definer_function_executable` 49, `authenticated_security_definer_function_executable` 888, `function_search_path_mutable` 19, `rls_enabled_no_policy` 152,
  `auth_leaked_password_protection`, `auth_otp_long_expiry`.
- **Advisors de desempenho:** 1064 achados em 7 grupos (201 políticas que reavaliam `auth.uid()` por linha, 527 políticas permissivas repetidas, 63 chaves estrangeiras sem índice,
  125 índices por usar, 2 índices duplicados em `products`, 145 tabelas sem chave primária). Nada de segurança; fica para uma ronda de desempenho.
- **Funções de preço que leem chaves secretas e correm como o utilizador (`SECURITY INVOKER`):** 4 (`pricing_calculate`, `pricing_calculate_loja`, a partilha do parceiro e o gatilho que reetiqueta a partilha).
  Só são chamadas por funções do dono `postgres` (RLS não se aplica) — nenhuma app nem Edge as chama direto. Se a leitura das chaves secretas fechar, uma conta normal que as chamasse daria o
  mesmo que o anónimo dá hoje; os valores de recurso escritos no código (0,10 e 0,05) são iguais aos de produção, por isso o resultado não muda (provado, ver S1).

## Regras de dinheiro: o que o cliente decide e o que só mostra

**Só mostra** (o servidor decide e confirma): total do carrinho (`quote_order_pricing`, `cart_store.dart:668`, `payment_service.dart:213`); taxa de pedido pequeno e taxa de serviço
(`small_order_fee.dart`, `remote_fees_service.dart`: leem o valor para o mostrar); cancelamento (`order_details_screen.dart:346-350` mostra; a Edge `client-cancel-order` calcula);
preço da corrida TVDE (a app mostra uma estimativa; o servidor corrige a distância com `_tvde_km_seguro` e calcula a tarifa); gorjeta (`tip_registar_dinheiro` verifica o dono do pedido);
`finalize_*` (só o estafeta atribuído); `client_set_order_invoice` (só o dono do pedido, NIF validado); `consume_tokens` (exige `auth.uid() = p_user_id`).

**Decide, e o servidor aceita:**
1. `payment_already_confirmed` (A1). 2. `subtotal`, `unit_price`, quantidade (A3). 3. Quando se gastam os tokens (A6). 4. Os pedidos novos por escrita direta (A2).
5. O parceiro calcula `products.price` no telemóvel com a fórmula `balcão ÷ (1−comissão) × (1+markup oculto)` (`lib/services/partner_price_rules.dart`) e grava-o direto
   (`restaurant_store.dart:870` e `:948`); a partilha dele no pedido sai depois do servidor, por isso o parceiro só consegue prejudicar a si próprio. Mas é esta leitura
   (as duas percentagens secretas) que obriga o S1 a uma exceção para donos de loja.
6. Código morto no cliente (B7) que tenta gravar `payment_status` e `bag_fee`: recusado pelo servidor.

## S1 — estado

- Ficheiros: `…/janela2/S1_platform_settings_segredos.sql` (completo), `S1_prova_rollback.sql` (provas por ator), `S1_prova_precos_antes_depois.sql` (preços antes/depois).
- Prova em transação desfeita (29/10; confirmei depois que nada ficou: política antiga, `0` vistas e funções de teste, `md5` do `get_setting` igual):
  `ANTES cliente = 48 secretas de 463` → `DEPOIS cliente = 0 secretas de 415`; parceiro `2 de 2` chaves próprias; admin e `service_role` `48 de 463`; anónimo `0` na tabela e `87` na vista;
  `get_setting` secreta: anon/cliente/parceiro `NULL`, admin/`service_role` `VALOR`, claims `{}` `NULL`, interno `VALOR`.
  As 81 chaves da app dão o mesmo `md5` por tabela, por vista e por `get_setting`.
- **Preços iguais.** Baseline de hoje, conta normal: parceira `17,25` (`md5 2a3fb771…`), não parceira `14,99` (`md5 2eccb40e…`); partilha do parceiro sobre 100 = `85,71` (igual a anon e a postgres).
  O script é determinístico (corri-o duas vezes: mesmos `md5`). O líder volta a corrê-lo depois de aplicar.
- **Exceção que o líder deve saber:** o ecrã "novo produto" do parceiro lê as duas percentagens secretas da tabela com a sessão dele (`partner_price_rules.dart:99`). Fechar sem exceção
  parte esse ecrã nas versões já instaladas. O S1 deixa-as visíveis só a donos de loja (política com `parceiro_minhas_lojas()`). Se o Danilo preferir que o parceiro não as veja,
  é fase 2 (RPC nova, `lib/` muda, versão mínima nas 3 lojas).
- **Lista nome a nome** (82 nomes, 81 existem, 15 lidos sem sessão) e o ficheiro:linha de cada um: fim do `S1_platform_settings_segredos.sql`. Além dos 82: `limpeza_guia_*` (6 chaves,
  `guia_limpeza.dart:34`). Lidas pela app e secretas: só `partner_hidden_markup_pct` e `partner_visible_commission_pct`.
  Falso positivo do varrimento: `priority_*_cost` (4) vêm de `token_config`.
- **Leitores do lado do servidor:** todas as Edge leem com a chave de serviço; o `admin-ai-assistant` lê como admin; o `pg_cron` corre como `postgres`. Nenhum parte.

## Pedidos ao líder, por ordem

1. Aplicar o S1 (já autorizado): `apply_migration` com o ficheiro; depois `S1_prova_precos_antes_depois.sql` e o plano de prova das 3 plataformas (fim do S1). Fecha A5 e M1.
2. Dinheiro, com "autorizo" do Danilo e data (nada se aplica sem ele): A1 → A2 → A3 → A6 (por esta ordem de risco); A4 (primeiro os crons); M2 e M3.
3. Sem dinheiro, pode ir já: M5, M6, M7, B1, B2 (apagar a política morta), B4.
4. Dispatch (só proposta): M4.

## Ficheiros desta auditoria

- Este relatório e `…/janela2/S1_*.sql` (3 ficheiros). Nada em `lib/`. Rascunhos e o bundle descarregado ficaram na pasta de rascunho da sessão.
