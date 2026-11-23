# Embalagem da Boom! Burger — relatório (23/11/2026)

Missão `prompt-embalagem-boom-2026-11-23` (ordem da Claude.ai, autorização do Danilo 23/11 10:44). Claude Code no PC, motor Opus 5.5. Registo: e2e_log fluxo `embalagem-boom-2026-11-23` (ids 13992 a 14014).

## Fiz isto

A app passou a mostrar a "Embalagem" da loja no lugar do saco de 0,30 €, com o nome e o valor que o servidor manda. No carrinho e no ecrã de pagamento a linha lê o `bag_label` e o `bag_fee` da cotação. Antes de a cotação chegar, a conta provisória segue a mesma fórmula do servidor: 1 € a cada 30 € na Boom. Com isto o total mostrado bate ao cêntimo com o que o servidor cobra. O detalhe e o seguimento do pedido do cliente perguntam ao servidor se aquele valor é a embalagem da loja.

Na app do parceiro aparece "Embalagem (é da loja)" no detalhe do pedido e no fecho da semana. No painel admin a ficha da loja tem um cartão novo, "Embalagem da loja", com os campos "Embalagem por escalão (€)" e "Escalão a cada (€) de pedido". Os dois vazios querem dizer saco normal. Ao gravar, o cartão lê de volta o que ficou no servidor. O acerto de caixa do pedido e o acerto semanal mostram "Embalagem (da loja)".

Na app do estafeta não mudei nada, porque já estava certa. Confirmei no código e no servidor que o "cobra ao cliente" vem do servidor, já com a embalagem. Confirmei também que o "paga à loja" continua a ser o preço de balcão, sem a embalagem, que vai para a loja no acerto da semana.

O ficheiro protegido dos preços (`pricing_service.dart`) não foi tocado: a troca é feita no carrinho, como já se fazia com o saco das festas. A Boom continua desligada no servidor; não gravei nada lá.

Ramo de ensaio `ai/2026-11-23-embalagem-boom`, com 2 commits: e9ba25e5 (o trabalho) e 3c5f2cf4 (correções do revisor). O ramo foi feito a partir do ramo de produção (a8d65c47).

## Falta isto (e porquê)

Falta enviar o ramo para o servidor e publicar nas 3 lojas. A tranca do PC recusou o envio, mesmo do ramo de ensaio, com a regra "publicar é da Claude.ai", e eu não a contornei. Por isso ainda não há versionCode Android nem build iOS novos, e não dá para ligar a Boom.

Os testes automáticos estão escritos (`test/embalagem_da_loja_test.dart`), mas não os corri no PC. Havia só 301 a 424 MB de memória livre, para um portão de 800 MB, e esta pasta não tinha as dependências instaladas. Vão correr no CI, no job A do build_ios, quando o ramo for enviado. Para compensar, um revisor de contexto limpo leu o código todo. Não encontrou erros de compilação e refez à mão os 6 totais do teste. Também apontou 3 defeitos pequenos, já corrigidos. A verificação nas 3 plataformas fica para depois do envio.

## Erros que encontrei (no servidor, não corrigi)

1. **O extrato do parceiro, em cada pedido, conta mal com a embalagem:**
   - o "cliente pagou" fica sem a embalagem;
   - a "parte da Bora" aparece mais baixa pelo valor da embalagem;
   - não devolve o valor da embalagem, por isso a app não pode mostrar essa linha em cada pedido do extrato.
2. **O acerto semanal do painel não mostra a embalagem.** A função que lista os acertos não devolve o `embalagem_total`; a app já está pronta para a mostrar quando vier.
3. **A migração da embalagem não está no repositório.** É regra que o SQL aplicado em produção também lá fique.
4. **A regra que decide se o valor é embalagem dá falsos positivos.** É a regra do resto da divisão, e com lojas de embalagem pequena (0,10, 0,15 ou 0,30) um saco normal passaria a chamar-se Embalagem. Na Boom (1 €) está certa.
5. **Três sítios ainda dizem "Sacos"**, com o valor certo: o cartão de preço do Assistente, o resumo de compra do estafeta e o fecho mensal do painel.

## Próximo passo

A Claude.ai:
1. envia o ramo `ai/2026-11-23-embalagem-boom` e abre o pedido de revisão para `autonomous-night-2026-04-29`;
2. vê o CI verde e publica nas 3;
3. liga a Boom (`embalagem_cents = 100`, `embalagem_escalao_cents = 3000`) e sobe a versão mínima.

Antes, convém corrigir os pontos 1 e 2 do servidor.
