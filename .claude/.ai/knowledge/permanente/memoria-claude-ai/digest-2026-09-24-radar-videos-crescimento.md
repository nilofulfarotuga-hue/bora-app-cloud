---
id: memoria-claude-ai-digest-2026-09-24-radar-videos-crescimento
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-24
zona: verde
confianca: alta
estado: atual
---

# Radar diário de vídeos de crescimento + playbook das redes (24/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-24-radar-videos-crescimento`, origem `claude-code`, atualizada em 2026-09-24T13:47:04.000177+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 24 radar videos crescimento · memoria claude.ai · claude_ai_memoria

O QUE PASSOU A EXISTIR. Todos os dias às 19:00 o PC do Danilo procura no YouTube vídeos novos sobre crescer no Instagram/Facebook/Reels/TikTok e sobre ganhar dinheiro online e marketing de apps. Tira a transcrição real (as legendas automáticas só saem do IP de casa; o YouTube bloqueia a VPS), manda a um modelo barato e guarda resumo, 3 ideias práticas e uma nota de 0 a 10 em public.radar_videos. Às 20:00 manda 5 linhas ao Danilo no Telegram. Ao domingo destila o playbook: só entra regra vista em 3 ou mais vídeos diferentes, com os links como prova. Nada disto gasta Claude no volume.

ONDE ESTÁ. Robô: C:\Users\danil\Desktop\QG\radar-crescimento\radar_crescimento.py (modos recolher | playbook | telegram), com cópia fiel no repo em .claude/.ai/provas/radar-videos-crescimento-2026-09-24/. Base: radar_videos e playbook_redes (RLS só admin lê; escrita por RPC com chave no Vault radar_videos_key). Painel admin PT-BR: "Radar de vídeos". Ficheiros: docs/marketing/PLAYBOOK-REDES.md e playbook-redes.json.

CASCATA DE MOTORES: Gemini primeiro, GLM (opencode) em reserva, Ollama local (qwen2.5:3b-instruct) como último recurso. A ordem é por VELOCIDADE: a 24/09 o GLM levou ~4 minutos por vídeo neste Celeron e 20 vídeos não cabiam numa corrida.

OS ROBÔS JÁ SEGUEM O PLAYBOOK. Na VPS há /opt/data/social/playbook_regras.py (leitor partilhado). Leem-no o social-reel.sh do Bora, o emdia_redes.py do Em Dia (modos hoje e stock) e o fiscal_video.py. O fiscal pede ao olho uma nota de 0 a 1 por regra e imprime PLAYBOOK v… x/n, mas é INFORMATIVO: não entra na nota /100 nem no aprovado/reprovado, para não mudar o que já está agendado. Sem ficheiro nenhum robô parte.

ARMADILHAS QUE CUSTARAM DUAS CORRIDAS (todas falham caladas). 1) Janela de datas: o yt-dlp não tem ytsearchdate, o YouTube ordena por relevância, e com 7 dias 68 de 70 candidatos eram deitados fora — a janela é agora RADAR_DIAS, 45 por defeito. 2) O opencode é um .CMD fora do PATH do subprocess: o GLM morria com WinError 2 e o radar caía sempre no Gemini sem dizer nada. 3) O opencode ecoa o prompt, e o prompt leva um exemplo de JSON: a busca gulosa do primeiro { ao último } apanhava o exemplo e rebentava sempre. 4) O Telegram: o bash do Git também não está no PATH, e depois disso os acentos passavam pela página de códigos da consola e a API devolvia 400 "strings must be encoded in UTF-8" — agora vai direto do Python em UTF-8, com a mesma credencial e a mesma prova (lê-se "ok":true no corpo, nunca o código HTTP).

ESTADO A 24/09 ÀS 14H45. 22 vídeos na base, 21 com transcrição. Playbook v20260924 com 2 regras: criar ganchos diferentes e testá-los antes de publicar (4 vídeos); testar formatos e tamanhos diferentes (3 vídeos). A v1 é curta porque o corte dos 3 vídeos está a funcionar, não por falta de material — cresce todas as semanas. Commit 53281009 + merge a093b9e8 no ramo autonomous-night-2026-04-29. flutter analyze sem erros, 17 testes do menu admin verdes.

POR FECHAR. A página playbook-redes no Córtex ficou em PROPOSTA (prop-01932840): o MCP não cria páginas novas, só atualiza existentes. Alguém com acesso à Central tem de a aprovar.
