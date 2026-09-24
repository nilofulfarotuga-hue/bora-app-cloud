# radar-crescimento — mensagem das 20:00 (Tarefa Agendada "RadarCrescimentoTelegramBora").
# Só lê o que já está na base e manda 5 linhas ao Danilo. Leve: não recolhe nem resume, por
# isso pode correr mesmo que a recolha das 19:00 ainda esteja a acabar.
$ErrorActionPreference = "Continue"
$BASE = "C:\Users\danil\Desktop\QG\radar-crescimento"
$PY = "C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if (-not (Test-Path $PY)) { $PY = "python" }
New-Item -ItemType Directory -Force "$BASE\logs" | Out-Null
Set-Location $BASE
Add-Content -Path "$BASE\logs\run_diario.log" -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] START telegram 20:00"
& $PY "$BASE\radar_crescimento.py" telegram 2>&1 | Out-File -Append -Encoding utf8 "$BASE\logs\run_diario.log"
