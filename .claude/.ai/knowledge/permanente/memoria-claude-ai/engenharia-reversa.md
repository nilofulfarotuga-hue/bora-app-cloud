---
id: memoria-claude-ai-engenharia-reversa
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-17
zona: verde
confianca: alta
estado: atual
---

# Engenharia reversa — método do Danilo para clonar o que já existe (pedido 17/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `engenharia-reversa`, origem `claude.ai chat 17/10/2026`, atualizada em 2026-10-17T09:12:50.068966+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: engenharia reversa · memoria claude.ai · claude_ai_memoria

PEDIDO DANILO 17/10/2026 (depois do vídeo "clonar qualquer app com Claude + skill REA"): a engenharia reversa passa a ser um MÉTODO FIXO do sistema. Sempre que algo for pago, tiver limite de créditos ou nos travar, a primeira pergunta é: "isto já existe grátis no mundo (GitHub, código aberto)? se não existe, dá para recriarmos as funções olhando por fora?". Vale para o filme das filhas (animação, boca a mexer, vozes, música), para o Bora App (tudo o que Uber, Glovo, iFood têm) e para qualquer ferramenta paga do dia a dia. Ele quer dizer "faz isso" e sair perfeito.

COMO SE FAZ (o que o vídeo ensina, confirmado):
1. Olhar por fora: o agente (Claude Code com navegador, ou emulador Android no PC) usa a app como um utilizador — clica em todos os botões, regista cada ecrã, o que abre, para onde vai — e lê a ajuda pública, notícias e documentação oficial.
2. Escrever o mapa: lista de ecrãs e funções, com prova (print) de cada uma.
3. Construir a nossa versão: o "motor por trás" é nosso, feito com as boas práticas; só as funções ficam iguais.
4. Antes de construir do zero, procurar no GitHub se alguém já clonou (muitas vezes já existe e é grátis).

LIMITES (regra desde 13/10, mantém-se): copiar FUNÇÕES olhando por fora é legal. NÃO desmontar o APK/código da Uber, Glovo, iFood ou de qualquer app de terceiros (os termos de uso proíbem; risco de banir contas e processo). Nunca copiar logótipos, nomes, imagens, textos nem código deles. O REA (desmontar por dentro) só se usa no NOSSO app (Bora e Em Dia), para ver o que um atacante veria: chaves e regras de dinheiro que estejam só dentro da app têm de passar para o servidor.

REA = Reverse Engineer Anything: ferramenta aberta (MCP + linha de comandos, repo morluto/rea, npm rea-agents) que liga o Claude Code a programas de análise (Ghidra/Hopper/IDA) e lê programas, APK Android, sites e capturas de rede. Instalar SÓ por "npx rea-agents setup"; há repositórios falsos com "download zip" que podem ser vírus (ex. gmlactran/REA).

PORQUE O RADAR NÃO AVISOU (achado 17/10): entre 12/10 e 17/10 o radar viu mais de 10 vídeos do REA com nota 8-9, registou uma proposta a 13/10 e marcou todos os outros como "já temos" sem nada estar feito. E a missão do emulador combinada a 13/10 (percorrer o Bora inteiro e confirmar no código cada falta) nunca correu (nada no e2e_log). Corrigido no prompt do radar a 17/10: "já temos" só com prova; o que foi só registado é "pendente"; assunto com 3+ vídeos fortes na semana é moda e vai sempre na mensagem ao Danilo; limite de 70 termos já não deixa de fora assunto forte.

O QUE JÁ ESTÁ APURADO DO BORA vs UBER/GLOVO/iFOOD: ver página paridade-uber-ifood-2026-10-13 (lista do que já temos e do que falta, e ordem sugerida).

ACHADOS DA PESQUISA MUNDIAL DE 17/10: acrescentados abaixo.
