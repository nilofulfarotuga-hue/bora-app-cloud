# Check-in, prémios e Favor — fecho do dia (04/11/2026)

Fiz isto. Os prémios de produto do check-in nas lojas não parceiras já funcionam de ponta a ponta. O cliente não paga o prémio, o estafeta compra no balcão e a Bora fica a dever-lhe esse valor. Encontrei que a correção do talão que a Claude.ai aplicou de manhã tinha ido para a função antiga, e a app usa outra. Pus a mesma regra na função certa, provei antes numa transação desfeita e apliquei. Na prova com um Big Mac, o cliente pagou só 3,59 € de entrega e taxas, o estafeta ficou com 4,50 € a receber da Bora, e o ganho dele não mudou. Um pedido normal ficou igual ao de antes. No ecrã do estafeta, a linha do prémio aparece destacada com "PRÉMIO do cliente: compra no balcão, a Bora paga-te este valor", sem o botão "Não há". No fim do talão aparece "A Bora devolve-te X € no acerto". Liguei os 7 prémios de produto do calendário: Leonidas nos dias 8 e 12, Burger King nos dias 11 e 17, Big Mac no 13, Tiago's no 18 e Fuku no 20. Confirmei que aparecem no calendário. Antes guardei uma cópia dos valores antigos.

O selo "Frescura garantida" deixou de aparecer na Mercadona de beleza e continua no Continente e nos restaurantes. O carrinho já sabe mostrar a linha "Prémio Bora Todo Dia: menos X €" e a frase "Faltam Y € para usares o teu prémio de X €", com o total igual ao do servidor.

No Favor, o painel tem agora "Diferenças de Favor" e o botão "Marcar entregue sem código", que pede um motivo e fica no registo. O cliente tem o cartão "Pagar a diferença" para mandar um MB Way novo quando o anterior expirou. O webhook da Stripe já tem o ramo dos pagamentos da diferença.

Falta isto, e porquê. O desconto em euros dos prémios do Continente e da Mercadona ainda não sai no pedido. O servidor está pronto e provado: 40,43 € passa a 37,43 € e o estafeta continua com 5,57 €. Mas a linha que manda o vale ao criar o pedido fica num ficheiro que a tranca não deixa mexer. Por isso deixei o desconto desligado na app, e os 6 degraus de desconto (dias 9, 10, 15, 16, 22 e 25) continuam desligados. Assim ninguém ganha um prémio que não consegue usar. As peças de servidor do Favor (tabela, botão do cliente, painel, entrega sem código) foram bloqueadas pela tranca; o SQL completo está numa proposta para a Claude.ai aplicar. Até lá, o cartão do cliente e o webhook ficam calados e o painel mostra um erro de carregamento. Os blocos B e D do Favor ficam no ecrã do Favor do estafeta, que é zona vermelha. A cópia para o repositório das migrações de hoje também foi bloqueada.

Erros que encontrei. Ao cancelar um pedido com vale de desconto, o vale não volta ao cliente, porque o gatilho só olha para pedidos com artigo-prémio. A correção é uma linha e está na proposta, porque a trava do banco a bloqueou. Com a conta demo não se consegue provar a devolução de um vale, porque o pedido demo nasce logo aceite. A comissão da Bora fica negativa (−2,01 €) num pedido não parceiro com desconto. A função do Favor manda à Stripe o valor em cêntimos no lugar do número da tentativa; não faz mal, mas fica anotado.

Próximo passo. A Claude.ai aplica as duas propostas e grava as migrações no repositório. Depois uma sessão em modo seguro faz três coisas: põe o vale no pedido (três linhas), liga os 6 degraus de desconto e trata do ecrã do Favor do estafeta.

## PARA A CLAUDE.AI / SESSÃO --safe-mode (e2e_log fluxo checkin-escada-premios-2026-11-04)

- e2e 6613: `lib/stores/order_store.dart`, o parâmetro `checkinValeId` no `createOrder` e `checkin_vale_id` no rpcInput. Depois, `checkinValeId: _checkinValeId` na chamada do `cart_store` e `CartStore.descontoCheckinNoPedido = true`.
- e2e 6614: a migração `20261104145309_checkin_premio_no_talao_nao_parceiro` está aplicada em produção e falta no repositório. O texto está em `supabase_migrations.schema_migrations`.
- e2e 6615: `docs/propostas/PROPOSTA_20261104_gatilho_cancelar_devolve_vale_desconto.md`.
- e2e 6618: `docs/propostas/PROPOSTA_20261104_favor_diferencas_e_entrega_sem_codigo.md`. Depois de aplicar, publicar `stripe-webhook-empresa` e `stripe-webhook` com o `_shared/stripe_webhook_core.ts` deste envio.
- e2e 6620: os blocos B e D do Favor ficam em `lib/widgets/errand_execution_sheet.dart`.
- e2e 6616: ligar os 6 degraus de desconto depois do e2e 6613. O backup está em `bkp_checkin_marcos_20261104`.
