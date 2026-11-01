# Missão infra-claude-tudo-2026-11-01 — relatório

Claude Code no PC do Danilo, 01/11/2026 20:30–22:30 UTC. Ordem do Danilo das 19:56 ("Claude em primeiro, sem limite,
nunca ficar sem; Dipsy com acesso a tudo; servidor arrumado; Bora Bastidores; eu não faço nada"). Registo passo a passo:
e2e_log, fluxo `infra-claude-tudo-2026-11-01` (ids 5981 a 6064 e seguintes).

## Fiz isto

**Os robôs usam o Claude sem ração (B1).** Até hoje o porteiro do crédito do Claude racionava por dia: os agentes e os
radares só podiam gastar metade da "parte do dia". Agora tudo passa pelo Claude enquanto houver crédito; só quando a
própria Anthropic disser "sem crédito" é que os robôs descem para os motores grátis, e voltam sozinhos (o porteiro testa
de 6 em 6 horas e no dia do crédito novo, 30/11). Erro de pedidos a mais: tenta outra vez em 2 minutos; chave recusada:
6 horas. A mesma regra ficou na função que as Edge Functions perguntam (`ia_claude_pode`, migração 20261101204928,
aplicada e registada). Prova com base falsa: 28 de 28 e 25 de 25. Prova real: três pedidos de agentes seguidos foram
todos ao Claude (ia_gastos 150 a 152); com "sem saldo" simulado foram ao Gemini grátis e voltaram ao Claude no fim
(ia_gastos 153). Há dois perfis novos: `claude-dipsy` (Sonnet, para o Dipsy) e `claude-opus` (Opus, só a pedido).
O livro de gastos continua (`ia_gastos`). e2e 6002–6004, 6064.

**Hermes/Emerson no Claude (B2).** Confirmei os 26 perfis: o Emerson, a torre, o crítico e o vendedor vão ao Sonnet; os
outros agentes ao Haiku. O batedor (o radar semanal) passou do Sonnet para o Haiku, como manda o mapa. Encontrei e
consertei um defeito: os perfis do escriba e do fiscal estavam com o ficheiro estragado desde 31/10 (cinco reservas
mortas coladas no sítio errado). Reiniciei o Hermes. Prova pelo Telegram (às 21:29): mandei "responde só ROTA-CLAUDE-OK"
ao BoraHermesbot e ele respondeu ROTA-CLAUDE-OK em texto e em voz, pelo Claude Sonnet. e2e 6039.

**O Dipsy pensa com o Claude e nunca fica sem motor (B3).** O Dipsy usa o porteiro da VPS pela Tailscale, com uma senha
própria; no PC não há chave da Anthropic. Normal: Claude Sonnet. Com /opus usa o Opus; /sonnet volta; /gratis usa só os
grátis; /motor diz o motor e o crédito. Se a VPS não responder em 8 segundos, vai pelo Kilo e depois pelo Gemini.
Provas: "ROTA-CLAUDE-DIPSY-OK" pelo Telegram em texto e voz; /opus respondeu "A capital de Portugal é Lisboa." pelo Opus
(ia_gastos com claude-opus-5-5); com a VPS "desligada" decidiu em 8 segundos e respondeu pelo Kilo. Pus também cache na
conversa do Dipsy: a segunda volta já lê da cache cerca de metade do que manda. e2e 6040.

**O Dipsy sabe tudo do Danilo (B4).** Escrevi o mapa de todos os projetos (Bora, painel, sites, Em Dia, BoraStudio e o
gibi da Tuca, o vault, a VPS, o livro): `~/.dsh/MAPA-DANILO.md`, e a página `dipsy-mapa-danilo` do livro marcada
[PESSOAL] (o repositório é público e as páginas [PESSOAL] não vão para lá). De hora a hora a ponte do Telegram põe no
arranque do Dipsy o mapa, as regras do Danilo, os erros aprendidos e o índice do livro. O Dipsy lê qualquer pasta; para
trabalhar noutro projeto há o comando /pasta (16 pastas). Prova pelo Telegram: "onde está o filme das meninas, o que é o
Em Dia e qual é o site do Jai?" → respondeu certo, com as pastas, em texto e voz. e2e 6054.

**Servidor do robô arrumado (B5).** De fora só estão abertas as portas 22, 80 e 443 (testei do PC). Liguei o fail2ban no
SSH (ontem houve 34 tentativas falhadas). Fechei pelo IPv6 as portas do Docker que só estavam fechadas pelo IPv4 (o
trader e o painel do Hermes). Disco: de 69,5% para 68,9%. Depois de tudo: Córtex, Hermes, motor, porteiro (também pela
Tailscale do PC), WhatsApp das lojas, voz, Conselho e OmniRoute vivos. Antes e depois em `docs/vps/rede-2026-11-01.md`.
e2e 6047.

**Bora Bastidores (B6).** Criei o grupo "Bora Bastidores" com o BoraHermesbot e o Dipsy, pela aplicação Telegram do PC
(o Telegram Web não tem sessão em nenhum perfil e não fiz login). O porteiro do Telegram manda para lá tudo o que é
informação; prova: um aviso de teste foi para o grupo e não para a conversa do Danilo. O resto do bloco 6 (porteiro
único, triagem, anti-repetidos, resumos 06:45 e 21:00) já estava feito desde 31/10. e2e 6062.

**Site do Jai sem o nome do Danilo (B7).** Tirei a nota interna do `index.html` e publiquei (deploy bdc9dab6). Em
jaiagarwala.com e nas versões pt/es/hi aparece zero vezes "Danilo". e2e 5987.

**Recibo do Vansh (B9).** O PDF (286,21 €, igual à conta das 20:20) foi enviado ao Vansh pelo WhatsApp às 21:19 com
"Here's the PDF.". e2e 6036.

## Falta isto (e porquê)

- **PDF do Jai não enviado.** O PDF dizia "em aberto desde 24/10: 186 €, total 214 €". Às 20:49 o Jai lembrou que já pagou
  os 186 € por cartão a 27/10, às 20:57 já lhe foi pedido desculpa ("this week it's only 28 €") e ele respondeu "make
  sure from next time". Mandar aquele PDF repetia o erro. Está pronto um PDF corrigido (28 €, com a nota de que os 186 €
  já foram pagos): `Downloads\Invoice_2026-11-01_Jai_Agarwal_corrigido.pdf`. e2e 6037.
- **Token dos bots não rodado.** Não há registo de exposição (nem no livro nem no Córtex); a ordem só manda rodar com
  exposição. e2e 6063.
- **Função `_shared/claude.ts`**: mudei a única ração que lá restava (quando a base não responde, os agentes passavam a
  não usar o Claude) e os 18 testes passam, mas não publiquei as 4 funções que a usam: só muda um caso raro e teria de
  comparar cada uma com o que está no ar. Entra na próxima publicação delas. e2e 6064.
- **Porta do painel do Hermes só local**: mudei o ficheiro do Hermes, mas só vale quando o contentor for recriado; não o
  recriei porque tem cerca de 11 500 coisas instaladas lá dentro que se perdiam. A porta já está fechada de fora.
- **Trader (8090)** não mexido: é dinheiro; a porta já está fechada de fora.
- **Stories "em breve" (B8)**: a proposta só chegou ao ramo às 22:07; o ajudante está a aplicá-la na VPS em ensaio (sem
  publicar nada). Resultado no e2e_log, fluxo `stories-em-breve-2026-11-01`.
- **A página do Dipsy no navegador** que estava aberta desde ontem ainda usa o motor antigo; muda sozinha quando o DIPSY
  for aberto outra vez. O Telegram do Dipsy já usa o Claude.

## Erros que encontrei pelo caminho

- Perfis escriba e fiscal do Hermes estragados desde 31/10 11:03 (consertado).
- IPv6 do servidor sem a regra que fecha as portas do Docker (consertado).
- A tranca leu dois nomes de variáveis como segredos (falso positivo; nomes mudados, registado em `docs/TRANCAS.md`).
- A nota "cérebro do WhatsApp a 388 de 400 MB" já não vale: usa 11 MB e o limite é 800 MB.
- O SSH do servidor ainda aceita senha (o fail2ban trava as tentativas).
- As pré-visualizações antigas do site do Jai na Cloudflare (ex.: 58e121cc.jai-agarwal.pages.dev) ainda mostram a nota.

## PARA O DANILO (só o que é teu)

1. Recibo do Jai: diz "envia o do Jai" e eu mando o PDF corrigido (28 €) com "Here's the PDF, bro.".
2. Se quiseres na mesma trocar o token dos bots, diz "troca o token" (não houve fuga registada).

## Próximo passo

Fechar o B8 quando o ajudante acabar; depois, numa janela calma, recriar o contentor do Hermes com o que está instalado
lá dentro passado para a imagem, e decidir se o SSH fica só com chave.
