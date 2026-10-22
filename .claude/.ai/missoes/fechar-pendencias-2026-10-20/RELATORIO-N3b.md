# RELATÓRIO N3b — duas de segurança (22/10/2026)

Sessão local_b16c6598 (Opus 5.5, ignorar permissões), combinada com local_6914492a: esta sessão fica
com o 3b e a vigia da fila; a outra com N5, N2, N9 e N10. Ordem do Danilo, prompt de 22/10 04:33,
passo 3b: "fechar a leitura/escrita das colunas de dinheiro das lavagens a quem não é admin, e
impedir que o cliente escreva a loja ou o estafeta no próprio pedido. Revisor, prova com defeito
plantado em transação desfeita, aplicar." As outras duas da mesma lista (prémio da loja no acerto,
taxa de serviço do prémio) não foram tocadas: são dinheiro e esperam o "autorizo".

RAM no arranque: 1467 MB disponíveis (portão leve 400 MB; só SQL e ficheiros, sem compilar).

## Fiz isto

**Pedidos.** O cliente deixa de poder escrever no próprio pedido de que loja ele é, se a loja é
parceira, o nome da loja, que estafeta o leva, a oferta a um estafeta, o estafeta pré-escolhido, o
ajudante, a lista de estafetas a saltar e o histórico de ofertas. Também não pode criar um pedido
direto na tabela já com nada disto. A app não escreve nenhuma destas coisas: criar o pedido vai pela
função do servidor, e as escritas diretas do cliente são notas, fotos, itens, sacos e o estado (este
já estava guardado desde 21/10). O estafeta, a loja, o admin e o servidor continuam como estavam.

**Lavagens.** O cliente e o lavador já não mudam pela tabela o estado, o total, o ganho do lavador,
o pagamento nem nada do resto da sua lavagem. A única coisa que a app escreve diretamente — o
cliente anexar as fotos do carro — continua a funcionar, e só o próprio cliente as muda (o lavador
não as pode trocar nem apagar). O servidor e o admin continuam a escrever.

Migrações: `20261022050000_n3b_lavagem_escrita_direta_guarda.sql` e
`20261022050100_n3b_pedido_cliente_loja_estafeta_guarda.sql` (ramo `n3b-22-10`). Reversão em
`n3b/reversao_N3b.sql` (desligar já sem apagar, ou tirar de vez).

## A prova (transação desfeita, nada ficou)

Ronda 1 (04:58): 13 ataques passavam antes, 14 recusados depois, 2 defeitos plantados apanhados.
O revisor de contexto limpo disse **NÃO** (REVISAO-N3b.md, e2e_log 4350) por 3 coisas:
(1) criar o pedido direto na tabela ainda deixava escolher os estafetas a saltar ou uma oferta;
(2) a parte "leitura" das lavagens não estava escrita para o Danilo em lado nenhum (o comentário
apontava para um relatório que não dizia isso); (3) o lavador podia trocar as fotos do cliente.
Mais: 3 casos "legítimos" da minha prova não provavam nada (loja fechada às 5h, admin sem regra de
escrita direta, código morto) e contavam como sucesso.

Corrigi as três e refiz a prova (ronda 2, ~05:35, `n3b/prova_n3b_rollback_r2_RESULT.json`):
- 17 ataques passavam hoje no ar; depois da correção 18 dão "proibido" (o 18.º, criar um pedido de
  loja já com estafeta, às 5h já era travado pela loja fechada; no horário passava).
- 11 caminhos legítimos passam e ficam iguais antes e depois (incluindo criar um pedido direto sem
  estafeta até ao fim, e a conta demo continuar a receber o estafeta demo).
- Os 3 casos vazios passaram a chamar-se "vazios" e só se mostra que ficam iguais.
- 4 defeitos plantados (guarda sem estafeta, lavagem sem total, fotos livres, INSERT sem a lista de
  estafetas a saltar): os 4 ataques correspondentes voltam a passar com o defeito — o teste não é vazio.
- Depois da prova: 0 gatilhos e 0 funções novas na base, os 3 pedidos de teste e as 2 lavagens com o
  mesmo md5 que o revisor mediu (`78a9b148…`, `6697513f…`), 0 pedidos de teste criados, fila de envios 0.

## Falta isto (e porquê)

Aplicar só depois do revisor dizer SIM na ronda 2; o envio dos ficheiros para o servidor faz-se um
de cada vez, combinado com a sessão local_6914492a (só migrações e documentos: não dispara build).

## PARA O DANILO

1. **A leitura do dinheiro das lavagens continua aberta.** Hoje o cliente vê, na sua própria lavagem,
   quanto o lavador ganha e quanto fica para a Bora (ex.: total 20 €, lavador 17 €, Bora 3 €); o
   lavador vê quanto fica para a Bora. Não fechei porque a app lê a lavagem inteira de uma vez (do
   lado do cliente e do lado do lavador) e o lavador precisa de ver o que ganha: tirar a leitura na
   base hoje fazia as duas apps darem erro. Para fechar: (a) mudar a app para cada um ler só o que
   precisa (o cliente o total; o lavador o seu ganho), (b) publicar nas 3 (Android, iPhone, web) e
   esperar que a maioria atualize, (c) só então tirar a leitura na base. Diz se queres que se faça.
2. **Buracos antigos que o revisor encontrou (não são da ordem de hoje, não mexi):**
   o estafeta consegue mudar a loja do pedido que está a levar; a loja parceira consegue pôr um
   estafeta direto no pedido sem passar pelo caminho oficial (a barreira
   `orders_driver_direct_update_block` está desligada); qualquer cliente com sessão consegue criar
   um pedido "cru" direto na tabela (sem itens, preço à escolha), saltando a função que calcula o
   preço — nenhuma app usa esse caminho, mas a porta está aberta. Este último toca preços:
   precisa da tua decisão.
3. O dono do pedido ainda consegue mudar as coordenadas de recolha e o telefone do estafeta que vê
   no próprio pedido (só o afeta a ele; o ganho do estafeta não usa as coordenadas de recolha).

## Erros encontrados pelo caminho (reportados, não corrigidos)

- `OrderStore.cancelDelivery` (lib/stores/order_store.dart:1499) é código morto: ninguém o chama, e
  se fosse chamado a base recusava (regra de acesso). O estafeta desiste pela função do servidor.
- O admin não tem regra de escrita direta em `orders` (as escritas de admin vão por funções); um
  UPDATE direto do admin muda 0 linhas.
- Erro meu: o primeiro commit desta sessão foi feito a saltar os ganchos do git; desfiz e refiz com
  os ganchos (b740fb3d).
