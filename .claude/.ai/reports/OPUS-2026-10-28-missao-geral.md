# Relatório — missao-geral-2026-10-28 (parcial, 29/10 05:10 UTC)

Motor: Opus 5.5 até às 04:58 de 29/10; depois Fable 5.1 só para fechar registos e este relatório, porque
o limite semanal do Opus acabou (volta a 1/11 às 18:00 de Lisboa). Cópia de trabalho
`C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`, 21 commits por cima do origin
9eed27ff. Nada foi enviado para o servidor git. Rasto completo no e2e_log, fluxo
missao-geral-2026-10-28, ids 5037 a 5095. Ponto de continuação em
`.claude/.ai/inbox/CONTINUAR-missao-geral-2026-10-28.md`.

## Acessos e caixas
Duas caixas bora-tranca pedidas (28/10 20:30, JANELA 1) e uma terceira a 29/10 04:55 (conserto do
fecho do mês), todas com Telegram antes. Nenhum push. Nenhuma Edge Function publicada. Nenhum
dinheiro devolvido nem saldo mexido.

## O que NÃO foi feito
Revisor independente do Bloco 1 (parou sem veredito; sem ele não se pede "publica"). Bloco 2 na app
(diálogo de cancelamento e textos). Bloco 3 N1 a N5 (NIF opcional nos ecrãs, entrega grátis no ecrã).
Bloco 4 ficou a meio (código do robô escrito, sem testes, sem instalar, sem tenant). Bloco 5 cartazes
(nada). Bloco 6 E5 (lista dos "reportado" antigos recolhida, não tratada). JANELA 2 não aconteceu.
Publicação: nenhuma. Tudo isto está mapeado no CONTINUAR.

## Bloco 0 — provado
JANELA 1 aplicada às 20:33 e 20:34 (versões 20261028203348 e 20261028203353), lida de volta: gatilho do
IVA ligado, função de teste apagada, dois backups com 1 linha, nota nova no fecho, função fechada a
anon. Prova em transação desfeita: fatura de novembro dá "IVA 23% incluído — regime normal", outubro
fica na isenção. Cinco ramos prontos juntados sem o histórico (7 commits; o NIPC foi tirado da cópia da
migração dos termos porque o repo é público). Conflito no horário das lojas resolvido pelo lado do
servidor. 204 de 205 testes dos ramos verdes; o único que falhava pedia à app uma regra que o servidor
não tem (madrugada pela véspera) e passou a provar a paridade. Cinco migrações de produção que faltavam
no repo foram copiadas com md5 igual ao da base; seis ficaram listadas para o Claude.ai pôr (a guarda
recusa o texto delas). Flutter analyze: 0 erros.

## Bloco 1 — estafeta (feito, à espera do revisor)
A: "7. 88", "7,88" e "7.88 €" dão 788 cêntimos; o campo só aceita dígitos e um separador; os avisos
aparecem dentro da folha; 30 s para a foto e 20 s para o fecho do talão, com a foto guardada para
tentar de novo. B: a recolha mostra o nome da loja e a morada no pedido único, na lista de compras, no
pino e na oferta adicional. C: o valor a cobrar vem sempre do servidor; sem ele é total menos saldo,
tokens e crédito, nunca o bruto; o estafeta vê "Total · já pago com saldo/tokens · RECEBER"; o cliente
vê o total e, à parte, o que paga em dinheiro; o painel tem a conta linha a linha com aviso. 262 testes
verdes em 24 ficheiros; analyze 0 erros; anti-trapaça limpo. Seis pedidos antigos com o erro do bruto
(09/09 a 28/10) estão num ficheiro fora do repo; soma dos cinco antigos: 18,34 € cobrados a mais. Nada
devolvido.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (para o Claude.ai, proposta prop-9f87a6c6): o acerto do estafeta a
dinheiro usa o total bruto nas funções post_order_to_ledger e apply_driver_cash_settlement; no pedido de
28/10 ficou −1,60 € quando devia ser +9,44 € (11,04 € contra o estafeta). A folha do Favor (ficheiro
protegido) ainda cobra o bruto. A faixa "entregar ao parceiro" contradiz o acerto semanal. A vigia C5
está pronta para a JANELA 2. A versão v2 da compra em loja parceira não tem chamadas (só reportar).

## Bloco 2 — reembolsos (servidor preparado, nada publicado)
Por leitura: cliente, admin, automático e refund devolvem ao meio original; o cancel-order-with-choice
sem escolha dava erro 400 (agora meio original); o reprocessamento manda MB Way falhado para o saldo; o
painel de pedidos de cancelamento vem com "saldo" marcado; o cancelamento pelo sistema não devolve o
saldo usado; quem cancela perde os tokens (contagem sempre 0 em 21 de 21 pedidos em 60 dias) e o
sistema devolve a mais pela janela de tempo. Quatro Edge Functions não vermelhas mudadas no repo (por
publicar) e o pacote completo em docs/propostas/.../bloco2 com a ordem de aplicação (o _shared v2 tem
de ir antes do SQL dos tokens, senão os tokens viram saldo). Recomendação: função idempotente
consumir_tokens_do_pedido chamada por gatilho no INSERT do pedido. Entrega ao Córtex: duas propostas
passaram (prop-38d65b15, prop-d7d3717b), a terceira foi cortada pelo classificador e não se insistiu
(docs/TRANCAS.md).

## Bloco 3 — Boom (parte fiscal feita)
Erro grave encontrado e consertado: a migração do IVA de ontem pôs "23%" dentro de um format() e o
"Fecho do mês" do painel falhava em qualquer mês desde as 20:34; reproduzido como admin, migração
20261029045558 aplicada às 04:55, provada (outubro 107,63 €, novembro e setembro respondem, nota do IVA
vem do servidor). Painel: filtro Semana e CSV com base e IVA (de novembro em diante base = valor ÷
1,23), faturas com NIF e nome, taxas de cancelamento. Para as Finanças, outubro: o fecho dá 107,63 € e a
soma das faturas da Bora 27,87 €; diferença 79,76 €, explicada ao cêntimo (83,13 € pagos a estafetas
entram no fecho e não na fatura; −1,87 € de um pedido no prejuízo; +1,00 € de TVDE sem fatura; −2,50 € de
taxa de cancelamento fora do fecho). Não se mexeu na conta. N6: a função da parte da loja arredonda uma
vez no fim; em 200 combinações 95 batem ao cêntimo e 105 não, diferença máxima 0,03 €, soma −0,96 €; face
ao balcão real a loja recebe 9,96% a mais até chegarem os preços certos. F1, F2 e F3 têm o SQL pronto e
provado em transação desfeita (F2 muda 17 linhas de prestadores; F3 tira uma loja da lista dos termos);
na app os termos só aparecem a lojas de comida e mercado aprovadas. 34 testes verdes.

## Bloco 4 — robô (a meio)
Código do modo restaurante escrito (fluxo pelo quote_order_pricing e create_order, moradas, avisos por
estado, nome vindo do tenant), SQL das colunas e da tabela order_origem pronto para a JANELA 2, tenant com
os números fora do repo. Sem testes, sem instalar, sem tenant criado, W4/W5/W6 por fazer. Commit marcado
WIP.

## Bloco 6 — erros
E1: o ataque de 401 era o nosso próprio script de sincronização das propostas do Córtex na VPS, a
chamar com a chave anon quatro funções fechadas a anon desde 04/09 (não 21/10). Estava partido há 8
semanas: a última proposta espelhada antes de ontem é de 04/09. Consertado com a chave de servidor lida
em tempo de execução (nada em ficheiro versionado), paragem de 30 min se a base recusar, filtro das
linhas que não são propostas e memória dos pids já enviados. Prova: 0 respostas 401 entre 28/10 20:56 e
29/10 04:44 (2715 × 200 e 7795 × 204); 72 propostas novas entraram na Central. E2: o carrinho reposto já
confirma a loja na base (adendo das melhorias, 3 testes); o servidor nunca confiou na app. E3: o 500 na
lista de utilizadores reproduzido (per_page=50) — três contas com campos de texto a NULL; conserto
preparado, não aplicado. E4: repositório continua público (só o Danilo fecha). E6: PADRAO_BORA §3.15 com
as seis regras, skill mods-bora com as duas armadilhas, duas linhas em erros-aprendidos.

## Juiz (parcial)
Anti-trapaça contra a produção: 0 testes apagados ou enfraquecidos, +242 casos; 10 avisos de "olho
humano" conferidos linha a linha (9 são só o formato de moeda PT do item 6, mesmos números; 1 é o aviso
da loja fechada a aceitar "amanhã às"). Analyze e bateria completa a correr no fecho desta sessão —
resultado no e2e_log (bF.a). Sem revisor independente do Bloco 1 e sem fiscal de segurança ainda.

## PARA O DANILO
Nada para clicar agora. O "publica" só se pede depois do revisor. Decisões só tuas, quando quiseres:
(1) se o estafeta entrega mesmo dinheiro à loja nalgum pedido (a faixa diz que sim, o acerto diz que
não); (2) o número do WhatsApp da Boom para o cartaz K3 (na base só há o telefone 923); (3) fechar o
repositório ("fecha"); (4) os 4 pontos de dinheiro das propostas prop-9f87a6c6 e prop-38d65b15 ficam
com o Claude.ai e esperam o teu "vai".
