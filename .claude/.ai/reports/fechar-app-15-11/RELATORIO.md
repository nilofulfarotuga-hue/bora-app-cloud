# Missão fechar-app-15-11 — relatório

Ordem do Danilo de 14/11/2026 21:55 (repetida às 22:14). Claude Code no PC, motor Opus 5.5, um ajudante de cada vez.
Tudo está no ramo de ensaio `ai/2026-11-15-fechar-app`, com pedido de revisão
[nilofulfarotuga-hue/bora-app-cloud#18](https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/18). Nada foi publicado.
Escrito às 01:50 de 15/11. A noite teve mais três missões pelo meio (vídeos, farmácias, loja Shopify); essas estão no relatório `RELATORIO-noite-15-11.md`.

## Fiz isto

Juntei num só ramo o trabalho que estava parado: a compra do estafeta guardada a cada toque e a fila de pedidos (só existia no PC), o conserto do estafeta lento com o preço de balcão certo, e o Editar perfil do cliente. As farmácias já estavam dentro.

O estafeta deixa de perder o preço das opções quando marca a compra. Era por isso que o valor de balcão voltava a aparecer sem as opções.

Abrir um mercado grande já não pede a loja inteira aos saltos. O Continente tem 19 808 produtos e era isso que dava o erro 500.

Quando o MB WAY falha, o cliente passa a ver porquê, numa janela com "Tentar outra vez" e "Escolher outro meio", e fica com o carrinho inteiro. Antes ficava sem carrinho e era mandado para o início. Os 4 pedidos cancelados em 14 dias eram todos MB WAY.

O robô do talão deixa de adivinhar a loja e de contar o saco duas vezes. No talão do McDonald's a soma passa de 25,40 para 25,10, que é o total impresso.

A app deixou de inventar um número de estafeta quando perde a sessão.

O ecrã "Acesso negado" do painel diz agora com que conta a pessoa entrou. O painel abre com a tua conta pessoal nilofulfarotuga; a conta boraappbora não tem perfil de administrador, e não o dei a ninguém.

O alerta para o teu WhatsApp já não é cancelado por ter o teu nome no texto. A 12/11 foi cancelado porque o cliente se chamava Danilo.

A vigia dos pedidos presos volta a ver. Estava cega há pelo menos 24 horas, com 142 consultas recusadas, e não avisava.

## O que o revisor encontrou, e o que mudou

Pedi a um revisor independente, com contexto limpo, para tentar derrubar o ramo. Encontrou um problema sério e onze mais pequenos. A lista inteira está em `docs/propostas/fechar-app-15-11/REVISAO-juiz-refinador.md`.

**O sério: pagar duas vezes no MB WAY.** Com a minha mudança, o cliente ficava no ecrã com o carrinho e o convite para tentar outra vez. Mas o pedido de pagamento antigo continua vivo na app do banco: o cancelamento da Bora não cancela o pagamento na Stripe, e o servidor reativa um pedido cancelado se o dinheiro entrar depois. Se o cliente aceitasse o antigo e o novo, pagava duas vezes.

O que mudou: o carrinho guarda agora qual é o pedido MB WAY que ficou à espera. Ao abrir o ecrã de pagamento, ao voltar à app e antes de criar qualquer pedido, a app vai ver esse pedido ao servidor. Se está pago ou ainda ativo, limpa o carrinho e abre os Pedidos em vez de criar outro. Se não há rede para confirmar, não deixa criar outro. A janela da falha diz "se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá". Nenhum valor, taxa ou regra de preço mudou.

No mesmo conserto ficaram resolvidos quatro defeitos vizinhos: o carrinho que ficava cheio depois de pagar, o pedido agendado que saía "para agora" na segunda tentativa, a mensagem que tapava o botão de pagar, e o botão que ficava ativo cedo demais.

Corrigi também: a vigia já não repete o aviso de 10 em 10 minutos nem conta pedidos agendados como presos; a peça que junta os carregamentos do estafeta já não pode ficar presa; o catálogo dos mercados grandes recomeça do princípio quando tudo recarrega.

## Falta isto

**Os testes ainda estão a correr.** Neste PC não se corre Flutter (ordem tua das 22:42), por isso os testes correm no servidor do GitHub. À hora deste relatório o envio com as correções do MB WAY ainda está na fila. Sem esse resultado, a correção não está provada. Fica registado no `e2e_log`, passo `mbway-pagamento-a-dobrar`.

**Um buraco do MB WAY continua aberto, e é dinheiro.** Se o cliente criar o segundo pedido e só depois aprovar o primeiro na app do banco, paga os dois. Isto já acontece hoje em produção. Só fecha quando o cancelamento da Bora cancelar também o pagamento na Stripe. ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo escrito em `docs/propostas/fechar-app-15-11/mbway-cancelar-pagamento.md` — confirma que eu preparo e a Claude.ai aplica.

Aplicar no servidor, pela Claude.ai, por esta ordem, antes de juntar o ramo:

1. `20261114190000_compra_guardada_e_fila_estafeta.sql`
2. `20261115010000_editar_perfil_cliente.sql`
3. `20261115010100_aprovar_account_update_pelo_nucleo.sql`
4. `20261115020000_push_token_papel_handyman.sql`
5. `20261115020100_cron_desencontrar_minutos_redondos.sql`
6. `20261115021000_products_indice_loja_ordem.sql`
7. `20261115023000_bkp_tabelas_fechadas.sql`

A proposta que tira as notas internas do alcance dos robôs (`8e_robos_sem_notas_internas.PROPOSTA.sql`) NÃO é para aplicar como está: o revisor mostrou que ainda deixa passar 9 trechos que falam de margens, comissão ou senha. Precisa de uma lista das secções que os clientes podem ver.

Publicar a função do talão (`ocr-receipt`) e copiar para a VPS os ficheiros `lembretes_lane.py` e `vigia_pedidos.py`.

Aplicar o remendo do ficheiro dos pedidos (`docs/propostas/fechar-app-15-11/bloco2_order_store.patch`). A tranca do PC recusou-o. Sem ele o estafeta já não recarrega a cada posição, mas cada recarga ainda traz a lista inteira, e o botão "Ver entregas mais antigas" só mostra o que já está na memória.

Do revisor ficaram por fazer: o robô do talão ainda deixa lojas diferentes "bater" por uma palavra comum (pizza, sushi, burger) e o painel não mostra porque é que um talão ficou para rever; o ecrã "Acesso negado" manda sair da conta mas não tem botão para isso.

Publicar nas 3 lojas e provar nas 3, e o pedido de teste a dinheiro do princípio ao fim. Não se fez: depende de tudo o que está em cima.

Farmácias: no servidor estão prontas e escondidas. O e-mail de entrada das duas já foi trocado para o verdadeiro (15/11 00:38). O link de senha vai na segunda 16/11 às 09:05, pela Claude.ai. Falta o IBAN e a revisão dos ecrãs com capturas.

Conversas ao vivo dos robôs: o ecrã no painel, assumir a conversa e o aviso no telemóvel não foram feitos.

## Erros que encontrei pelo caminho

Os robôs dos clientes pesquisam notas internas. De 605 trechos de conhecimento, 568 são notas de programação e do cérebro interno. Num deles há uma palavra-passe escrita ao lado da conta driver@bora.app. Não a li. Essa palavra-passe tem de ser trocada.

As tarefas agendadas do servidor arrancam todas no mesmo segundo e não cabem: em 47 horas perderam-se 273 corridas, incluindo tarefas de pagamentos e de chamada de estafetas.

Há 20 tabelas de cópia de segurança sem proteção; 13 podem ser lidas e escritas sem login.

No MB WAY, erros antigos que vi e não corrigi porque são dinheiro: quando o servidor responde que o pedido "já foi tratado", a app cancela-o como pagamento falhado, mesmo que já esteja pago; quando o pagamento entra tarde, os tokens não são descontados na app.

O teste antigo `test_restaurante.py` da pasta do assistente falha no PC (duas falhas), numa parte que esta missão não tocou.

## PARA O DANILO

- Dizer "autorizo" (ou não) à correção de raiz do MB WAY: o cancelamento da Bora passar a cancelar o pagamento na Stripe.
- Trocar a palavra-passe da conta driver@bora.app.
- Dizer se queres mover as 12 tarefas agendadas que tocam em dinheiro para fora dos minutos redondos.
- Dizer se a conta boraappbora deve abrir o painel.
- O PC: quem gasta memória é o Chrome (3,5 GB) e a consola da ponte (cerca de 1 GB). Para libertar essa consola tenho de reiniciar a ponte, que cai uns segundos. Não o fiz porque disseste para não a fechar.

## Onde está o detalhe

`e2e_log`, fluxo `fechar-app-15-11`, linhas 8918 a 8987. Trancas em `docs/TRANCAS.md`. Propostas em `docs/propostas/fechar-app-15-11/`.
