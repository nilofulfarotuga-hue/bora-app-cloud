---
id: memoria-claude-ai-digest-2026-10-11-cartao-corrida-motorista
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-11
zona: verde
confianca: alta
estado: atual
---

# PC do Danilo 11/10 — cartão da corrida do motorista por fases

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-11-cartao-corrida-motorista`, origem `claude-code`, atualizada em 2026-10-11T21:51:30.53841+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 11 cartao corrida motorista · memoria claude.ai · claude_ai_memoria

Missão cartao-corrida-motorista (Claude Code, PC do Danilo, 11/10). O ecrã da corrida do motorista TVDE (lib/screens/driver/tvde/tvde_ride_active_screen.dart) passou a ter o padrão Uber/Bolt Driver. O botão da fase (Cheguei ao passageiro / Iniciar viagem / Finalizar viagem / Vou a caminho) está FIXO no fundo, sempre visível, no BoraBottomActionBar; a gaveta assenta por cima. O cabeçalho diz a fase do lado do motorista (novo TvdeRide.driverPhaseTitle; o statusLabel do cliente não mudou): a caminho "A caminho da recolha · nome" e só a recolha em grande; chegou "À espera de nome" + cronómetro; em viagem "A levar nome ao destino" e só o destino (ou a próxima paragem). ETA uma vez só (Chegas em / Chegada em / Chegada ao destino em, com paragem). Navegar é um botão pequeno ao lado da morada. A gaveta recolhida mostra o cabeçalho inteiro (altura medida), abre até 88% ou ao fim do conteúdo, toque ou arrasto, e volta a recolher ao mudar de fase. O detalhe (passageiro, cobrar em dinheiro, balcão, pacote, mudança de destino, paragens, próxima corrida, devolver reserva, Viagem: recolha → destino) vive na gaveta aberta. Nada de valores, despacho ou RPC mudou. Lição: snapSizes do DraggableScrollableSheet tem de ser guardado no State (lista nova a cada build cancela o arrasto do dedo). Publicado: Play versionCode 664, web bundle e2f6e754ae8e, Apple build 183 e versão 1.0.17 em revisão. Commits a1e7eddf e 864b835e. Falta: teste numa corrida real em dinheiro; decidir o título da reserva por confirmar; restaurar 6 ficheiros do Cérebro e orquestracao/vigia-vps.sh estragados por escritas do Córtex com caminho undefined a 07–08/10 (precisa da palavra do Danilo); a causa no Córtex continua por corrigir.
