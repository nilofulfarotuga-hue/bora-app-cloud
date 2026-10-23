# Relatório da missão omniroute-23-10 — 23/10/2026

Acessos. Não criei conta nenhuma em serviço de fora e não entrei em conta nenhuma tua. Criei, só dentro do
OmniRoute da VPS, uma palavra-passe do painel (está em /opt/data/.env, com o nome OMNIROUTE_PASSWORD) e três
chaves internas: uma para os agentes (agentes-bora), uma para o juiz (conselho-juiz) e uma para o OpenCode do teu
PC (pc-opencode-danilo). O painel do OmniRoute não está aberto à internet: só se chega a ele de dentro da VPS ou
pelo Tailscale, no endereço http://100.120.181.115:20128.

O que NÃO ficou feito, primeiro. A chave do OpenCode Go expirou: o próprio OpenCode do teu PC diz "This API key
has expired". Por isso o glm-5.2 e o qwen3.8-max, que eram para ser os primeiros da fila, estão mortos até
criares uma chave nova em opencode.ai/console (pode ser a assinatura que acabou, e isso é dinheiro, por isso é
decisão tua). Até lá tudo anda pelo Gemini e pelos outros grátis, e eles voltam ao topo sozinhos no minuto em
que eu trocar a chave. Os dois modelos grátis do OpenCode Zen que a ordem pedia, o nemotron e o hy3, ficaram de
fora de propósito: a OpenCode só deixa usar o Zen grátis dentro do próprio OpenCode, e para os pôr aqui era
preciso fingir ser o programa deles, que é exactamente o que a missão proíbe. O nemotron entrou na mesma, mas
pela chave da NVIDIA e pelo OpenRouter, que é legítimo. Na prova do Telegram enganei-me uma vez: a tua
mensagem das 06h16 foi respondida, mas ainda pelo caminho antigo, porque o processo do Telegram já estava a
correr há cinco dias e não via a chave nova; reiniciei-o e, nesse reinício, a tua mensagem das 06h22 ficou sem
resposta. Peço desculpa por essa. A das 06h27 já foi pelo OmniRoute: respondida às 06h34 (438 caracteres,
11 chamadas ao modelo, todas pelo combo "agentes"). Uma chamada de fundo dessa conversa apanhou o Gemini
"com muita procura" e o próprio Hermes repetiu-a; o OmniRoute devolveu esse erro em vez de descer de nível,
fica para vigiar. O voz-up.sh não existe nesta
VPS; verifiquei a voz pela porta que existe, o comando voz, e chegou-te uma mensagem de voz. Os outros 18
perfis do Hermes continuam no Motor Bora, porque a ordem só pedia estes; passam-se com um comando quando
quiseres.

Fiz isto. Medi a VPS antes de mexer: 3,8 GB de memória com 2,7 GB disponíveis, 8 GB de disco livre e um só
processador muito afogado (67% do tempo é roubado pelo anfitrião). O OmniRoute ocupa cerca de 330 MB e ficaram
2,5 GB disponíveis, por isso passou o portão de 1 GB. Instalei-o num contentor próprio, com a imagem oficial
fixa na versão 3.8.52, a reiniciar sozinho, com os dados numa pasta do servidor. A palavra-passe de fábrica
nunca chegou a ser usada; gerei uma forte. Reiniciei o contentor de propósito e voltou com tudo: os combos, as
ligações e a chave.

Fornecedores, só por chave de API: Gemini com as duas chaves que já tínhamos, NVIDIA, OpenRouter grátis, Groq,
Cloudflare e o Motor Bora antigo como último recurso. Provei cada modelo sozinho, sem recuo e sem cache, que é a
lição de 19 de Agosto, e depois com uma ferramenta e com um pedido do tamanho real do Hermes. A compressão ficou
desligada, como pediste, e a função de disfarce de ligação também. O OmniRoute traz de fábrica uns
fornecedores sem chave, alguns deles pontes para contas de terceiros; as nossas chaves estão fechadas e não lhes
conseguem chegar (provado: dão recusa).

Combos, do melhor para o pior, e descem sozinhos quando um falha. O "agentes" serve o Emerson, os cinco bots, o
OpenCode do PC e o juiz. O "privado" é só da torre, porque a torre pode ver dados de clientes: só usa quem por
escrito não treina com o que recebe (OpenCode Go, Cloudflare e Groq). Há ainda o rápido, o de volume, o de
visão e três vozes para o juiz, cada uma com um modelo diferente por baixo, para as três opiniões não virem do
mesmo. Prova de descida: estraguei de propósito as duas chaves do Gemini e respondeu o da NVIDIA; repus as
chaves e o Gemini voltou.

Hermes. O Emerson, o fiscal, o batedor, o escriba, o crítico e o vendedor estão no "agentes"; a torre no
"privado". Mudei os dois sítios de cada um, a configuração e o ficheiro de ambiente, com cópia de segurança. O
Emerson, quando escolhe a quem passar uma tarefa, também pergunta ao OmniRoute e, se este não responder, ao
Motor Bora. Os seis responderam um a um, a ronda de teste da torre fechou "feita", o juiz respondeu com as três
vozes, e o script da ponte continua a correr.

Quando o limite do Claude acaba no PC: pus no Ambiente de Trabalho o SEM-LIMITE.cmd. Abre o OpenCode na pasta
do Bora já ligado ao OmniRoute pelo Tailscale. Testei: pedi-lhe para mudar uma linha num ficheiro de teste,
mudou, e eu desfiz.

Robôs do app, só relatório. Os robôs do app chamam o Gemini directamente a partir do Supabase: o chat de
suporte, o assistente do cliente, o chat humano, o assistente do painel, a análise de conversas, o decisor, a
leitura de talões, o robô B e os dois que fazem a indexação. Só alguns trocam de modelo dentro do próprio
Gemini; nenhum salta para outro fornecedor. Pôr o OmniRoute como reserva deles tem dois custos: as mensagens e
os talões dos clientes passariam por fornecedores grátis que podem treinar com eles, e o OmniRoute teria de ser
aberto à internet, porque o Supabase não está no nosso Tailscale. Se um dia quiseres, só faz sentido com o combo
"privado" e por um endereço seguro com chave própria. Não mexi em nada.

Painel. No ecrã Motores do painel há agora um cartão OmniRoute com os fornecedores vivos e mortos, o combo em
uso, quem está a responder em cada combo e o consumo do dia. A VPS escreve o estado de 10 em 10 minutos numa
tabela que só os administradores lêem. Publiquei o site e verifiquei que o ecrã abre e mostra o cartão, no
computador e no telemóvel.

Erros que encontrei pelo caminho e não corrigi. A ponte do contentor do Hermes tenta chegar ao PC pelo nome
"bora-pc", que já não existe no Tailscale (o PC chama-se agora "danilo"). A firewall da própria VPS está
desligada e há portas a ouvir para fora: o painel do Hermes (32768), o bora-trader (8090), outra aplicação na
8099 e o serviço de impressoras (631); não verifiquei se a Hostinger tem uma firewall por fora que as tape. O carteiro do loop tem uma cadeia de recurso pelo plano Go (qwen3.8-max, qwen3.7-max,
minimax-m3) que está morta pela mesma chave expirada. O Cerebras não tem saldo (dá 402 com as duas chaves);
deixei-o desligado. Três modelos da NVIDIA (kimi-k3, deepseek e gpt-oss) já não existem (410). A voz gratuita
da Microsoft está a falhar e a voz cai para a reserva local, que funciona. O Groq grátis não aguenta os pedidos
grandes do Hermes (limite de 8 mil tokens por minuto), por isso só serve as chamadas pequenas. Se a linha de
definições do suporte desaparecer, dois robôs (o chat humano e a análise de conversas) voltam a modelos Gemini
que já não existem (1.5 e 2.5 flash); hoje a linha existe e diz gemini-3.5-flash-lite, por isso não estão
partidos. O
disco da VPS ficou com 6 GB livres (88% cheio). E, nesta pasta do PC, ficaram cópias de ficheiros da missão
fora do controlo de versões (a pasta ferramentas/omniroute e uma migração): a tranca não me deixou apagá-las e
são iguais às que já estão no servidor; antes de outra sessão actualizar o ramo, essas cópias têm de sair.

Próximo passo. Se quiseres o OpenCode Go de volta, cria a chave e eu troco-a. Depois de 30/10, se tudo estiver
estável, desligo o Motor Bora antigo e passo os outros 18 perfis.

## PARA O DANILO

Uma decisão só tua: renovar ou não o OpenCode Go (é a assinatura paga). Endereço: opencode.ai/console.

## Registo técnico

Detalhe com hora e prova literal no e2e_log, fluxo omniroute-23-10. Digest no Córtex (caixa hermes-reporte,
ref-f783a7) e em claude_ai_memoria, página digest-2026-10-23-omniroute. Código e instruções em
ferramentas/omniroute/ (README). Commit do painel 40c9c2ec.
