# radar-crescimento — trata a radar_fila (historico + pagina inicial do YouTube do Danilo, canal Sons do Ceus).
# Missao radar-fila-2026-11-23. Corre a seguir ao recolher das 19:00 (run_diario.ps1) e sozinho as 03:00
# (Tarefa Agendada "RadarFilaBora"). Um radar pesado de cada vez. A prova e' o logs/radar.log e o SELECT
# select origem, estado, count(*) from radar_fila group by 1,2 — nao o "Last Result 0" da tarefa.
param([int]$Lote = 40, [switch]$JaDentroDoDiario)
$ErrorActionPreference = "Continue"
$BASE = "C:\Users\danil\Desktop\QG\radar-crescimento"
$PY = "C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if (-not (Test-Path $PY)) { $PY = "python" }
$LOG = "$BASE\logs\run_diario.log"
New-Item -ItemType Directory -Force "$BASE\logs" | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LOG -Value "[$stamp] START run_fila lote=$Lote"
Set-Location $BASE
# yt-dlp rebenta com WinError 448 se o caminho do Cua estiver no PATH
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notmatch 'Cua' }) -join ';'
if (-not $JaDentroDoDiario) {
  $outro = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object { $_.CommandLine -match 'radar_crescimento.py|run_nightly|b3_legendas|b5_leitura' }
  if ($outro) { Add-Content -Path $LOG -Value "[$stamp] SALTA run_fila: ja ha um radar a correr (pid $($outro.ProcessId))"; exit 0 }
}
& $PY "$BASE\radar_crescimento.py" processar-fila $Lote 2>&1 | Out-File -Append -Encoding utf8 "$BASE\logs\run_diario.log"
Add-Content -Path $LOG -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FIM run_fila"
