---
id: memoria-claude-ai-digest-2026-09-28-emdia-redes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-28
zona: verde
confianca: alta
estado: atual
---

# Claude Code PC 28/09 — redes do Em Dia (E1 reels, E2 grupos, E3 playbook)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-28-emdia-redes`, origem `claude-code`, atualizada em 2026-09-28T10:38:33.890075+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 28 emdia redes · memoria claude.ai · claude_ai_memoria

Reels do Em Dia saem sozinhos: /opt/data/emdia-redes/gerador/tool/redes/reel_diario.py corre na VPS (contentor hermes, venv com Pillow) as 03:40 Lisboa (cron do host 40 2 * * *, reel-diario.sh espera por outro ffmpeg), preenche o primeiro dia sem reel com um dos 12 temas provados sem datas, texto reescrito pelo Motor Bora (perfil volume) com verificador por codigo, monta com reel.py com camara (zoom 0,18 + deriva 0,5) e so entra no calendario.json com fiscal_video >= 90; o robo emdia_redes.py hora publica as 20:30 na pagina Em Dia e @em_dia_app. Sem a camara os reels do Em Dia davam movimento 7,5-8,8 (minimo 12) e eram todos chumbados. Primeiros: G20260929/G20261003/G20261006/G20261010, fiscal 100. Grupos do Facebook: maquina de PLANO (nao adere nem publica; Termos da Meta + conta pessoal partilhada com o Bora) em /opt/data/emdia-redes/grupos, plano no Telegram as 08:40, registo com grupos_emdia_registar.py (aderi/aceite/publiquei/regras/aviso). Playbook: pagina playbook-redes-emdia (40 regras). FALTA: 7 reels agendados a mao na Meta (R01 28/09, R02, R05, R08, R12, R14, R16) mostram Mes gratis ate 23/10 no ecra; versoes corrigidas em pecas/reels-v2 do ramo redes-diario-2026-09-28 do em-dia-app (commit 056fca4), troca no Business Suite por decidir. O codigo das redes do Em Dia vive nesse ramo, nao no main (o main nao tem os 9 commits de 24/09).
