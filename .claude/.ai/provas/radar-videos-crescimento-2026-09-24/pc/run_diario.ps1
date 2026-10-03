# radar-crescimento — corrida diária (Tarefa Agendada "RadarCrescimentoBora", 19:00).
# 1) recolher ~20 vídeos novos (legendas do IP de casa) e resumir (GLM -> Gemini -> Ollama)
# 2) ao domingo: destilar o playbook (regras vistas em >= 3 vídeos)
# O Telegram das 20:00 e' outra tarefa (run_telegram.ps1). Um processo pesado de cada vez;
# nunca em paralelo com o
#    RadarVideoBora das 02:00. A prova é o logs/radar.log, não o "Last Result 0" da tarefa.
$ErrorActionPreference = "Continue"
$BASE = "C:\Users\danil\Desktop\QG\radar-crescimento"
$PY = "C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if (-not (Test-Path $PY)) { $PY = "python" }
$LOG = "$BASE\logs\run_diario.log"
New-Item -ItemType Directory -Force "$BASE\logs" | Out-Null
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LOG -Value "[$stamp] START run_diario"
Set-Location $BASE
# se ainda houver um radar a correr, não arranca outro (um pesado de cada vez)
$outro = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object { $_.CommandLine -match 'radar_crescimento.py|run_nightly|b3_legendas|b5_leitura' }
if ($outro) { Add-Content -Path $LOG -Value "[$stamp] SALTA: ja ha um radar a correr (pid $($outro.ProcessId))"; exit 0 }
& $PY "$BASE\radar_crescimento.py" recolher 2>&1 | Out-File -Append -Encoding utf8 "$BASE\logs\run_diario.log"
if ((Get-Date).DayOfWeek -eq 'Sunday') {
  & $PY "$BASE\radar_crescimento.py" playbook 2>&1 | Out-File -Append -Encoding utf8 "$BASE\logs\run_diario.log"
}
# O Telegram NAO sai daqui: tem tarefa propria (RadarCrescimentoTelegramBora, 20:00), porque
# a recolha pode levar quase uma hora e a mensagem do Danilo tem hora certa.
Add-Content -Path $LOG -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FIM run_diario"
