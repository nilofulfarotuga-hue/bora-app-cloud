[MODELO: SONNET]

ORDEM FIXA — RECOLHA DA NOITE DO RADAR: HISTÓRICO E PÁGINA INICIAL DO YOUTUBE DO DANILO (canal "Sons do Céus")
Dispara às 02:00 (Agendador de Tarefas "BoraRadarHistorico" → `orquestracao\disparar-ordem-fixa.cmd radar-historico`).

> Reescrita 2026-11-23 (missão radar-fila-2026-11-23, ordem da Claude.ai). A versão de 28/09 procurava no
> Chrome pessoal 5b260cdd, onde a conta do Danilo não tem sessão no YouTube (ciclo reload=9) e a outra
> conta é das filhas: de 192 vídeos de IA/negócio que ele viu desde 14/08, 122 nunca entraram no radar.
> Cópia da versão antiga: `radar-historico.md.bak-20261123` (mesma pasta).

O MÉTODO NÃO VIVE AQUI: vive na página do livro `radar-recolha-sons-do-ceus` (fonte única; se mudar,
muda lá). Faz isto e nada mais:

1. Lê a página inteira (MCP Supabase, projeto `ojykpzwqrtusfeakzrna`):
   `select conteudo from public.claude_ai_memoria where pagina = 'radar-recolha-sons-do-ceus';`
2. Carrega a skill `chrome-browser`. Escolhe o navegador SEMPRE pelo deviceId
   **`e6eec594-387c-40fe-841c-815992781ada`** (perfil "TikTok Vo Tonico", YouTube na conta Sons do Céus):
   `list_connected_browsers` → `select_browser` com esse deviceId. **NUNCA** o `5b260cdd` nem o `d9e862e0`.
   Se o e6eec594 não estiver na lista, abre o perfil
   (`"C:\Program Files\Google\Chrome\Application\chrome.exe" --profile-directory="TikTok Vo Tonico" https://www.youtube.com/feed/history`;
   a pasta do perfil chama-se mesmo "TikTok Vo Tonico"), espera 10 s e lista outra vez; se continuar fora,
   regista no `e2e_log` (`radar-historico`, passo `noite-AAAA-MM-DD`, estado `erro`, causa real) e termina.
3. Segue os passos 1 a 7 da página à letra: confirma a conta (logado=true, nilofulfaro@gmail.com),
   lê o histórico e a página inicial pelo JavaScript da página, deita fora o conteúdo das filhas
   (desenhos, músicas infantis, gibis, quizzes), música, futebol, notícias, cripto e trading, e põe o
   resto na `radar_fila` com a consulta única do passo 5.
4. Só LÊS o YouTube: não carregas em nada, não gostas, não subscreves, não apagas histórico, não mudas
   de canal nem de conta, não escreves senhas. Fecha o separador que abriste.
5. Linha final no `e2e_log`: `fluxo='radar-historico'`, `passo='noite-AAAA-MM-DD'`, `estado='ok'` com
   quantos vistos (histórico e página inicial), quantos escolhidos, quantos novos na fila e o estado da
   fila (`select estado, count(*) from radar_fila group by 1`). `ok` também com 0 novos, desde que diga
   quantos viu. Nunca `ok` sem ter lido a página.

A legenda, o resumo e a transcrição de cada vídeo da fila são do PC: `radar_crescimento.py processar-fila`
(a seguir ao recolher diário e às 03:00, tarefa "RadarFilaBora").
