# Fecho dos pendentes — 31/10/2026 (missão fecho-pendentes-2026-10-31)

Acessos: Claude Code no PC, pasta de trabalho nova C:\BoraLocal\wt-fecho-31-10 (ramo
fecho-pendentes-2026-10-31, feita a partir do servidor 895e0383, porque a pasta principal estava 302
alterações atrás e com trabalho de outras sessões por guardar). Supabase pelo MCP e pelo CLI 2.122.
Autorização: a tua, escrita no chat da Claude.ai a 31/10/2026 22:08, "autorizo publicar e fazer tudo o
que tem que fazer aí", só para esta missão. e2e_log: fluxo fecho-pendentes-2026-10-31 (5794 em diante).

## O que fiz

**Peso ao quilo.** O estafeta já pode tocar no preço de um produto ao quilo na lista de compras e
escrever o valor da etiqueta da balança. A linha mostra "peso variável · toca no preço"; depois de
confirmar fica com o valor real, o previsto riscado e "ajustado ao peso", e marca-se como comprada. Se
a diferença passar dos 30% o servidor recusa e a folha diz para pesar outra vez ou marcar "Não há",
com o intervalo aceite. O cliente recebe o aviso (sino e push), que abre o pedido, e vê no pedido e
no recibo a linha "Ajustado ao peso: 1,12 € → 1,40 €". Nos cartões, na ficha do produto e no carrinho
aparece "Preço aproximado · o valor final depende do peso". No painel admin, em Operação do dia, há
o ecrã "Ajustes de peso" (lista, filtro de 7, 30 ou 90 dias, CSV, abre o pedido); no catálogo há o
interruptor e o filtro "Peso variável" (pede motivo); o detalhe do pedido mostra os ajustes; e as três
definições aparecem explicadas. No servidor: a função e o gatilho que marcam sozinhos como "ao quilo"
os produtos novos do Continente, Auchan, Intermarché e Pingo Doce (fruta e legumes avulsos, talho e
peixaria frescos, charcutaria ao corte); revi uma amostra de 40 produtos que ficam de fora e estão
todos bem de fora (embalados com peso escrito). A regra nova apanhou mais 7 que estavam esquecidos
(banana, laranja, cebola, maçã, abóbora e melancia do Intermarché na secção errada, e a meloa da
Auchan): agora são 1185. A melancia "com poucas sementes" já não fica de fora. A cópia de teste de 26/10
foi apagada.

**Melancias e melões.** Os 32 da Auchan e do Intermarché tinham o preço do quilo como se fosse a peça
(o Melão Amarelo da Auchan estava a 1,99 €). Agora a peça leva o peso médio: melancia 4 kg, mini e
metade 2 kg, melão 2 kg, metade 1 kg, meloa 1 kg, metade de meloa 0,5 kg. Exemplo: Melão Amarelo
Auchan passa a 3,98 € e o nome acaba em "(~2 kg)". O robô semanal da Auchan, que à terça escreve o
preço do quilo, já não estraga isto: o servidor converte sozinho (provado sem gravar: 2,29 €/kg virou
4,58 €). O estafeta acerta o peso real na balança como nos outros.

**Cobrança no cartão.** A função cobrar-diferenca-peso está publicada e DESLIGADA. Provei: sem chave
recusa (401); com a chave do servidor responde "desligado, nada cobrado". Só cobra com o interruptor
ligado, no mesmo cartão do pagamento, o valor exacto que o talão gravou e uma vez só.

**Robô de suporte.** Publiquei a versão 30 (com login obrigatório, igual à que estava). Tirei do texto
do Gemini as comissões, a margem de 15%, a divisão das reservas entre o restaurante e a Bora, e a frase
"sem margem". Nos dois motores o reembolso agora diz: tu escolhes, carteira Bora com o valor todo e
podes usar logo, ou devolução para o cartão ou MB Way com o valor todo em 5 a 10 dias úteis; o 80/20
saiu. Os tokens: numa compra usas no máximo metade do valor dos tokens que tens. Também tirei o teu
nome das descrições das ferramentas que vão para o Gemini. Provas com a conta de teste: a "oi"
respondeu "Olá! Tudo bem? Em que posso ajudar-te hoje na Bora?"; a "quero o meu dinheiro de volta"
pediu o pedido e o que aconteceu; a "quanto ganha a Bora com isto?" respondeu que isso não pode
partilhar e ofereceu ajuda. Respondeu o Claude (claude-sonnet-5-5). A ronda das chaves deu 43
respostas certas.

**As 3 alterações antigas** da pasta principal (beac89d3, 8a5f3ab0, bdfbf1d6) já estão no servidor
desde 25/10, com o conteúdo igual letra por letra. Não havia nada a enviar.

**Limpeza.** O ecrã de cancelar diz "Cancelamento sem taxa: marcaste há menos de 5 minutos." nos
primeiros 5 minutos depois de marcar, igual ao servidor. A marcação já não mostra "Antecedência
mínima: 0 h".

**Porteiro do Telegram.** No painel, em Robôs e Autonomia, "Porteiro do Telegram": a fila dos avisos,
o nível (urgente, resultado, informação), para onde foi (chat ou registo), se já foi tratado, e o
botão "Reenviar". No servidor fiz as duas funções, só para admin (provado: sem ser admin recusa).

**Texto da App Store** ("O que há de novo") atualizado com o peso ao quilo e a limpeza; estava parado
desde 17/10.

## Publicação

Antes de enviar: o Juiz anti-batota deu limpo (41 ficheiros, 33 casos de teste novos); o analisador
do Flutter deu zero erros; a bateria toda de testes com o Flutter do CI deu 247 ficheiros e 2663
testes verdes, zero falhas. Com o Flutter mais novo do PC há 4 ficheiros que ficam vermelhos por um
aviso novo desse Flutter, em ecrãs em que não mexemos; o CI usa o outro e passa.

Enviado para o servidor a 01/11 às 02:22 (hora UTC), commit 21cb44ed, com três registos: o do peso e
companhia, o do robô e um de notas. As três plataformas publicaram:
- Web: verde às 02:24. O app.boraguarda.com e o bora-app-web.pages.dev dizem commit 21cb44ed, e o
  código da página já tem a folha da balança, os ajustes, a limpeza e o porteiro.
- Android: verde às 03:04. O autoteste dos 3 perfis passou, o pacote foi para a Play Store (teste
  interno, fechado e produção) e o versionCode subiu para 703.
- iPhone: verde às 04:10. O simulador passou, a versão 1.0.33 (build 221) foi enviada e submetida à
  Apple, que a leu de volta "à espera de revisão", com lançamento automático depois da aprovação.

## Erros que encontrei e não corrigi (ficam para decidir)

1. Pingo Doce: "Melancia - unidade 1KG" está a 19,48 € e "Melão Branco - unidade 4.25KG" a 10,90 €;
   parecem errados. Não mexi (a ordem era Auchan e Intermarché).
2. Lidl e Mercadona têm as secções do catálogo trocadas (detergente e chocolate em Peixaria, por
   exemplo). Por isso ficaram fora do gatilho do peso.
3. A secção "Frutas & Legumes" do Pingo Doce tem coisas que não são fruta (velas, escovas de dentes,
   vinho). E o "Choco com Tinta" do Intermarché fica fora do peso por causa da palavra "tinta".
4. Os tabuleiros de fruta cortada da Auchan ("pedaços Kg") também têm o preço do quilo como peça.
5. No painel, o interruptor geral do peso (weight_adjust_enabled) aparece só para ler; o limite de
   30% edita-se pelo caminho do dinheiro, com motivo.
6. O caminho antigo de "cobrar diferença no cartão" das lojas parceiras (processExtraCharge) marca o
   pedido como pago sem cobrar. Na prática não corre, porque nas parceiras o estafeta não acrescenta
   produtos. Está numa zona protegida: não mexi.
7. Os pushes de estado do pedido do cliente (notify-client) não abrem o pedido ao tocar; só o do peso
   abre.
8. O catálogo carregado normalmente não traz a coluna "maior de 18", por isso a etiqueta +18 só
   aparece pela pesquisa.
9. A pasta principal C:\BoraLocal\projetosflutter\bora_app continua 302 alterações atrás, com trabalho
   de outras sessões por guardar. Não mexi.

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO

Aplicado nesta missão, dentro da tua autorização: os preços das 32 peças (melancias, melões e meloas
da Auchan e do Intermarché), registados em catalog_price_updates com decided_by
claude_code_fecho_31_10; reverte-se com o comando que está na migração 20261031222024. A função de
cobrança no cartão está no ar mas DESLIGADA. Para a ligar é só pôr weight_adjust_card_charge_enabled
a true nas Definições; no primeiro pedido com cartão que pese mais, ver em Operação do dia → Ajustes
de peso se ficou "cartão cobrado", e se ficar "Bora assume" chega um aviso urgente ao Telegram.
Nos últimos 60 dias não houve nenhum pedido a cartão, só dinheiro e MB Way.

## Falta

Não fiz a prova com um pedido verdadeiro a dinheiro no emulador (banana e frango do Continente,
como dizia o prompt de 26/10). O PC tinha entre 1,2 e 3,5 GB livres e o emulador precisa de 3 GB
seguros; e um pedido de teste em produção é oferecido a estafetas reais. Em vez disso: as contas do
servidor já tinham sido provadas a 26/10 com o pedido 11926093 em transação desfeita, e hoje a folha
do estafeta, a nota do cliente, a linha ajustada e a limpeza têm testes automáticos (27 casos novos) e
fotografias em 3 tamanhos de ecrã. A primeira compra real ao quilo vê-se em Operação do dia → Ajustes de
peso.

A página regras-do-danilo do livro ainda diz que o reembolso para a carteira é 80% saldo e 20%
tokens. Não lhe mexi porque é a tua página de regras; a Claude.ai deve atualizá-la com a tua ordem de
31/10 06:44.
