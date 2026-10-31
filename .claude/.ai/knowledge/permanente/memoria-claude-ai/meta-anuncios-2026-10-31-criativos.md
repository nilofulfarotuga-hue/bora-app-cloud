---
id: memoria-claude-ai-meta-anuncios-2026-10-31-criativos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Anúncios Meta 31/10 — criativos finais (juiz ≥ 9) e porque o anúncio antigo não deu pedidos

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `meta-anuncios-2026-10-31-criativos`, origem `claude-code`, atualizada em 2026-10-31T09:40:54.201943+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: meta anuncios 2026 10 31 criativos · memoria claude.ai · claude_ai_memoria

CRIATIVOS FINAIS (31/10, depois do juiz visual: as 6 peças refeitas têm nota 9; os cartões 2, 4 e 5 são os aprovados pelo Danilo às 06:47, sem mudanças). NADA ESTÁ LIGADO NA META: só liga com o "aprovo" do Danilo.
Endereços públicos (product-images/meta-2026-10-31/, todos lidos de volta com 200):
Folha 1x1: https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/meta-2026-10-31/folha-1x1-final.jpg
Folha 9x16: https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/meta-2026-10-31/folha-9x16-final.jpg
Anúncio 1 (McDonald's, Burger King e Continente): .../a1-marcas-1x1-final.jpg e .../a1-marcas-9x16-final.jpg
Carrossel: .../c1-o-que-e-, c2-tokens-, c3-mes-, c4-premios-, c5-comeca- + 1x1-final.jpg / 9x16-final.jpg (prefixo https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/meta-2026-10-31/).

O QUE MUDOU NAS 3 PEÇAS REPROVADAS: anúncio 1 com um Big Mac só (sem a meia-foto por baixo) e o morango trocado por um saco de compras de papel com "Continente" em letra (desenhado por código, não IA) e legumes reais soltos, longe do telemóvel. Cartão 1 com Supermercados = o saco e Restaurantes da Guarda = prato real de kebab do Pôr do Sol. Cartão 3 com tokens em TODOS os 30 dias, confirmado na função public._checkin_estado (depois do Dia 7 volta ao Dia 1; ciclo 5,5,10,10,15,15,40, por isso dia 8 = +5, 14 = +40, 30 = +5) e os dias 10, 15 e 30 marcados como prémio (salgados, açaí, limpeza ou lavagem do carro). O juiz correu 13 rondas no total; cada nota está no e2e_log (passo G2b-juiz, ids 5596-5602).

PORQUE O ANÚNCIO DE 26 A 31/10 TROUXE VISITAS E 0 PEDIDOS (8 linhas):
1. O objetivo era Tráfego, que a Meta otimiza para cliques baratos, não para quem instala e pede.
2. O destino era a página /entregas do site, não a loja: a pessoa ainda tinha de procurar a app, instalar, criar conta e só depois pedir.
3. O criativo não mostrava nenhuma loja que a pessoa conhece (McDonald's, Burger King, Continente), por isso não havia razão imediata para pedir.
4. O público era só a Guarda, sem interesses (comida, entregas, estudantes), e com pouco orçamento a Meta mostrou-o a quem clica mais, não a quem compra.
5. A app não lê a origem da instalação (não há install referrer nem SDK da Meta no código; confirmado no ramo de produção a 31/10), por isso nem um pedido vindo do anúncio seria atribuído.
6. Os 3 anúncios novos corrigem 3 e 4: marcas grandes na peça, oferta clara de 5 € (BEMVINDO) e um carrossel que explica tokens e prémios. O conjunto do IPG junta o público de estudantes.
7. "Instalações da app" (o objetivo que a Glovo usa em todos os anúncios ativos) AINDA NÃO SE PODE USAR: a única app registada na Meta é "Robo Redes Em Dia" (1750149980445990), não a app do Bora.
8. Para o usar falta: criar a app Bora na Meta com as plataformas Android (pt.boraapp.bora) e iOS (6809954739), autorizá-la na conta de anúncios 1105400138585537 e, para medir instalações e pedidos, pôr o SDK/eventos da app (trabalho de código, fica para missão própria).

NOTAS PARA O DANILO (não corrigidas por ordem "não mexer"): nos cartões aprovados 2, 4 e 5 em 9x16 a etiqueta do topo está em y 200 e o logótipo perto do fundo, dentro da zona que a interface dos Stories tapa; e o c2 1x1 tem o logótipo noutra caixa. Se ele quiser, desce-se em 5 minutos.
O www.boraguarda.com/baixar continua recusado pela Meta como destino (a meta apple-itunes-app do bora-site); o envio do site foi travado pelo classificador e espera o "vai" dele (docs/TRANCAS.md).
