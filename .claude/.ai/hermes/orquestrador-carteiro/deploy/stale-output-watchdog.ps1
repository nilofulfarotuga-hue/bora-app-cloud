param(
  [Parameter(Mandatory=$true)][string]$LiveLog,
  [Parameter(Mandatory=$true)][string]$StampFile,
  [int]$StaleMinutes = 20,
  [int]$HardCeilingMinutes = 240,
  [int]$PollSeconds = 30,
  [string]$ProcessName = 'claude',
  [string]$Fingerprint = 'loop autonomo do Bora|CLAUDE-JUIZ de qualidade do Bora'
)
# stale-output-watchdog.ps1 -- FASE 1.9 (2026-07-16, pos-morte ordem 7838, pedido Danilo).
# Corre em processo separado, em paralelo ao claude.exe do run-claude-loop.cmd. So mata por
# INATIVIDADE real (LIVELOG sem crescer ha $StaleMinutes) -- NAO por relogio total. A 7838 foi
# morta por TIMEOUT-3600s x2 (o antigo `timeout 3600` do carteiro.sh, lado VPS) quando ainda
# estava viva e a produzir output nos testes finais -- desperdicio total. $HardCeilingMinutes
# (default 4h) fica como rede de seguranca final -- nunca pendurado infinito mesmo que o LIVELOG
# va crescendo devagar para sempre. Fingerprint identico ao cleanorphans (executor-lock.ps1) --
# nunca mata um claude.exe interativo do Danilo, so o executor da esteira.
$ErrorActionPreference = 'SilentlyContinue'
Remove-Item -LiteralPath $StampFile -Force -ErrorAction SilentlyContinue
$inicio = Get-Date
while ($true) {
  Start-Sleep -Seconds $PollSeconds
  $alvo = @(Get-CimInstance Win32_Process -Filter "Name='$ProcessName.exe'" -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrEmpty($_.CommandLine) -and $_.CommandLine -match $Fingerprint })
  if ($alvo.Count -eq 0) { break }   # executor ja terminou sozinho -- nada a vigiar, watchdog sai
  $lastWrite = $inicio
  if (Test-Path -LiteralPath $LiveLog) {
    $item = Get-Item -LiteralPath $LiveLog -ErrorAction SilentlyContinue
    if ($null -ne $item) { $lastWrite = $item.LastWriteTime }
  }
  $silencioMin = ((Get-Date) - $lastWrite).TotalMinutes
  $decorridoMin = ((Get-Date) - $inicio).TotalMinutes
  if ($silencioMin -ge $StaleMinutes) {
    "INATIVIDADE:$([math]::Round($silencioMin))" | Set-Content -LiteralPath $StampFile -Encoding UTF8 -NoNewline
    $alvo | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    break
  }
  if ($decorridoMin -ge $HardCeilingMinutes) {
    "TETO-DURO:$([math]::Round($decorridoMin))" | Set-Content -LiteralPath $StampFile -Encoding UTF8 -NoNewline
    $alvo | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    break
  }
}
