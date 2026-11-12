---
id: memoria-claude-ai-prompt-conversas-ao-vivo-2026-11-12
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-12
zona: verde
confianca: alta
estado: atual
---

# Missão conversas ao vivo dos robôs + robô esperto (12/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-conversas-ao-vivo-2026-11-12`, origem `claude-ai`, atualizada em 2026-11-12T06:27:03.444674+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt conversas ao vivo 2026 11 12 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️
MOTOR: Opus 5.5 · PORTA: Claude Code no PC do Danilo (pasta bora_app / repo bora-app-cloud, branch autonomous-night-2026-04-29), sessão nova, Ignorar permissões.
Invoca primeiro o orquestrador CEO-AI em .claude/skills/ceo-ai/ e segue o protocolo-missao-bora.
Fluxo e2e_log: 'conversas-ao-vivo-2026-11-12' (um passo por bloco, com prova).

AUTORIZAÇÃO (texto literal do Danilo, 12/11/2026 06:22): "quando o robô estiver falando com o cliente, respondendo, tem que chegar aqui em tempo real para mim. Notificação mesmo no meu telemóvel, na aplicação, que eu tenho o painel administrativo... E aí eu clicar nesse robô na conversa deles, já vai para a tela que eles estão conversando. E se eu quiser interromper e falar alguma coisa, eu consigo também... Eu quero que faça essa missão aí. E corrigir o robô. O robô tem que saber tudo."

CARTA DE AUTONOMIA: decides sozinho, nunca terminas o turno à espera, saltas o que travar e voltas depois, reportas pelo Telegram (Hermes). Preço, comissão e Stripe NÃO se mexem nesta missão. Antes de mexer em cada coisa, diz no e2e_log o que vais mexer (função/tabela/ecrã) e porquê. Outro erro que encontres pelo caminho: REPORTA, não corrijas calado. Cópia de segurança (tabela bkp_*_20261112) antes de qualquer UPDATE/DELETE em dados.

CONTEXTO (medido hoje por SQL, Claude.ai):
- Há 3 robôs a falar com clientes e o Danilo NÃO vê as conversas em tempo real:
  1) Robô do suporte da app — Edge support-chatbot → support_chatbot_sessions / support_chatbot_messages, support_tickets, support-human-chat.
  2) Amigo Bora / Bora Assistente — Edge client-assistant → assistant_conversations / assistant_chat_messages, assistant_gaps, assistant_learned.
  3) Robôs das lojas no WhatsApp (Boom Burger e outros tenants) — servidor_cerebro na VPS → assistant_tenants / assistant_messages.
  (O WhatsApp da Bora 937 501 673 — whatsapp_messages — tem o robô desligado: whatsapp_settings.envio_ligado=false. FICA DESLIGADO: é o Danilo que responde lá à mão. Não religar.)
- Hoje só chega ao Danilo o "precisa de ti" (passagem à equipa) pelo Telegram e pelo caminho notify_admin_urgent_push() → admin_notifications + Edge notify-admin-urgent (FCM para admin_push_tokens + Telegram).
- Caso real: Isabel Dias falou com o Amigo Bora às 01:57–02:01 de 12/11 (tokens, mudar-se para Pinhel) e o Danilo só viu um "pedido de ajuda" sem a conversa.

BLOCO A — Diagnóstico (só leitura): confirma as 3 fontes acima, os ecrãs que já existem no painel admin (Suporte, WhatsApp, Assistente) e o caminho de push do admin. Regista no e2e_log.

BLOCO B — Ecrã "Conversas ao vivo" no painel admin (PT-BR, termos técnicos explicados entre parênteses):
- Lista única com TODAS as conversas dos 3 robôs, ordenada pela última mensagem, ao vivo (Supabase Realtime). Em cada linha: origem (Suporte da app / Amigo Bora / Robô <loja> no WhatsApp), nome e contacto do cliente (nunca só o número), última mensagem, estado (robô a responder / Equipa assumiu / à espera da equipa), contador de não lidas. Filtro por origem e "só à espera da equipa".
- Ao tocar: ecrã da conversa inteira, balão a balão (Cliente / Robô / Equipa Bora), ao vivo; chamadas de ferramentas escondidas mas abríveis; atalho para a ficha do cliente e para o pedido se houver.

BLOCO C — Interromper e falar:
- No ecrã da conversa: caixa de texto + "Enviar como Equipa Bora", botões "Assumir conversa" e "Devolver ao robô".
- Quando o Danilo escreve ou assume: o robô PARA nessa conversa (não responde mais) até ele carregar "Devolver ao robô" ou passarem 12 h sem mensagem dele.
- A mensagem chega ao cliente no MESMO canal: app → aparece no chat do cliente em tempo real + push ao cliente; WhatsApp de loja → sai pelo número da Bora pela VPS. Assina sempre "Equipa Bora", nunca o nome do Danilo (regra do anonimato).
- Servidor: RPC só para admin (is_admin()), com auditoria. Código defensivo (rede cai, toque duplo, null).

BLOCO D — Notificação em tempo real no telemóvel do Danilo (app do painel admin):
- Cada mensagem nova numa conversa de robô (do cliente E do robô) gera push FCM ao admin. Título: "<origem> · <nome do cliente>"; corpo: "Cliente: ..." ou "Robô: ...".
- Agrupar por conversa (Android tag / iOS thread-id): a notificação da conversa atualiza-se com as últimas linhas, não enche o ecrã.
- Tocar na notificação abre DIRETO o ecrã dessa conversa (deep link) — provar em Android, iPhone e web.
- Gatilho: triggers AFTER INSERT nas 3 tabelas de mensagens → Edge (nova ou extensão da notify-admin-urgent) com junção de mensagens a menos de 3 s; tudo dentro de EXCEPTION para NUNCA partir o robô. O sininho guarda uma linha por conversa (atualizada), não uma por mensagem. Telegram continua só com o "precisa de ti" (não inundar).
- Painel: interruptor por origem e "silenciar esta conversa". Por defeito TUDO LIGADO; mensagens de contas de teste marcadas [teste].

BLOCO E — Robô esperto (os 3 robôs):
- JÁ FEITO por Claude.ai hoje via MCP (migração robos_area_entrega_guarda_2026_11_12): assistant_learned com 2 entradas source='admin' da zona de entrega (só Guarda, até 15 km do centro; Pinhel, Celorico da Beira, Trancoso, Sabugal, Covilhã, Vilar Formoso fora); desligadas 2 "respostas aprendidas" que eram trechos de notas internas; skill GENERAL_FAQ do suporte com a cobertura firme e a regra certa dos tokens (máximo METADE do valor dos tokens que tem). VERIFICA no código do client-assistant que as lições source='admin' entram SEMPRE no prompt (não só por question_norm igual); se não entram, faz entrar.
- Põe a mesma regra da zona de entrega no conhecimento de TODOS os tenants de WhatsApp (assistant_tenants.knowledge, Boom incluída).
- CAUSA-RAIZ a tratar: support_knowledge_chunks tem 471 trechos source_type='obsidian' (notas internas de programação: bugs, auditorias, TODOs) e o robô respondeu a clientes com isso ("Resumo por Esforço", "Próxima sessão → Firebase push"). Tira as notas internas do que os robôs pesquisam (filtro no match_knowledge ou nas Edge; backup antes, nada apagado de vez), reindexa o business_rules.md atual e o manual da app, e impede o auto-aprender de guardar trechos que começam por "[secção]".
- Resolve as perguntas em aberto de assistant_gaps (Pinhel feito; pintura → ver o que a categoria Casa e Manutenção oferece hoje; eventos da Guarda → pesquisa web que já está ligada).
- Regra: o robô não diz "não sei"/"passei à equipa" sobre o que está nas regras do negócio; vê os últimos 7 dias de report_gap/handoffs e preenche o conhecimento.
- PROVA: 8 perguntas simuladas com conta de teste nos 2 robôs da app (Pinhel; Celorico; "mas é distrito da Guarda"; "pago 15 € de entrega"; "tenho 1060 tokens, quanto posso usar"; "quero alguém para pintar a casa"; horário do Fuku Sushi; "quero falar com humano") — respostas firmes, sem passar à equipa no que é sabido. Guarda perguntas e respostas no e2e_log.

BLOCO F — Alertas e revisão diária:
- Bug: o alerta para o WhatsApp do Danilo foi CANCELADO pela trava do anonimato (whatsapp_saida 12/11 04:38, estado 'cancelada-anonimato') porque o texto tinha o nome "Danilo" do cliente. A trava do anonimato vale só para mensagens a clientes; NUNCA para alertas ao número do próprio Danilo (351931992662). Corrige e prova.
- A revisão diária do WhatsApp dava como "sem resposta" conversas a que o Danilo respondeu à mão (farmácias 11/11). Grava as mensagens enviadas pelo próprio telemóvel da Bora (fromMe, pela VPS) como saída 'manual-equipa' e a revisão conta-as como resposta. A revisão explica cada caso em português simples: quem é (nome, nunca "662"), o que perguntou, o que lhe responderam, e o link da conversa no painel.

BLOCO G — Publicar e provar nas 3 plataformas (Android, iPhone, web): ecrã Conversas ao vivo, push com deep link e interromper a funcionar em cada uma. App em PT-PT, painel em PT-BR. O CI incrementa o versionCode (não mexer à mão). Termina com git push origin autonomous-night-2026-04-29.

FIM: relatório curto no Telegram ("fiz isto, falta isto"), regista o prompt e o estado no vault Obsidian (C:\Users\danil\Desktop\Bora\prompts\) e no e2e_log, depois corre /ctx doctor e /ctx stats.
