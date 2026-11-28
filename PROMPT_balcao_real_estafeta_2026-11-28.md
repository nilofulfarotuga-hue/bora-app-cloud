⚠️ MODO PROTECÇÃO TOTAL ⚠️

# Missão balcao-real-2026-11-28 — o estafeta vê sempre o preço de balcão certo

- **MOTOR:** Opus 5.5
- **PORTA:** Claude Code na nuvem (claude.ai/code, ambiente Default), repo `bora-app-cloud`, ramo de trabalho `ai/2026-11-28-balcao-real` (já existe, com as migrações e este ficheiro).
- **run_id / fluxo e2e_log:** `balcao-real-2026-11-28`
- **Entrada:** invoca o orquestrador CEO-AI (`.claude/skills/ceo-ai/`), depois `protocolo-missao-bora` e `modo-automatico`. Lê `PADRAO_BORA.md`, `CLAUDE.md` e `AGENTS.md` antes de planear.
- **Autorização:** Danilo, 28/11/2026 16:12, "Sim" à proposta da Claude.ai (preço de balcão real para o estafeta; o preço do cliente não baixa). **Não é mudança de dinheiro:** o que o cliente paga, o reembolso ao estafeta (é o valor do talão) e os ganhos ficam exatamente como estão. Se achares que alguma linha tua mexe em dinheiro, PARA nesse ponto, escreve "⚠️ ISTO MEXE EM DINHEIRO" no relatório e segue com o resto.
- **Supabase:** esta sessão NÃO corre SQL no projeto (na nuvem cada SQL pede permissão e ninguém está a ver). Todo o SQL que achares preciso vai para `docs/missoes/balcao-real-2026-11-28-sql.md` e a Claude.ai aplica por MCP. Se escrever no `e2e_log` pedir permissão, regista os passos no relatório final e segue sem parar.

## A regra do Danilo (28/11/2026, pedido KFC 14658088)

Talão de 13,60 € quando a app mostrava ao estafeta "ao balcão 15,67 €" (13,23 do Box Meal Mix + 2,44 da maçaroca extra).
- Talão MAIS BARATO → o robô do talão corrige o preço de balcão que o ESTAFETA vê, para da próxima vez ele ver o valor certo. O preço do CLIENTE fica igual.
- Talão MAIS CARO → sobe o preço do cliente (já era assim) e o balcão acompanha.
- O cliente só paga mais quando o talão sai mais caro. Nunca paga menos por o talão sair mais barato (a diferença fica com a Bora — regra de 05/10).

## O que a Claude.ai JÁ FEZ no servidor (não refazer, não reaplicar)

Migrações já aplicadas em produção e já neste ramo:
- `supabase/migrations/20261128161615_preco_balcao_real_estafeta_2026_11_28.sql`
  - `products.preco_balcao_real` (+ `_em`, `_fonte`): balcão real quando o talão saiu mais barato que `products.price`. NULL = o balcão é o `products.price`.
  - `catalog_price_update_from_receipt`: mais barato com confiança ≥ 0,9 → grava só `preco_balcao_real` e uma linha `catalog_price_updates` com `status='estafeta'`; mais barato com confiança baixa → `pending` como antes; mais caro → sobe `price` e limpa `preco_balcao_real`.
  - `admin_approve_catalog_price_update`: aprovar uma proposta mais barata → `status='estafeta'` (só estafeta), nunca baixa `price`.
  - `admin_revert_catalog_price_update`: aceita `status='estafeta'` (limpa o balcão real).
  - RPC nova `admin_preco_balcao_real(p_product_id text, p_valor numeric)`: pôr à mão (tem de ser menor que `price`) ou tirar (NULL/0).
  - Trigger `zzzzz_orders_carimba_balcao_real` (BEFORE INSERT em `orders`, só não-parceiro): cada item cujo produto tem balcão real leva a chave `balcaoReal` = base SEM extras (as opções continuam em `selected_options_priced[].items[].price_add`).
- `20261128161639_alerta_pedido_balcao_real_2026_11_28.sql`: o "Ao balcão" do Telegram usa `balcaoReal ?? basePrice` + extras.
- `20261128160322_lupa_sugestoes_so_de_madrugada_2026_11_28.sql` (outro assunto, do mesmo dia): a lista de sugestões da lupa só se refaz de madrugada. **A migração antiga do ramo `ai/2026-11-17-lupa-sugestoes` (recalculo de hora a hora, 90 s cada) NUNCA pode voltar a ser aplicada nem juntada por cima desta.**

Provas já feitas: carimbo testado numa tabela temporária (Big Mac com `balcaoReal`, loja parceira sem carimbo, produto desconhecido intacto); Telegram dá 11,30 € para 2 Big Mac a 5,65; 9 produtos já têm balcão real (Menu Golden Double KFC, Cheeseburger McDonald's e 7 do Continente); 18 propostas duvidosas rejeitadas.

## B1 — App do estafeta (PT-PT) — o que mexer e porquê

O estafeta vê o balcão por uma fonte única: `lib/services/preco_balcao.dart` (`precoBalcaoUnidade`, `precoBalcaoLinha`, `totalBalcao`), usada no `driver_map_screen.dart` (cartão laranja "TENS DE FAZER A COMPRA", lista "Ver compras", total, valor sugerido do talão).
1. `lib/models/cart_item.dart`: ler e guardar `balcaoReal` (double?) do JSON do item; `toJson`/cópias preservam-no. Ver também `lib/widgets/driver_item_options.dart` (~linha 31), que recria `CartItem` — não pode perder o campo.
2. `precoBalcaoUnidade`: se `balcaoReal != null` e não for parceiro → `balcaoReal + soma dos price_add das opções`; senão exatamente como hoje.
3. NÃO mexer em: `PricingService`, carrinho, checkout, `cash_total_due`, reembolso, ganhos, `finalizePurchase`, `dispatch_engine` (zonas protegidas). Isto é só ecrã.
4. Testes unitários: item com `balcaoReal` → usa-o (+ opções); sem `balcaoReal` → igual a hoje; parceiro → igual a hoje; quantidade > 1.

## B2 — Painel admin (PT-BR, termos técnicos explicados entre parênteses)

1. `lib/screens/admin/admin_correcoes_preco_screen.dart` (aba Correções): o estado novo `estafeta` aparece como "Corrigido só para o estafeta (o cliente continua a pagar o mesmo)", com filtro próprio e o botão Reverter (a RPC já trata). Aprovar uma proposta mais barata mostra a resposta `so_estafeta`.
2. `lib/screens/admin/admin_product_prices_dialog.dart`: mostrar "Preço de balcão real (último talão)" com a data, e deixar pôr/tirar à mão pela RPC `admin_preco_balcao_real`. Mostrar o erro `balcao_real_tem_de_ser_menor_que_o_preco` em português.
3. Se o detalhe do pedido no painel (`admin_order_detail_screen.dart`) mostra o valor ao balcão, usar o mesmo `balcaoReal ?? basePrice`.

## B3 — Auditoria (REPORTA, não corrige por conta própria)

Funções SQL que leem `basePrice`: `encomenda_telefone_resumo`, `partner_chamar_estafeta`, `_order_edit_build`, `estafeta_ajustar_peso`, `_talao_casar_itens`, `_trg_alerta_preco_catalogo_fn`, `demo_boom_criar_pedido` (definições nas migrações do repo). Classifica cada uma: só ecrã/aviso (deve passar a `balcaoReal ?? basePrice`) ou dinheiro (não se toca). Para as de ecrã, escreve o SQL proposto no ficheiro de SQL. As de dinheiro ficam só no relatório.

## B4 — Talão de combos do KFC (estudo + SQL proposto, não aplicar)

O talão do pedido 14658088 (receipt `73a07b48-f1f3-48b7-bd0f-9e9981c0d0b0`) deu `sem_match=1`: o balcão deu peças diferentes das da app (3 hot wings, batata média e molhos em vez de maçaroca). Estuda `_talao_casar_itens` (migrações do repo) e propõe uma regra segura para pedidos com UM só produto de menu: total do talão menos saco e depósito = esse produto, com as mesmas guardas (0,4× a 2,5×) e confiança só alta quando a loja e o total batem. SQL proposto + casos de teste no ficheiro de SQL. Reporta também: o talão trazia "DEPOSITO 0,75" e a app cobrou 0,10 de depósito Volta pela lata — só relatório.

## B5 — Provas, Juiz e publicar nas 3

1. Gate do Juiz: `python .claude/juiz/anti_trapaca.py`, `flutter analyze` 0 erros, `flutter test` verde, rubrica UI.
2. Pedido de revisão do ramo `ai/2026-11-28-balcao-real` para `autonomous-night-2026-04-29` (só os ficheiros desta missão), testes verdes, publicar com `node .claude/tools/publicar/publicar-pedido.mjs <número>`.
3. Conferir nas 3 (Android, iPhone, web) que a versão nova saiu. O `versionCode` é do CI, nunca à mão.

## B6 — Fecho

- `e2e_log` (fluxo `balcao-real-2026-11-28`, um passo por bloco) ou, se pedir permissão, a lista no relatório.
- Relatório curto em português simples em `docs/missoes/balcao-real-2026-11-28-RELATORIO.md`: o que ficou, o que ficou por aplicar no servidor (ficheiro de SQL), outros erros achados pelo caminho (reportados, não corrigidos).
- Digest no livro se tiveres acesso; se não, o relatório basta.
- Outros erros que encontrares: REPORTA, não corrijas calado.
- Carta de autonomia: não pares à espera de ninguém; bloqueado → regista e salta; só o dinheiro para.
- Termina com `/ctx doctor` e `/ctx stats`.
