---
id: memoria-claude-ai-dsh-como-usar-novidades-2026-10-31
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Dipsy: o que ficou novo a 31/10 (complemento da pagina dsh-como-usar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `dsh-como-usar-novidades-2026-10-31`, origem `claude-code`, atualizada em 2026-10-31T12:25:42.97105+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: dsh como usar novidades 2026 10 31 · memoria claude.ai · claude_ai_memoria

Complemento da pagina dsh-como-usar (missao retoma-geral-2026-10-31, bloco 3). Guia completo no PC: ~/.dsh/COMO-USAR.md.

Voz: o "Ouvi" chega em poucos segundos. Com menos de 1,5 GB de memoria livre o audio vai direto ao Gemini; com mais, o PC tenta sozinho so 10 segundos (medido a 31/10: sozinho, o whisper do PC levou 76 s e percebeu mal). Se o Dipsy demorar mais de 20 s, diz "Estou a pensar".

Botoes novos no Telegram do Dipsy (@dipsy_bora_bot): Planear (/planear e o pedido: so faz o plano, a guarda nao deixa mexer em nada; depois /aprovar), Objetivo (/objetivo e a meta: trabalha sozinho ronda a ronda ate cumprir, maximo 6; /objetivo parar), Corrigir (/corrigir a meio: para e continua o mesmo trabalho com a correcao), Voltar atras (/voltar: esquece o ultimo pedido e diz que ficheiros esse pedido mudou), Conversa nova (/nova), Libertar memoria (/libertar, corre ~/.dsh/limpar-ram.ps1 em modo normal). O Dipsy agora continua a conversa enquanto as mensagens tem menos de 30 min de intervalo.

Creator Mode: pede-se "cria uma ferramenta que..." e o Dipsy cria uma receita so de leitura (um SELECT a base do Bora corrido em transacao so de leitura, ou um GET a um sitio nosso), testa-a no laboratorio, promove-a e passa a ter a ferramenta fc_<nome>. Primeira: fc_pedidos_hoje.

Seguranca: a rede do Dipsy tem lista branca (so sitios do Bora; o resto e barrado; pesquisar na internet e com o Claude Code). Se a guarda dsh-bora nao ligar, a ponte nao deixa o Dipsy trabalhar. Quando o Dipsy passa trabalho ao Claude Code (claude -p), esse Claude Code leva um hook que barra apagar em massa, apagar tabelas, push forcado, reescrever historico, matar processos e segredos (ainda nao ligado nos executores carteiro/loop do PC e da VPS).

App de computador do dsh para Windows: nao instalada (o canal oficial nao publica instalador).
