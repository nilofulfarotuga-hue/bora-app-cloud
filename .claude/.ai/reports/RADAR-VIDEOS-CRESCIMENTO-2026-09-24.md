# Radar de vídeos de crescimento — missão `radar-videos-crescimento-2026-09-24`

> Escrito pelo Claude Code no PC do Danilo, 24/09/2026. Fluxo do `e2e_log`:
> `radar-videos-crescimento-2026-09-24`. Prova material: cada linha aqui tem saída literal
> (log, `SELECT`, `dart analyze`, `bash -n`) atrás dela.

## O que isto faz, em português simples

Todos os dias às 19:00 o PC do Danilo procura no YouTube vídeos novos sobre **crescer no
Instagram, Facebook, Reels e TikTok** e sobre **ganhar dinheiro online / marketing de apps
e pequenos negócios**. De cada vídeo tira a **transcrição real** (as legendas automáticas só
saem do IP de casa; a VPS está bloqueada pelo YouTube), manda a um **modelo barato** (GLM da
opencode, senão Gemini, senão Ollama local) e guarda: resumo, **3 ideias práticas** e uma
**nota de utilidade de 0 a 10** para o Bora e o Em Dia.

Uma vez por semana (domingo) destila o **playbook**: só entra uma regra que apareça em **3 ou
mais vídeos diferentes**, com os links como prova. Os robôs de conteúdo passam a ler esse
playbook, e o fiscal de vídeo pontua as mesmas regras na peça.

Às 20:00, cinco linhas no Telegram a dizer o que aprendeu.

**Nada disto gasta Claude no volume.** O Claude escreveu a máquina uma vez; o trabalho diário
é do yt-dlp e de modelos baratos.

## Blocos

### 1. Base de dados (Supabase Bora `ojykpzwqrtusfeakzrna`) — FEITO

Migration `supabase/migrations/20260924140000_radar_videos_crescimento.sql`, aplicada.

- `radar_videos` — um vídeo por linha (título, canal, visualizações, data, duração, link,
  tema, pesquisa que o encontrou, se tem transcrição, resumo, ideias, nota, motor usado).
- `playbook_redes` — as regras destiladas, com as provas em JSON e o número de vídeos.
- RLS: **só o admin lê**. Quem escreve é o robô do PC, por RPC com chave guardada no Vault
  (`radar_videos_key`) — a chave nunca está no repositório.
- RPCs: `radar_videos_registar`, `radar_videos_ler`, `playbook_redes_registar`,
  `admin_radar_videos(p_dias, p_tema)`, `admin_playbook_redes()`.

### 2. O robô do PC — FEITO

`C:\Users\danil\Desktop\QG\radar-crescimento\radar_crescimento.py`, três modos:
`recolher`, `playbook`, `telegram`. 18 pesquisas em rotação (PT-BR, PT-PT e inglês), 6 por
dia, a rodar pelo dia do ano, para não ver sempre os mesmos canais.

Três avarias apanhadas e corrigidas na primeira corrida real (todas falhavam **em silêncio**):

1. **Janela de datas de 7 dias deixava a recolha a zero.** O `yt-dlp` desta versão não tem
   `ytsearchdate`, portanto o YouTube devolve por relevância e não por data: 68 dos 70
   candidatos foram cortados por serem mais velhos que uma semana, e a corrida rendeu **2
   vídeos**. A janela passou a `RADAR_DIAS` (45 dias por defeito).
2. **O GLM parecia mudo.** No Windows o `opencode` é um `.CMD` fora do PATH do `subprocess`:
   todas as chamadas morriam com `WinError 2` e o radar caía sempre no Gemini sem dizer nada.
   Resolvido com `shutil.which` dentro do `sh()`.
3. **O parser de JSON apanhava o próprio prompt.** O `opencode` ecoa o prompt antes da
   resposta, e o prompt leva lá dentro um **exemplo de JSON**; a busca gulosa do primeiro `{`
   ao último `}` juntava os dois e rebentava sempre. Agora lê-se de trás para a frente
   (cercas ```` ```json ```` primeiro) e limpam-se as cores ANSI.

### 3. Painel admin (PT-BR) — FEITO

- `lib/screens/admin/admin_radar_videos_screen.dart` — ecrã novo, só leitura: os vídeos do
  dia (ou de 7/30 dias), filtro por tema, cada vídeo com nota, resumo, as 3 ideias e o link;
  e o playbook em vigor por baixo.
- `lib/screens/admin/admin_menu_registry.dart` — item `robos_radar_videos`, logo a seguir ao
  das decisões do robô.
- `dart analyze` aos dois ficheiros: **No issues found**.

### 4. Os robôs passam a seguir o playbook (VPS) — FEITO

- `/opt/data/social/playbook_regras.py` — leitor partilhado. Sem ficheiro devolve vazio e
  **rc=0**: nenhum robô parte por o playbook ainda não existir.
- `fiscal_video.py` — pede ao olho uma nota de 0 a 1 para até 4 regras do playbook e imprime
  `PLAYBOOK v… x/n`, que também fica no `.txt` da prova. **Informativo:** não entra na nota
  /100 nem no aprovado/reprovado, para não mudar o que já está agendado.
- `social-reel.sh` (Bora) e `emdia_redes.py` (Em Dia, modos `hoje` e `stock`) — registam no
  log a versão do playbook e as regras que valem nesse dia.
- Backups `.bak-playbook-2026-09-24` de cada ficheiro. Verificação: `ast.parse` nos dois
  Python e `bash -n` no shell, todos limpos.

### 5. Horários — FEITO

| Tarefa do Windows | Hora | O que faz |
|---|---|---|
| `RadarCrescimentoBora` | 19:00 | recolhe e resume; ao domingo destila o playbook |
| `RadarCrescimentoTelegramBora` | 20:00 | cinco linhas ao Danilo |

Ambas com **"arrancar mesmo com bateria"** e **"arrancar mal seja possível"** ligadas (no XML:
`DisallowStartIfOnBatteries=false`, `StopIfGoingOnBatteries=false`, `StartWhenAvailable=true`).
A recolha salta-se sozinha se já houver outro radar a correr — **um processo pesado de cada
vez**, como o Danilo pediu depois da VPS ter caído a 24/09.

O Telegram saiu da corrida das 19:00 para tarefa própria porque a recolha pode levar quase
uma hora e a mensagem tem hora certa.
