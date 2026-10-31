---
id: memoria-claude-ai-prompt-motor-claude-2026-10-31
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Prompt Motor Claude 31/10: robôs usam primeiro o crédito da API do Claude (plano Ultra) e depois a rotação grátis

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-motor-claude-2026-10-31`, origem `claude-ai`, atualizada em 2026-10-31T06:20:16.315988+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt motor claude 2026 10 31 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5 (se as salvaguardas da Anthropic marcarem a sessão, troca para Sonnet 5.5 e continua)
PORTA: sessão NOVA do Claude Code no PC do Danilo, pasta bora_app (bora-app-cloud). VPS por SSH pelo nome público srv1786862.hstgr.cloud, Supabase por MCP, Chrome do Danilo pela extensão.
FLUXO e2e_log: motor-claude-31-10 · run_id: motor-claude-2026-10-31 · nome da sessão: "Motor Claude 31/10"

Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/ e segue o PADRAO_BORA. Antes de começar, lê a memória (erros-aprendidos, hermes-agent, radar-ia, whatsapp-loja, empresa-agentes, livro-comum), o Córtex e a página claude_ai_memoria 'motores-rotacao-2026-10-29' (medição de 29/10 com o mapa de TODOS os sítios onde os robôs escolhem o motor). É o teu ponto de partida, mas confirma tudo na máquina: o papel não é prova.

AUTORIZAÇÃO DO DANILO (31/10/2026 06:08, texto literal): "Sim. É, vai ser tipo rotatório. Quando acabar o do Claude Code, vai utilizar o que nós estamos utilizando no gratuito. Mas vamos utilizar aqui o do Claude Code. Então você tem que fazer os robôs utilizar. Tem que fazer a máquina bora funcionar da melhor forma possível. Ela ser super inteligente. Aprender com os erros, fazer tudo, responder, fazer de tudo."

O QUE É E PORQUÊ
O plano Ultra do Danilo inclui 200 dólares por mês de crédito da API do Claude, na organização da Console "danilo's Individual Org" (ligada a 17/10). Último crédito: 111,82 USD (subida para o Ultra a 29/10). Próximo: 200 USD a 30/11. O crédito vence no fim de cada ciclo e não passa para o seguinte, e hoje NENHUM robô o usa, por isso está a perder-se. Cobre a API do Claude, Managed Agents, Agent SDK e playground. NÃO cobre o Claude Code.
Objetivo: todos os robôs da Bora usam primeiro o Claude, pago por este crédito. Quando a parte do dia ou o crédito do mês acaba, caem sozinhos na rotação grátis que já existe. Quando chega o crédito novo, voltam sozinhos ao Claude. E a máquina fica mais inteligente: sabe tudo do Bora e aprende com os erros.

REGRAS DURAS
1. A chave nunca aparece no chat, em logs, em ficheiros do git nem em linhas de comando visíveis (passa sempre por stdin). Ficheiros com a chave: chmod 600 e dono certo.
2. NUNCA pôr ANTHROPIC_API_KEY em variáveis globais do PC nem em nenhum sítio onde corre o Claude Code: o crédito não cobre o Claude Code e partia o Claude Code do Danilo. Não mexer no run-claude-loop.cmd:144 (essa variável é do gateway Go e é obrigatória). Consumidores que vivem no PC (ex.: juiz) chamam o porteiro da VPS pela Tailscale; nenhuma chave no PC.
3. Nada de comprar créditos, pôr cartão na Console nem ligar a recarga automática. Se encontrares cartão ou recarga ligada na Console, desliga a recarga e reporta (não apagues o cartão).
4. Não ligar o envio do WhatsApp da Bora (whatsapp_settings.envio_ligado fica false: o Danilo quer conversar antes de ligar). Não mudar o modo dos tenants (boom-burger e secretario-demo em 'teste', mister-navalha 'desligado').
5. Não mexer no Dipsy/DeepSeek Harness (tem missão própria), no OpenCode SEM-LIMITE, em preços, comissões ou pagamentos, nem nos ficheiros das outras sessões que estejam a correr (anúncios da Meta, Casa & Manutenção).
6. Antes de mexer num ficheiro da VPS: cópia com data ao lado. Reinicia um serviço de cada vez, com prova logo a seguir; se partir, repõe a cópia e reporta. O motor-bora serve o Hermes e o WhatsApp: reinicia-o com cuidado.
7. Mede a RAM antes (portões: PC 400/800 MB, VPS 1 GB). Se o PC estiver abaixo, faz o trabalho na VPS e adia o Flutter.
8. Qualquer OUTRO erro que encontres pelo caminho: REPORTA. Não o cales nem o corrijas por conta própria, excepto o que este prompt manda.

BLOCO 0 — Estado real (só ler)
Confirma na máquina o mapa da página 'motores-rotacao-2026-10-29': assistente-negocio (tabela assistant_tenants, motores.py, classificador em assistente.py), Motor Bora (/opt/motor-bora, catalogo.py PERFIS), OmniRoute (/opt/omniroute/or_combos.py: agentes, privado, rapido, volume, visao), Hermes/Emerson (/opt/data/config.yaml: modelo principal e fallback_providers; 25 perfis em /opt/data/profiles), rotinas (/opt/data/rotinas: despachante, emerson, carteiro_caca, radar_freelas, cobrador), juiz do carteiro, cérebro do WhatsApp da Bora (/opt/whatsapp-bora/cerebro) e as Edge Functions da app que chamam IA (decidir, os robôs com o ecrã de troca de modelo, admin-ai-assistant, Robot B). Lista também o que JÁ existe para "aprender com os erros" (cérebro do WhatsApp, vigia-habilidades, livro comum, escriba e crítico). Não reconstruas o que existe. e2e_log 'b0-estado'.

BLOCO 1 — Crédito e chaves do Claude
a) Chrome do Danilo, perfil PESSOAL (deviceId 5b260cdd-9d4f-49d6-842b-ebfbfea69c75; NUNCA o d9e862e0): platform.claude.com, "Continuar com o Google" na conta nilofulfarotuga@gmail.com, organização "danilo's Individual Org". Se o Google pedir confirmação no telemóvel, manda-lhe pelo WhatsApp (do número pessoal dele para o número da loja, regra de 29/10) uma linha a dizer onde carregar, e continua com o resto enquanto esperas.
b) Billing da Console: lê em "Promotional credits" o valor e a validade de cada crédito, e confirma que não há cartão nem recarga automática. Em claude.ai/settings/billing lê o "Próximo crédito". Grava em platform_settings: claude_credito_atual_usd, claude_credito_validade, claude_proximo_credito, claude_credito_mensal_usd = 200.
c) Cria o workspace "Robos Bora" com limite de gasto mensal de 200 USD e duas chaves nele: "robos-vps" (VPS) e "app-supabase" (Edge Functions). Duas chaves para se poder cortar uma sem parar a outra.
d) A "robos-vps" fica num ficheiro só para isto na VPS (ex.: /opt/segredos/claude.env, 600), ligado aos serviços que precisam. A "app-supabase" vai como segredo ANTHROPIC_API_KEY das Edge Functions (supabase secrets set, a ler de stdin). Em mais lado nenhum.
e) Se o sistema travar a criação da chave, usa o caminho provado a 30/10 (token do Dipsy): deixa o formulário preenchido à frente do Danilo, ele só carrega em "Create key" e "Copy"; um vigia no PC apanha a chave da área de transferência (padrão sk-ant-api), valida-a com uma chamada mínima, grava-a na VPS por stdin e limpa a área de transferência. O pedido do clique vai-lhe pelo WhatsApp, numa linha.
f) Prova: uma chamada mínima ao claude-haiku-5-5 com cada chave, HTTP 200. e2e_log 'b1-chave'.

BLOCO 2 — O porteiro do crédito (Claude primeiro, grátis depois)
Um sítio só decide, para cada pedido de cada robô, se vai ao Claude ou à rotação grátis. Escolhe tu onde (o Motor Bora é nosso e é o mais fácil de mexer; o OmniRoute ou passa por ele ou segue a mesma regra) e explica a escolha no relatório. Comportamento:
- Livro de gastos: tabela ia_gastos (robô, modelo, tokens de entrada, saída e cache, custo_usd pelos preços oficiais, quando). Preenche também tokens e custo em agentes_corridas (hoje estão sempre a 0).
- Ritmo: o crédito que resta divide-se pelos dias até ao próximo crédito, para durar o mês todo e não acabar em dois dias.
- Prioridades: P1 respostas a clientes (WhatsApp das lojas) usam o Claude enquanto houver crédito. P2 o Emerson a falar com o Danilo e as decisões (decidir, despachante, torre, juiz) usam até à parte do dia. P3 agentes, radares e volume usam só até metade da parte do dia. Acabou a parte, esse pedido vai logo para a rotação grátis, sem erro para ninguém.
- Se a API responder sem saldo (400 "credit balance is too low"), 429, 529, 5xx, ou demorar mais de 20 s: salta logo para a rotação grátis. Sem saldo = Claude "dormido" até ao próximo crédito; no dia do crédito novo testa com uma chamada mínima e volta sozinho.
- Modelos e preços oficiais (31/10, USD por milhão de tokens): claude-haiku-5-5 0,10 entrada / 0,50 saída / 0,01 cache (até 100 mil tokens por pedido; acima disso fica 5x mais caro); claude-sonnet-5-5 2 / 10 / 0,10; claude-opus-5-5 4 / 20 / 0,20. Regra: conversas com clientes, Emerson e decisões = Sonnet 5.5; classificar, resumir, agentes e volume = Haiku 5.5; Opus nunca automático. Cache sempre ligado no texto fixo (manual, regras, menu, lições): usa a API nativa (Messages) para o cache funcionar; se usares a compatível com OpenAI, prova que o cache funciona. Trabalho que pode esperar vai pela Batch API (metade do preço).
- A rotação grátis atrás do Claude é a medida a 29/10: groq gpt-oss-120b, gemini-3.1-flash-lite, groq qwen3.8-27b, gemini-3.5-flash-lite, groq gpt-oss-20b, gemini-3-flash-preview. Tira das cadeias os mortos: go:*, gemini2:*, zen por API e ollama.
Prova: pedido normal vai ao Claude; saldo "acabado" simulado só no porteiro (nada na Console) dá resposta da rotação grátis em menos de 30 s; parte do dia esgotada num P3 manda-o para o grátis enquanto um P1 continua no Claude; depois volta ao normal. e2e_log 'b2-porteiro'.

BLOCO 3 — Ligar cada robô ao porteiro (um de cada vez, com prova)
a) WhatsApp das lojas (assistente-negocio): fornecedor Claude no motores.py; cadeias dos 3 tenants = Claude Sonnet 5.5 e depois a rotação grátis (o mister-navalha ainda tem go:glm-5.2 morto: corrige); classificador = Haiku 5.5 e depois groq. Corrige também o que a medição de 29/10 apontou: timeout de 45 s com repetição (passa a 20 s, sem repetir) e o _castigar que não trata 401/402. Prova com simular_boom.py: 3 mensagens certas em português (entrega 4 km = 2,50 €; 6 km = 3,50 €; preço que não está no menu = não inventa), motor usado = Claude, menos de 10 s cada.
b) Emerson/Hermes: modelo principal Claude Sonnet 5.5 pelo porteiro; troca os fallback_providers mortos (opencode-go, opencode-zen) pela rotação grátis viva; perfis escriba e fiscal igual. Prova: oneshot (-z) respondido pelo Claude e uma mensagem real no Telegram do Danilo em voz e texto (a voz tem de continuar a funcionar).
c) Os 25 perfis, os combos do OmniRoute (agentes e privado com Claude à frente; rapido e volume com Haiku à frente), as rotinas e o juiz do carteiro: cada um com a prioridade e o modelo do bloco 2. Prova: uma ronda da torre e uma do crescimento com tokens e custo gravados.
d) Cérebro do WhatsApp da Bora: Claude à frente (cadeia.txt e Motor Bora), tira ollama e zen. O envio continua DESLIGADO. Prova só em simulação.
e) Robôs da app (Edge Functions): Claude como primeira opção e o Gemini atual de reserva, no decidir, nos robôs com o ecrã de troca de modelo (acrescenta Claude Haiku 5.5 e Sonnet 5.5 à lista desse ecrã) e no admin-ai-assistant (o chat do painel que ficou parado desde junho à espera de uma chave Anthropic). Prova: uma chamada a cada função respondida pelo Claude. Se o sistema travar a publicação de alguma função, reporta qual e segue.
e2e_log 'b3-<robô>' por robô.

BLOCO 4 — Super inteligente e a aprender com os erros
a) Todos os robôs passam a ter, em cache no início de cada pedido, o LIVRO-ESSENCIAL do livro comum, as regras do Danilo e as lições ativas dos robôs. Com o cache sai barato.
b) Lições: quando o Danilo corrige um robô (resposta ao Emerson no Telegram, ou quando assume uma conversa no WhatsApp porque o robô falhou), quando um cliente reclama, ou quando o juiz ou o crítico reprovam, o escriba grava uma linha em licoes_robos (data, robô, o que errou, regra certa, origem), igual ao caderno de erros do Claude.ai. De noite o crítico (Sonnet 5.5) junta as repetidas e arquiva as que já não valem. Todos os robôs lêem as lições ativas.
c) Prova com um ciclo real: resposta errada de propósito em simulação, correção, lição gravada, e a mesma pergunta respondida certa a seguir. e2e_log 'b4-licoes'.

BLOCO 5 — Painel admin (ecrã /admin/motores, já existe)
Faz numa worktree própria (C:\BoraLocal\wt-motor-claude-31-10, a partir da autonomous-night-2026-04-29) para não colidir com as outras sessões. Cartão "Crédito Claude" em PT-BR, com os termos técnicos explicados entre parênteses: crédito que resta e quando vence, próximo crédito, gasto de hoje e do mês, gasto por robô, parte do dia, e para cada robô um interruptor "usar Claude" e o modelo (Haiku ou Sonnet). Exportar o livro de gastos. Lições: lista com editar e arquivar. Tudo editável pelo Danilo (autoridade total). flutter analyze com 0 erros. Envia para o servidor só os ficheiros desta missão (git push origin autonomous-night-2026-04-29) e verifica o ecrã depois da publicação nas 3: web, Android e iPhone. e2e_log 'b5-painel'.

BLOCO 6 — Fecho
- Copia para o repo (ferramentas/vps/...) os scripts da VPS que mudaste, sem chaves.
- Dipsy: NÃO mexer. Deixa no relatório a linha exata para ele usar o porteiro (endereço e perfil), para a missão dele.
- Registo: e2e_log 'fim'; digest no Córtex (para o ChatGPT, o Emerson e o Dipsy lerem); nota no Obsidian (C:\Users\danil\Desktop\Bora); página claude_ai_memoria 'motor-claude-2026-10-31' com o estado final.
- Mensagem final ao Danilo pelo Telegram, em voz e texto, curta: o que ficou feito, quanto se gastou nas provas, o que falta.
- Relatório final em texto corrido, sem tabelas nem emojis: "fiz isto, falta isto".

AUTONOMIA: decides tudo sozinho, não acabas o turno à espera de ninguém, saltas o que estiver bloqueado e voltas a ele no fim. Só paras para mudança de preço ou comissão (não há nenhuma nesta missão). Se precisares de um clique físico do Danilo, manda-lhe pelo WhatsApp uma linha só, com o sítio exato, e continua com o resto.

/ctx doctor
/ctx stats
