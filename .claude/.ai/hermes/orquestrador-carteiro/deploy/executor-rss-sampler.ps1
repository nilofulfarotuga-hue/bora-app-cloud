<#
  executor-rss-sampler.ps1 -- mede o PICO REAL de memoria de um executor do loop.

  PORQUE: o pre-voo de RAM (ram-preflight.ps1) precisa de saber quanto pesa mesmo um executor.
  Ate 2026-08-01 o limiar era um numero inventado (800 MB de "free") que nunca correspondeu a
  medicao nenhuma -- e recusava a maquina em condicoes em que o trabalho estava a correr. Este
  sampler corre EM PARALELO ao claude.exe do executor (tal como o stale-output-watchdog.ps1),
  segue a arvore de processos a partir do cmd.exe dono do ciclo, e grava uma linha por execucao em
  .claude/executor-rss.csv. A partir da 1a linha o limiar deixa de ser opiniao e passa a ser dado.

  MEDE DUAS COISAS DIFERENTES, DE PROPOSITO:
   * peak_ws_mb      -- PeakWorkingSet64: pico de RAM FISICA que o processo chegou a ter residente.
                        E' o numero que responde a "quanta memoria fisica isto quer".
   * peak_private_mb -- maximo amostrado de PrivateMemorySize64: quanto COMMIT o processo reservou.
                        E' o numero que responde a "isto cabe no commit limit?" -- a pergunta que
                        decide se a alocacao FALHA (ver cabecalho do ram-preflight.ps1).
  O Windows mantem o pico de working set sozinho (exacto); private bytes nao tem pico nativo, por
  isso e' amostrado -- com -PollSeconds 3 o erro e' pequeno e sempre por defeito (nunca inflaciona).

  COMO DISTINGUE O EXECUTOR DAS SESSOES DO DANILO
  ----------------------------------------------
  Por LINHA DE COMANDO, nao por arvore de processos. A 1a versao seguia descendentes de -RootPid
  (%MYPID% do .cmd) e nunca gravou nada: em cmd.exe, `for /f ('comando')` corre o comando num
  cmd.exe INTERMEDIO (%COMSPEC% /c), logo o ParentProcessId que o powershell ve e' esse cmd.exe
  transitorio -- que morre no instante seguinte. %MYPID% nao e' o dono do ciclo, e a arvore a
  partir dele esta vazia. (Nao mexo no calculo de %MYPID%: ele e' tambem o dono do executor.lock e
  isso esta fora do ambito desta correcao -- fica registado aqui como divergencia conhecida.)
  O executor e' identificado por dois marcadores que so ele tem: `--append-system-prompt` (o GUARD
  do loop) e `--max-budget-usd`. As sessoes interactivas do Danilo nao os levam, e o Claude Desktop
  (Electron, tambem chamado Claude.exe) e' excluido pelo caminho \Claude\claude-code\ -- misturar
  os dois foi o que fez o numero de 2026-08-01 parecer 1002 MB quando esse pico era de um renderer
  do Desktop, nao de um executor. Filtro adicional: so processos nascidos DEPOIS deste sampler
  arrancar (janela de 60s), para nunca medir um executor de outro ciclo.
#>
[CmdletBinding()]
param(
  # Mantido por compatibilidade com a chamada do run-claude-loop.cmd; NAO e' usado como filtro
  # (ver cabecalho: %MYPID% aponta para o cmd.exe transitorio do `for /f`).
  [int]$RootPid = 0,
  [string]$CsvPath = "$PSScriptRoot\..\..\..\..\executor-rss.csv",
  [int]$PollSeconds = 3,
  [int]$HardCeilingMinutes = 260,
  [string]$Tag = '',
  # Ficheiro de estado reescrito a CADA amostra com o pico corrente ("ws,private,dur").
  # PORQUE existe: o sampler e' lancado com `start /B` a partir de um .cmd que corre por SSH; quando
  # o comando remoto termina, o OpenSSH do Windows mata a arvore de processos e o sampler NUNCA
  # chegava ao fim para escrever o CSV (2 corridas reais, 0 linhas gravadas, log vazio). Agora quem
  # grava a linha final e' o proprio run-claude-loop.cmd, que e' sincrono e chega sempre ao fim --
  # o sampler so tem de deixar o numero mais recente aqui.
  [string]$StateFile = "$env:TEMP\bora_rss_current.txt"
)

$ErrorActionPreference = 'SilentlyContinue'

$peakWs = 0; $peakPriv = 0; $vistos = 0; $ausencias = 0
$deadline = (Get-Date).AddMinutes($HardCeilingMinutes)
$inicio = Get-Date
$janela = $inicio.AddSeconds(-60)   # so executores nascidos nesta janela contam

while ((Get-Date) -lt $deadline) {
  $cli = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
           Where-Object {
             $_.ExecutablePath -like '*\Claude\claude-code\*' -and
             $_.CommandLine -like '*--append-system-prompt*' -and
             $_.CommandLine -like '*--max-budget-usd*' -and
             $_.CreationDate -ge $janela
           })

  if ($cli.Count -gt 0) {
    $vistos = 1; $ausencias = 0
    foreach ($c in $cli) {
      $ps = Get-Process -Id ([int]$c.ProcessId) -ErrorAction SilentlyContinue
      if ($null -eq $ps) { continue }
      $ws = [int]($ps.PeakWorkingSet64 / 1MB)
      $pv = [int]($ps.PrivateMemorySize64 / 1MB)
      if ($ws -gt $peakWs)   { $peakWs = $ws }
      if ($pv -gt $peakPriv) { $peakPriv = $pv }
    }
    if ($peakWs -gt 0) {
      $d = [int]((Get-Date) - $inicio).TotalSeconds
      Set-Content -LiteralPath $StateFile -Value "$peakWs,$peakPriv,$d" -Encoding ASCII -ErrorAction SilentlyContinue
    }
  } elseif ($vistos -eq 1) {
    # ja tinha visto o executor e agora desapareceu -> acabou. 2 ausencias seguidas para nao
    # fechar num piscar de olhos entre o fim de um processo e o arranque do seguinte.
    $ausencias++
    if ($ausencias -ge 2) { break }
  } else {
    # ainda nao arrancou; desiste ao fim de 3min para nao ficar um sampler orfao para sempre.
    if (((Get-Date) - $inicio).TotalMinutes -gt 3) { break }
  }
  Start-Sleep -Seconds $PollSeconds
}

if ($vistos -eq 1 -and $peakWs -gt 0) {
  $dir = Split-Path -Parent $CsvPath
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (-not (Test-Path -LiteralPath $CsvPath)) {
    Set-Content -LiteralPath $CsvPath -Value 'ts,peak_ws_mb,peak_private_mb,dur_s,tag' -Encoding UTF8
  }
  $dur = [int]((Get-Date) - $inicio).TotalSeconds
  $ts  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Add-Content -LiteralPath $CsvPath -Value "$ts,$peakWs,$peakPriv,$dur,$Tag" -Encoding UTF8
  Write-Output "RSS-SAMPLER: peak_ws=${peakWs}MB peak_private=${peakPriv}MB dur=${dur}s -> $CsvPath"
} else {
  Write-Output "RSS-SAMPLER: nenhum claude.exe de executor observado (nada gravado)"
}
