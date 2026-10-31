# Como usar o Dipsy

O Dipsy é o segundo ajudante do teu PC, ao lado do Claude Code. Trabalha com um motor grátis. Não precisas de escrever
nenhum comando: falas com ele como falas com uma pessoa.

## Como abrir
Faz duplo clique em **DIPSY**, no Ambiente de Trabalho. Espera uns 30 segundos. Abre uma janela preta (deixa-a aberta)
e, no navegador, a página do Dipsy.

## Como falar com ele
- **No teclado:** na página que abriu, escreve o que queres, como falas com uma pessoa.
- **No Telegram:** escreve ao bot do Dipsy. É o @dipsy_bora_bot (o nome também aparece na janela preta). Só tu consegues
  falar com ele, mais ninguém.
- **Por voz, no Telegram:** manda um áudio. O Dipsy responde primeiro "Ouvi: …" com o que percebeu, para confirmares, e
  depois trata do pedido.
- **Fotos:** manda uma foto e ele vê-a.
- No Telegram há um menu com botões para tocares: o que está a fazer, as tarefas marcadas, parar o pedido, o que sabe fazer,
  e desligar.

## Como ele responde (regra tua)
Tudo o que o Dipsy te manda chega sempre **em texto completo e em áudio do texto inteiro**. Se a resposta for comprida, o
áudio vem em várias partes, por ordem, cada uma com frases inteiras, e nunca cortado. O mesmo vale para o Hermes: todos os
avisos, relatórios e respostas dele chegam em texto e em áudio completos.

## O que ele sabe fazer
- Ler e escrever ficheiros do projeto do Bora, e guardar o trabalho no git depois de passar no Juiz.
- Consultar e, com regras, mexer na base de dados do Bora.
- Ver o ecrã do PC e as fotos que lhe mandares.
- Ler o email da Bora e preparar rascunhos, sem nunca enviar.
- Ver o Drive e o calendário (só ler).
- Auditar a segurança do nosso site, do nosso APK e das nossas funções (só ler).
- Pesquisar no Córtex, no livro e nas conversas antigas.
- **Fazer tarefas a uma hora marcada.** Pede-lhe, por exemplo: "todos os dias às 8 faz-me o resumo dos pedidos". Ele marca,
  e à hora certa faz sozinho e manda o resultado em texto e áudio. Só funciona com o PC ligado. Vês a lista no botão
  "agenda".
- **Passar trabalho difícil ao Claude Code.** Quando o trabalho é delicado, o Dipsy pede ao Claude Code (o teu, o oficial).
  Gasta o teu plano, por isso só o faz para o que for difícil. Nunca envia nada para o servidor.
- **Trabalhar em equipa.** Para trabalho grande, o Dipsy cria colegas (dois ou mais agentes) que fazem partes diferentes e
  usam um quadro de tarefas partilhado. É uma função experimental.
- **Lembrar-se entre conversas.** O Dipsy guarda o que aprende contigo (por exemplo, que queres tudo em texto e áudio) e
  lembra-se na conversa seguinte. Nunca guarda palavras-passe nem chaves.

## O que ele não faz
- Não envia emails nem mensagens para fora. Não publica nada. Não envia código para o servidor.
- Não mexe em dinheiro, preços, comissões, carteiras, tokens nem no Stripe sem o teu "autorizo".
- Não apaga dados de produção, não apaga ficheiros em massa e não lê nem escreve segredos.
- Não mexe em apps ou sites de outras empresas.

## Como ele fica seguro
Antes de cada coisa que ele faz, uma guarda confere se pode. Se a guarda barrar, ele diz-te o que queria fazer e segue
com o resto. Todo o trabalho que ele guarda no git passa primeiro pelo Juiz, o mesmo que vigia os outros ajudantes.
A telemetria do motor oficial do dsh está desligada: medimos a rede durante um pedido e ele só falou com o motor grátis
(Kilo), o Supabase e o Córtex.

## Cuidados
- O motor é grátis e pode guardar o que lhe mandas. Não lhe mandes palavras-passe nem chaves.
- Quando ele vê o ecrã ou uma foto, a imagem vai para a Google (plano grátis). Evita ter janelas de banco ou de
  palavras-passe abertas quando lhe pedires para ver o ecrã.
- O Dipsy não consegue ler o espaço do disco nem a memória do PC (o sandbox não deixa). Para isso pede ao Claude Code.

## Como parar
- **Parar tudo:** carrega numa tecla na janela preta do DIPSY. Isso fecha a página e a ligação ao Telegram.
- **Só cancelar um pedido:** no Telegram, toca em "Parar".
- **Desligar o Telegram sem tocar no PC:** no Telegram, toca em "Desligar".

## Se não funcionar
Fecha a janela preta e abre o DIPSY outra vez. Se continuar mal, diz ao Claude Code: "o Dipsy não abre" ou "o Dipsy
não responde no Telegram". Ele resolve e não tens de escrever comandos.
