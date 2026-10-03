# Noite de fecho — 24 para 25 de setembro de 2026

Missão `noite-fecho-2026-09-24`. Sete blocos, todos tocados. O que segue é o que ficou feito,
o que ficou por fazer, e os erros que apareceram pelo caminho e que não corrigi porque a
ordem mandava reportar e seguir.

## O que ficou feito

**A página de verificação do motorista já abre pelo caminho curto.** Era o bloco mais
importante, porque é o que uma autoridade vê quando aponta a câmara ao QR do motorista. O
endereço `boraguarda.com/verificar/<token>` dava "página não encontrada"; só funcionava a
forma comprida, com `?t=`. A causa não era o que parecia: a regra de reescrita apontava para
`/verificar/index.html`, e a Cloudflare redireciona qualquer endereço acabado em `.html` para
a forma limpa — a reescrita morria nesse salto. O alvo passou a ser a pasta. Pelo caminho
corrigi outra coisa que estava mal sem dar sinal: os ficheiros de regras tinham fins de linha
do Windows, e num deles isso faz a regra ser descartada em silêncio. Provei com um código
novo: os dois endereços devolvem a mesma página, e a consulta que a página faz devolve os
dados do motorista.

**O aviso crítico por email já sai.** O relatório antigo dizia "chave da Resend sem
permissão". Não era a chave: era o `notify-admin-urgent`, que nunca ia buscar a chave ao
cofre — ao contrário das funções irmãs — e por cima tinha um remetente de um domínio que não
está verificado. Escrevia "email saltado" treze vezes por dia e ninguém reparava. Corrigi as
duas coisas e provei em três degraus, o último deles com o email do aviso crítico a chegar
mesmo à caixa.

**O decisor deixou de morrer à espera.** Esperava vinte segundos por modelo e repetia o mesmo
modelo quando o Google dizia que estava cheio, que é precisamente quando repetir não serve de
nada. Passou a oito segundos, uma tentativa por modelo, e a saltar logo para o seguinte. Nas
mesmas vinte perguntas que a 23 de setembro tinham ficado dezanove sem motor nenhum, agora
responderam as vinte, sem um único erro, em menos de um segundo cada.

**O Hermes já pergunta ao decisor, em sombra.** Em vez de pôr a chave de serviço do Supabase
na VPS — que daria àquela máquina poder para ler e escrever tudo por causa de uma pergunta
que só grava uma linha — fiz uma porta estreita com chave própria. Está ligada em dois
sítios: o Porteiro que decide se uma tarefa interrompe o Danilo, e o despachante que escolhe
o agente. Nenhum dos dois muda de comportamento: só fica o registo para depois se comparar.

**O radar dos vídeos afinal corre.** Corre todas as noites às duas, escreve o relatório e a
mensagem chega ao Telegram — está no registo da ponte a 22, 23, 24 e 25. O que faltava era
outra coisa, e é por isso que parecia parado.

**Os três ecrãs do painel estão publicados.** Confirmei-os no próprio ficheiro que o navegador
descarrega, e confirmei que as consultas que eles fazem respondem.

## O que falta, e porquê

**O painel dos documentos dos motoristas abre vazio.** Não é avaria: a tabela tem zero linhas
porque ninguém carregou documentos ainda.

**O radar da noite traz zero vídeos novos, e vai continuar a trazer.** A fonte dele é uma
exportação do histórico do YouTube que está parada: os doze vídeos já foram lidos e a memória
salta-os. Enquanto não houver uma exportação nova, aquilo não tem o que mastigar. Mudei a
mensagem do Telegram para levar os números à frente, em vez de dizer sempre "corrida
terminou" — assim vê-se de relance que entraram zero, sem abrir ficheiro nenhum. Quem quiser
vídeos novos todos os dias já tem isso no outro radar, o das sete da tarde.

**O decisor acerta mal.** Responde depressa e sempre, mas responde "não" a quase tudo: cinco
em dez nas sugestões do robô, duas em seis no suporte. A confiança separa bem — sessenta e um
por cento quando acerta, vinte e oito quando falha — o que aponta para o corte e não para a
leitura. Está em sombra, e é onde deve ficar até alguém olhar para o corte. Não mexi nisso.

**O Jev continua sem chave.** O registo no TypeSafe está fechado. Deixei escrito no
`MOTORES.md` a linha exacta para ligar, quando a chave aparecer.

**Os commits do site continuam por empurrar para o GitHub.** O guardrail só deixa empurrar o
ramo de trabalho do Bora, e a Trava não deixa mexer no próprio guardrail. O que está no ar
não depende disso — a publicação do site é por upload direto e já foi feita.

## Erros encontrados e não corrigidos, como a ordem mandava

Os três testes do ecrã da ficha legal falham por um `ListTile` dentro de uma caixa com cor de
fundo. Apareceu ontem, não tem nada a ver com esta missão, e não lhe toquei.

## Uma armadilha que quase me fez mentir no relatório

Procurei "Decisões (Jev)" e "Radar de vídeos" no ficheiro que o navegador descarrega e deu
zero nos dois. Ia escrever que o painel estava atrasado. Era falso: no código compilado os
acentos vão escapados, e procurando pelos identificadores sem acentos aparecem todos. Fica a
regra: não se conclui "não está lá" a partir de uma busca com acentos num ficheiro compilado.
