---
id: memoria-claude-ai-meta-anuncios-2026-10-30-textos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Textos finais dos 2 anúncios Meta de 30/10/2026 (Instala e pede + Check-in diário)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `meta-anuncios-2026-10-30-textos`, origem `claude-code`, atualizada em 2026-10-31T06:43:05.366772+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: meta anuncios 2026 10 30 textos · memoria claude.ai · claude_ai_memoria

Textos finais, gravados antes de publicar (missão meta-anuncios-2026-10-30, Claude Code, 30/10/2026 ~22:30).

CORREÇÃO AO PROMPT: o código BEMVINDO dá 1000 tokens = 5,00 € (promo_codes value_cents 1000; client_redeem_promo_tokens com token_value_cents_x100=50 devolve euro_value 5,00). Os anúncios dizem 5 €, não 10 €. Subir para 10 € é dinheiro e espera o "autorizo" do Danilo.

ANÚNCIO 1 — "Instala e pede"
Texto principal: A Guarda tem tudo à porta. Supermercado, restaurantes, farmácia ou aquele favor de que precisas: pedes no Bora e chega a casa. Entrega desde 2,50 €. Instala hoje, usa o código BEMVINDO e recebes 5 € em tokens de boas-vindas.
Título: 5 € de boas-vindas no Bora
Descrição: Entrega desde 2,50 € na Guarda
Botão: Transferir
Link: https://www.boraguarda.com/baixar?de=meta-instala-e-pede&utm_source=meta&utm_campaign=instala-e-pede
Imagens: anuncio1-instala-e-pede-1x1.jpg e -9x16.jpg (fotos reais: hambúrguer do Pôr do Sol, salgados da Keli, Goola Bowl; ícones da app).
Público: Guarda, raio 8 km, 18-55.

ANÚNCIO 2 — "Abre todos os dias e ganha" (carrossel Check-in diário)
Texto principal (Guarda 8 km): Sabias que abrir uma app todos os dias pode valer um açaí? No Bora, cada check-in diário dá tokens. Ao 10.º dia seguido ganhas 2 salgados da Keli, ao 15.º um açaí do Goola e ao 30.º escolhes 2 horas de limpeza em casa ou uma lavagem exterior do carro. Instala hoje com o código BEMVINDO e começas já com 5 € em tokens. Prémios com telemóvel confirmado e um pedido pago nos últimos 30 dias; um prémio por sequência; nos produtos pagas só a entrega e as taxas.
Texto principal (estudantes IPG): Estudas no Politécnico da Guarda? Abre o Bora entre aulas e faz o check-in: tokens todos os dias, 2 salgados da Keli ao 10.º dia seguido, um açaí do Goola ao 15.º e, ao 30.º, 2 horas de limpeza ou uma lavagem exterior do carro. Instala hoje com o código BEMVINDO e começas com 5 € em tokens. Prémios com telemóvel confirmado e um pedido pago nos últimos 30 dias; um prémio por sequência; nos produtos pagas só a entrega e as taxas.
Cartões (título): 1) Dia 1 a 7: tokens todos os dias 2) Dia 10: 2 salgados da Keli 3) Dia 15: um açaí do Goola 4) Dia 30: limpeza ou lavagem do carro 5) BEMVINDO = 5 € em tokens
Botão: Transferir
Link Guarda: https://www.boraguarda.com/baixar?de=meta-checkin&utm_source=meta&utm_campaign=checkin-diario
Link IPG: https://www.boraguarda.com/baixar?de=meta-checkin-ipg&utm_source=meta&utm_campaign=checkin-ipg
Valores confirmados na base a 30/10 21:50: checkin_rewards [5,5,10,10,15,15,40]; checkin_marco_salgados dia 10, checkin_marco_acai dia 15, checkin_marco_mes dia 30 (limpeza 2 h ou lavagem exterior); exige telemóvel e pedido pago nos últimos 30 dias; escada ativa (um prémio por sequência). Goola e Sabores do Brasil coming_soon=false.

Medição: a contagem é pelo de= (link_clicks / site_visits). O apex boraguarda.com/baixar sem www NÃO conta (regra da Cloudflare), por isso os links levam www.

ATUALIZAÇÃO 31/10 00:00 (publicado): a Meta recusa a /baixar como destino de Tráfego ("URL da app", #1487810, por causa da meta apple-itunes-app da página). Destinos finais: Anúncio 1 → https://www.boraguarda.com/entregas ; carrossel → https://www.boraguarda.com/ ; utm_source=meta&utm_medium=pago&utm_campaign=instala-e-pede / checkin-diario / checkin-ipg nos Parâmetros de URL. Descrição do anúncio 1: "Entrega desde 2,50 € na Guarda"; botão "Descarregar". IDs: campanha 52680337414474 (conjunto 52680337414874, anúncio 52680337414674, 2,50 €/dia); campanha 52680349790474 (conjunto Guarda 52680349790874 1,00 €/dia + anúncio 52680349790674; conjunto IPG 52680351300874 1,50 €/dia, 18-26, interesses Na faculdade/Higher education/Estudante/Universidade + anúncio 52680351301074 com o texto para estudantes). Todos de 31/10 08:00 a 04/11 23:59, Praça Velha +8 km, anúncios DESLIGADOS até os fundos chegarem a 25 €.

=== VERSÃO G (31/10 ~07:00, criativos refeitos depois da reprovação do Danilo às 05:50/05:59) ===
Correções confirmadas na base antes de escrever: Lidl está DESLIGADO na app (is_active_admin=false) → fica fora. Lojas abertas: McDonald's, Burger King, Continente, Pingo Doce, Wells (farmácia). BEMVINDO = 1000 tokens = 5 €, mas em cada pedido só se usa até metade dos tokens (create_order: token_balance_max_use_pct=50) → o 1.º pedido desconta no máximo 2,50 €; por isso NUNCA "5 € no 1.º pedido", sempre "começas com 5 € em tokens". Dia 1 a 7 = 5+5+10+10+15+15+40 = 100 tokens = 0,50 €.

ANÚNCIO 1 "Instala e pede" (marcas grandes)
Texto principal:
McDonald's, Burger King, Continente e Pingo Doce, entregues em casa na Guarda.
Escolhes na app do Bora e um estafeta da Guarda leva-te tudo a casa. Entrega desde 2,50 €.
Instala hoje com o código BEMVINDO e começas com 5 € em tokens.
Título: McDonald's, Burger King e Continente em casa
Descrição: Bora: a app de entregas da Guarda
Botão: Descarregar · UTM utm_campaign=instala-e-pede · 2,00 €/dia

CARROSSEL DIDÁTICO "O que é o Bora?" (Guarda)
O Bora é a app de entregas da Guarda: McDonald's, Burger King, Continente, Pingo Doce, farmácia e favores, tudo entregue em casa.
Tokens são dinheiro para gastar na app (1000 tokens = 5 €) e ganhas só por fazeres o check-in todos os dias; aos 10, 15 e 30 dias seguidos há prémios: 2 salgados da Keli, um açaí do Goola, 2 h de limpeza ou lavagem do carro.
Instala com o código BEMVINDO e começas já com 5 € em tokens.
(versão IPG, 1.ª linha) Estudas no Politécnico da Guarda? O Bora é a app de entregas da cidade: McDonald's, Burger King, Continente e farmácia, entregues onde estiveres.
Cartões: 1 O que é o Bora? · 2 O que são tokens? · 3 O teu mês no Bora · 4 O que ganhas · 5 Começa hoje. Rodapé dos prémios: 1 prémio por sequência · pedido pago nos últimos 30 dias · pagas só a entrega e as taxas · telemóvel confirmado. 1,00 €/dia Guarda + 1,00 €/dia IPG.

ANÚNCIO 3 "Favores - vídeo (31/10)"
Precisas de algo da farmácia e não podes sair? Pede um Favor no Bora.
Um estafeta da Guarda vai buscar e leva-te a casa; ele adianta o valor e tu pagas-lhe na entrega.
Instala com o código BEMVINDO e começas com 5 € em tokens.
Cenas e personagens criadas com IA. Os ecrãs são da app verdadeira.
Título: Favores na Guarda, entregues em casa · Botão: Descarregar · UTM utm_campaign=favores-video · 1,00 €/dia · vídeo reel-favores-30s.mp4 (9:16, legendas já gravadas, aprovado a 17/10).
Nota: o prompt da Claude.ai dizia "pagas em dinheiro ou MB Way" e "tens 5 € no 1.º pedido"; nenhum dos dois ficou porque não se confirmou o MB Way nos Favores e o 1.º pedido só usa até metade dos tokens.
