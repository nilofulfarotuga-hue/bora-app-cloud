---
id: memoria-claude-ai-dsh-como-usar
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Como usar o Dipsy (dsh)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `dsh-como-usar`, origem `claude-code`, atualizada em 2026-10-31T14:01:28.114189+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: dsh como usar · memoria claude.ai · claude_ai_memoria

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
- No Telegram há um menu com botões para tocares: Estado, Planear, Aprovar, Objetivo, Corrigir, Voltar atrás, Conversa
  nova, Libertar memória, Agenda, Parar, Ajuda e Desligar.
- **Ele lembra-se da conversa.** Enquanto falam (com pausas de menos de 30 minutos), o Dipsy continua a mesma conversa, como
  o Claude Code. Para começar do zero, toca em "Conversa nova".

## Os botões novos (31/10)
- **Planear:** escreve /planear e o que queres. Ele investiga e manda-te só o plano, sem mexer em nada (a guarda não o
  deixa mexer). Se gostares, tocas em **Aprovar** e ele faz. Se não, mandas /corrigir e o que queres diferente.
- **Objetivo:** escreve /objetivo e a meta (por exemplo, "deixar o relatório da semana pronto"). Ele trabalha sozinho,
  ronda a ronda, até a meta estar cumprida (no máximo 6 rondas), e diz-te como vai. Para parar: /objetivo parar.
- **Corrigir:** a meio de um trabalho, escreve /corrigir e a correção. Ele para, e continua o mesmo trabalho já com a
  correção, sem começar do zero.
- **Voltar atrás:** ele esquece o último pedido, como se não o tivesses feito. Os ficheiros que esse pedido mudou não
  voltam atrás sozinhos; ele diz-te quais foram, e o Claude Code repõe-nos se pedires.
- **Libertar memória:** liberta memória do PC quando está lento (só fecha o que é seguro; nunca as sessões do Claude, o
  Chrome nem o Telegram). Também lho podes pedir por palavras.
- **Fazer ferramentas novas (Creator Mode):** pede-lhe, por exemplo, "cria uma ferramenta que me diz quantos pedidos houve
  hoje". Ele cria-a, testa-a, e se o teste passar passa a usá-la sempre. As ferramentas que ele cria só podem LER a base
  de dados do Bora ou os nossos sites; nunca escrevem nem mexem em dinheiro.

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
Desde 31/10: o Dipsy só fala com sítios do Bora na internet (boraguarda.com, o nosso Supabase, o Córtex, o nosso GitHub e
as lojas de apps). Qualquer outro sítio é barrado pela guarda; para pesquisar na internet, pede ao Claude Code. Se a guarda
não ligar por algum erro, o Dipsy recusa-se a trabalhar e diz-te. E quando o Dipsy passa trabalho ao Claude Code, esse
Claude Code também leva uma guarda que barra apagar em massa, apagar tabelas, push forçado, matar processos e segredos.

## Cuidados
- O motor é grátis e pode guardar o que lhe mandas. Não lhe mandes palavras-passe nem chaves.
- Quando ele vê o ecrã ou uma foto, a imagem vai para a Google (plano grátis). Evita ter janelas de banco ou de
  palavras-passe abertas quando lhe pedires para ver o ecrã.
- A voz que mandas vai sempre à Google (plano grátis) para ser percebida: foi a tua escolha a 31/10, porque assim o
  "Ouvi" chega em 3 segundos. O PC só tenta perceber sozinho se a Google falhar (sozinho, o PC demorava 45 a 76 segundos e
  às vezes percebia mal). O registo diz qual foi o caminho de cada áudio.
- O Dipsy não consegue ler o espaço do disco (o sandbox não deixa); para isso pede ao Claude Code. A memória do PC ele já
  liberta: toca em "Libertar memória".

## Como parar
- **Parar tudo:** carrega numa tecla na janela preta do DIPSY. Isso fecha a página e a ligação ao Telegram.
- **Só cancelar um pedido:** no Telegram, toca em "Parar".
- **Desligar o Telegram sem tocar no PC:** no Telegram, toca em "Desligar".

## Se não funcionar
Fecha a janela preta e abre o DIPSY outra vez. Se continuar mal, diz ao Claude Code: "o Dipsy não abre" ou "o Dipsy
não responde no Telegram". Ele resolve e não tens de escrever comandos.

