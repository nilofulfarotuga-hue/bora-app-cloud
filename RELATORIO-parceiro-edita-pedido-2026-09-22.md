# Parceiro edita pedido — relatório (run_id parceiro-edita-pedido-2026-09-22)

**Acessos usados nesta sessão.** Conta GitHub do repositório nilofulfarotuga-hue/bora-app-cloud, branch autonomous-night-2026-04-29. Supabase ojykpzwqrtusfeakzrna pelo conector (a mesma conta nilofulfarotuga@gmail.com). Córtex pelo conector. Nada foi criado em Stripe, nenhuma conta nova, nenhuma chave nova. O Telegram foi pela função do banco `_telegram_admin` (a ponte por SSH não existe nesta máquina da nuvem).

**O que NÃO ficou feito, logo à cabeça.** A parte que mexe em dinheiro está pronta e provada mas não está ligada: a migração do dinheiro, a Edge Function que faz o reembolso parcial e a cobrança da diferença, e o interruptor que mostra os botões. Por isso, hoje, nem o parceiro, nem o cliente, nem o estafeta veem nada de novo: os botões só aparecem quando o interruptor `order_edit_enabled` passar a verdadeiro, e isso faz parte do "vai". Também não tirei fotografias dos ecrãs novos (com o interruptor desligado não aparecem no endereço público; ficam para a prova depois do "vai"). Não escrevi no vault do Obsidian, porque esta sessão corre na nuvem e o vault vive no PC; o registo ficou no Córtex e em `claude_ai_memoria`, que o sincronizador já leva para lá.

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Quando disseres "vai", faço três coisas, por esta ordem: aplico `supabase/migrations/20260922200100_PROPOSTA_parceiro_edita_pedido_dinheiro.sql` (que guarda antes o corpo actual da função da carteira numa tabela de backup e, no fim, liga o interruptor); publico a Edge Function `order-edit-settle` com verificação de sessão; e faço a prova real com um pedido de teste em dinheiro na Sabores de Casa. Nenhuma cobrança real é feita nos testes.

O que essa parte muda no dinheiro, dito simples. Quando a loja marca um produto em falta, o pedido fica logo com o valor certo e o cliente recebe a diferença: no cartão, é um reembolso parcial no mesmo pagamento; no MB Way (e no que foi pago com carteira), é crédito na carteira pela regra que já existe, oitenta por cento livre e vinte por cento em tokens; em dinheiro, o estafeta passa a cobrar menos. Quando a loja quer acrescentar, o cliente recebe o aviso e decide; se aceitar, em dinheiro soma ao total (e recusa se passar dos 40 euros), no cartão cobra o cartão guardado do pedido e, se o banco pedir confirmação, abre a folha de pagamento no telemóvel dele, e no MB Way manda um pedido MB Way só da diferença. Só depois de pago é que o pedido muda. Se recusar, fica tudo como estava.

A única função de dinheiro que já existe e que é alterada é `wallet_credit_refund_split`: ganha um quinto campo opcional, a chave de repetição. Sem esse campo continua a fazer exactamente o mesmo ao cêntimo. Porque é preciso: hoje ela só aceita UM crédito por pedido — um segundo crédito no mesmo pedido (uma segunda falta, ou um cancelamento depois de uma falta) era engolido em silêncio. A Trava do PC bloqueia qualquer texto que mencione `add_tokens`, por isso esta migração tem de ser aplicada por ti ou por mim com o teu "vai" explícito.

## O que foi feito e como foi provado

**Bloco 1 — servidor.** Aplicada e no ar só a base, sem dinheiro: a tabela `order_edits` com as colunas pedidas (e mais o `grupo_id` que junta as linhas de uma mesma proposta, o nome e as opções do produto e o campo `liquidacao` que regista o dinheiro que se mexeu), com segurança por linha: o parceiro vê só as da loja dele, o cliente só as do pedido dele, o estafeta só as do pedido que leva, o admin vê tudo. Ninguém escreve directo na tabela — só pelas funções do servidor, para os valores nunca virem da app. A tabela entrou no tempo real. Ficou o interruptor `order_edit_enabled` a falso, e duas funções do painel: a lista geral e cancelar uma proposta pendente. Migração: `supabase/migrations/20260922200000_parceiro_edita_pedido_base.sql`.

A proposta de dinheiro recalcula tudo pela regra que já está no ar e não mete percentagens no código: o subtotal novo é o antigo menos o preço da linha tirada, mais o preço de app do produto acrescentado com os extras (a mesma função que o orçamento do cliente usa para os extras); a taxa de serviço, o markup oculto e a comissão saem de `pricing_calculate` com o mesmo acerto por loja do gatilho `zz_relabel_partner_split_por_loja` (por isso lojas com percentagem própria, como o Mr Kebab a 15 por cento, ficam certas); a taxa de pedido pequeno sai de `small_order_fee_calc` com a loja e dá zero; entrega, saco e ganho do estafeta não mudam. O que a loja recebe no fim continua a sair do livro (`post_order_to_ledger`) na entrega, que lê o subtotal do pedido nesse momento — ou seja, o editado. Só se pode editar enquanto o pedido não saiu da loja, só o dono da loja (ou o admin), e com o pagamento já confirmado.

Provas. Corri a proposta inteira dentro da base real, numa só transacção que se desfaz no fim, com todos os gatilhos verdadeiros dos pedidos. As dez provas passaram: tirar com dinheiro (total de 9,67 para 7,21, igual ao cêntimo a um pedido que tivesse nascido já assim, e a soma subtotal mais taxa mais entrega mais saco bate com o total, e loja mais markup mais comissão bate com o subtotal); tirar com cartão (reembolso de 1,23, igual a total antes menos total depois); acrescentar com cartão, que fica à espera sem mexer no pedido, depois pede a cobrança de 33,60 e só depois de pago aplica, outra vez igual ao cêntimo a um pedido nascido assim; acrescentar recusado, pedido intacto; MB Way numa loja com 15 por cento, tirar duas vezes seguidas, com a carteira a receber as duas diferenças inteiras (13,04, repartidas oitenta/vinte); e as guardas (outra conta não mexe na loja, dinheiro acima de 40 euros recusado, depois de sair da loja já não se mexe). Depois confirmei que nada ficou gravado. Numa cópia local do esquema fiz ainda um varrimento de 4 000 pares de valores entre 0,01 e 200 euros nas duas lojas: zero diferenças ao cêntimo. A prova real apanhou um erro que a cópia local não tinha — `total` e `customer_total` são colunas calculadas a partir do preço e não se podem escrever — e ficou corrigido. Tudo em `provas/parceiro-edita-pedido-2026-09-22/`.

**Bloco 2 — app do parceiro (PT-PT).** No cartão de cada pedido, por baixo dos itens, aparecem "Acrescentar produto" e "Marcar em falta". Marcar em falta abre a lista das linhas com um contador por linha. Acrescentar abre os produtos da loja com um campo de pesquisa no topo que filtra enquanto se escreve e ignora acentos ("acai" encontra "Açaí"); ao tocar num produto abrem as opções e extras com as mesmas regras do carrinho do cliente, e a quantidade. Antes de enviar há sempre um resumo com o total antes e o total novo, vindo do servidor. Cada proposta mostra o estado: "À espera do cliente", "Aceite", "Aceite · a pagar", "Em falta · devolvido", "Recusado". Enquanto há uma proposta à espera, o botão de acrescentar fica parado. E o catálogo do parceiro ganhou o mesmo campo de pesquisa.

**Bloco 3 — app do cliente (PT-PT).** No acompanhamento e no detalhe do pedido aparece "A loja quer acrescentar ao teu pedido: X (+Y). Total novo: Z" com Aceitar e Recusar, e "Produto em falta: X. Foram devolvidos Y ao teu cartão / à tua carteira Bora / Pagas menos Y na entrega". O push vai pela função de avisos do cliente com o aparelho do cliente. O recibo mostra o que ele leva de facto, porque os itens do pedido passam a ser os editados; nunca mostra comissão nem markup. No resumo do acompanhamento faltava a linha do saco e a soma não batia com o total por 0,30 — acrescentei a linha. As frases novas têm inglês.

**Bloco 4 — estafeta.** A lista e o valor a cobrar em dinheiro chegam actualizados pelo tempo real dos pedidos. No cartão da entrega em curso e no mapa aparece "A loja alterou o pedido: saiu X / entrou Y. Cobra Z na entrega". O push vai pela função que já avisa o estafeta em todos os aparelhos dele.

**Bloco 5 — painel admin (PT-BR).** Novo item "Edições de pedidos (parceiros)" na Operação, com a lista geral filtrada por loja e por estado, exportar CSV, e em cada proposta: quem, quando (hora de Lisboa), antes e depois, o dinheiro que se mexeu, e os botões cancelar proposta, aprovar em nome do cliente e forçar estorno. No detalhe de cada pedido há um separador novo "Edições" com o histórico desse pedido. Aprovar e forçar estorno só funcionam depois do "vai".

**Bloco 6 — fecho.** `flutter analyze`: zero erros (as 251 notas que aparecem já existiam antes). Testes: 15 novos em `test/parceiro_edita_pedido_test.dart` (o JSON que se envia, a conta do rascunho sem erro de vírgula num varrimento de 0,01 a 200 euros, o agrupamento das propostas, os textos de estado, a pesquisa sem acentos e a hora de Lisboa com as mudanças de hora); a suíte inteira deu 633 verdes. O teste apanhou um erro verdadeiro na tabela de acentos (o "ç" virava "n") e ficou corrigido. Chão anti-trapaça do Juiz limpo, nenhuma zona protegida tocada.

## Coisas fora do âmbito que encontrei (não corrigi)

Há pedidos antigos de loja parceira com a taxa de pedido pequeno gravada mas não somada ao total — por exemplo o e1078830 da Goola: taxa 1,39 gravada, total 16,16 que não a inclui. Convém ver se foi cobrada. A função da proposta protege-se disto: só conta a taxa pequena se ela estava mesmo dentro do total.

O ecrã `restaurant_dashboard_screen.dart` parece morto — ninguém o abre — e é um gémeo do painel do parceiro.

A Edge Function `charge-extra` aceita qualquer valor de qualquer pessoa com sessão (cria o pagamento sem o confirmar, por isso o risco é baixo, mas não valida dono nem valor).

O reconciliador de pagamentos vai marcar os pagamentos da diferença como "metadados desconhecidos" (nível informativo). Depois do "vai" convém ensinar-lhe o ramo `purpose = 'order_edit'`, que confere em `order_edits` pelo `order_edit_group`.

A guarda do dinheiro vivo `enforce_cash_payment_limit` tem os 40 euros escritos à mão, em vez de ler `max_cash_amount_cents`.

A função da carteira engolia falhas do registo com "quando der erro, não faças nada" — a proposta troca isso por um aviso registado.

As travas do `.claude/settings.json` apontam para caminhos do Windows; nas sessões na nuvem só vale a lista de proibições, os ganchos não correm. Respeitei a regra à mão.

Na especificação, a segurança dizia "o parceiro insere as da loja dele". Optei por nenhuma inserção directa: só pela função do servidor, que calcula os valores. É mais apertado do que o pedido e evita que a app mande preços.

## PARA O DANILO

Só uma coisa: responder "vai" para eu aplicar a parte do dinheiro e ligar o interruptor. Depois disso faço a prova real em dinheiro na Sabores de Casa e mando as fotografias.

## Atualização — "vai" do Danilo, 22/09 ~21:00 (hora de Lisboa ~22:00)

Aplicada a migração do dinheiro, agora com o nome `supabase/migrations/20260922200100_parceiro_edita_pedido_dinheiro.sql`. A única diferença para a proposta é que deixou de ligar o interruptor. Antes de aplicar, o ficheiro final passou outra vez as 13 provas na cópia local. Depois da aplicação confirmei o resultado:
- a função da carteira tem a chave nova e o corpo antigo ficou guardado em `bkp_fn_wallet_credit_refund_split_20260922`;
- as nove funções novas existem;
- só o servidor as pode chamar onde deve;
- o interruptor continua desligado.

Publicada a Edge Function `order-edit-settle` (versão 1, com verificação de sessão). Um teste inofensivo com uma proposta que não existe devolveu 404, como devia, sem tocar na Stripe. O reconciliador de pagamentos passou à v3 e passa a reconhecer as cobranças das edições: confere que a proposta foi aplicada com esse mesmo pagamento, e uma segunda cobrança paga para a mesma proposta aparece como crítica. Corri-o uma vez: 0 achados, 0 erros.

Prova real em dinheiro na Sabores de Casa, com um pedido de teste da conta de demonstração do cliente (dinheiro, marcado como teste, Estafeta Demo). O pedido tinha 3 Paçocas, 2 Filtros e 1 Água, com o total de 9,67:
- O dono marcou 1 Paçoca em falta. O total desceu para 8,44 e ficou registado "pagas menos 1,23 € na entrega".
- O dono propôs acrescentar um Copo Mega com Mel (+15,75). A proposta ficou à espera do cliente.
- O cliente aceitou e o total subiu para 24,19.
- No fim, subtotal 20,37 mais serviço 1,02, entrega 2,50 e saco 0,30 dá exatamente 24,19.
- A loja recebe 17,46. Loja mais markup mais comissão bate com o subtotal.
- Os valores são os mesmos que a regra dá a um pedido acabado de fazer.
- O cliente recebeu os dois avisos na app. O push do cliente respondeu "sem aparelho", porque a conta de demonstração não tem nenhum registado.

**A prova apanhou uma falha, que ficou corrigida.** O aviso ao estafeta não chegava. A função `notify-driver-assigned` que está no ar recusava o tipo `order_updated` com erro 400, e o aviso dentro da app ia para o `drivers.id` em vez do `user_id`. A correção está na migração `20260922210000_order_edit_aviso_estafeta.sql`:
- o aviso passa a ir com o tipo `order_reassigned`, que a app do estafeta já mostra com o título e o texto enviados;
- o aviso dentro da app passa a ir para o `user_id` do estafeta.

Provado depois da correção: push enviado aos 2 aparelhos do Estafeta Demo (2 de 2) e aviso dentro da app no `user_id` certo.

O pedido de teste foi fechado com `admin_cancel_order`: dinheiro, taxa 0, reembolso não aplicável, e zero linhas no livro e na carteira. A criação do pedido de teste disparou o aviso normal de "pedido novo" ao admin (Telegram e push). Foi esse aviso, não um erro.

**Interruptor `order_edit_enabled`: LIGADO a 22/09 às 22:56 (Lisboa).**
- A primeira corrida do build (850b812) falhou no autoteste. O arnês media a janela de loja fechada em UTC e não em hora de Lisboa, e às 22h de Lisboa os supermercados fecham. O teste foi corrigido no commit d0f499e.
- A corrida 35784854572 (d0f499e) passou o autoteste nos 3 perfis e o envio ao Google Play: build 617, versão 1.0.2+617.
- Só depois disso: `UPDATE platform_settings` com valor `true`, mais uma linha em `admin_audit_log` (`platform_setting_changed`). Confirmado por SELECT: `order_edit_enabled = true`.
- Telegram enviado (resposta 200).
- Para desligar: `order_edit_enabled=false`. A app deixa de mostrar os botões em até 2 minutos (cache do `ativo()`), e o servidor recusa logo com `EDICAO_DESLIGADA`.
