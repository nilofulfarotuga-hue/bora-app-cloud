# radar-video — corrida noturna (B2-B6). Retomavel: usa cache_ids_processados.txt para
# nunca reprocessar o mesmo video duas vezes. Corre as 02:00 pela Tarefa Agendada do Windows
# "RadarVideoBora" (ver registo em run_nightly_setup.txt).
#
# B1 (zip do Takeout -> videos.jsonl) corre sozinho aqui SE o zip ja estiver em Downloads —
# o Danilo nao clica nem arrasta nada. Mas ESTE script nao consegue ele mesmo detectar o
# email "a tua exportacao esta pronta" nem descarregar o zip: isso exige Gmail + um browser
# com sessao autenticada, que uma Tarefa Agendada do Windows (PowerShell puro) nao tem. Isso
# fica para uma sessao Claude Code futura verificar (ver continuacao da missao
# radar-video-2026-09-17). yt-dlp+cookies do Chrome continua bloqueado pelo App-Bound
# Encryption — NAO tentar de novo (ver INVENTARIO.md, armadilha registada).

$ErrorActionPreference = "Continue"
$BASE = "C:\Users\danil\Desktop\QG\radar-video"
$LOG = "$BASE\_execucoes_nightly.log"
$STAMP = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content -Path $LOG -Value "[$STAMP] START run_nightly"

Set-Location $BASE

# Limpeza dos intermediarios: se B3/B4/B5 encerrarem cedo (ex.: cache ja tudo processado,
# nada novo numa noite), os ficheiros da noite anterior NAO podem chegar ao B6 como se
# fossem desta. Antes: a corrida de 19/09 releu candidatos_com_texto.jsonl de 18/09 e o
# relatorio dizia "Dentro do tema: 0" mas listava achados completos (enganoso).
$INT = @(
    "candidatos_tema.jsonl",
    "fora_tema.jsonl",
    "candidatos_com_texto.jsonl",
    "sem_legenda.jsonl",
    "candidatos_nomes.json",
    "candidatos_nomes_TODOS.json",
    "candidatos.md",
    "leitura_candidatos.json"
)
foreach ($f in $INT) {
    if (Test-Path "$BASE\$f") {
        Remove-Item -LiteralPath "$BASE\$f" -Force
        Add-Content -Path $LOG -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] limpo $f (intermediario da corrida anterior)"
    }
}

python scripts\b1_ingest_takeout.py *>> $LOG
python scripts\b2_filtro_tema.py *>> $LOG
python scripts\b3_legendas.py *>> $LOG
python scripts\b4_extrair_nomes.py *>> $LOG
python scripts\b5_leitura_ollama.py *>> $LOG
python scripts\b6_gerar_relatorio.py *>> $LOG

# Desde 28/09: os videos do tema do historico (gravado as 01:45 pela ordem fixa
# radar-historico em historico\) vao tambem para a tabela radar_videos do Supabase.
python "C:\Users\danil\Desktop\QG\radar-crescimento\radar_crescimento.py" historico *>> $LOG

# Marca como processados (para a proxima corrida nao repetir)
if (Test-Path "$BASE\candidatos_tema.jsonl") {
    Get-Content "$BASE\candidatos_tema.jsonl" | ForEach-Object {
        ($_ | ConvertFrom-Json).id
    } | Add-Content "$BASE\cache_ids_processados.txt"
}
if (Test-Path "$BASE\fora_tema.jsonl") {
    Get-Content "$BASE\fora_tema.jsonl" | ForEach-Object {
        ($_ | ConvertFrom-Json).id
    } | Add-Content "$BASE\cache_ids_processados.txt"
}

$STAMP2 = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LOG -Value "[$STAMP2] FIM run_nightly"

# Avisa por Telegram (so texto, o relatorio completo fica no ficheiro)
$HOJE = Get-Date -Format "yyyy-MM-dd"
$RELATORIO = "$BASE\RELATORIO-radar-video-$HOJE.md"
# Desde 04/10 o resumo diario e da tarefa agendada do Claude.ai "Radar de videos", que cruza
# os videos com o que o Danilo ja tem e diz o que fez. Esta linha diaria repetia sempre o
# mesmo ("Entraram na corrida: 3. Fora do tema: 20") e treinava-o a ignorar o Telegram.
# So volta a sair com RADAR_VIDEO_TELEGRAM=1.
if ($env:RADAR_VIDEO_TELEGRAM -eq "1" -and (Test-Path $RELATORIO)) {
    Set-Location "C:\BoraLocal\projetosflutter\bora_app"
    # A mensagem leva os NUMEROS, nao so "terminou". Ate 25/09 dizia sempre a mesma coisa
    # e o Danilo nao tinha como saber, sem abrir o ficheiro, que ha quatro noites entravam
    # ZERO videos novos (a fonte e um historico do Takeout que ninguem voltou a exportar).
    # Uma linha que diz sempre o mesmo treina a pessoa a ignora-la.
    $LINHA = (Select-String -Path $RELATORIO -Pattern "^Entraram na corrida" | Select-Object -First 1).Line
    if (-not $LINHA) { $LINHA = "sem linha de contagem no relatorio" }
    $MSG = "radar-video $HOJE - $LINHA Relatorio: $RELATORIO"
    # PATH do Git Bash a absoluto: a Tarefa Agendada nao tem o bash no PATH (provado
    # 2026-09-19 — GRITO nao chegava). Com o caminho certo, o bridge vai ao VPS e a
    # prova le-se em /opt/data/social/log.md.
    & "C:\Program Files\Git\bin\bash.exe" orquestracao\ponte-telegram.sh --so-texto $MSG
}
