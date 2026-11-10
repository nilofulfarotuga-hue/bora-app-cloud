# Fecho do contabilista — relatório (10/11/2026)

Missão fecho-contabilista-2026-11-10 · Claude Code (Opus 5.5) no PC · ramo de ensaio `ai/2026-11-10-fecho-contabilista`.

**Fiz isto.** Arrumei o que vai para cada um com as regras que fechaste com o Hugo. No email do fecho ao
contabilista tirei o "a Bora fatura esta comissão à loja", o "recibo verde ao adquirente" e o TVDE; ficou
a frase "Cada prestador fatura a sua parte; o regime de IVA e a retenção de cada um são confirmados pelo
contabilista". A faturação da parte da Bora passou a ser uma só linha "consumidor final" (outubro: 159,17 €),
nunca às lojas. Juntei ao fecho os tokens oferecidos e os descontados (outubro: 3,29 € descontados em 3
pedidos), os códigos promocionais (o BEMVINDO: 7 usos, 35 € em tokens), os prémios do check-in, os cancelados
e reembolsos, as taxas da Stripe só da parte da Bora (outubro: 5,95 €), os pedidos com prejuízo, os pedidos
em que o cliente pediu NIF e a lista do que falta a cada prestador para a lei DAC7. O email aos estafetas, à
limpeza e às lojas também ficou com as regras novas (sem "isento de IVA" nem "sem retenção" fixos; às lojas:
"a parte da Bora é faturada aos clientes"). Outubro não foi reenviado a ninguém.

No painel, o ecrã do fecho do mês tem agora "Para o contabilista" com o mesmo texto que vai ao Hugo, com
os botões copiar, CSV, nota tua e reenviar. Há um ecrã novo "Dados fiscais (DAC7)" com quem tem dados em
falta. Hoje faltam dados a 7 (4 prestadores e 3 lojas parceiras; os nomes estão no painel, não aqui,
porque este ficheiro vai para o repositório público). Quem tem dados em falta passa a ver na app uma barra
vermelha "Faltam dados para as Finanças" que abre o formulário — limpeza, Casa, lavagem e lojas. Na app do
estafeta tirei o resto do NIF da Bora: o cartão do NIF só aparece quando o cliente pediu fatura.

Conferi outubro e novembro pedido a pedido: o dinheiro bate com o que o estafeta e as lojas receberam. Só
há quatro coisas a saber: dois pedidos em dinheiro de outubro sem o valor em dinheiro escrito (um Favor de
10,08 € e um pedido de loja parceira de 24,81 €); em novembro o Burger King cobrou mais 2 € na Stripe, que é a
gorjeta, está certo; e o Favor de 03/11 tem 10,77 € que o cliente te pagou à parte. Não mexi em dinheiro de
ninguém. O código BEMVINDO não é desconto num pedido: dá 1000 tokens (5 €) na conta do cliente, por isso o
uso fica sem pedido; agora fica a ligação gravada. Pus um teste automático que avisa se, num mês, as contas
do fecho não baterem (passou na produção de setembro a novembro). Escrevi o passo a passo para dar ao Hugo
acesso só de ver à Stripe da empresa.

**Falta isto.** Publicar. A trava de segurança do PC não deixa esta sessão mexer no banco, nas funções do
servidor nem enviar para as lojas — isso é a Claude.ai que publica. Deixei tudo pronto e provado numa cópia
local com os dados reais de outubro e novembro (42 verificações certas), com a lista exata em
`docs/propostas/fecho-contabilista-2026-11-10/LEIA-ME_PUBLICAR.md`. Também falta dar o acesso à Stripe ao
Hugo: precisa do email dele e do teu "autorizo" nesse dia. A tarefa do WhatsApp do dia 1 não a mudei: a
Claude.ai ajusta-a para mandar o texto novo depois de publicar.

**Erros que encontrei pelo caminho.** Um grave: hoje qualquer pessoa com conta na app consegue ler o resumo
da Stripe e a lista dos prestadores com NIF, email e ganhos (provei-o). A correção está pronta e marcada
como urgente para a Claude.ai aplicar primeiro. Também: a versão 3 do email aos prestadores já estava
publicada (o pedido dizia que não); o fecho de novembro dizia que a entidade era tu em nome individual (fica
a sociedade); o extrato da Stripe da empresa ainda não tem linhas de novembro, por isso as taxas de
novembro vão pela estimativa dos pedidos.

**Próximo passo.** A Claude.ai aplica primeiro a correção de segurança, depois o fecho, publica as funções e
a app nas 3, e ajusta a tarefa do WhatsApp.

## Provas

- SQL: `docs/propostas/fecho-contabilista-2026-11-10/PROVA.md` (saída literal, 42 OK, "TUDO CERTO").
- Teste D3 na produção: `fecho_mensal_consistencia_test: OK`.
- Segurança (produção, só leitura): como utilizador comum com uid inventado, `fecho_mensal_prestadores(2026,10)`
  devolveu 2 estafetas e `stripe_extrato_resumo` devolveu o resumo.
- App: `flutter analyze` (Flutter 3.41.2 do CI) sem erros novos; testes dos ficheiros mexidos 100/100;
  bateria completa com o Flutter 3.41.2: 304 ficheiros, 3261 testes, 0 falhas.
- Juiz anti-trapaça (`--base HEAD`): CLEAN, +17 casos de teste.
- Email do contabilista desenhado com os dados de outubro: 12/12 verificações.
- Publicações nas 3 lojas: não feitas nesta sessão (tranca → Claude.ai).
