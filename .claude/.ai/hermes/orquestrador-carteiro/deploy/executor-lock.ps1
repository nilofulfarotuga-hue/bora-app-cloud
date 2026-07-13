param(
  [Parameter(Mandatory=$true)][ValidateSet('acquire','release','cleanorphans')][string]$Action,
  [string]$LockFile = '',
  [int]$OwnerPid = 0,
  [int]$MaxWaitSec = 480,
  [int]$PollSec = 5,
  [int]$LockOrphanMin = 30,
  [int]$ProcOrphanMin = 10
)
# executor-lock.ps1 -- CURA DA RAIZ DOS TRAVAMENTOS (2026-07-13, ordem 4833).
# So 1 claude.exe executor de cada vez: lock em ficheiro (PID+timestamp). Lock orfao
# (PID morto OU idade > LockOrphanMin) e assumido na hora, sem esperar. cleanorphans mata
# processos claude/cmd/python presos (~0% CPU ha >ProcOrphanMin) MAS so os que tem a
# impressao digital da esteira Bora na linha de comando -- nunca sessoes interativas do
# Danilo nem daemons do heartbeat-desktop. Ver .claude/.ai/knowledge/inbox/lock-concorrencia-2026-07-13.md
$ErrorActionPreference = 'SilentlyContinue'

function Now-Epoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Read-Lock([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-Lock([string]$path, [int]$pid_, [long]$ts) {
  $obj = [pscustomobject]@{ pid = $pid_; ts = $ts }
  ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
}

function Is-Alive([int]$processId) {
  if ($processId -le 0) { return $false }
  return ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue))
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
      $alive = Is-Alive ([int]$info.pid)
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
        if ((Is-Alive ([int]$lockInfo.pid)) -and ($lockAge -le ($LockOrphanMin * 60))) {
          foreach ($treePid in (Get-ProcessTree ([int]$lockInfo.pid))) { $protected[$treePid] = $true }
        }
      }
    }
    $killed = @()
    foreach ($name in @('claude','cmd','python')) {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
      foreach ($p in $procs) {
        if ($p.Id -eq $PID) { continue }
        if ($protected.ContainsKey($p.Id)) { continue }
        if ($p.StartTime -gt $cutoff) { continue }
        try {
          $cim = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $p.Id) -ErrorAction SilentlyContinue
          if ($null -eq $cim -or [string]::IsNullOrEmpty($cim.CommandLine) -or $cim.CommandLine -notmatch $fingerprint) { continue }
          $cpu1 = $p.CPU
          Start-Sleep -Milliseconds 1000
          $p2 = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
          if ($null -eq $p2) { continue }
          if (($p2.CPU - $cpu1) -lt 0.05) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $killed += "$($p.Id):$name"
          }
        } catch {}
      }
    }
    if ($killed.Count -gt 0) { Write-Output ('KILLED:' + ($killed -join ',')) } else { Write-Output 'KILLED:none' }
  }
}
