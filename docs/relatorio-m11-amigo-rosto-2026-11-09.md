# Relatório M11 — o Amigo com rosto, os talões no Drive, a pesquisa e a Casa (09/11/2026)

Missão `m11-amigo-rosto-2026-11-09`, com os adendos 1 (05:23), 2 (05:40), 3 (07:02) e 4 (07:42).
Registo passo a passo no `e2e_log` (fluxo `m11-amigo-rosto-2026-11-09`). Publicado no ramo de
produção em três envios: d8b4d351 (07:18), 2ff432e4 (08:07) e a5e483d3 (09:28).

## Fiz isto

**O Amigo com rosto.** O Amigo deixou de ser uma conversa escrita e passou a ser o robozinho do
Dipsy dentro da app: verde, antena laranja, olhos num ecrã escuro, com as seis expressões (alegre,
triste, surpreso, pensativo, confuso, a falar) e ainda "a ouvir". Pisca os olhos, mexe o olhar,
respira, dá um pequeno salto quando muda de cara. Por defeito aparece com o corpo e a camisa com o
logótipo da Bora; no painel pode passar a só cara. A boca acompanha a voz sílaba a sílaba, a voz é
sempre de Portugal (nunca brasileira nem inglesa; sem voz de Portugal, fala por legenda). Na página
inicial está "Sou o Amigo. Fala comigo" com o rostinho, e há o mosaico "Amigo" no início das
categorias. O ecrã do Amigo tem a legenda grande, o microfone "Fala comigo", "Escrever" e "Ver
conversa". A cara reage ao que acontece. No painel há a secção "Rosto do Amigo" com o rosto ao vivo,
os interruptores e os números de uso.

**Adendo 1.** No fim de cada conversa o Amigo diz em voz, com a cara alegre, a deixa que o sistema
escolheu, e mostra-a num cartão que conta o clique. E deixou de se chamar "de compras" em todo o
lado que o cliente vê.

**Adendo 2, talões no Drive.** Carregaste em "Continuar" na página da Google e a Bora passou a ter
acesso só aos ficheiros que ela própria cria no Drive (mais nada). Os 4 segredos foram gravados no
servidor, a cópia diária ficou ligada e a primeira cópia correu na hora: 45 talões copiados de 45,
na pasta "Talões" do Drive da Bora, verificados um a um.

**Publicação 1 (07:11–07:18).** Banco (definições do Amigo e a tabela dos números de uso), função do
servidor do Amigo e app. Web no ar às 07:20, Android às 08:01 (versão 719), iPhone às 09:04.

**Adendo 4, o Amigo a 100%.** O erro que viste no iPhone ("O cliente disse claramente que não quer
comprar…") tinha três causas e as três foram corrigidas: "não quero comprar" era lido como pedido
de compra; o aviso interno do servidor ia como se fosse uma mensagem tua; e a resposta escrita
para esse aviso chegava ao cliente. Agora o aviso vai como instrução interna, e uma resposta que fale
"do cliente" na terceira pessoa ou cite as regras é deitada fora. Na conversa solta ele fala como
amigo: na primeira pessoa, caloroso, pergunta de volta, sem listar serviços e sem empurrar compras.
Prova com 22 conversas reais nas contas de teste, duas voltas: na segunda, 21 de 22 como amigo,
zero na terceira pessoa, zero "de compras", e as deixas mudam de conversa para conversa. Voz no
telemóvel: o navegador do iPhone só deixa falar depois de um toque, por isso o primeiro toque em
qualquer sítio desbloqueia a voz; se mesmo assim não sair som, aparece "Toca para ouvir" e o toque
repete a frase. O botão do som tem quatro estados claros (Som, Sem som, Sem voz, Toca para ouvir), e
o logótipo da camisa deixou de falhar no Safari antigo. Publicado às 08:07 e 08:11 (função do
servidor versões 19 e 20). Web no ar às 08:10, Android às 08:52 (versão 720; a primeira tentativa
caiu por uma falha de rede a descarregar uma ferramenta e foi repetida).

**Adendo 2, a pesquisa.** Medi primeiro como estava: de 60 pesquisas reais com as palavras que as
pessoas escrevem (com erros e tudo), só 40 mostravam o produto certo nos 5 primeiros. Com o motor
novo dão 60 de 60, no Continente cada pesquisa passou de 316–583 milésimos de segundo para 5–148.
Percebe acentos, plural, palavra a meio, erros de escrita ("bolaxas", "nugets", "papel higenico"),
palavras coladas ("cocacola", "benuron") e uma tabela de 246 sinónimos que se muda no painel
("gelado" leva ao McFlurry e ao Sundae, "paracetamol" ao Ben-U-Ron). Quando não acha nada, aparece
"Não encontrei X aqui" e o botão "Pede ao Amigo", que abre o Amigo já com a frase escrita. A pesquisa
aprende: quando 3 pessoas diferentes escolhem o mesmo produto depois de uma pesquisa sem resultado,
o sinónimo entra sozinho. No painel há "Pesquisas sem resultado". Está no servidor desde as 09:24 e
já serve também as apps antigas, porque a função que elas chamam manteve o nome; provei em produção
como cliente sem conta: "gelado" no McDonald's dá Sundae e McFlurry, "nugets" dá McNuggets,
"paracetamol" na Wells mostra o Ben-U-Ron, "papel higenico" no Continente dá papel higiénico.

**Adendo 3, a Casa & Manutenção.** Ícone novo 3D em cartoon (caixa de ferramentas laranja em fundo
pêssego, 1024 por 1024), selo "Novo" que se liga e desliga no painel com data, o material passou a
ser obrigatório ("Sim, já tenho tudo": o profissional leva só as ferramentas) e aparece na oferta e
no trabalho do profissional. O código foi para as 3 lojas no envio das 09:28 e a chave do selo já
existe no servidor. A Casa continua desligada para os clientes (ver "Falta isto").

**Publicação 2 (09:16–09:29).** Pesquisa no servidor, chave do selo, e o envio da app com a pesquisa,
o "Pede ao Amigo", o painel das pesquisas, a Casa (desligada) e a última correção do Amigo. Web no ar
às 09:32 (confirmado no app.boraguarda.com: o código novo está lá). Android e iPhone: ver o fim.

Todas as vezes que desliguei as travas foi só para publicar, com cópia antes e religadas logo a
seguir, sempre conferidas iguais à cópia: 07:11–07:18, 08:04–08:07, 08:08–08:11, 08:52 (só para
repetir a compilação do Android), 09:15–09:20, 09:23–09:26 e 09:27–09:29.

## Falta isto (e porquê)

**A Casa ainda não está ligada.** O servidor recusou aprovar-te como profissional da Casa: a tua
ficha de profissional da Casa não tem IBAN, data de nascimento nem a autocertificação, e o NIF não
está com os 9 números. É a regra legal das plataformas (DSA e DAC7) que pusemos no servidor, e esses
dados só tu os podes dar. Não a forcei. Sem nenhum profissional aprovado, ligar a Casa deixava os
clientes a pedir sem ninguém para ir, por isso também não liguei a Casa, a faixa da home, o pedido de
prova nem a notificação aos clientes. Está tudo pronto e provado (docs/casa/PUBLICACAO2-casa.md): logo
que a tua ficha estiver completa, corro o resto em poucos minutos.

**Roupeiro (80 €), cama (70 €) e televisão (45 €) não se conseguem pedir.** A Casa só aceita dinheiro
e o dinheiro tem o limite de 40 €. ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Há duas saídas e as duas
precisam do teu "autorizo": cartão e MB Way na Casa pelo mesmo caminho da Limpeza (está escrito e
pronto), ou um limite de dinheiro próprio da Casa.

**Voz do servidor da Google** (para telemóveis sem voz de Portugal): não liguei, porque o projeto da
Google não tem faturação e a Google exige-a mesmo no escalão grátis.

**Vetores do Gemini para a pesquisa:** opcionais (a pesquisa já usa os vetores grátis, que todos os
48 271 produtos têm); a ação para os encher aos poucos está escrita mas não a publiquei.

## Erros que encontrei pelo caminho

A primeira tentativa da pesquisa no servidor foi recusada com "permissão negada" por causa de um
ajuste do motor de erros de escrita: no servidor real não somos administradores e o módulo tem de
estar carregado antes. Reproduzi o erro igual num Postgres local, corrigi com uma linha e provei; a
tentativa falhada não deixou nada aplicado. O script que desliga as travas falhou uma vez a meio
(um ficheiro estava aberto por outro processo): repus tudo primeiro, conferi, e só depois desliguei
de novo. Dois ficheiros antigos (o principal do Android e o web/index.html) têm uma chave da Google lá
dentro e a trava não os deixa gravar; contornei mudando o meu código de sítio, sem mexer na chave. O
teste antigo m10_nif_caixa_app_test tem 6 vermelhos neste PC, que já falham no código de produção
(o Flutter deste PC é mais novo que o do CI); a suíte inteira deu 3173 verdes. Na pesquisa: há dois
índices iguais na mesma coluna dos produtos (gastam espaço), o Lidl está desligado mas os produtos
dele ainda aparecem dentro da loja, há nomes com erros no Continente ("higenico"), e a parte "por
significado" não funciona dentro das lojas para quem não tem conta (a tabela dos vetores não deixa
ler); nenhuma das 60 provas depende disso. Na Casa: o "Trocar candeeiro" (30 €) está no ofício
Eletricidade, que está desligado; aprovar-te ocupa 1 das 5 vagas "2 meses sem comissão". No iPhone,
a faixa "instalar a app" do navegador tapa o microfone do Amigo. Às 07:45 a tua sessão na web tinha
caído (o Amigo dava "sem sessão"): basta entrar de novo.

## PARA O DANILO

1. Completar a tua ficha de profissional da Casa na app (entrar como profissional da Casa, abrir a
   candidatura e preencher NIF, IBAN, data de nascimento e a autocertificação, e enviar). Diz-me
   quando estiver e eu ligo a Casa, a faixa, o pedido de prova e a notificação.
2. Para o roupeiro, a cama e a TV: "autorizo cartão e MB Way na Casa" ou "autorizo limite de dinheiro
   da Casa de X €".
3. Opcional: faturação na Google para a voz do servidor.

## Próximo passo

Acabar de ver o Android e o iPhone da publicação 2, e assim que a tua ficha estiver completa, ligar
a Casa como novidade pelos passos já provados.
