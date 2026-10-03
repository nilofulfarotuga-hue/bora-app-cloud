---
id: memoria-claude-ai-digest-2026-10-02-assistente-negocio
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-02
zona: verde
confianca: alta
estado: atual
---

# Claude Code 01-02/10 — Assistente de Negócio no WhatsApp (Mister Navalha, teste)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-02-assistente-negocio`, origem `claude-code`, atualizada em 2026-10-02T11:03:22.978926+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 02 assistente negocio · memoria claude.ai · claude_ai_memoria

O QUE FUNCIONA: "funcionário digital" multi-cliente no WhatsApp. Tabelas assistant_tenants/contacts/messages/tasks; 1.º cliente Barbearia Mister Navalha em modo TESTE (só atende 931 992 662 e 937 472 634; perguntas ao dono vão para o 931). Cérebro na VPS: /opt/assistente-negocio (serviço assistente-negocio, 127.0.0.1:8795), código em ferramentas/assistente-negocio do repo. A porta vps-baileys (ligar.js) pergunta primeiro /quem; se o número não for de um assistente segue o cérebro antigo da Bora, que continua PAUSADO (envio_ligado=false + ficheiro ENVIO_DESLIGADO reposto). Agenda pelas funções assistente_*_v2 (mesma lógica de vagas da app, get_available_slots); marcações pagas no local (waived), aparecem na app de parceiro como "Paga no local · marcado pelo WhatsApp". Áudios: transcreve (Groq whisper, reserva faster-whisper local) e responde com texto + nota de voz pt-PT (edge-tts Raquel). Pessoal/grupos/blocklist = silêncio; dono escreve na conversa = 12 h calado; pergunta ao dono com código P123, prazo e vigia, resposta aprendida. Rotinas: lembrete véspera 18h, avaliação 1h depois, reativação 35 dias, lista de espera, resumo domingo 20h. Painel admin: Robôs e Autonomia > Assistentes (funcionário digital).
PROVAS: 18 conversas + 3 áudios simulados; troca real do 931 (11 mensagens + 1 marcação, tudo entregue) e áudio real do 931 respondido com texto + voz (entregues, status 3). Número fora da allowlist: bloqueado.
MOTOR: principal OpenCode Go (decisão do Danilo; não subir o tecto da chave Google com faturação). Go esgotado no limite MENSAL (429) a 01-02/10 -> respondem Gemini 3 Flash grátis (2 projetos), Flash-Lite, Groq.
FALTA/RISCOS: repasse semanal conta marcações do WhatsApp como "ao balcão" (taxa hoje 0 € — decisão de dinheiro do Danilo); corrida app×WhatsApp sem tranca na app; cérebro da Bora falha aberto se o Supabase cair (mitigado pelo ficheiro). Chamadas de voz: só com a API oficial do WhatsApp. Relatório: .claude/.ai/reports/assistente-negocio-mister-navalha-2026-10-02.md
