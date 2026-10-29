---
id: memoria-claude-ai-adendo-7-retomar-missao-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# ADENDO 7 (Claude.ai, 21:30) - RETOMAR a missao publica-2026-10-29 depois de a sessao ter perdido a ligacao ao PC

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `adendo-7-retomar-missao-2026-10-29`, origem `claude.ai`, atualizada em 2026-10-29T21:26:40.761725+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: adendo 7 retomar missao 2026 10 29 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️ - Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/. MOTOR: o desta sessao. PORTA: a sessao "Missao geral Bora 2026-10-28" (session_01HPEpVCfPzS9j8Nzb5E1fRc) no PC do Danilo, pasta bora-app-cloud.

CONTEXTO: a sessao "Missao geral Bora 2026-10-28" (session_01HPEpVCfPzS9j8Nzb5E1fRc) perdeu a ligacao ao PC as ~20:50 e nao volta. O trabalho dela esta na worktree C:\BoraLocal\wt-missao-geral-28-10 (ramo missao-geral-2026-10-28, ultimo ba11c59e; ja junto em autonomous-night-2026-04-29 = 26ab6a7b) e no ficheiro CONTINUAR-final-app-2026-10-29.md dessa worktree. Le primeiro: esse CONTINUAR, as paginas claude_ai_memoria prompt-publica-e-fecha-2026-10-29 (+ adendos 1 a 6) e o e2e_log fluxo publica-2026-10-29. Prioridade: fechar a missao da Bora HOJE. Danilo as 21:16: "quero tudo terminado hoje, tudo publicado hoje".

O QUE FALTA (por ordem; reporta outros erros em vez de os corrigir calado):
1) Publicacao nas 3 lojas: CI das publicacoes 2 (ce2af44c) e 3 (26ab6a7b): web OK (20:34 e 20:44), Android da 2 OK (Play), iOS da 2 e Android+iOS da 3 a correr. Vigiar ate acabarem; se falhar, causa raiz + relancar. Prova final: version.json, Play Console (versao em teste interno/producao), App Store Connect/TestFlight. Registar A.4/E.1 no e2e_log.
2) REEMBOLSOS (Bloco D) - AUTORIZADO pelo Danilo as 21:16: "A partir de hoje, o que for para reembolsar, nos vamos reembolsar. So nao vai reembolsar nada de ontem para tras." REGRA: nenhum reembolso retroativo; reprocess-refund NAO corre sobre refund_status=failed antigos (so pedidos cancelados a partir de 29/10 21:16 Lisboa); nenhum teste com dinheiro real. Publicar as 6 Edge Functions + _shared/cobranca_stripe.ts v2 + SQL dos tokens (paginas reembolsos-b2-* e reembolsos-dashboard-passos). CLI sem token: correr `npx supabase login` nesta sessao - abre o browser do PC; o Danilo faz o login no Supabase e carrega em autorizar (dizer-lhe em UMA linha quando a pagina abrir, pelo Telegram e pelo chat). Depois `supabase functions deploy` uma a uma, na ordem da pagina reembolsos-b2-ordem, com prova (200 em teste a dinheiro/MB Way de teste, logs sem erro). Se o login nao der em 10 min, fica registado como bloqueado com o passo exato que falta.
3) Adendo 6 (pagina adendo-6-publica-2026-10-29): robo Boom nao recebeu a mensagem das 19:41 (VPS, ponte whatsapp-bora/assistente-negocio); subir 17 fotos (6 Letra + 11 vinhos) ao Storage e trocar products.photo_url; completar C4 partes 2 e 3 (ficheiro 20261029200800_c4_promocoes.sql da seccao 4 em diante) com supabase db push/psql; corrigir a pagina boom-robo-conhecimento (2 frases).
4) NIF OPCIONAL na fatura do cliente (adendo 4 de 28/10): confirmar por leitura + captura no emulador que o checkout tem o campo NIF opcional (order_invoice_requests/client_billing_profile) e que esta nas 3 plataformas publicadas hoje; se faltar algo, corrigir e publicar.
5) Bloco E: relatorio final, fecho, aviso ao Danilo por Telegram e pelo WhatsApp da Bora (937501673 -> 351931992662), S1 migration no repo (A.5), policy tmp_cartazes_anon_insert_20261029 em storage.objects a apagar.
Termina com /ctx doctor e /ctx stats.
