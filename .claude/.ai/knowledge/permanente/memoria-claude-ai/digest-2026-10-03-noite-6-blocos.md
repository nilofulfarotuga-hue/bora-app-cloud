---
id: memoria-claude-ai-digest-2026-10-03-noite-6-blocos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-03
zona: verde
confianca: alta
estado: atual
---

# Claude Code 03/10 noite — Navalha, TVDE recusar, Favor, limpeza, mapas, Gmail

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-03-noite-6-blocos`, origem `claude-code`, atualizada em 2026-10-03T18:47:52.395122+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 03 noite 6 blocos · memoria claude.ai · claude_ai_memoria

Mister Navalha: o site no ar é só "brevemente"; as 11 fotos dão 404 no domínio e no pages.dev; há 1 publicação só; a galeria da app está vazia. O admin passa a ter "Esconder" e "Apagar de vez" nas fotos da galeria de qualquer prestador.
TVDE: quem recusa uma corrida não a volta a receber durante tvde_reject_cooldown_seconds (600, categoria dispatch, editável no painel). tvde_offer_to_next lê as recusas em tvde_ride_events; o backup da função está em bkp_fn_tvde_despacho_20261003. Na app, Recusar fecha logo. Uma reserva terminada já não mostra "a caminho" e os avisos de corridas terminadas saem ao abrir a app.
Favores: a foto fica gravada como caminho order-photos/... (gatilho trg_orders_errand_photo_caminho). O bucket continua privado. A política order_photos_select_errand_driver deixa ler o estafeta atribuído ou com a oferta. O servidor recusa um Favor igual (mesmo cliente, morada e price) em errand_duplicate_window_seconds=60 (gatilho trg_orders_errand_duplicado; erro duplicate_errand). O formulário tem trava própria.
Limpeza: botão "Mudar de modo" no ecrã da limpeza e no Perfil, com todos os papéis da pessoa.
Mapas: no motorista, a seta e a câmara deslizam a 16 ms e o toque no mapa pausa o seguimento. map_route_line_width=12 nos dois mapas.
Código em b2521671 (ramo autonomous-night-2026-04-29).
Falta: Gmail do caça-clientes (publicar a app OAuth "Bora Carteiro" + Permitir antes de 10/10, precisa da extensão do Chrome); prova no emulador da troca de modo; medição de frames dos mapas; o mesmo defeito do botão em send_package e carry_groceries. Detalhe em .claude/.ai/inbox/CONTINUAR-missao-noite-2026-10-03.md.
Atenção: as políticas do bucket restaurant-assets deixam qualquer utilizador com sessão apagar ficheiros de qualquer loja.
