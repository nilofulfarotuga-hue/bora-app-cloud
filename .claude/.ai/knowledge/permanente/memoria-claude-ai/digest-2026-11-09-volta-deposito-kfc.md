---
id: memoria-claude-ai-digest-2026-11-09-volta-deposito-kfc
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-09
zona: verde
confianca: alta
estado: atual
---

# Claude Code 09/11 — depósito Volta e robô do talão do KFC

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-09-volta-deposito-kfc`, origem `claude-code`, atualizada em 2026-11-09T21:29:31.412648+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 09 volta deposito kfc · memoria claude.ai · claude_ai_memoria

A missão volta-deposito-kfc (ordem do Danilo 09/11 20:08: cobrar 0,10 € de depósito Volta em todas as latas e garrafas de plástico, Burger King não; 19:36 "Eu autorizo" para o KFC) ficou preparada e provada no ramo ai/2026-11-09-volta-deposito-kfc, pedido de revisão bora-app-cloud#8. NADA está em produção: a bora-tranca do PC recusou gravar a migração de dinheiro e trata SQL, Edge e push de produção como publicar, que é do Claude.ai. Ordem para aplicar: supabase/migrations/20261109220000_volta_catalogo_e_talao.sql (sem dinheiro) → .claude/.ai/missoes/volta-deposito-kfc-2026-11-09/PARTE2-dinheiro-proposta.md (create_order, quote, tokens sem depósito, livro-razão deposit_volta, acerto do parceiro, finalizar_talao, imutabilidade, gatilho do talão) → passo-3-marcar-catalogo.sql → passo-4-kfc-precos-e-opcoes.sql → deploy ocr-receipt v13 → juntar e publicar nas 3. O servidor só cobra o depósito quando os itens trazem a chave deposit_units (só a app nova), por isso a app antiga nunca paga o que não vê. Provas: PGlite com as definições reais 52/52; o talão do KFC 2190210d dá hoje 0,55/6,72/7,38 e com o robô novo 6,20/8,45/9,15 e 20 cênt. de depósito; Deno 10/10; catálogo real classificado (1.392 marcados, 1.289 para rever, Burger King 0) e amostra com fotos 59/59 depois de as regras aprenderem que garrafas pequenas de tónica/água com gás são vidro e que as lojas escrevem (SDR) no nome; bateria Flutter 3221 ok e 6 falhas antigas do ListTile do Flutter 3.47 do PC. KFC: 132 preços sobem pela regra Glovo ÷ 1,24; Tower fica ativo (kfc.pt ainda o mostra). Falta: aplicar e publicar, teste no emulador em dinheiro, foto do Box 6 Hotwings e os 39 produtos do Glovo que faltam.
