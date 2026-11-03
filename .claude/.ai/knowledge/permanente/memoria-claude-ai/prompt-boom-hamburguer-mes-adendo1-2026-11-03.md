---
id: memoria-claude-ai-prompt-boom-hamburguer-mes-adendo1-2026-11-03
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-03
zona: verde
confianca: alta
estado: atual
---

# Adendo 1 (03/11 07:50): carrinho esquecido, anúncio da Boom, autorização de promoções, números dos anúncios, próximo anúncio

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-boom-hamburguer-mes-adendo1-2026-11-03`, origem `claude-ai`, atualizada em 2026-11-03T07:46:13.248088+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt boom hamburguer mes adendo1 2026 11 03 · memoria claude.ai · claude_ai_memoria


⚠️ MODO PROTECÇÃO TOTAL ⚠️ — ADENDO 1 à missão boom-hamburguer-mes-2026-11-02 (retoma 03/11). MOTOR Opus 5.5, mesma sessão "PC do Danilo". Regista cada bloco no e2e_log, fluxo boom-hamburguer-mes-2026-11-02. Faz isto DEPOIS dos blocos B, C e D da retoma (ou em paralelo onde não houver choque), e antes do fecho E.

AUTORIZAÇÃO (Danilo, 03/11/2026 07:43, texto literal): "Sim, vamos fazer todas essas seis aí. É, só que aumentar de 5 para 10 eu não quero, não. Vamos deixar 5 euros por dia, tá bom."
Não mexe em preços nem em taxas de entrega/serviço (a proposta de entrega grátis nas lojas de sushi/kebab/pizza está à espera de outro "autorizo" dele).

F — AVISO DE CARRINHO ESQUECIDO (porquê: existe desde 04/10, nasceu desligado e nunca foi ligado; 8 carrinhos largados em 7 dias e 0 avisos — ex.: cliente novo largou 24,03 € no Fuku Sushi a 02/11 19:36). A Claude.ai tentou ligar daqui e o sistema travou.
- platform_settings key carrinho_abandonado_ligado = true. Minutos, título e texto ficam como estão. O cron 100 (carrinhos_abandonados_avisar, de 15 em 15 min) já está ativo.
- Provar: na corrida seguinte do cron, carrinhos reais elegíveis ficam com avisado_em preenchido e o push sai (notification log / notify-client). Ver o ecrã "Carrinhos abandonados" do painel admin com o interruptor ligado. Não mandar a carrinhos de teste do Danilo.

G — ANÚNCIO DA BOOM COM O REEL (porquê: o anúncio da Boom é o que mais rende — 99 visitas a 0,04 € cada no 1.º dia)
- Quando o reel do Café de Paris (bloco D) estiver aprovado pelo juiz e publicado, trocar a imagem do anúncio da campanha "Boom! Burger chegou à Bora - Guarda 8 km (02/11)" (id 52680841873474, conta act_1105400138585537, Chrome Bora d9e862e0) por esse reel, com o mesmo texto e o mesmo destino. ORÇAMENTO FICA 5 €/dia, fim 07/11 — NÃO aumentar. Provar com captura do Gestor de Anúncios.

H — AUTORIZAÇÃO DE PROMOÇÕES NO REGISTO (porquê: só 3 de 217 clientes aceitaram receber promoções, por isso não se pode mandar nada aos 12 clientes novos de ontem; padrão Glovo/Uber Eats)
- App cliente (PT-PT): no fim do registo, uma caixa simples "Queres receber promoções e novidades das lojas da Guarda? Podes mudar quando quiseres no Perfil." com Sim / Agora não, NUNCA pré-marcada (RGPD). Aos clientes que já existem e nunca responderam, mostrar UMA vez ao abrir a app. Interruptor no Perfil. Grava users.marketing_opt_in e marketing_opt_in_at.
- Painel admin (PT-BR): quantos aceitaram, lista, e data.
- Publicar nas 3 (Play, App Store/TestFlight, web) junto com o bloco C e provar nas 3.

I — NÚMEROS DOS ANÚNCIOS NO RESUMO DAS 21:30 (porquê: o resumo diz "não sei" porque a VPS não tem META_ADS_TOKEN; erro (#200) sem ads_read)
- Na Meta Business (Chrome Bora d9e862e0), criar um token de utilizador de sistema SÓ com ads_read para a conta act_1105400138585537. Guardar como META_ADS_TOKEN no .env da VPS (nunca no repo, nunca no chat). Provar que o resumo das 21:30 (corrida a seco) mostra gasto, cliques e visitas da campanha da Boom.

J — PRÓXIMO ANÚNCIO, DEPOIS DE SEXTA (porquê: repetir a receita que trouxe os 12 clientes; fim do plano de 14 dias a 06/11, anúncio da Boom acaba 07/11)
- Preparar em RASCUNHO (sem ligar) uma campanha igual à da Boom: 5 €/dia, Guarda 8 km, 18-55, objetivo Tráfego, destino a loja na app; loja conhecida da cidade — McDonald's primeiro (entrega grátis a partir de 20 €), depois Continente (grátis a partir de 30 €). Arte com foto real de comida/produto, de cinema, logo da Bora, "entrega grátis a partir de X €" e BEMVINDO; juiz com visão antes.
- Mandar a arte e o texto ao Danilo (WhatsApp da Bora → 931992662) para ele aprovar ANTES de ligar (regra 31/10). Início previsto 07/11.

K — SÓ REGISTAR (análise da Claude.ai, 03/11): desde a entrega grátis de 23/10, McDonald's, Continente e Burger King tiveram 4 carrinhos e os 4 viraram pedido (antes: 6 largados em 7). Os carrinhos largados agora são das lojas de telefone sem entrega grátis (Fuku 3 vezes, Pôr do Sol). A mesma receita para Fuku, Jyosmi, Pôr do Sol, DaVinci, Tiago's Pizza e KFC está proposta ao Danilo e à espera do "autorizo". NÃO mexer nisso nesta missão.

Fecho: igual ao bloco E da retoma (e2e_log, envio só dos ficheiros da missão, relatório curto, digest, /ctx doctor, /ctx stats).

