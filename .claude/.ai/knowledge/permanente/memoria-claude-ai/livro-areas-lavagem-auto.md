---
id: memoria-claude-ai-livro-areas-lavagem-auto
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Serviço próprio de lavagem de carros com recolha e entrega dentro do Bora App — modelo, serviços e preços que o Danilo definiu a 26/08

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-lavagem-auto`, origem `claude-ai`, atualizada em 2026-10-23T05:38:59.319019+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas lavagem auto · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/lavagem-auto.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: lavagem-auto
description: Serviço próprio de lavagem de carros com recolha e entrega dentro do Bora App — modelo, serviços e preços que o Danilo definiu a 26/08
sources: [chat]
aliases: [lava jato, lavagem auto, lavagem de carros, leva e traz do carro]
---
- [stated] 26/08: quer abrir um serviço PRÓPRIO de lavagem de carros na Guarda, dentro do [[bora-app]]
- [stated] Modelo: leva-e-traz — alguém vai buscar o carro do cliente pelo app, leva a lavar e devolve
- [stated] Quem faz o serviço é ele próprio e mais um colega, em DOIS para ser mais rápido, com o carro dele ou a moto de um parceiro; vai recrutar parceiros para o serviço como fez na [[limpeza-vertical]]
- [stated] NÃO abre instalação própria — usa as máquinas do Baleia Verde (lavagem self-service da Guarda): a moeda custa-lhe ~€1–2 para aspirar e ~€4–5 para lavar, ~€7 de gasto no total
- [stated] Só dois ou três preços, nada de luxo/detalhe (SUBSTITUI o nível "luxo" que tinha falado antes): lavagem por fora, e lavagem completa (por fora + aspirar e passar o pano por dentro)
- [stated] Preços que ele pôs em cima da mesa: ~€12 a lavagem por fora e ~€20 a completa (já com deslocação incluída no pacote)
- [stated] Fluxo que quer: cliente escolhe "chamar agora" (ou daqui a 30/40 min) ou agenda hora, e o sistema chama o parceiro cadastrado — igual à Limpeza
- [stated] QUER CATEGORIA NOVA no ecrã inicial, não meter dentro da Beleza; disse que se já existir algo com o mesmo sistema é "copiar e colar e fazer o que está a faltar"
- [stated] Quer ter todos os dias alguma novidade no grupo a mostrar que estão a entrar lojas novas, para chamar atenção

Decisões fechadas 27/08
- [stated] PREÇOS FINAIS: lavagem exterior €12, lavagem completa (fora + aspiração e pano por dentro) €20. Terceiro serviço "Só interior" €12 fica criado mas DESLIGADO, para ele ligar no painel se quiser
- [stated] Aceitou o nome de categoria "Lavagem Auto" (ladrilho novo no ecrã inicial) e a marca da loja "Lava & Leva", cadastrada como parceiro real com ele como dono — sem dono inventado
- [stated] Base técnica decidida: clonar o motor da [[limpeza-vertical]] para tabelas/funções `carwash_*`/`washers`, sem tocar em nada `cleaning_*` (a Limpeza está viva)
- [stated] REGRA DAS FOTOS (corrigida por ele): para o CLIENTE a foto do carro é sempre OPCIONAL, com convite simpático, nunca obrigatória. Para o LAVADOR são obrigatórias 4 fotos na recolha (frente, trás, lateral esquerda, lateral direita, só câmara na hora) e o botão "Recolhi o carro" não avança sem elas; fotos da entrega opcionais
- [stated] PROMPT ENDURECIDO entregue 27/08: PROMPT_lavagem_auto_lava_e_leva_2026-08-27.md, motor OPUS (ele não quer gastar o Fable), janela Claude Code no PC — scope: categoria completa em produção (base de dados, app cliente PT-PT, app do lavador, pagamentos pelos caminhos existentes, painel admin PT-BR, notificações data-only, teste ponta-a-ponta em dinheiro, Em breve reposto no fim). Estado: EXECUTADO 27/08 e verificado por mim via MCP — 6 tabelas `carwash_*`/`washers` com RLS e políticas, 42 funções, 14 settings, bucket de fotos privado, push data-only, Limpeza intacta; só `carwash_quote` aberta a anónimo (de propósito, ver preço sem conta). Zero pedidos na base, lavador criado (credenciais ficam no relatório no PC dele, não aqui)
- [stated] SEGURA POR UM INTERRUPTOR (ultrapassado 27/08): `carwash_enabled` esteve `false` — o ladrilho nem aparecia na app; liguei-o por MCP a pedido dele
- [stated] CATEGORIA ABERTA em produção (27/08): `carwash_enabled=true`, cartão/MB WAY ligados, realtime ligado em `carwash_bookings`/`carwash_messages`, tokens no fecho aplicados por mim via MCP no padrão da Limpeza (cliente 3 tokens/€ mínimo 1, lavador +40, idempotente). Build 551 publicado
- [stated] CORREÇÃO DELE que substitui a minha decisão anterior de adiar o cartão: nada de lançar só com dinheiro — ver [[regras-lancamento-categorias]]
- [stated] FICA POR FECHAR: MB WAY recusado pelo provedor nos testes (código igual ao que funciona desde abril) — ele tem de dizer que número tem MB WAY; ladrilho ainda com ícone simples porque a quota da chave Gemini do PC estourou; e o teste de pagamento com cartão real, que só ele pode fazer (nenhum agente escreve dados de cartão)

