# O que os vídeos ensinaram — e o que foi feito na noite de 08 para 09/11/2026

Missão `m10-noite-toda-sem-travas-2026-11-08`, sessão "M10 radar e VPS" (Claude Code, Opus 5.5).
Ordem do Danilo, 08/11 às 23:21: "pega todos os vídeos que já viu, analisa as coisas boas e FAZ; o nosso
sistema tem de ficar o melhor que existe; vê o GitHub e o mundo inteiro, país a país".
Cada passo tem prova no `e2e_log` (fluxo `m10-noite-toda-sem-travas-2026-11-08`, passos `2B.x` e `2.15`–`2.18`).
Inventário do que está instalado com prova: [INVENTARIO.md](INVENTARIO.md). Top 10 por país:
[mundo-2026-11-09.md](mundo-2026-11-09.md) (dados brutos em `mundo-2026-11-09.json`).

## O que o radar tinha guardado

Li a tabela `radar_videos` inteira: 1362 vídeos de 24/09 a 08/11, 694 com nota 8 ou mais. Vereditos: 290 "já
temos", 224 "novo", 262 "pendente", 457 rejeitados (208 por nota baixa) e 129 sem veredito. Li também a página
`ideias-videos-danilo` (45 secções), as páginas `livro-areas-radar-ia` (3 partes), as 20 propostas pendentes do
Córtex e as reclamações do Danilo sobre o radar (17/09, 24/09 — "4.ª vez que peço, nunca tive resposta" —, 04/10,
17/10 — o radar calou o REA —, 21/10, 31/10 e 08/11). O padrão das reclamações é sempre o mesmo: o radar regista
e propõe, mas nada fica feito. Por isso a regra nova desta noite é "pendente vira tarefa com nome de missão, e só
sai da lista com prova".

Os pendentes e novos com nota alta, juntos por tema: agentes e orquestração 166, CRM e atendimento por WhatsApp
97, Claude Code, skills e hooks 76, redes e crescimento 37, motores grátis e rotação 36, segurança 27, engenharia
reversa 26, animação e vídeo com IA 8.

## Por tema: o que foi feito esta noite, o que ficou e porquê

**Agentes, motores grátis e Claude Code.** O Dipsy passou a ter o mesmo tecto de 64 000 tokens também quando cai
para os motores grátis (antes era 4 000 na reserva); provei antes que o Gemini grátis aceita esse tecto e que o
Groq é saltado sozinho pelo limite por minuto. A M3 achava que a resposta longa do Dipsy não ficava no registo de
gastos: ficou (11 017 tokens às 20:48 de 08/11, no ficheiro da VPS e no Supabase). A "Free LLM API" que os vídeos
mostram é o repositório tashfeenahmed/freellmapi (MIT, 49 mil estrelas): o nosso Motor Bora já faz o mesmo, com 10
fornecedores grátis vivos e centenas de modelos — está no inventário com prova. O Token Economizer da Microsoft é
aberto (Apache-2.0) e é um plugin do Claude Code que corta 18 a 31% do gasto; instalei-o no Claude Code da VPS e os
ganchos correram, mas desfiz porque descobri que o executor `claude -p` da VPS não tem sessão iniciada desde julho
(os robôs que dependem dele não correm — iniciar sessão é coisa do Danilo). No PC não o instalei a meio da noite:
a poda automática de ferramentas podia esconder ferramentas a missões que estavam a correr. Fica como tarefa, com o
passo seguinte escrito. O Billion Context foi rejeitado (é um proxy dentro do Claude Code, proibido pelos termos) e
o Jev continua fora (pago).

**Hermes e VPS.** A firewall estava ligada e provei-a de fora: só passam as portas 22, 80 e 443. Limpei 1,35 GB de
disco regenerável (de 72% para 69%). O painel do Hermes deixou de estar acessível pela internet: agora só abre pela
rede privada, com senha; os outros sítios da VPS ficaram iguais (medidos antes e depois). A atualização do Hermes
para a 0.23 ficou ADIADA com razão medida: a imagem nova traz outra versão do Python e outra configuração, e obriga
a recriar o contentor, o que perde mais de 11 mil mudanças feitas lá dentro (a rede privada que liga o Dipsy e o
OmniRoute incluída). Testei a 0.23 isolada, sem rede, e apaguei a imagem no fim. O porteiro único do Telegram, o
ramo do OmniRoute e o filtro de lojas das redes já estavam feitos de antes; provei cada um outra vez esta noite.

**Radar a nunca mais ficar para trás.** O radar de IA semanal não saía desde a semana 40 (início de outubro): os
cinco modelos falhavam todos no mesmo segundo. Passou a pedir o texto ao Motor Bora primeiro, com a cadeia antiga de
reserva, e ganhou a varredura mundial por país (GitHub, grátis, sem credencial) dentro do material de domingo. A
regra nova do radar diário está escrita no livro (página `ideias-videos-danilo`, secção de 09/11): pendente vira
tarefa por tema com nome de missão, a moda vai sempre na mensagem, e "já temos" só com prova no inventário.

**CRM e atendimento por WhatsApp (pacote PMEs).** O "Deskcom" dos oito vídeos com nota 10 é o
melgarafael/DeskcommCRM (MIT, 5 284 estrelas, atualizado a 08/11, feito no Brasil). O Waziper é um script pago e
fica fora. Não instalei: precisa de um Supabase próprio (um projeto novo custa dinheiro e é decisão do Danilo; o
Supabase inteiro dentro da VPS não cabe nos 2,2 GB livres), de uma chave de IA paga e de um número ligado por QR
(só o Danilo). Medições e alternativas abertas (WAHA, Baileys, WPPConnect, Whaticket) estão no e2e_log.

**Redes e crescimento.** A fábrica de cortes de reels aprovada a 25/10 estava sem prova: provei o corte automático
de pausas num vídeo com fala em português e ruído de fundo (15 s para 9,3 s, a fala ficou inteira). Falta a prova
com um vídeo filmado por uma pessoa (não havia nenhum no PC). Publicar nas redes estava proibido esta noite.

**Engenharia reversa (só o nosso).** Auditei a nossa app web sem a executar: nenhum segredo no código (nenhuma chave
secreta da Stripe, do Supabase, do Telegram ou de modelos de IA). Encontrei um ponto de configuração a corrigir, que
ficou registado só no e2e_log e numa tarefa do Córtex (não se descreve aqui porque este repositório é público). O
APK fica para uma janela com memória livre.

**Animação e vídeo grátis (Studio).** Só registo, como pedido: o caminho da página `caminhos-animacao-filme` já
estava atualizado com a ordem de 05/10. Sem placa de vídeo no PC e com 1 processador na VPS, nada local.

**Córtex.** As 20 propostas pendentes ficaram tratadas: a dos preços do Boom rejeitada formalmente (o Danilo disse
não a 31/10), a do gancho nos executores marcada "não se aplica" (era uma trava), duas feitas com prova, as outras
juntadas em 11 tarefas por tema com nome de missão; a do GPS do despacho fica à espera do Danilo (zona vermelha).

## Top do mundo, país a país (o detalhe com 10 por país está em mundo-2026-11-09.md)

Brasil: akitaonrails/ai-memory (memória longa para agentes de código, MIT, 15 mil estrelas) e o DeskcommCRM.
Portugal: andredelgado/continente-mcp (pesquisa de produtos do Continente para agentes, MIT, 06/11) — útil para o
catálogo dos mercados. Espanha: SantanderAI/ralph e llm_bridge (Apache), six2dez/burp-ai-agent (segurança).
França: suitenumerique/conversations (chatbot aberto do Estado francês, MIT). Alemanha: n8n (kit de IA
auto-alojada, skills e a skill que encontra trabalho manual repetido). Índia: frappe/crm (CRM aberto para PMEs,
AGPL) e frappe/erpnext. China: deepseek-harness (a base do Dipsy), QwenLM/qwen-code e alibaba/open-code-review
(Apache). Japão: antfu/skills e yomiyasu (reescreve texto de IA para soar natural — a ideia serve ao PT-PT).
Coreia: graykode/abtop (ver as sessões do Claude Code como um htop) e bam-bam-2/solo-skills (38 skills para quem
trabalha sozinho). Rússia: pouco que passe as regras (T8RIN/ImageToolbox). Turquia: cobanov/websum (resume páginas
e vídeos com motores locais) e cobanov/awesome-jev. Indonésia: pondok-ai (um ChatGPT privado para uma sala).
Nigéria: quase nada aberto e recente que passe as regras. Polónia: software-mansion/argent (agente que controla e
depura apps Android e iOS — candidato forte para os testes da app) e mrexodia/agent-cost-dashboard.

## O que fica e porquê (tarefas no Córtex, cada uma com o passo seguinte)

`radar-tarefa-hermes-023` (migração de dia, com o Danilo acordado), `radar-tarefa-crm-whatsapp-pmes` (Supabase,
chave e QR), `radar-tarefa-token-economizer` (PC numa janela calma; executor da VPS sem sessão),
`radar-tarefa-seguranca-chave-maps`, `radar-tarefa-pacote-pmes` (preços do Danilo), `radar-tarefa-redes-crescimento`
(publicar com aprovação), `radar-tarefa-em-dia`, `radar-tarefa-studio-animacao`, `radar-tarefa-agentes-autonomia`,
`radar-tarefa-bora-ideias` (mexem em preços ou na app) e `radar-tarefa-rea-apk`.
