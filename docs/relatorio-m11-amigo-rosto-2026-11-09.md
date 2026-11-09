# Relatório M11 — o Amigo com rosto (09/11/2026)

Missão `m11-amigo-rosto-2026-11-09`, mais o adendo 1 (05:23). Registo passo a passo no
`e2e_log` (fluxo `m11-amigo-rosto-2026-11-09`). Ramo `ai/2026-11-09-m11-amigo-rosto`,
worktree `C:\BoraLocal\wt-m11-2026-11-09`.

## Ficou feito

Encontrei o protótipo do Dipsy inteiro na pasta bora-amigo-teste do Ambiente de Trabalho: o
robozinho verde com antena laranja e os olhos num ecrã escuro, as seis expressões, a boca que
acompanha a voz e o vídeo de 57 segundos. Vi o vídeo a uma imagem por segundo e escrevi a
ficha da personagem em docs/amigo/ficha-personagem-2026-11-09.md, com as seis imagens de
referência.

O Amigo passou a ser esse rosto dentro da app, desenhado pela própria app (não é uma página
web lá dentro), por isso corre igual no Android, no iPhone e na web. Tem as seis expressões
(alegre, triste, surpreso, pensativo, confuso, a falar) e ainda "a ouvir". Pisca os olhos com
tempo natural, mexe o olhar, respira, dá um pequeno salto quando muda de cara, e acena com o
braço quando fica alegre. Há duas versões que se escolhem no painel: só a cara, ou a cara com
o corpo e a camisa com o logótipo da Bora ao peito (é esta que vem por defeito).

A boca acompanha a voz sílaba a sílaba, com as regras do português de Portugal, e acerta-se em
cada palavra que o telemóvel diz. A voz é a do próprio telemóvel ou navegador, sempre em
português de Portugal; se o aparelho não tiver voz de Portugal, o Amigo fala só por legenda e
nunca passa para brasileiro nem inglês. Há um botão para ligar e desligar o som, que fica
lembrado. No navegador Edge a voz escolhida é a mesma Raquel do Dipsy.

Na página inicial, o botão "Ajuda-me a escolher" com a bolha sem rosto saiu. No lugar está o
rostinho vivo com "Sou o Amigo. Fala comigo", e há um mosaico "Amigo" no início das
categorias, também com o rostinho. Ao tocar, abre o ecrã do Amigo: o rosto grande acorda,
sorri e diz a saudação em voz alta, pelo nome e a lembrar o habitual. O que ele diz aparece em
legenda grande, com a palavra a ser dita a laranja, como no filme do Dipsy. Em baixo há o
microfone grande "Fala comigo", o "Escrever" e o "Ver conversa", que abre a conversa escrita
de sempre, com a mesma conversa. A cara reage: a ouvir fica atenta, à espera fica pensativa,
com produto ou pedido fica alegre, quando não há ou está fechado fica triste, quando não
percebe fica confusa. Os cartões dos produtos, o pôr no carrinho, a memória, o esquecer tudo e
o resto ficaram como estavam, partilhados com a conversa escrita.

Adendo 1: no fim de cada conversa o Amigo diz em voz, com a cara alegre, a deixa que o sistema
escolheu (promoção, parceiro novo, tokens ou check-in) e mostra-a num cartão por baixo da
legenda; o toque continua a contar como "clicada". A deixa continua escrita pelo sistema com
dados do banco. E o Amigo deixou de ser "de compras": a causa era a primeira frase das
instruções do servidor, "És o Bora Assistente, o assistente de compras" — houve mesmo uma
resposta real a dizer "o teu assistente de compras". Com a personalidade ligada, a frase passa
a ser a do Amigo para tudo (conversar, comida, mercado, Favores, limpeza, reservas, serviços,
dúvidas sobre a Guarda e a app), com a ordem de nunca se apresentar como "de compras". O
subtítulo da conversa escrita também deixou de falar só de compras.

No servidor, a resposta do Amigo traz agora um campo novo e opcional com a cara que ele
escolheu; as versões antigas da app ignoram-no. No painel do administrador, no separador Amigo
Bora, há a secção "Rosto do Amigo": o rosto ao vivo, um botão por expressão, uma caixa para
escrever uma frase e ouvi-lo falar, a escolha da versão, os interruptores (rosto ligado, voz
ligada, velocidade da voz, mosaico) e os números de uso (aberturas, voz contra escrita, tempo
de conversa, por plataforma). Gravar fica na auditoria como o resto do painel.

## Provas

Testes: 65 testes do Amigo verdes (rosto, pestanejar, transições, boca, voz, ecrã, home,
mosaico, painel, traduções). Fotografias das seis expressões nas duas versões e do ecrã em
três tamanhos de telemóvel em test/golden/_fotos/amigo_*. A suíte inteira deu 3135 verdes; os
únicos vermelhos que sobram são 6 de um teste da M10 (m10_nif_caixa_app_test) que já falham no
código de produção sem nada desta missão. O Juiz anti-trapaça deu limpo, com 47 casos de teste
a mais, e a análise do código deu zero erros. No servidor: 16 testes verdes e a verificação de
tipos limpa. A migração nova foi provada num Postgres local: correu duas vezes sem estragar
nada e passou as 17 verificações.

Vídeo: C:\BoraLocal\missoes\m11-amigo-rosto-2026-11-09\amigo-rosto-m11.mp4, 54 segundos com
som, gravado imagem a imagem a partir do ecrã verdadeiro da app, com as três cenas da missão do
Dipsy ("Olá, eu sou o Amigo", o hambúrguer, e a cara triste e confusa). A voz do vídeo é a
Raquel das gravações do Dipsy e a boca segue o tempo real de cada palavra; o servidor e o
microfone são um guião com dados de demonstração. Há também o vídeo lado a lado com o do Dipsy
(lado-a-lado-dipsy-vs-app.mp4): é a mesma personagem.

Voz e boca a sério, no aparelho: fiz uma demonstração do ecrã do Amigo que corre sem servidor
nem contas (tool/amigo_demo) e testei-a. No navegador deste PC, com a voz Microsoft Helia de
Portugal, disse as mesmas 5 frases que o Dipsy usou: a boca atualiza em média 10 milésimos de
segundo depois de cada palavra (no máximo 14; o alvo era abaixo de 100) e o rosto anda a 60
imagens por segundo, sem nenhuma imagem lenta. No telemóvel virtual Android 15, pelo Chrome,
encontrei um erro: o Chrome do Android tem a voz "Portuguese Portugal", mas ela só aparece uns
segundos depois de a página abrir, e o Amigo desistia antes e ficava só com legenda. Corrigi
(espera mais e volta a procurar antes de falar) e, à segunda, falou com a voz de Portugal. O
Chrome do Android não diz em que palavra vai, por isso aí a boca segue o texto; pus a voz a
aprender a velocidade real do aparelho no fim de cada frase para a boca ficar mais certa. No
telemóvel virtual o desenho é lento (2 imagens por segundo) porque esse emulador desenha sem
placa gráfica; o Dipsy viu o mesmo. A app Android a sério (APK) não deu para compilar aqui: falta
o ficheiro de configuração do Firebase no worktree e as regras não me deixam copiar ficheiros de
chaves. Provas em docs/amigo/provas/.

## Ficou a faltar (e porquê)

As travas estão ligadas, como mandaste, e barraram três passos com a mensagem "publica o
Claude.ai": a migração no banco, a função do servidor e o envio do código para o GitHub. Não as
contornei. Está tudo pronto, com a ordem certa, em docs/propostas/PROPOSTA_20261109_m11_amigo_rosto.md
e numa cópia do ramo em C:\BoraLocal\missoes\m11-amigo-rosto-2026-11-09\m11.bundle. Por isso a
versão nova ainda NÃO está no Android, no iPhone nem em app.boraguarda.com, e não deu para
provar na web nem no TestFlight.

A trava também não me deixou gravar o ficheiro principal do Android (tem lá dentro a chave do
mapa, que já lá estava). A linha que o Android 11 precisa para encontrar a voz do telemóvel foi
para os ficheiros do Android de cada tipo de versão, que se juntam sozinhos ao principal.

Também ficaram por fazer, porque precisam da versão publicada ou de entrar com uma conta: as 5
conversas de prova sem "de compras", as 2 conversas com deixas diferentes e uma linha nova por
conversa na tabela das deixas, e o pedido de teste no emulador com a conta de cliente. Entrar
com uma conta real de produção a partir de um teste não me é permitido.

## Erros que encontrei pelo caminho

O teste m10_nif_caixa_app_test tem 6 casos vermelhos no código de produção (já estavam assim
antes desta missão). O commit 884e3def da barra do parceiro ainda não foi publicado e leva
capturas para a pasta de provas do repositório público, uma delas chamada
3-login-cliente.png: convém ver se tem dados pessoais antes de publicar.

## Precisa do Danilo

Publicar: dizer ao Claude.ai (ou abrir as travas para esta missão) para seguir a proposta, que
põe a migração, a função do servidor e a app nas três lojas, junto com o 884e3def. Voz: se
quiseres a Raquel em todos os telemóveis (e não só a voz de cada aparelho), é a Azure da
Microsoft, que é paga — decisão tua.
