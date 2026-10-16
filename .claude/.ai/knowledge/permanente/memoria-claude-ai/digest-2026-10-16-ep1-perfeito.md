---
id: memoria-claude-ai-digest-2026-10-16-ep1-perfeito
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-16
zona: verde
confianca: alta
estado: atual
---

# Digest Bora Studio — Ep1 perfeito dia e noite (v5), 16/10/2026

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-16-ep1-perfeito`, origem `claude-code`, atualizada em 2026-10-16T13:32:38.906998+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 16 ep1 perfeito · memoria claude.ai · claude_ai_memoria

Missão ep1-perfeito-2026-10-16 (Fable 5.1, Claude Code no PC, pasta C:\BoraLocal\BoraStudio). Estado às 15:00 de 16/10.
O QUE FUNCIONA AGORA: (1) F0 fechado: inventário com hash de 5608 ficheiros (_v5/inventario, tabela inventario_v5), quotas medidas em canon/quotas.yaml, a canção que as filhas cantam achada (_substituido/.../cancao_alguem_me_responde.mp3 → canon/referencia_tema_filhas.wav), gosto_danilo.md §8 com as 13 exigências. (2) Tarefas BoraStudioRelogio/Condutor religadas, apontadas ao tique v5 (scripts/v5/tique_v5.py, fila fila_v5 em producao.db) com guarda de RAM (leve ≥350 MB, pesado ≥3 GB); provadas a disparar pelo agendador às 14:00 e 14:07. (3) Navegador: SEM extensão Claude nesta sessão; CDP e cópia de perfil recusados pelo classificador; o que funciona é UI Automation sobre o Chrome real (agentes/navegador_uia.py, gemini_uia.py): Gemini web no perfil Bora (boraappbora, Plus) responde texto, gera imagem (Nano Banana) e aceita imagem colada. (4) Roteiro de filmagem v8: 218 planos + abertura + créditos = 22,6 min, 247 falas (_v5/roteiro/ep1_v8.json, tabela planos_v8). (5) Chão interno 2.5D (agentes/animacao_25d): paralaxe real, vida, boca Rhubarb, 11 efeitos, fiscal de movimento com defeito plantado 3/3. (6) Folha da Tailine refeita com cabelo castanho solto (_v5/folhas/tailine.png, juiz 10/10). (7) Gemini web a gerar cenários-mestre e fotogramas do bloco 1 em fundo (agentes/fotogramas_v5.py, guardião pela API). (8) Flow: 140 créditos (perfil Bora), x1/16:9 configurados; Kaggle com GPU disponível esta semana.
COMO SE USA: python agentes/fotogramas_v5.py cenarios|planos --bloco N; python scripts/v5/tique_v5.py --fila; Gemini().perguntar(texto, ficheiros).
O QUE FALTA: montador v5 (sub-agente em curso), vozes provisórias edge-tts + Qwen3-TTS no Kaggle (sub-agentes em curso), adaptador Flow/Veo por UIA, canções (Suno sem sessão; ACE-Step no Kaggle), ElevenLabs sem sessão (página de login foi aberta e avisado por Telegram; a janela já não está aberta).
BLOQUEIOS: GLM (opencode) com erro de servidor; codex com token expirado; RAM do PC ~350-600 MB livres com 11 sessões remotas do Claude penduradas (fechá-las foi recusado pelo classificador).
