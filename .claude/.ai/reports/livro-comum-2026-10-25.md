# Livro comum — relatório da missão (pedida a 23/10, feita a 25/10/2026)

Fiz isto. Agora há um livro só para todos. A Claude.ai, o Hermes, o Claude Code, o OpenCode e o ChatGPT leem a
mesma tabela, que é a memória da Claude.ai. O cartão novo de todos os agentes chama-se AGENTS.md e tem cem linhas:
quem tu és, as regras de ouro, e a ordem de acordar (erros aprendidos, as tuas regras, o índice do livro e o último
resumo). Os dois CLAUDE.md, o do projeto e o geral do PC, ficaram curtos. Nada se perdeu: o texto inteiro antigo
está numa página do livro e numa pasta de documentos. A alma do Hermes passou de 611 linhas para 116. De meia em
meia hora ela é refeita com as tuas regras e os erros aprendidos colados no fim. O espelho do livro na VPS também
passou a correr de meia em meia hora. Provei com o Hermes e com uma sessão nova do Claude Code: perguntei a tua
última correção sem os deixar procurar, e os dois responderam certo. O OpenCode também lê o cartão sozinho.

Aprender nos dois sentidos também ficou feito. Quando tu corriges um agente, ele grava uma linha com a data no fim
dos erros aprendidos: o Hermes com o comando aprender, o Claude Code com a skill aprender. Nunca apaga o que lá
está. Todas as noites, o que o Hermes aprende sozinho vai para o livro, assim como as skills que ele criou e a
memória do Claude Code. Aos domingos à noite, o escriba e o crítico fazem a faxina do livro: apontam regras
repetidas e regras que se contradizem, sem apagar nada. A primeira faxina já saiu. Encontrou, por exemplo, que
"pergunta autorizas o envio?" choca com "não perguntes aprovas?". Pedido com dados pessoais passou a ir só para
motores que não treinam com o conteúdo. Provei: um pedido normal foi para o Gemini, um marcado pessoal foi para a
Cloudflare.

As skills agora estão numa pasta só, a do projeto, com 145. Entraram as 11 que a Claude.ai partilhou, as 66 que só
viviam no PC e 6 do Hermes aprovadas pelo crítico. O que ficou de fora está numa lista, com o motivo de cada uma, e
nada foi apagado. As da Anthropic com licença fechada não entraram. O Hermes já lê a pasta comum e usou a skill de
design numa maquete de teste. A Claude.ai vê as skills na página skills-indice do livro.

Sobre o caça-clientes: estava parado desde 7 de outubro porque a fila secou, não por causa do Gmail. Os 15
negócios com email já tinham recebido. Agora o Hermes caça em ciclo. Nos dias úteis às 7 e meia, procura 10 a 20
negócios novos em Portugal inteiro e em duas cidades do Brasil: alojamento, clínicas, advogados, imobiliárias,
barbearias e oficinas. Confirma o email no site do próprio negócio e só fica com quem tem um defeito real no site,
como falta de https, de versão para telemóvel ou do livro de reclamações. Para cada um faz uma maquete honesta, sem
elogios inventados. O resto é a máquina que já existia: escreve pelo molde aprovado e envia no máximo 5 por dia,
entre as 9 e meia e as 11 e meia.

Quando alguém responde, há quatro casos:
- Resposta automática ou só assinatura: é ignorada.
- "Não": fica marcado e nunca mais é contactado.
- Pergunta simples: o Hermes responde sozinho, sem preços.
- Pedido de preço, reunião ou fechar: recebes uma nota de voz com o rascunho, e só sai quando disseres "manda"
  ou "muda para...".

Fiz as três provas. Primeiro, uma clínica de Coimbra caçada, com maquete no ar e proposta pronta (sai amanhã na
janela). Depois, uma pergunta simulada respondida sozinha, para o email da Bora. Por fim, um pedido de preço
simulado que chegou em voz e só saiu depois do "manda"; um segundo "manda" foi recusado. O relatório da manhã
ganhou três linhas do caça-clientes. O radar de trabalhos freelance manda às 8 e meia, no Telegram, a lista com as
propostas escritas. No painel, o ecrã Caça-clientes mostra o funil (caçados, contactados, responderam, à tua
espera, fechados) e deixa mudar o máximo por dia.

No WhatsApp fiz só o esqueleto, como pediste. O envio continua desligado, confirmado antes e depois. Cada conversa
tem agora um tipo (loja, pessoal ou incerto), que se muda no painel; todas estão em incerto. As perguntas em aberto
estão na página whatsapp-a-discutir. O modo rascunho existe, mas está desligado e ninguém recebe nada.

Falta isto, e porquê. A tranca do Bora recusou pôr o gancho de arranque no settings.json do PC, e o sistema recusou
criar uma tarefa agendada no Windows. Por isso, a cópia do livro no PC só se renova quando corre o
renovar-livro.cmd. Está escrito em docs/TRANCAS.md o passo exato, para tu decidires. O Codex não respondeu porque a
sessão dele expirou: precisa de entrares outra vez. O ficheiro para o projeto Bora do ChatGPT está pronto e é
refeito todas as noites, mas não o carreguei, porque esta sessão não tinha a extensão do Chrome. O 99Freelas
bloqueia a VPS e o Upwork já não tem lista pública, por isso essas propostas só vão pelo Chrome do PC. Não confirmei
se a app do Gmail "Bora Carteiro" está publicada, mas o token está a funcionar. As maquetes estão num endereço da
VPS e não em boraguarda.com; um endereço da marca seria melhor.

Erros que encontrei pelo caminho:
- **Fuga de dados pessoais (o mais grave):** o repositório do Bora no GitHub está público e o espelho do livro
  estava a pôr lá 32 páginas tuas marcadas pessoal (família, morada, finanças). Parei: essas páginas já não vão e
  saíram da versão atual, mas continuam no histórico antigo. Avisei-te no Telegram.
- **O resto do livro também é público:** está lá tudo o que não é pessoal, incluindo regras internas, como
  "ninguém pode saber que o Danilo é o dono". Só tu decides se o repositório fica privado; nesse caso o CI passa a
  custar.
- **Duas skills do Hermes contra a regra de honestidade:** a hermes-auto-configuracao, que ele usa, e uma linha da
  memória dele mandam esconder falhas.
- **O catálogo do Motor Bora:** dá como seguros motores grátis que podem usar os dados.
- **A voz principal (edge-tts) está a falhar** e cai sempre para a voz de reserva.
- **Um vigia antigo voltava a colar a hierarquia comprida na alma do Hermes;** já ficou acertado.

Próximo passo: decidir se o repositório fica privado e aprovar o gancho do PC.

## PARA O DANILO
1. Repositório público com o livro (e histórico com páginas pessoais): fechar o repositório? (CI passa a custar.)
2. Gancho de arranque no `~/.claude/settings.json` ou tarefa horária no Windows: qual aprovas? (passo em docs/TRANCAS.md)
3. Entrar de novo no Codex (sessão expirou).

Provas: tabela e2e_log, fluxo livro-comum-2026-10-23 (passos bloco0a … bloco7, adendo-livro-30min, adendo-skills,
erros encontrados). Commit d9af7d87 no ramo autonomous-night-2026-04-29.
