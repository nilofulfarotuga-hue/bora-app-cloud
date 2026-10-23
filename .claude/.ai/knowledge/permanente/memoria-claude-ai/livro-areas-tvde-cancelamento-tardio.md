---
id: memoria-claude-ai-livro-areas-tvde-cancelamento-tardio
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo (17/10/2026) para o cliente que cancela uma corrida TVDE depois dos 3 minutos — cobra a corrida inteira e o motorista recebe 3,75 €; caso Ney e o prompt da missão (app, painel, publicar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-cancelamento-tardio`, origem `claude-ai`, atualizada em 2026-10-23T05:42:41.697519+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde cancelamento tardio · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-cancelamento-tardio.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-cancelamento-tardio
description: Regra do Danilo (17/10/2026) para o cliente que cancela uma corrida TVDE depois dos 3 minutos — cobra a corrida inteira e o motorista recebe 3,75 €; caso Ney e o prompt da missão (app, painel, publicar)
sources: [cowork]
aliases: [cancelamento tardio, cancelar depois dos 3 minutos, taxa de cancelamento TVDE, compensação ao motorista, 3,75 ao motorista]
---

- [stated] 17/10/2026 13:36 perguntou de uma corrida TVDE cancelada com o motorista (Ney) já no local: o cliente perdeu 2,50 € e esses 2,50 € foram para o motorista
- [stated] REGRA (17/10 13:45): se o cliente cancelar depois dos 3 minutos, deve cobrar-se a corrida completa dele e dar ao motorista uma taxa de cancelamento de 3,75 €
- [stated] Caso Ney (17/10 13:45): como essa corrida não cobrou isso ao cliente, "só manda os 2,50 pro Ney, pra carteira dele" — mandado uma vez; essa corrida não se compensa de novo
- [stated] 17/10 13:50 respondeu "Autorizo" ao pedido para pôr a regra no sistema (servidor, painel admin, aviso ao motorista e valor real na app do cliente); cobre só esta regra — outra mudança de preços, comissões, ganhos ou Stripe pede "autorizo" novo
- [stated] Pediu que cada prompt fique registado na memória (data, sessão, scope, estado) — este: colado por mim a 17/10 16:05 (Lisboa) numa sessão NOVA do Claude Code no PC (Controlo Remoto), session_01QiZAckTkqHj8jdpNiQpaX1 "Cancelamento tardio: app, painel, publicação", motor Opus 5.5, missão cancelamento-tardio-app-painel-2026-10-17, run_id e2e cancelamento-tardio-20261017. Scope: app do cliente (diálogo com o valor real), app do motorista (aviso e ícones), painel admin (definições, cancelamentos, compensar à mão, alertas), cópia da migração no repo, testes, publicar e provar nas 3 plataformas; sem mexer em SQL nem Edge. Servidor já feito por MCP (migração tvde_cancelamento_tardio_corrida_inteira, versão 20261017143124). Estado final (17/10 ~19:55 Lisboa): missão fechada — app do cliente, app do motorista e painel publicados nas 3 plataformas (web 222, Android 676, iPhone build 194 / 1.0.21 à espera da revisão da Apple, sai sozinho); relatório no repo (commit 2050df59); em aberto: prova visual do painel, achados do servidor (dinheiro, pedem "autorizo" novo) e a proposta do Córtex prop-d2fcdfed
- [stated] REGRA NO-SHOW (22/10/2026, caso Martim, reserva em que o passageiro não apareceu): o motorista recebe a taxa de cancelamento de 3,75 € e tem de lhe aparecer na app; o restante fica 100% para a Bora porque o cliente não compareceu

