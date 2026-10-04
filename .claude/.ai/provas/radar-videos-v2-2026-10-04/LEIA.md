# Radar de vídeos v2 (04/10/2026)

Pedido do Danilo (04/10): o agente de vídeos tem de ver também como ganhar dinheiro com IA,
automação, projetos e ferramentas — tudo o que ele conversa com o Claude — e usar as sugestões
da página inicial do YouTube dele; e ele tem de VER o resultado (até aqui o Telegram dizia
"Vou aplicar" e nada aplicava).

Cópias fiéis do que corre no PC (feitas pela Claude.ai pela ponte do computador, com
`*.bak-20261004` ao lado de cada original no PC):

- `C:\BoraLocal\QG\radar-crescimento\radar_crescimento.py` — os temas vêm da tabela
  `radar_pesquisas` (RPC `radar_pesquisas_do_dia`, 8 por dia, lista fixa de reserva se o Supabase
  falhar); as pesquisas alternam para os ~20 vídeos não saírem todos do mesmo tema; o prompt do
  resumo mede a utilidade para as 4 frentes (Bora, Em Dia, sistema de agentes, ganhar dinheiro com
  IA) e tem temas novos; o modo `historico` lê também `recomendados-*.json`; filtro de vídeos de
  criança (a conta do YouTube é partilhada com as filhas); o Telegram das 20:00 só fala quando o
  dia corre mal.
- `C:\BoraLocal\QG\radar-video\scripts\run_nightly.ps1` — a linha diária do Telegram (sempre
  igual) só sai com `RADAR_VIDEO_TELEGRAM=1`.
- `C:\BoraLocal\projetosflutter\bora_app\orquestracao\ordens-fixas\radar-historico.md` — passo 5b:
  às 01:45 grava também as sugestões da página inicial (`recomendados-AAAA-MM-DD.json`). A cópia
  de segurança está em `C:\BoraLocal\QG\radar-video\radar-historico.md.bak-20261004`.

Supabase: migração `20261004150308_radar_pesquisas_e_veredito` (tabela `radar_pesquisas` com 48
temas iniciais, colunas `veredito/para/acao/revisto_em` em `radar_videos`).

Resumo diário: tarefa agendada na nuvem "Radar de vídeos: o que presta hoje"
(`trig_01HyoFVDdR2xe42uYRbZVuhN`, 20:52 Lisboa, notificação no telemóvel). Revê os vídeos, grava
o veredito, acrescenta o que presta à página `ideias-videos-danilo` da `claude_ai_memoria`, propõe
no Córtex, aprende temas novos (vídeos bons e conversas das últimas 48 h) e desliga os que não
rendem, e diz ao Danilo em 3 linhas.

Painel admin: o ecrã "Radar de vídeos" ainda não mostra `veredito/para/acao` nem a lista de
temas — fica para a próxima missão que mexer no painel (gatilho de paridade).
