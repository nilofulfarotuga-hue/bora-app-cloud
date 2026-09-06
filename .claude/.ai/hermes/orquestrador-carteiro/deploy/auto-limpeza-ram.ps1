param(
  [string]$Mode = 'manual',
  [int]$ZombieMin = 10,
  [int]$LowRamMB = 300,
  [int]$TempAgeMin = 15,
  [int]$StaleOutputMin = 15
)
# auto-limpeza-ram.ps1 -- rede de seguranca de RAM/zumbis (2026-07-13).
# Base logica: agente limpeza-pc (produtividade-ia\.claude\agents\limpeza-pc.md), adaptada para
# correr sozinha em 2 gatilhos: (1) hook no fim de cada ciclo do run-claude-loop.cmd, via
# auto-limpeza-ram.cmd; (2) schtask BoraAutoLimpezaRAM a cada 15min como rede de seguranca.
#
# NUNCA mexe no Claude Desktop (WindowsApps\Claude_*) nem no executor Bora ativo:
#   Tier A (claude/cmd/python) delega no executor-lock.ps1 -Action cleanorphans, ja testado --
#   so mata processos com a impressao digital da esteira Bora na linha de comando E fora da
#   arvore do dono atual do lock (executor.lock). Nao reimplementado aqui de proposito.
#   Tier B (cmd/conhost/python) so mata processos com PAI JA MORTO (orfao real, sinal
#   inequivoco que nao depende de fingerprint) -- nunca toca 'claude' nesta tier: e a
#   categoria mais sensivel, fica so na Tier A testada.
$ErrorActionPreference = 'SilentlyContinue'

$Root = 'C:\Users\danil\Desktop\projetosflutter\bora_app'
$Deploy = Join-Path $Root '.claude\.ai\hermes\orquestrador-carteiro\deploy'
$LockFile = Join-Path $Root '.claude\executor.lock'
$LockPs = Join-Path $Deploy 'executor-lock.ps1'
$LogFile = Join-Path $Deploy 'auto-limpeza-ram.log'
$LiveLog = Join-Path $Root '.claude\bora-live.log'

function Get-FreeMB {
  $os = Get-CimInstance Win32_OperatingSystem
  return [math]::Round($os.FreePhysicalMemory / 1024, 0)
}

function Log([string]$msg) {
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mode, $msg
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
  Write-Output $line
}

$ramBefore = Get-FreeMB
Log "inicio :: RAM livre = ${ramBefore}MB"

# Tier A -- zumbis claude/cmd/python da esteira Bora (delega no executor-lock.ps1 ja testado).
# LiveLog+StaleOutputMin (2026-07-13): PID vivo nao chega -- se o LIVELOG nao cresce ha
# >StaleOutputMin, o executor-lock.ps1 mata mesmo com CPU a saltitar (terminal preso numa
# pergunta/sugestao do proprio Claude Code, nunca respondida em modo headless).
$tierA = 'sem-lockfile'
if (Test-Path -LiteralPath $LockPs) {
  $tierA = & powershell -NoProfile -ExecutionPolicy Bypass -File $LockPs -Action cleanorphans -LockFile $LockFile -ProcOrphanMin $ZombieMin -LiveLog $LiveLog -StaleOutputMin $StaleOutputMin
}
Log "tierA (fingerprint claude/cmd/python, via executor-lock.ps1) :: $tierA"

# Tier B -- cmd/conhost/python verdadeiramente orfaos (processo pai ja morreu), parados ha
# mais de ZombieMin minutos. Nunca inclui 'claude' aqui.
$cutoff = (Get-Date).AddMinutes(-$ZombieMin)
$killedB = @()
foreach ($name in @('conhost', 'cmd', 'python')) {
  $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    try {
      if ($p.Id -eq $PID) { continue }
      if ($p.StartTime -gt $cutoff) { continue }
      $path = $p.Path
      if ($path -and $path -match 'WindowsApps\\Claude_') { continue }
      $cim = Get-CimInstance Win32_Process -Filter ("ProcessId=$($p.Id)") -ErrorAction SilentlyContinue
      if ($null -eq $cim) { continue }
      $parentAlive = $null -ne (Get-Process -Id $cim.ParentProcessId -ErrorAction SilentlyContinue)
      if ($parentAlive) { continue }
      $cpu1 = $p.CPU
      Start-Sleep -Milliseconds 800
      $p2 = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
      if ($null -eq $p2) { continue }
      if (($p2.CPU - $cpu1) -lt 0.05) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        $killedB += "$($p.Id):$name(pai-morto)"
      }
    } catch {}
  }
}
Log ("tierB (pai-morto cmd/conhost/python) :: " + $(if ($killedB.Count -gt 0) { $killedB -join ',' } else { 'nenhum' }))

$ramAfterKill = Get-FreeMB
Log "RAM livre apos zumbis = ${ramAfterKill}MB"

# Modo agressivo -- so se RAM continuar critica apos matar zumbis. Limpeza de disco (temp),
# nunca toca bora_app/Documents/produtividade-ia/config (lista NAO APAGA NUNCA do limpeza-pc).
# So apaga temp com mais de TempAgeMin (default 15min) -- um Remove-Item "$env:TEMP\*" cego
# apanha ficheiros que o proprio Claude Code ativo esta a usar nesse instante (task outputs,
# etc.) e parte a ferramenta a meio (visto ao vivo no teste 2026-07-13: apagou o output file
# desta mesma chamada). Ficheiro velho = seguro; ficheiro dos ultimos minutos = pode estar em uso.
if ($ramAfterKill -lt $LowRamMB) {
  Log "RAM CRITICA (< ${LowRamMB}MB) -- limpeza agressiva de temp (so ficheiros com >$TempAgeMin min)"
  $tempCutoff = (Get-Date).AddMinutes(-$TempAgeMin)
  foreach ($tempDir in @($env:TEMP, 'C:\Windows\Temp')) {
    if (-not (Test-Path -LiteralPath $tempDir)) { continue }
    Get-ChildItem -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -lt $tempCutoff } |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$ramFinal = Get-FreeMB
$ganho = $ramFinal - $ramBefore
Log "fim :: RAM livre = ${ramFinal}MB (delta ${ganho}MB)"
Write-Output "RESUMO auto-limpeza-ram :: antes=${ramBefore}MB depois=${ramFinal}MB delta=${ganho}MB"
