---
id: memoria-claude-ai-digest-2026-10-21-retoma-fable
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-21
zona: verde
confianca: alta
estado: atual
---

# Digest 21/10/2026 — retoma Fable do Ep1 perfeito (Claude Code no PC)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-21-retoma-fable`, origem `claude-code`, atualizada em 2026-10-21T20:37:47.621252+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 21 retoma fable · memoria claude.ai · claude_ai_memoria

ESTADO ÀS 19:00 DE 21/10 (Claude Code/Fable 5.1, pasta C:\BoraLocal\BoraStudio, commits locais até d8621c2, nada empurrado, nada pago).

O QUE FUNCIONA AGORA: (1) a fábrica (tique de 15 min) ressuscita tarefas, grita no Telegram, respeita prazos; provada 8/8. (2) Montagem completa do Ep1 sempre em disco (saida/episodio1_final_v5_atual.mp4, 22:39): abertura-mestre nova (50 s, só imagens aprovadas, −14 LUFS, R60) + cartão "Episódio 1 — Haja Luz" único; SFX 57/58 com licença CC0 (3 refeitos pelo ouvido); −14,7 LUFS e pico −1,2 dBTP (o AAC somava 1,6 dB: tecto do limiter a −3). (3) MÚSICA v6 (ACE-Step 1.5 em fp32 no Kaggle — o fp16 dava NaN na T4): 4 canções com letra ≥ 90 % instaladas (alguem_me_responde, coincidencia, quem_sao_eles, um_dia_vao_ver); o tema ficou a 89,2/90,6, a ser refeito. (4) Vozes: Gustavo e Sussurrador aprovados com reserva pelo Representante; Davi com voz MISTA provisória (4 falas edge-tts Hyunsu + gritada antiga; continuidade 10/10) — decisão de gosto PARA O DANILO. (5) Bocas desenhadas 2D carimbadas (Tabita 10, Gustavo 10 com juiz a 3 votos); fiscal da boca com regra nova para remendo escurecido; produção dos 4 planos de dois falantes à espera do juiz (lei nova: falante parte de boca fechada). (6) Juízes: o 3.5-flash estava marcado morto há 5 dias (marca que não expirava) — corrigido; quota de topo esgota em 20 pedidos/dia.

O QUE NÃO FUNCIONA: (a) REPROVAÇÃO DO DANILO (18:40): as imagens do Gemini saíam com crianças do mesmo tamanho, duplicados, Mateus misturado, adultos em falta, Tailine maior que a Tabita — o juiz não conferia tamanho, contagem nem presença. Feito: geração PARADA, 95 fotogramas de hoje em_revisao (fora da montagem), lei em gosto_danilo.md, régua de alturas com números (canon/regua_alturas.md), fiscal "elenco do plano" com veto (prova 5/5 com juiz falso), auditoria de folhas (17 personagens só com ficha de 1 vista); amanhã 08:30 pelo tique: prova real, lineup do elenco, re-julgamento dos 95, Telegram com os números. (b) VIA 3D: malha da Tabita OK (100 k faces, cor por vértice), a CENA constrói-se (boca com 9 shape keys), mas o Kaggle cancela o kernel ~60–100 s depois de o Blender começar a renderizar a NOSSA cena (7 versões; o cubo de controlo vive 165 s); bissecção com 26 sondas em curso; se nada isolar, Colab. (c) InfiniteTalk: lote 1 reprovado 8/8 (fotograma substituído sem quarentena, cabeça a andar vs máscara estática, cauda muda); pipeline corrigido (base por sha, máscara seguida, cauda cortada); lote 2 preparado com prompt de cauda parada, só a partir das 21:30. (d) Flow: 26 créditos, volta amanhã.

COMO SE USA: python scripts/v5/montar_atual.py monta; o tique faz o resto; _v5/relatorios/2026-10-21.md é a verdade por hora; _v5/CONTINUAR-EP1-PERFEITO-2026-10-21-1150.md para retomar.

PARA O DANILO: voz do Davi (aceitar mista / outra voz / reescrever a gritada); alturas de Deus Pai/Jesus/Espírito Santo no cânone; vó Mônica 1,58 vs Mateus 1,50; nome espirito_santo/espirito; 7 itens de gosto da régua de estúdio (roteiro v9 proposto, não aplicado).

ACTUALIZAÇÃO 21:00: tema v6 instalado (tema_v6_4, 90,6 na régua maior; 6 sementes novas ficaram a 82–88) e a abertura passa a 60 s — o master v6 está renderizado mas o carimbo (fiscal de texto = juiz de visão) espera a quota de amanhã (tarefa abertura_carimbar 08:40). 3D: 32 sondas no Kaggle — a sessão cai 5–13 s depois de o Blender tocar na personagem, aleatório, não é nosso; COLAB pronto (receptor na VPS, notebook leve, motorista no Chrome do perfil Bora, notebook já no Drive da conta Bora) e PARADO no diálogo "Termos de Utilização do Colab": DECISÃO DO DANILO (sim/não), pedida por Telegram 19:41. InfiniteTalk lote 2 (prompt de cauda parada) entra às 21:30 pelo tique; colheita amanhã com juiz. Flow parado até 22/10 10:00. Amanhã pelo tique: 08:20 marioneta (bases neutras da Tailine), 08:30 elenco e escala (prova real do fiscal, lineup, re-julgar os 95, Telegram com números), 08:40 carimbo da abertura, 09:30 portão dos fotogramas (só abre com lineup + fiscal armado).

21:40 — NOITE: o InfiniteTalk lote 2 nao arrancou porque todos os fotogramas estao em_revisao (so parte de aprovados) -> fica para depois do re-julgamento de 22/10; a colheita 3D do Kaggle esta estacionada (cena vai pelo Colab, termos pendentes). Esta noite so o relogio monta. Commits locais ate 296f309.
