---
id: memoria-claude-ai-digest-2026-10-06-auditoria-3-plataformas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-07
zona: verde
confianca: alta
estado: atual
---

# Claude Code 07/10 — auditoria das 3 plataformas: 9 consertos publicados (Play 656, Apple 1.0.13, web 200)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-06-auditoria-3-plataformas`, origem `claude-code`, atualizada em 2026-10-07T19:19:12.362995+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 06 auditoria 3 plataformas · memoria claude.ai · claude_ai_memoria

Auditoria pedida pela página prompt-auditoria-3-plataformas-2026-10-06, corrida a 07/10 no PC (chefe Opus; a sessão não troca de motor; investigação de leitura em agentes; verificador de contexto limpo). O que funciona agora: o painel arrastável do ecrã da corrida já não rebenta no fim da corrida (era o erro mais repetido, 27 vezes desde 01/10: o SOS condicional sem chave fazia recriar o painel com o mesmo controlador); a câmara do mapa da corrida já não é mexida depois de o mapa sair; o GPS com serviço em primeiro plano só se liga com a app à frente ou com permissão "sempre" e religa ao voltar à frente (antes, terminar uma corrida com a app em fundo deixava calado o GPS que alimenta o despacho — 4 vezes no telemóvel do Danilo), com protecção contra arranques sobrepostos; o aviso ao parceiro quando o admin força a loja aberta/fechada ou muda o horário chega (a função do servidor nunca enviava: extensions.net e chave anónima; migration 20261007105848) e o Android passou a mostrá-lo; a web deixou de apagar a subscrição de avisos a cada publicação; o botão de e-mail do suporte abre no Android; o GPS da entrega no iPhone continua em fundo; app.boraguarda.com deixou de ter 4 h de cache no navegador (zona Cloudflare a respeitar a origem). Também: pedido #1 do GitHub fechado sem juntar (já estava tudo na produção); 4 continuações arquivadas. Provas: suite 1037 -> 1055 verdes, cada conserto com teste que falha no código antigo, anti-trapaça limpo; CI Android 506 (versionCode 656), iPhone 173 (1.0.13 build 173, VALID, WAITING_FOR_REVIEW; a 1.0.12 do cartão preso já está READY_FOR_SALE), web 200 (versao.json 8bf8ccda nos dois domínios). Relatório .claude/.ai/reports/auditoria-3-plataformas-2026-10-06.md. Falta: GPS da corrida herda o fluxo da home (o geolocator partilha um fluxo por app), Time Sensitive no iPhone (portal Apple), som no Safari, avisos web para cliente/parceiro, aviso de versão nova do iPhone (app_latest_version_code_ios=0) — tudo em .claude/.ai/inbox/CONTINUAR-auditoria-3-plataformas-2026-10-06.md. Dinheiro só proposto (Córtex prop-3b74506b). OAuth do Gmail tem de ser publicado até 10/10 (ordem-20261007111613-ede9). NÃO pôr is_admin dentro de log_admin_action (parte cliente e parceiro).
