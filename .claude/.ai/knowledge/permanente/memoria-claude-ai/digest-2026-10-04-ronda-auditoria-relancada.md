---
id: memoria-claude-ai-digest-2026-10-04-ronda-auditoria-relancada
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-04
zona: verde
confianca: alta
estado: atual
---

# Claude.ai 04/10 noite — ronda de correções da auditoria (relançada)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-04-ronda-auditoria-relancada`, origem `claude-ai`, atualizada em 2026-10-04T20:25:34.093374+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 04 ronda auditoria relancada · memoria claude.ai · claude_ai_memoria

A 1.ª ronda (sessão 016XYhZ) morreu ao arrancar; achados/*.md perderam-se. Relançada 21:00 a partir das missões guardadas na conversa.
FEITO e aplicado em produção (migrations 20261004192557..194849, notify-driver v42, tvde-payment v18, notify-tvde-client v6, notify-tvde-driver v21):
- despacho: dispatch_candidatos_entrega (fantasmas >900s fora, 1 oferta de cada vez, favor sozinho, raio 20 km), driver_cancel_order identidade certa, heartbeat já não põe online, chamada do estafeta no tempo de preparação. FALTA: ligar o dispatch-engine (zona protegida, edição recusada) — SQL/diff em feito/despacho.md.
- app-estafeta: sair da conta desliga tudo (caso Ney), 1 só heartbeat, posição 60s, ganhos, oferta 60s, talão, reportar problema, foto de entrega.
- tvde: km do servidor (linha reta×1,25), preço fixo no fim, procura máx 6 min com reembolso, graça desde aceitação, refund só de canceladas, plano de outro cliente fechado, PT-PT, partilhar viagem (tvde_partilhas + web/viagem.html).
- cliente-app: suporte, favoritos por id, estados carregar/erro/vazio, pedir de novo, reportar problema (file_complaint corrigido), RGPD, loja em pausa.
- checkout: takeaway com cartão funciona, markup e limite de dinheiro lidos de settings, deixar à porta, loja em pausa, MB Way com sessão, carrinho abandonado (cron desligado). FALTA na app: pricing_service (0,99 €/takeaway), cart_store, gorjeta no total — edições recusadas.
- triagem: robot_suggestions 0 abertas; 9 skill_suggestions fechadas; Córtex sem pendentes.
NÃO ARRANCARAM (recusados pela proteção automática): dinheiro-entregas, parceiro, admin-dinheiro, admin-geral, seguranca-bd.
Código junto: ramo analise-integra-ronda-04-10 (CI verde, 949 testes, run 37231464618). Ainda NÃO está no ramo de produção — app/web publicados continuam com o código antigo.
