param(
  [Parameter(Mandatory=$true)][ValidateSet('acquire','release','cleanorphans')][string]$Action,
  [string]$LockFile = '',
  [int]$OwnerPid = 0,
  [int]$MaxWaitSec = 480,
  [int]$PollSec = 5,
  [int]$LockOrphanMin = 10,
  [int]$ProcOrphanMin = 10,
  [string]$LiveLog = '',
  [int]$StaleOutputMin = 15
)
# executor-lock.ps1 -- CURA DA RAIZ DOS TRAVAMENTOS (2026-07-13, ordem 4833).
# So 1 claude.exe executor de cada vez: lock em ficheiro (PID+timestamp). Lock orfao
# (PID morto OU idade > LockOrphanMin, default 10min) e assumido na hora, sem esperar. cleanorphans mata
# processos claude/cmd/python presos (~0% CPU ha >ProcOrphanMin) MAS so os que tem a
# impressao digital da esteira Bora na linha de comando -- nunca sessoes interativas do
# Danilo nem daemons do heartbeat-desktop. Ver .claude/.ai/knowledge/inbox/lock-concorrencia-2026-07-13.md
#
# ACHADO 2026-07-13 (Danilo): PID vivo != executor a trabalhar. Um terminal pode ficar VIVO
# para sempre a espera que o Danilo clique numa sugestao/pergunta que o proprio Claude Code fez
# (ex.: "How is Claude doing?") -- isso NAO aparece como PID morto, e a amostra de CPU de 1s do
# cleanorphans pode falhar (ruido). Sinal mais direto: o LIVELOG (stream-json parseado) para de
# CRESCER quando o executor para de produzir output, mesmo que o processo continue vivo. Por
# isso cleanorphans agora tambem mata se o LIVELOG nao tiver escrita nova ha > StaleOutputMin
# (default 15min) -- independente da amostra de CPU. Ver .claude/.ai/knowledge/inbox/
# disco-e-deteccao-preso-2026-07-13.md.
#
# FASE 1.8 (2026-07-14, lock orfao definitivo): a checagem "PID vivo?" sozinha NAO chega --
# o Windows RECICLA numeros de PID. Se o dono do lock morre e minutos/horas depois o SO da
# esse mesmo numero a outro processo qualquer (ja visto no .loop-noturno.lock do E2E, ver
# .claude/.ai/knowledge/inbox e memoria project_e2e_loop_ram_stall.md), Get-Process -Id
# devolve "vivo" para sempre e o lock NUNCA mais e considerado orfao -- foi o que travou a
# fila 2x no mesmo dia (PID 14592 e 8172, ambos na verdade mortos). Fix: o lock agora grava
# tambem o start-time (epoch) do processo dono; a validacao exige PID vivo E start-time igual
# -- discrepancia = PID reciclado = orfao IMEDIATO, sem esperar tolerancia nenhuma.
$ErrorActionPreference = 'SilentlyContinue'

function Now-Epoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Read-Lock([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-ProcStartEpoch([int]$processId) {
  if ($processId -le 0) { return $null }
  $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if ($null -eq $p) { return $null }
  try { return [int64][DateTimeOffset]::new($p.StartTime.ToUniversalTime()).ToUnixTimeSeconds() } catch { return $null }
}

function Write-Lock([string]$path, [int]$pid_, [long]$ts) {
  $startEpoch = Get-ProcStartEpoch $pid_
  $obj = [pscustomobject]@{ pid = $pid_; ts = $ts; start = $startEpoch }
  ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
}

# Confirma que o dono gravado no lock e REALMENTE o mesmo processo -- nao so um PID vivo
# qualquer que por acaso calhou no mesmo numero (reciclagem de PID pelo Windows). Locks
# escritos por uma versao anterior deste script (sem campo "start") sao tratados so pela
# existencia do PID, para nao quebrar um lock legitimo a meio de um deploy.
function Test-LockAlive($info) {
  if ($null -eq $info) { return $false }
  $curStart = Get-ProcStartEpoch ([int]$info.pid)
  if ($null -eq $curStart) { return $false }
  $hasStart = ($info.PSObject.Properties.Name -contains 'start') -and (-not [string]::IsNullOrWhiteSpace($info.start))
  if (-not $hasStart) { return $true }
  return ([int64]$curStart -eq [int64]$info.start)
}

# Arvore de processos (root + descendentes) do dono do lock atual -- usado por cleanorphans
# para NUNCA matar o executor ativo (o claude.exe legitimo fica a 0% CPU durante segundos
# enquanto espera resposta da API; sem esta protecao, uma tarefa >10min seria apanhada como
# "orfa" e morta por engano por OUTRA invocacao do loop, recriando o mesmo travamento).
function Get-ProcessTree([int]$rootPid) {
  $all = @{ $rootPid = $true }
  $frontier = @($rootPid)
  $depth = 0
  while ($frontier.Count -gt 0 -and $depth -lt 6) {
    $next = @()
    foreach ($ppid in $frontier) {
      $children = Get-CimInstance Win32_Process -Filter ("ParentProcessId=$ppid") -ErrorAction SilentlyContinue
      foreach ($c in $children) {
        $cid = [int]$c.ProcessId
        if (-not $all.ContainsKey($cid)) { $all[$cid] = $true; $next += $cid }
      }
    }
    $frontier = $next
    $depth++
  }
  return $all.Keys
}

switch ($Action) {

  'acquire' {
    if ([string]::IsNullOrWhiteSpace($LockFile) -or $OwnerPid -le 0) { Write-Output 'ERRO-PARAM'; break }
    $waited = 0
    while ($true) {
      $info = Read-Lock $LockFile
      if ($null -eq $info) {
        Write-Lock $LockFile $OwnerPid (Now-Epoch)
        Write-Output 'ACQUIRED'
        break
      }
      $age = (Now-Epoch) - [int64]$info.ts
      $alive = Test-LockAlive $info
      if ((-not $alive) -or ($age -gt ($LockOrphanMin * 60))) {
        Write-Output "[loop-lock] lock orfao assumido (pid_anterior=$($info.pid) vivo=$alive idade_s=$age)"
        Write-Lock $LockFile $OwnerPid (Now-Epoch)
        Write-Output 'ACQUIRED'
        break
      }
      if ($waited -eq 0) {
        Write-Output "[loop-lock] outro executor a correr (pid=$($info.pid) idade_s=$age) - a espera"
      }
      if ($waited -ge $MaxWaitSec) {
        Write-Output 'TIMEOUT'
        break
      }
      Start-Sleep -Seconds $PollSec
      $waited += $PollSec
    }
  }

  'release' {
    $info = Read-Lock $LockFile
    if ($null -ne $info -and [int]$info.pid -eq $OwnerPid) {
      Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
      Write-Output 'RELEASED'
    } else {
      Write-Output 'SKIP-NOT-OWNER'
    }
  }

  'cleanorphans' {
    $fingerprint = 'loop autonomo do Bora|CLAUDE-JUIZ de qualidade do Bora|bora_loop_task|bora_judge_task|run-claude-loop\.cmd|run-claude-judge\.cmd'
    $cutoff = (Get-Date).AddMinutes(-$ProcOrphanMin)
    $protected = @{}
    if (-not [string]::IsNullOrWhiteSpace($LockFile)) {
      $lockInfo = Read-Lock $LockFile
      if ($null -ne $lockInfo) {
        $lockAge = (Now-Epoch) - [int64]$lockInfo.ts
        if ((Test-LockAlive $lockInfo) -and ($lockAge -le ($LockOrphanMin * 60))) {
          foreach ($treePid in (Get-ProcessTree ([int]$lockInfo.pid))) { $protected[$treePid] = $true }
        }
      }
    }
    # Limpeza preventiva do proprio executor.lock -- corre no INICIO de cada ciclo (antes do
    # 'acquire'), para nunca depender so do proximo 'acquire' reparar um lock orfao (PID morto
    # OU PID reciclado pelo Windows, fingerprint start-time nao bate). Log explicito para o
    # LIVELOG mostrar sempre que isto aconteceu.
    if (-not [string]::IsNullOrWhiteSpace($LockFile) -and (Test-Path -LiteralPath $LockFile)) {
      $preInfo = Read-Lock $LockFile
      if ($null -ne $preInfo -and -not (Test-LockAlive $preInfo)) {
        Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
        Write-Output "[loop-lock] limpeza preventiva: executor.lock orfao removido no arranque do ciclo (pid_anterior=$($preInfo.pid))"
      }
    }
    # Sinal de "preso": LIVELOG (stream-json em texto) sem escrita nova ha > StaleOutputMin.
    # Vale para TODO o ciclo (1 executor, 1 log) -- por isso e calculado uma vez, fora do loop
    # de processos. PID vivo + CPU a saltitar nao prova progresso; o log parado prova estagnacao.
    $outputStale = $false
    if (-not [string]::IsNullOrWhiteSpace($LiveLog) -and (Test-Path -LiteralPath $LiveLog)) {
      $lastWrite = (Get-Item -LiteralPath $LiveLog -ErrorAction SilentlyContinue).LastWriteTime
      if ($null -ne $lastWrite -and $lastWrite -lt (Get-Date).AddMinutes(-$StaleOutputMin)) { $outputStale = $true }
    }
    $killed = @()
    foreach ($name in @('claude','cmd','python')) {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
      foreach ($p in $procs) {
        if ($p.Id -eq $PID) { continue }
        if ($p.StartTime -gt $cutoff) { continue }
        # protegido normalmente escapa a limpeza -- exceto se o output ja provou estagnacao
        # (PRESO-VIVO: aparenta "executor ativo" pelo lock, mas nao produz output ha 15min+).
        if ($protected.ContainsKey($p.Id) -and -not $outputStale) { continue }
        try {
          $cim = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $p.Id) -ErrorAction SilentlyContinue
          if ($null -eq $cim -or [string]::IsNullOrEmpty($cim.CommandLine) -or $cim.CommandLine -notmatch $fingerprint) { continue }
          $cpu1 = $p.CPU
          Start-Sleep -Milliseconds 1000
          $p2 = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
          if ($null -eq $p2) { continue }
          $idleCpu = ($p2.CPU - $cpu1) -lt 0.05
          if ($idleCpu -or $outputStale) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $reason = if ($outputStale -and -not $idleCpu) { 'preso-vivo:output-stale' } elseif ($outputStale) { 'idle+output-stale' } else { 'idle-cpu' }
            $killed += "$($p.Id):$name($reason)"
          }
        } catch {}
      }
    }
    if ($killed.Count -gt 0) { Write-Output ('KILLED:' + ($killed -join ',')) } else { Write-Output 'KILLED:none' }
  }
}
