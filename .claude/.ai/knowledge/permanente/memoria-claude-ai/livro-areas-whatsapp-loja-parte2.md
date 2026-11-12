---
id: memoria-claude-ai-livro-areas-whatsapp-loja-parte2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-12
zona: verde
confianca: alta
estado: atual
---

# Regras fixas do Danilo para o atendimento automático do WhatsApp da loja — ler antes de mexer nesse atendimento (parte 2 de 2)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-whatsapp-loja-parte2`, origem `claude-ai`, atualizada em 2026-11-12T07:14:46.857952+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas whatsapp loja parte2 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/whatsapp-loja.md, parte 2 de 2), copiada a 12/11/2026 07:15 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

COBRADOR DAS 09:30 (aviso diário de "mensagens sem resposta")
- Existe um cobrador que às 09:30 manda ao Danilo, pelo Telegram, a lista de quem está sem resposta e as mensagens já redigidas para ele carregar em enviar. NÃO está documentado no Córtex (`cortex_buscar` deu 0) — vale a lição de 04/09: ausência no Córtex não prova ausência no sistema.
- 08/09: mandou dois falsos alarmes. Causa achada por SELECT: contava como pendentes as linhas do CENSO de 02/09 (`porta='censo'`, `decisao='historico'`, 132 linhas, algumas de 2025 — o histórico antigo importado, a que o Danilo já respondeu à mão) e não contava como resposta as saídas posteriores à última entrada. Colou ainda a story do dia (com "Facebook: ok" e ID de Instagram) dentro do corpo de uma mensagem para cliente, e os textos saíam sem acentos.
- [stated] Danilo mandou corrigir e disparar pelo carteiro. ORDEM `ordem-20260908101414-29f3` (zona verde) EXECUTADA E FECHADA 08/09 (juiz + conselho, ronda 1): ignorar censo/histórico; dar por respondida a conversa com saída posterior à última entrada; story sempre em bloco separado; acentos em UTF-8. ONDE VIVE O COBRADOR (custou uma ordem a descobrir): `/opt/data/rotinas/cobrador.py` na VPS, FORA do repo git do bora_app — se a VPS for reposta a correção perde-se; fica apontado que vale versioná-lo. Confirmado por mim por SELECT depois do fecho: com a regra nova, zero conversas pendentes.
- [stated] A Isabel (pergunta de 16/08 sobre demora de um pedido) fica decisão dele, à mão — confirma a regra já filada de que mensagens antigas ficam.

PAUSA GERAL DO ENVIO (13/09)
- [stated] Danilo mandou pausar o atendimento automático antes de ele próprio escrever pelo WhatsApp da loja (razão dele: "não está muito bom, tenho que consertar"). Fica pausado até ele mandar ligar outra vez — a ordem de religar é dele.
- FEITO por MCP (Claude.ai, sem executor): `whatsapp_settings.envio_ligado=false`, mais `envio_desligado_em` e `envio_desligado_motivo`. É AQUI que vive o interruptor geral do envio (tabela `whatsapp_settings`, chave `envio_ligado`), vale para as duas portas. PROVADO: a mensagem que entrou 4 segundos depois (whatsapp_messages id 866) ficou com `decisao='silencio-missao'` e não saiu resposta nenhuma. Consequência avisada a ele: com isto desligado NENHUM cliente recebe resposta automática nesse número.
- [stated] 23/10: o WhatsApp da loja NÃO é só da loja — é também dele, as pessoas falam com ele lá; o bot antigo não sabia distinguir o que é da loja do que é pessoal. Antes de ligar qualquer resposta automática quer discutir com calma como responder; por agora só o esqueleto, nada ligado. Gostava também que um agente respondesse por ele no WhatsApp (ideia em aberto)
- [stated] 29/10/2026 (robô da loja parceira, caso [[boom-burger]]): a resposta tem de ser NA HORA — o cliente manda e o WhatsApp já responde, sem ficar à espera; e o robô tem de ser "super inteligente": saber tudo da app e tudo da loja (menu, preços, horário, morada), e pedir ao cliente todas as informações do pedido (morada, etc.). Ele testa pelo telemóvel pessoal e quer resposta imediata
- [stated] 31/10/2026 09:53 (depois de o suporte responder a um "oi" com "não tenho resposta para isso" — "o suporte está muito burro"): o agente de suporte passa a ser o Claude (crédito da API do plano Ultra, missão "motor Claude primeiro") e tem de responder a TUDO o que cliente, estafeta ou parceiro perguntarem, a orientar como a Claude.ai o orienta a ele — "como se fosse eu conversando aqui com você"; só passa o contacto dele quando a pessoa pedir para falar com alguém. Pedido acrescentado ao prompt prompt-motor-claude-2026-10-31 (bloco 3f, prova com 6 mensagens simuladas)
- [stated] 31/10/2026 10:01 (vale para TODOS os robôs: WhatsApp da Bora, assistente das lojas, suporte, Emerson): têm de ser "super inteligentes" — passar-lhes tudo o que eu sei; lêem o livro comum e o Córtex; o que não souberem vão consultar em algum lado antes de responder; o WhatsApp da loja tem de saber tudo do BORA, não só da loja; cuidado com a informação que não é para dar; e conversar como um chat humano, mesmo em assunto pessoal. Posto no prompt prompt-motor-claude-2026-10-31 (bloco 4d, com lista do que nunca se diz e prova de 6 perguntas)
- [stated] 12/11/2026: quer ter acesso a TODA conversa em que um robô responde a um cliente (o robô da Boom Burger incluído) — tem de lhe chegar pela app/painel ou pelo Hermes ("se o bot está respondendo o cliente, eu tenho que ter acesso à conversa"); o "662" dos relatórios de revisão é o número pessoal dele (931 992 662), que está na lista de teste do robô da Boom
- [stated] 12/11/2026: o WhatsApp da Bora (937 501 673) é respondido por ele à mão — quando o robô manda o cliente falar com a equipa, é lá que ele responde; o robô antigo desse número (whatsapp_settings.envio_ligado) fica desligado
- [stated] 12/11/2026 06:22: quer notificação no telemóvel, na app do painel admin, de CADA mensagem das conversas dos robôs (do cliente e do robô), em tempo real; tocar abre logo o ecrã dessa conversa; e poder interromper e escrever ele. Missão "conversas ao vivo" registada (ver [[robo-suporte]])

