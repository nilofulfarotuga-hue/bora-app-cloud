---
id: memoria-claude-ai-paridade-uber-ifood-2026-10-13
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-13
zona: verde
confianca: alta
estado: atual
---

# Paridade Bora vs Uber/Uber Eats/iFood + REA (vídeos de 13/10)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `paridade-uber-ifood-2026-10-13`, origem `claude.ai chat 13/10/2026`, atualizada em 2026-10-13T20:13:18.207805+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: paridade uber ifood 2026 10 13 · memoria claude.ai · claude_ai_memoria

PEDIDO DANILO 13/10/2026: viu 3 vídeos sobre o REA (Reverse Engineer Anything) e quer tudo o que Uber, Uber Eats e iFood têm no Bora.

REA: MCP + CLI open-source (morluto/rea, npm rea-agents), corre local, liga agentes (Claude Code) a Ghidra/Hopper/IDA; lê binários, Electron, APK Android, sites, capturas HAR. Passou 115k estrelas a 12/10. Funciona melhor em Mac/Linux. CUIDADO: há repos falsos a oferecer "download zip" (ex. gmlactran/REA) = possível malware; instalar só por npx rea-agents setup.
REGRA: NÃO desmontar o APK da Uber/iFood (termos de uso proíbem, risco de banir contas/processo). Copiar FUNCIONALIDADES observando o app por fora (emulador, ajuda pública, novidades oficiais) = legal e já é a regra do Bora. REA serve para o NOSSO app: achar bugs e ver se há regra de dinheiro/chave só dentro do app (pricing_service.dart, _previewSplit) — agora qualquer um lê o APK do Bora.

JÁ EXISTE NO BANCO DO BORA (verificado por SQL 13/10): pedido agendado (orders.scheduled_for), recolha/takeaway+curbside, substituições, alergénios, PIN de entrega, gorjeta (tips), códigos promo e convites, favoritos, assistente de carrinho IA (assistant_cart_proposals), WhatsApp (whatsapp_*), banners home, carrinhos abandonados, suporte chatbot, reservas com lista de espera e planta de mesas. TVDE: preço fixo, paragens, reserva agendada, partilhar viagem, SOS, planos/assinatura de corridas, mudança de destino, envio de encomenda.

FALTA / NÃO ENCONTRADO (a confirmar no código antes de construir):
Cliente entregas: pedido em grupo; dividir conta; assinatura tipo Uber One/Clube iFood (entrega grátis por mês); "pedir de novo" num toque (confirmar); foto prova de entrega (sem coluna própria); ofertas de cesto com sugestões para chegar ao mínimo; recompensa por voltar a pedir; cartão-presente; selos de fidelidade por loja; pesquisa única para tudo (pendente em home-cliente-faixas); assistente que monta carrinho a partir de foto de lista (confirmar se o nosso aceita foto); compra num clique pelo WhatsApp (iFood, jul/2026).
Cliente TVDE: escolher categoria (XL, Pet, elétrico, conforto); dividir corrida; perfis família/empresa; gravar áudio da viagem; "encomenda a caminho" (motorista traz o café — Uber Eats for the Way, abr/2026); pedir corrida por voz.
Estafeta/motorista: ganho garantido visível antes de aceitar (Uber tip guarantee); ver na hora quanto muda o preço quando cliente muda destino/paragem; espera paga a contar mais cedo nas paragens; ecrã de metas (iFood); antecipar ganho diário sem taxa (iFood, até R$400/dia); mapa em ecrã cheio com zonas e promoções; contestar bloqueio com texto e até 5 fotos (iFood set/2026); lista de pedidos disponíveis para escolher (iFood Rotas Disponíveis); assistente de voz; filtro de mensagens ofensivas no chat.
Parceiro: anúncios pagos dentro da app; descrições de menu por IA; aparecer por categoria de produto; relatório por loja.

ORDEM SUGERIDA (foco dele = faturar o que já existe; desempate = o que rende todos os meses): 1) pedir de novo + pesquisa única; 2) assinatura mensal de entregas (receita recorrente); 3) ganho garantido visível ao estafeta; 4) encomenda a caminho na corrida TVDE; 5) pedido em grupo / dividir conta.
PRÓXIMO PASSO: missão no PC (emulador) — 1.º percorrer o Bora inteiro e confirmar no código cada "falta"; depois Uber e iFood por observação (ordem que ele fixou a 08/10, ver area analise-apps-emulador).
