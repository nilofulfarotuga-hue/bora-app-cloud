# Depósito Volta e KFC — relatório da missão volta-deposito-kfc-2026-11-09

Sessão Claude Code (Opus 5.5) no PC, 09/11/2026 20:37–23:00, ramo de ensaio `ai/2026-11-09-volta-deposito-kfc`
(worktree `C:\BoraLocal\wt-volta`). Registo passo a passo no `e2e_log`, fluxo `volta-deposito-kfc-2026-11-09`.

## Fiz isto

Preparei e testei tudo o que a missão pede, mas nada está em produção: a tranca deste PC recusou gravar a
migração que mexe no dinheiro do pedido ("migration que toca tokens/wallet/pagamentos/ledger") e, desde o
modo automático seguro de 05/11, aplicar SQL em produção, publicar Edge Functions e enviar para o ramo de
produção é "publicar", que é do Claude.ai. Não contornei. Ficou tudo pronto para o Claude.ai aplicar por
ordem, com provas.

O depósito Volta passa a ser cobrado ao cliente numa linha própria, 0,10 € por lata ou garrafa de plástico
até 3 litros, calculado sempre no servidor pelo catálogo. Fica fora do subtotal: não leva a margem de 15 %,
nem comissão, nem taxa de serviço, nem pedido pequeno, não dá tokens e não se paga com tokens. No parceiro
vai 100 % para ele no acerto semanal, numa linha à parte; no não-parceiro fica com a Bora. Produto em falta
devolve o depósito com o produto. Quando o robô lê o talão e há mais depósito do que o pedido cobrou, a
diferença vai ao cliente: em dinheiro entra no valor que o estafeta cobra; em cartão ou MB Way fica como
dívida na carteira (a cobrança extra no cartão está desligada desde 26/10). Se o talão tiver menos depósito,
devolve-se: em dinheiro desconta no que o estafeta cobra, senão vai para a Carteira Bora. O produto que
gerou o depósito a mais fica marcado para a próxima vez. A app antiga nunca paga o depósito sem o ver: o
servidor só o cobra quando a app manda a chave `deposit_units` nos itens, e só a app nova a manda.

O robô do talão está corrigido. Com o talão do KFC de hoje, a versão que está no ar dá exatamente os erros
de hoje (0,55 na caixa, 6,72 e 7,38 nos menus); a nova dá 6,20, 8,45 e 9,15, e lê 20 cêntimos de depósito.
Menus com cabeçalho a 0,00 somam todas as sublinhas, caixas com o preço partido somam-se, depósito e saco
nunca entram no preço de um produto, e propostas absurdas (menos de 40 % ou mais de 250 % do preço atual)
deixam de entrar. Nos outros 26 talões lidos até hoje, 25 dão igual e 1 do Burger King ficou melhor (a
bebida premium do menu passa a contar). O NIF do cliente agora escolhe-se entre todos os NIF impressos e
nunca é o da loja — o caso de hoje ("N. Contrib." da loja e "NIF:" do cliente logo a seguir) fica certo.

Marquei o catálogo por regras escritas (lei do Volta) e revi 60 produtos com fotos. A primeira versão
marcava como plástico 7 garrafas pequenas de vidro (tónicas, água com gás de 25 cl); as regras aprenderam e
a mesma amostra fica 59 em 59. Resultado previsto: 1.392 produtos e opções marcados, 1.289 duvidosos (vão
para a lista "rever" do painel, a 0 €), Burger King 0. No KFC ficam marcadas todas as latas e águas dos
menus (497 opções).

No KFC: o site nacional ainda mostra o Tower e o Tower Double, por isso não dá para confirmar o fim no
balcão da Guarda — o Tower fica ativo (o Menu Tower já tinha sido desligado pela Claude.ai). A regra do
balcão (Glovo ÷ 1,24, só para subir, nunca acima do Glovo) sobe 132 preços; os 3 do talão de hoje ficam.
"Bull Energy Drink" passa a "Red Bull Energy Drink", os nomes de caixa "V …" ficam com nome de gente, os
duplicados de água e Red Bull juntam-se sem partir pedidos antigos, e a Pepsi e a Pepsi Zero (que o balcão
tem) entram nas bebidas dos menus. A lista completa (antes → depois → fonte) está em
`.claude/.ai/missoes/volta-deposito-kfc-2026-11-09/relatorio-catalogo.md`.

Apps: na app do cliente aparece "+0,10 € depósito Volta" na página do produto, no cartão e no carrinho, e a
linha "Depósito Volta (N embalagens)" no carrinho, no pagamento, no detalhe e no seguimento do pedido e no
recibo por email. Na app do estafeta aparece "Este pedido tem N embalagens com Volta (X €)" e o acerto do
talão; o valor a cobrar continua a vir do servidor. No painel (PT-BR) há o ecrã "Depósito Volta" (resumo
por loja, lista com filtros Com/Sem/Rever, editar, exportar CSV, relatório mensal), as duas definições em
Configurações e o cartão do depósito no detalhe do pedido e no acerto do parceiro.

## Provas

- Base de dados no PGlite com as definições reais de produção: 52 provas, 0 falhas (`prova-pglite.md`).
- Robô do talão (Deno): 10 testes, 0 falhas.
- Juiz: anti-trapaça limpo (36 ficheiros, +49 casos de teste); `flutter analyze` 0 erros e nenhum aviso
  novo; testes novos do cliente/estafeta 15 verdes, do painel 23 verdes.
- Bateria completa (`flutter test -j 2 -r json`, 299 ficheiros): 3.221 certos, 6 falhas, todas em
  `test/m10_nif_caixa_app_test.dart` (cartão do NIF do estafeta, ficheiro em que esta missão não mexeu).
  Corrido sozinho mostra o aviso do ListTile do Flutter 3.47 deste PC (o CI usa 3.41.2) — o problema já
  conhecido, não vem desta missão.

## Falta isto (e porquê)

1. Aplicar no servidor, por esta ordem (é publicar, é do Claude.ai):
   `supabase/migrations/20261109220000_volta_catalogo_e_talao.sql` → a proposta de dinheiro
   `PARTE2-dinheiro-proposta.md` (gravar também como `20261109220100_volta_cobranca.sql`) →
   `passo-3-marcar-catalogo.sql` → `passo-4-kfc-precos-e-opcoes.sql` → Edge `ocr-receipt` v13.
   **⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.** (A PARTE 2 e o
   passo 4 mexem no que o cliente paga; a ordem do Danilo de 20:08 é a autorização da missão, mas a tranca
   exige que seja o Claude.ai a aplicar.)
2. Publicar nas 3 (Play, App Store, web) depois de o servidor estar aplicado — juntar o ramo
   `ai/2026-11-09-volta-deposito-kfc` ao ramo de produção é do Claude.ai.
3. Teste no emulador com pagamento em dinheiro (pack de 6 latas no Continente e menu com lata no KFC):
   só faz sentido depois do servidor; não foi feito.
4. Foto real do Box 6 Hotwings e os 39 produtos do Glovo que faltam no Bora (lista com estimativa no
   relatório do catálogo): não entraram porque precisam de foto real e, nos menus, dos grupos de opções.

## Erros que encontrei pelo caminho (reportados, não corrigidos calado)

- O catálogo do KFC estava quase todo a Glovo ÷ 1,35, com menus mais baratos do que o próprio sanduíche
  (Menu Wrap Clássico 5,24 e Wrap Clássico 5,65; Menu Wrap Kentucky BBQ 6,73 e Wrap Kentucky BBQ 7,51).
- As bebidas "Pretende uma Bebida?" do KFC custam mais em extra do que soltas (7Up +2,23 contra 2,00).
- O ecrã de pagamento calcula o limite dos tokens sobre o total já com o depósito; o servidor corta o
  certo, mas o ecrã pode mostrar uns cêntimos a mais de desconto (zona de tokens, não mexi).
- O `order_store.dart` (zona protegida) reconstrói os itens sem o número de embalagens de cada linha; a
  chave vai e o servidor calcula, por isso funciona, mas o valor por linha da app não chega.
- O robô do catálogo nunca atualiza bebidas soltas (são tratadas como acompanhamento) — já era assim.
- Mr Kebab (parceiro) tem 160 bebidas sem indicação de lata ou vidro: ficam na lista "rever" a 0 €.

## Próximo passo

O Claude.ai aplica as 4 partes no servidor e a Edge, prova com os SELECT do fim da proposta, junta o ramo e
publica nas 3; depois o teste no emulador em dinheiro. A lista "rever" do painel (1.289) e os 39 produtos
do KFC ficam para quem tiver tempo de olhar foto a foto.
