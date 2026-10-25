---
id: memoria-claude-ai-whatsapp-a-discutir
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-25
zona: verde
confianca: alta
estado: atual
---

# WhatsApp — o que ainda está por discutir com o Danilo (esqueleto desligado)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `whatsapp-a-discutir`, origem `claude-code`, atualizada em 2026-10-25T18:51:26.391974+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: whatsapp a discutir · memoria claude.ai · claude_ai_memoria

# WhatsApp — o que ainda está por discutir com o Danilo (25/10/2026)

Missão livro-comum-2026-10-23, Bloco 6. O Danilo disse a 23/10: "do WhatsApp só o esqueleto; ainda há muito a discutir".
Nada foi ligado. whatsapp_settings.envio_ligado = false (desde 13/09, pausa pedida por ele) e
whatsapp_settings.modo_rascunho_ligado = false (novo, 25/10). Ninguém recebe resposta nenhuma.

## O que já ficou feito (esqueleto, desligado)
- Coluna whatsapp_contacts.tipo_conversa: loja / pessoal-danilo / incerto. Por defeito "incerto" para todos os 97 contactos.
- No painel admin, ecrã WhatsApp: cada conversa mostra o tipo e o menu de três pontos deixa marcá-lo.
- No Hermes, o ponto de encaixe /opt/data/rotinas/whatsapp_modo_rascunho.py: lê os dois interruptores e sai sem fazer nada enquanto estiverem desligados. Não tem relógio (cron) nem é chamado por ninguém.

## Perguntas abertas (decisões do Danilo)
1. Como distinguir loja de pessoal? Hipóteses: marcar à mão no painel (já possível); regra "contacto que existe como cliente/parceiro/estafeta na base = loja"; tudo o resto fica incerto até ele marcar. Pessoal nunca recebe nada automático.
2. O que o bot pode responder sozinho, mesmo em modo rascunho? Proposta: nada sai sozinho; só horários, link da app e estado de um pedido, e mesmo isso primeiro como rascunho.
3. Número pessoal vs número da loja: separar? Um número só da Bora (WhatsApp Business oficial, Meta Cloud API) acabaria com a mistura e com o risco do ponto 4.
4. Risco de bloqueio: o número atual está ligado por um programa não oficial (whatsapp-bora / ligar.js na VPS, emparelhado como WhatsApp Web). O WhatsApp pode banir números que enviam por programas não oficiais, e esse número é também o pessoal do Danilo. Responder em massa aumenta o risco.
5. Modo rascunho no Telegram: a mensagem chega ao bot, o Hermes escreve a resposta e manda ao Danilo no Telegram; ele diz "manda" ou "muda para…" (igual ao caça-clientes, comando caca). Só para conversas "loja". Ligar exige: decidir 1-4, depois modo_rascunho_ligado=true, e o envio_ligado continua false até ele dizer o contrário.
6. Quem é avisado quando um cliente escreve fora de horas, e em quanto tempo?

## Regra até lá
Nada liga sem ordem dele, com data. Se alguém pedir para ligar, a resposta é: "está à espera da decisão do Danilo; ver whatsapp-a-discutir".

