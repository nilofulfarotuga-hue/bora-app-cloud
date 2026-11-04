---
id: memoria-claude-ai-digest-2026-11-04-checkin-escada-premios
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Digest 04/11 — escada de prémios do check-in

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-04-checkin-escada-premios`, origem `claude-code`, atualizada em 2026-11-04T12:29:26.64715+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 04 checkin escada premios · memoria claude.ai · claude_ai_memoria

Missão checkin-escada-premios-2026-11-04 (PC, worktree C:/BoraLocal/wt-checkin-04-11). C no ar: checkin_premio_intervalo_dias=30, _checkin_premio_proximo_em/_checkin_premio_bloqueado; dentro do prazo o Levantar devolve reason=intervalo e o guardado NÃO se perde; no último degrau só levanta sozinho se puder (migração 20261104111431). D: _checkin_estado_marcos traz foto_url/loja_nome por marco e tokens_por_dia (20261104111807); app com CalendarioPremios (grelha de 30 dias) e "Próximo prémio disponível a DD/MM"; checkin_marco_texto atualizado. E: os degraus criados por MCP tinham category=null e não apareciam no painel (corrigido); admin_checkin_degrau_criar e admin_checkin_premios_custos (20261104112622); painel lista degraus dinamicamente (antes 4 chaves fixas). A: tipo desconto + minimo_cents + 6 degraus DESLIGADOS (20261104114014); o desconto no pagamento fica por fazer (quote_order_pricing/create_order, zona protegida). B: não provado, 5 degraus não-parceiros desligados — não há reembolso ao estafeta da compra ao balcão de um prémio a 0 € e o fecho por talão pode cobrar o prémio ao cliente. Proposta em docs/propostas/PROPOSTA_20261104_checkin_desconto_e_premio_nao_parceiro.md. Publicado: web 711, Android 712; iOS a compilar. Patches de função por âncora (pg_get_functiondef + replace + EXECUTE dentro de DO) evitam reescrever funções grandes e falham com RAISE se a âncora não existir. O Danilo (c9fccf85) está bloqueado até 28/11 por ter levantado o açaí a 29/10.
