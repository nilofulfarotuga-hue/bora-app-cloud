---
id: memoria-claude-ai-livro-areas-tvde-sobreposicao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo para sobreposição de corridas TVDE (back-to-back estilo Uber) — ler antes de mexer em despacho, oferta ou fila de corridas

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-sobreposicao`, origem `claude-ai`, atualizada em 2026-10-23T05:34:57.805479+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde sobreposicao · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-sobreposicao.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-sobreposicao
description: Regra do Danilo para sobreposição de corridas TVDE (back-to-back estilo Uber) — ler antes de mexer em despacho, oferta ou fila de corridas
sources: [chat]
aliases: [sobreposição, back-to-back, corrida em fila, empilhar corrida, próxima corrida]
---

- [stated] REGRA (14/09): quando uma corrida do [[tvde-vertical]] é largada e o outro motorista está OCUPADO, o sistema tem de lhe tocar na mesma, com uma SOBREPOSIÇÃO — ele aceita, volta ao ecrã do passageiro que já leva, finaliza essa, e entra sozinho no ecrã do próximo cliente. "Tem que ser exatamente assim"
- [stated] Voltar a oferecer a corrida ao motorista que a largou, quando não há mais ninguém online, está CERTO — é rotação normal e não é bug. O erro é o motorista ocupado nunca entrar na roda
- [stated] Mandou copiar o comportamento da Uber "bem a fundo, igualzinho", e disse que a ENTREGA do Bora já tem algo parecido — é para aproveitar esse princípio
- [stated] PROMPT ENTREGUE 14/09 (histórico de prompts): `PROMPT_tvde_sobreposicao_back_to_back_2026-09-14.md` — motor FABLE, sessão NOVA no Claude Code, repo bora-app-cloud; scope: despacho chamar motorista ocupado, fila na aceitação, ecrãs do motorista e do cliente, painel admin com reatribuição. Estado: ficheiro colado por ele + adenda de correção enviada na mesma janela

FALHA REAL VIVIDA POR ELE 20/09 — a sobreposição NÃO funcionou
- [stated] Estava no ecrã da corrida activa (cliente Tatiana, ride b7312342) quando lhe entrou a oferta da reserva da meia-noite (ride d26e76f1, push reservation_offer 20:22:48 UTC, aceite pelo FCM). O toque chegou, NENHUM cartão apareceu, não houve forma de aceitar. "Tinha que sobrepor um cartão, aceitar ou recusar. E não funcionou, tem que funcionar isso daí"
- [stated] Pediu também que o CLIENTE veja "o motorista aceitou o seu pedido, ele está a terminar uma viagem e já vai" + o tempo até chegar
- SERVIDOR ESTÁ CERTO, provado por eventos: tvde_offer_to_next já oferece a ocupados (pool único, migration 20260914150204), RLS deixa ler, rotação de reservas roda. É 100% Flutter + 1 Edge
- CAUSA DO CASO DE HOJE (C1): a oferta de RESERVA não tem sobreposição nenhuma — `TvdeReservationOfferCard` está montado SÓ na home (tvde_driver_home_screen.dart:819) e fica tapado pelo ecrã da corrida. O banner de 14/09 (`_QueuedOfferBanner`) só trata da oferta IMEDIATA (current_offer_driver_id), nunca da reserva
- Outras 5 causas confirmadas ficheiro a ficheiro: (C2) oferta expirada renderiza vazio — tvde_ride_active_screen.dart:2513 `if (_secondsLeft <= 0) return SizedBox.shrink()` + tvde_driver_store.dart:254-261 carrega sem filtrar offer_expires_at > now(); (C3) tvde_driver_store.dart:337 corre `_limparOferta()` em QUALQUER update realtime da corrida activa (cheguei/iniciar/parada) e mata a oferta a contar; (C4) tvde_driver_home_screen.dart:315 `!_activeOpen` bloqueia o ecrã cheio, logo o banner é ponto único de falha; (C5) não há overlay global TVDE — o offer_presentation_gate.dart é exclusivo de ENTREGAS, e a notificação de oferta TVDE não tem botões (notification_service.dart:2593-2652); (C6) gancho `tvdeOfferReload` preso ao initState/dispose da home (:93, :150-152) — a MESMA cicatriz de 20/08 que obrigou a mover o tvdeReservationReadyTap para main.dart:401
- LADO DO CLIENTE JÁ EXISTE e não é preciso reconstruir: tvde_ride_tracking_screen.dart com `_queueEtaMinutes` (:130), `_pollQueueEta` pela RPC tvde_ride_queue_info (:977-993) e os textos "está a terminar uma corrida ... chega em ~X min" (:1904-1922, :2273-2281). Falta só provar que aparece e afinar o texto/ETA vivo
- PROMPT ENTREGUE 20/09 (histórico de prompts): `PROMPT_tvde_sobreposicao_cartao_2026-09-20.md` — motor OPUS, porta Claude Code, sessão NOVA na pasta bora-app-cloud; 6 blocos (apresentação global por navigatorKey/Overlay servindo oferta imediata E reserva; fechar as 3 fugas silenciosas; botões Aceitar/Recusar na notificação + Edge notify-tvde-driver pela CLI; confirmar o lado do cliente; painel admin com ofertas em voo, reatribuir e as 4 settings backtoback editáveis; provas em emulador). Estado: entregue, por rodar

OFERTA FANTASMA (01/10)
- [stated] Queixa: depois de aceitar, fazer e finalizar uma corrida, volta a aparecer o ecrã "Nova corrida" da MESMA corrida, sem som e travado; outras vezes só um aviso em cima como se houvesse outro pedido. Quer isto limpo
- PROMPT ENTREGUE 01/10 (histórico de prompts): `PROMPT_tvde_oferta_fantasma_2026-10-01.md` — motor OPUS, colado por mim na sessão "PC do Danilo"; scope: ecrã de oferta fecha a própria rota, home não empilha corrida sobre oferta, cancelar aviso pelo id, leituras antigas ignoradas. Estado: na fila, PC estava offline

CARTÃO PRESO DEPOIS DE ACEITAR (06/10, corrida real 3835a143, volta do pacote, cliente Martim Cruz, versão 1.0.4+651)
- [stated] Queixa: aceitou a corrida, o ecrã da corrida abriu por baixo, mas o cartão "Nova corrida — agora" ficou em cima, parado em 0s, com Recusar/Aceitar. "Já tinha mandado consertar isso"
- PROMPT ENTREGUE 06/10 (histórico de prompts): `PROMPT_tvde_cartao_preso_apos_aceitar_2026-10-06.md` — motor OPUS, colado por mim numa sessão NOVA de Controlo Remoto no PC (session_01N6YCAfxPPofroZk5Xtibi4; a antiga "PC do Danilo" session_01L5D1vJBvUdq63dn5EJETd3 morreu — "ambiente excluído"). Scope: só Flutter, achar qual caminho de aceite não actualiza o store da raiz + rede de segurança no cartão. Estado: a correr

