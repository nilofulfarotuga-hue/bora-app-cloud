---
id: memoria-claude-ai-digest-2026-09-30-videos-ipg
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-30
zona: verde
confianca: alta
estado: atual
---

# Claude Code 30/09 — 5 vídeos IPG (7 ficheiros) à espera de aprovação

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-30-videos-ipg`, origem `claude-code`, atualizada em 2026-09-30T14:44:15.08585+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 30 videos ipg · memoria claude.ai · claude_ai_memoria

Feitos 7 vídeos 9:16 para o público do IPG, em Desktop\Bora\videos-ipg\: 1 fast food (PAGO e ORGÂNICO), 2 supermercado (PAGO e ORGÂNICO), 3 Goola Açaí, 4 Sabores de Casa, 5 Lavagem Auto (Exterior €12 · Completa €20, confirmados em platform_settings). Todos com fiscal ≥80 (máquina 45/45 na VPS + olho pelo Codex gpt-5.5, porque a API grátis do fiscal deu 429). Enviados ao Danilo no Telegram (msg 8811–8817) às 15:4x; NADA publicado nem pago: Blocos 3 (orgânico às 18:00, um por dia) e 4 (campanha raio IPG, Meta €5/dia + Google €3/dia) só depois do "aprovado" dele, vídeo a vídeo.
Como se faz: montar_ipg.py (docs/marketing/videos-ipg no repo) monta clip/foto/telemóvel/cartão final; o telemóvel mostra ECRÃS REAIS da app (Playwright no app.boraguarda.com, lojas públicas sem login); marca Bora nos sacos/caixas colada por colar_logo_embalagem.py; nas versões orgânicas o saco leva o nome da loja em letra simples com o Bora por baixo (pedido do Danilo por voz; risco assinalado). QR ?de=ipg-<video> ou pago-ipg, código BEMVINDO (283 usos livres de 300).
Erros reportados, não corrigidos: (1) boraguarda.com/baixar é 302 no Cloudflare e não grava visitas desde 23/09, por isso as origens de campanha não são medidas; (2) app: preço não sobe com a quantidade na ficha da maçã; (3) reel de 08/09 tem caixa "Guardapio" (IA); (4) ~/.codex/config.toml com gpt-6-sol parte a via codex (usar -m gpt-5.5); (5) Veo do Gemini Plus: limite de 2–3 vídeos/dia; Chrome congela com a aba em segundo plano (Ctrl+9 com a janela à frente). Relatório: Desktop\Bora\videos-ipg\RELATORIO-videos-ipg-2026-09-30.md.
