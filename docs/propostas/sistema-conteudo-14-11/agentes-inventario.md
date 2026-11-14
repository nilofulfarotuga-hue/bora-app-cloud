# Agentes do Bora: quem trabalha de facto (14/11/2026)

Missão `sistema-conteudo-14-11`, bloco 2-ter. Tudo lido a 14/11 por volta das 13h (Lisboa), só leitura:
datas dos ficheiros de sessão do Claude Code, contagem de `"subagent_type":"<nome>"` nas transcrições
(2008 ficheiros, 4,2 GB, de 31/08 a 14/11, por ripgrep), tabelas `despacho`, `agentes_estado`,
`agentes_corridas`, `e2e_log`, `radar_*`, `assistant_*`, `support_*` e `robot_crosstalk` pelo MCP do Supabase,
e os registos do Dipsy e do opencode. Não entrei na VPS: as tabelas já provam o que lá corre.
Memória livre medida antes do teste A/B: 631 MB (o portão do trabalho leve é 400 MB).

## O que encontrei, em texto corrido

O Claude Code no PC trabalha todos os dias: entre 36 e 168 sessões por dia nos últimos 8 dias, a última
de hoje. Mas quase tudo corre sem agente especializado: o tipo geral foi chamado cerca de 647 vezes e o
Explore 70, contra 14 dos 31 agentes da pasta `.claude/agents` (a pasta tem 33 ficheiros; o README e o
template não são agentes). Os outros 17 nunca foram chamados. Os números contam menções nas transcrições,
por isso cada chamada pode aparecer duas ou três vezes; servem para comparar, não como valor exato.

O mais grave: o agente `juiz-revisor` nunca correu. O cabeçalho dele tem dois pontos sem aspas na
descrição ("Gate obrigatório: nenhum…"), o leitor de YAML recusa-o e o Claude Code não o carrega. A
mensagem "Agent type 'juiz-revisor' not found" aparece 396 vezes nas transcrições. O `evolution-engine`
tem o mesmo defeito. O `template.md` carrega como um agente falso chamado "nome-do-agente". O Juiz que
funciona são os scripts (anti-trapaça e zonas): último registo `juiz` ok no e2e_log a 11/11. O registo do
juiz do Dipsy só tem testes de 30/10. Não existe nenhum "refinador": não encontrei agente, skill nem registo.

Na VPS (Hermes/Emerson), a tabela `agentes_estado` tem 25 agentes. Doze correram nas últimas 24 horas,
todos com ok: a torre de hora a hora (336 corridas em 14 dias), o gestor de parceiros, o cobrador, a
qualidade, os dois vendedores e o crescimento uma vez por dia, e hoje também redes, escriba, atendimento,
gestor-em-dia e designer. Três estão ligados mas parados: recrutador e fiscal sem correr desde 07/09, e o
crítico nunca correu. Dez estão desligados. No `despacho` há 5 tarefas do Emerson à espera do Danilo
(a última de hoje), 3 que falharam hoje, uma do Dipsy à espera desde 09/11 e três antigas de setembro
(designer, cobrador) esquecidas no mesmo estado. O porteiro do Telegram escreveu 362 linhas em 7 dias,
a última às 13h de hoje. O agente de segunda já tem uma tarefa feita hoje.

O Dipsy (dsh) está vivo: sessão de hoje às 12h11, a ponte do Telegram a correr (uma falha de rede às
12h08, recuperou) e 114 registos do filme no e2e_log, o último de hoje. O opencode também: registo de
hoje às 12h28, com o motor grátis deepseek-v4.1-flash-free.

O radar está vivo: 1582 vídeos, o último recolhido hoje às 00h55 (UTC), 131 pesquisas, e o resumo
diário na nuvem correu ontem às 20h56. Dos robôs da app, o assistente da app respondeu hoje (561
mensagens, a última às 05h53), o chat de suporte ontem às 19h13 e o robô de documentos hoje às 10h00.
O assistente por WhatsApp está calado desde 11/11 (pode ser só falta de mensagens). A ponte Robô A para
Robô B está parada desde 09/09 (7 linhas no total). Não há nenhum pedido de suporte em `support_tickets`.

## Teste A/B (barato, uma vez cada)

Corri o mesmo pedido de leitura com `claude -p --model claude-haiku-5-5` (Claude Code da subscrição,
sem chave da API), uma vez com o agente (`--agent`) e outra sem agente. Comparei com a resposta certa
tirada por SQL. É uma amostra de uma corrida cada: indica, não prova.

Primeiro pedido, agente `seguranca`: "que tabelas do public têm RLS desligada". A resposta certa é 20,
todas cópias `bkp_`. Com o agente acertou em 32 s e custou 0,019 USD. Sem agente também acertou, em
29 s e por 0,017 USD. Empate, e o agente sai 14% mais caro.

Segundo pedido, agente `admin`: "quantos pedidos criados ontem e quantos entregues". A resposta certa é
3 e 3. Com o agente acertou (3 e 3), por 0,015 USD, mas a sessão demorou 233 s (só 30 s de modelo; o
resto foi espera de ganchos e do fecho da sessão). Sem agente falhou: não encontrou a ferramenta do
Supabase, tentou o CLI, foi recusado e desistiu, por 0,017 USD.

Conclusão: o agente não ganha em saber mais. Ganha quando diz onde estão as ferramentas (o MCP do
Supabase). Esse ganho cabe numa linha no CLAUDE.md ou numa skill, sem precisar de 31 agentes.

## Propostas de simplificação (não apaguei nada)

- Corrigir já os cabeçalhos de `juiz-revisor.md` e `evolution-engine.md`: pôr a descrição entre aspas.
  Sem isto o Juiz como agente não existe. Tirar o `template.md` da pasta, ou mudar-lhe a extensão.
- Juntar os 17 agentes nunca usados aos que trabalham, e arquivá-los numa subpasta `_arquivo` depois do
  sim do Danilo: dados-sql com backend-supabase; checkout-fixer e e2e-test-builder como braços do Juiz;
  catalogo-visual com mercados; diretor-criativo, social-media e marketing-push num só agente de
  marketing; agent-memory e obsidian-sync com bibliotecario-cerebro; favores e parceiro-servicos com
  cliente e parceiro-restaurante. O dispatch e o pagamentos-wallet ficam, porque só propõem e guardam
  zonas protegidas.
- Pôr no topo de cada agente que fica uma linha "ferramentas: MCP Supabase (carregar com ToolSearch),
  Córtex, …", que foi o que fez a diferença no teste.
- Na VPS, desligar ou consertar o recrutador, o fiscal e o crítico (ligados sem correr) e fechar as três
  tarefas de setembro que ainda estão à espera do Danilo.

## O que falta para a automação total (só a lista; a orquestração é a missão da caixa 8)

- Um maestro único que receba uma tarefa e a mande para o Claude Code, o Dipsy ou o Emerson pela
  mesma fila (`despacho`). Hoje a fila só alimenta a VPS e o agente de segunda. O `maestro-autonomia`
  existe mas nunca foi chamado.
- Um Juiz automático depois de cada tarefa, no PC e na VPS: o agente partido e o crítico parado deixam
  isto em aberto.
- O quadro Sim/Não no painel admin para as tarefas "à espera do Danilo" (a proposta de migração já
  está na árvore).
- O agente de segunda com horário fixo e relatório (já correu uma vez hoje).
- Um vigia de agentes parados: alerta quando um agente ligado não corre há mais do dobro da sua cadência.
- Gasto por agente também no PC (a `agentes_corridas` só mede a VPS).
- Decidir se a ponte Robô A para Robô B volta a funcionar ou se sai do sistema.
