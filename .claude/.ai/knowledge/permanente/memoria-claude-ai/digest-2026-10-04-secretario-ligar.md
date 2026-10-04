---
id: memoria-claude-ai-digest-2026-10-04-secretario-ligar
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-04
zona: verde
confianca: alta
estado: atual
---

# PC do Danilo 04/10 — Secretário Virtual ligado (página + VPS)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-04-secretario-ligar`, origem `claude-code`, atualizada em 2026-10-04T18:31:19.650133+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 04 secretario ligar · memoria claude.ai · claude_ai_memoria

O que funciona agora: boraguarda.com/secretario está no ar (200, noindex no cabeçalho e na meta); /baixar continua a mandar Android para a Play e iPhone para a App Store. O secretario.html faltava na lista do deploy-cloudflare.sh e foi acrescentado (commit local e563a13 no bora-site). Na VPS: assistente-negocio atualizado pelo instalar.sh (active, /saude ok, tenants Mister Navalha e "Bora Secretário Virtual — demo" em modo teste); ligar.js novo com whatsapp-bora LIGADO; carteiro_caca.py novo em /opt/data/rotinas. Cópia de segurança em /root/backups/secretario-2026-10-04.
O que falta: (1) a base de produção recusa cliente_tipo secretario-virtual porque a parte a) da migration 20261004120000_secretario_virtual.sql (o ALTER da prospects_presenca_cliente_tipo_check) não está no ar. O caçador achou 13 negócios e os 13 deram HTTP 400; o total gravado é 0. Aplicar o ALTER e correr outra vez o cacar_secretario.py (os 13 estão no CSV de 04/10). (2) secretario_envio_ligado continua false. (3) Os commits do bora-site (ramo motorista-ficha-legal-2026-09-23, 8 commits; junção com main sem conflitos) não foram para o GitHub porque o guardrail só deixa enviar autonomous-night. (4) Erros antigos: a rotina orcamento do assistente dá float division by zero a cada minuto; o ligar.log tem 1,79M linhas, sem rotação.
Relatório: .claude/.ai/reports/secretario-ligar-2026-10-04.md
