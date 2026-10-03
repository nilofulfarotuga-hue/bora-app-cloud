---
id: memoria-claude-ai-digest-2026-10-03-caca-clientes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-03
zona: verde
confianca: alta
estado: atual
---

# Claude Code FABLE 03/10 — caça-clientes: máquina montada, ainda sem enviar

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-03-caca-clientes`, origem `claude-code`, atualizada em 2026-10-03T09:21:54.957194+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 03 caca clientes · memoria claude.ai · claude_ai_memoria

A missão caca-clientes-2026-10-03 montou o circuito mas nenhum email saiu ainda. O que funciona agora: a tabela prospects_presenca tem as colunas de contacto (email_verificado, email_fonte, canal_preferido, livro_reclamacoes_ok, gancho, ultimo_contacto_em, proximo_seguimento_em, resposta, cliente_tipo); o caçador de contactos (bora_app/.claude/.ai/provas/caca-clientes-2026-10-03/pc/cacar_contactos.py) correu sobre 74 alvos e deixou 12 com email verificado (16 por cento, a meta era 60) e 9 só com rede social; o carteiro está em /opt/data/rotinas/carteiro_caca.py na VPS com os modos redigir, enviar, ler, resumo, teste; a fila, os dois seguimentos (3 e 7 dias), respostas, recusas e devoluções são decididos na base de dados por RPC (carteiro_fila, carteiro_marcar, carteiro_threads, carteiro_resumo_dia, redator_fila), com tecto de 5 novos por dia útil e janela 09h30-11h30; o interruptor é platform_settings.caca_clientes_enabled e está desligado; o painel admin tem o ecrã Caça-clientes (enviar agora, pausar, recusou, cliente, editar, apagar, CSV), publicado no push 36e87f39. O que falta: copiar PROSPECTS_KEY para /opt/data/.env da VPS (a cópia foi recusada pela trava de segurança, espera o vai do Danilo); criar o cliente OAuth no Google Cloud e autorizar o Gmail boraappbora (variáveis GMAIL_BORA_CLIENT_ID, GMAIL_BORA_CLIENT_SECRET, GMAIL_BORA_REFRESH_TOKEN); instalar o cron (enviar 09h40 dias úteis, ler de hora a hora, resumo 09h50); ligar vendedor e vendedor-servicos em agentes_estado; email de teste e primeira onda; peças novas (só há 10 amostras de 24/09 e 2 maquetes premium com email: Herdade do Mondego e Quinta do Rio Noémi); alargar a varredura a outros concelhos e nichos. Regras do carteiro: assina Bora App — Guarda, nunca sou o Danilo, sem preço, link único, opt-out no rodapé. Os textos antigos de 30/08 ainda dizem sou o Danilo. Relatório em bora_app/.claude/.ai/reports/FABLE-2026-10-03-caca-clientes.md.
