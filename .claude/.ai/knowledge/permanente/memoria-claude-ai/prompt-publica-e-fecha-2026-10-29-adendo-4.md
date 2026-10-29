---
id: memoria-claude-ai-prompt-publica-e-fecha-2026-10-29-adendo-4
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Adendo 4 (29/10 19:10): robô WhatsApp da Boom AO VIVO para o teste do Danilo, resposta na hora, super inteligente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-publica-e-fecha-2026-10-29-adendo-4`, origem `claude-ai`, atualizada em 2026-10-29T19:08:00.851122+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt publica e fecha 2026 10 29 adendo 4 · memoria claude.ai · claude_ai_memoria

ADENDO 4 ao prompt-publica-e-fecha-2026-10-29 (Claude.ai, 29/10 19:10). URGENTE, entra à frente dos Blocos B/C (logo a seguir ao A.4): o Danilo quer testar AGORA o robô da Boom pelo telemóvel dele.

FACTO: às 19:03 o Danilo escreveu do número pessoal (351931992662) para o WhatsApp da Bora (351937501673): "Pode me mandar a lista dos hambúrguer". Nada chegou à tabela whatsapp_messages (última entrada registada: 16:12, do Emanuel, com decisao 'silencio-missao') e o robô não respondeu. Ordem literal dele (19:06): "tem que ser a resposta na hora. O cliente mandou, o WhatsApp já tem que estar respondendo. E ele tem que ser super inteligente, super. Tem que saber tudo do aplicativo e da hamburgueria Boom. Pedir todas as informações, endereço, essas coisas, tudo."

A FAZER (VPS, assistente-negocio / robô baileys):
1. Descobrir porque a mensagem das 19:03 não entrou: ligação baileys caída? filtro do número do dono (LEMBRETES_NOMES_DONO / anti-nome)? modo 'silencio-missao' ainda ligado? modo 'simulado' (as 42 saídas da prova foram simuladas, não enviadas)? Regista a causa no e2e_log 'A.7-robo-boom-causa'.
2. Pôr o robô AO VIVO para o número do Danilo (janela modo_demo_loja já aberta até 30/10 15:36Z, cliente demo bb9ff342): tirar o silêncio da missão, tirar o modo simulado para esse número, garantir que o número pessoal dele NÃO é ignorado pelo filtro do dono (o filtro dos lembretes serve só para não escrever o nome dele; não para ignorar mensagens dele).
3. Resposta NA HORA: primeira resposta em menos de 5 s (acusar e já responder), nunca deixar o cliente à espera; se o motor principal demorar, responde com o texto rápido (menu/horário) enquanto pensa, e rotaciona para o motor seguinte (adendo 2, só grátis).
4. Super inteligente: o robô tem de saber TUDO da Boom (menu completo com preços de balcão certos — 27 produtos atualizados às 16:20, opções, bebidas em falta até o Emanuel mandar, horário 19h15-23h e dias, morada da loja, entrega grátis acima de 30 €, taxa de entrega 2,50 até 4 km, saco 0,30, pagamento só dinheiro pelo WhatsApp e as outras formas na app, tempo médio) e TUDO da app Bora (como instalar: boraguarda.com/baixar, o que é, como acompanhar o estafeta, código BEMVINDO). Fluxo do pedido: pede nome, morada completa (rua, número, andar, referência), telefone de contacto, forma de pagamento, confirma o total linha a linha e cria o pedido pelo caminho já provado (create_order com as mesmas contas do servidor). Confirma que a base de conhecimento do robô está carregada com o catálogo real (SELECT de products da boom-burger-guarda), não com texto antigo.
5. Prova: manda tu próprio (pelo caminho de teste que já existe) 3 mensagens como se fosse o Danilo — "lista dos hambúrgueres", "quanto fica um Clássico entregue na Rua X", "quero pedir 2 Kamikaze" — e confirma resposta certa e tempo < 5 s na primeira resposta. Depois responde à mensagem REAL das 19:03 do Danilo (com a lista dos hambúrgueres e preços) e regista 'A.7-robo-boom-ao-vivo' no e2e_log com os tempos.
6. Se algo disto for zona vermelha ou precisar de chave que não há, regista e segue — mas o robô tem de responder ao Danilo hoje.
