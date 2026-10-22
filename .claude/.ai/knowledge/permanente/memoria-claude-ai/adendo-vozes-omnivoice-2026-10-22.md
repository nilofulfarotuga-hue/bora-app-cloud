---
id: memoria-claude-ai-adendo-vozes-omnivoice-2026-10-22
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-22
zona: verde
confianca: alta
estado: atual
---

# Adendo de vozes: A/B do motor OmniVoice (k2-fsa) no filme Ep1

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `adendo-vozes-omnivoice-2026-10-22`, origem `claude-ai`, atualizada em 2026-10-22T06:04:54.920347+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: adendo vozes omnivoice 2026 10 22 · memoria claude.ai · claude_ai_memoria

ADENDO 21/10 21:30 — do Danilo via Claude.ai (vídeo sobre o "Voice Studio", "ElevenLabs com engenharia reversa, de graça no GitHub"). Fica NA FILA DEPOIS do elenco/alturas. Decisão do Davi de 22/10: provisória edge-tts aceite; fala gritada reescrita como "a chamar alto, aflito" sem grito.

O QUE É (verificado na fonte 21/10): não é ElevenLabs craqueado. É a app OmniVoice Studio / VoiceStudio (github.com/debpalash/OmniVoice-Studio, AGPL-3.0, beta) que embrulha modelos abertos. O motor que interessa é o OmniVoice da k2-fsa (github.com/k2-fsa/OmniVoice, código Apache-2.0, pip install omnivoice, notebook Colab oficial): clonagem por 3 s e VOICE DESIGN por atributos (género, idade, pitch, sotaque, sussurro), 600+ línguas. Licença (R45): tokenizador Higgs Audio 2 com Boson Higgs Audio 2 Community License — amarelo, como o Chatterbox; o Ep1 não é para publicar. A APP NÃO se instala no PC; só o motor, no Kaggle T4. No vídeo o português saiu embaralhado em 2 de 3 gerações — entra por medição.

O QUE FAZER (degrau novo da cascata de vozes, entra em último, ordem por medição):
1) Kernel Kaggle k_omnivoice_ab: voice design SEM referência para Davi (adulto, grave), Gustavo 10 anos (menino, nunca homem), Sussurrador (35-40, alto, sorrisinho na voz), Tailine 7, Luara 4. Atributos do cânone; falas reais do roteiro v8; 4 sementes por fala.
2) Julgar com a régua existente (HNR por duração, F0 na banda do cânone, Whisper WER, "mesma pessoa") + Representante. A/B contra o instalado.
3) Ganhou → voz desenhada vira referência e o OmniVoice clona-a para as restantes falas do personagem (um motor por personagem). Perdeu → "reprovado" com números, não volta.
4) Proibido clonar pessoas reais ou dobradoras. Só voz desenhada.
5) e2e_log estado vozes-omnivoice-ab com números por personagem; Telegram ao Danilo numa linha.
