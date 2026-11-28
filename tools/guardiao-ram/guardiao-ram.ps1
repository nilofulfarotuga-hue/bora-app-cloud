# guardiao-ram.ps1 -- vigia a memoria do PC e age ANTES de o PC travar.
#
# Escrito 2026-11-28 (missao pc-sem-travar, run_id pc-sem-travar-2026-11-28).
# Corre pelo agendador (tarefa "GuardiaoRAM") de 3 em 3 minutos, escondido.
#
# NIVEIS (medidos com o contador de memoria do Windows, "Available", nao "Free"):
#   VERDE    livre > 4 GB e commit < 80%   -> so regista
#   AMARELO  livre < 3 GB ou commit > 85%  -> fecha o que esta parado e nao serve:
#            processos orfaos (node/claude/bash/cmd cujo pai ja morreu, parados 15 min),
#            daemons do Gradle e do Kotlin parados 10 min, servidor de analise do Dart
#            parado 30 min, emulador Android com o ecra a dormir ha 30 min e sem build.
#   VERMELHO livre < 1,5 GB ou commit > 92% -> tudo o do amarelo e ainda:
#            claude.exe (Claude Code, nunca a app Claude Desktop) com mais de 4 GB de
#            memoria privada e parado 20 min = fuga de memoria -> termina-o
#            (a sessao retoma com "claude --resume");
#            sessao do Claude Code parada ha 12 h ou mais -> termina-a (idem);
#            UM aviso ao Danilo pelo porteiro do Telegram (texto + voz), no maximo
#            1 a cada 30 min, e so quando o vermelho e novo, quando fechou alguma coisa,
#            ou de 3 em 3 horas se continuar vermelho.
#            "Fechou alguma coisa" = 300 MB ou mais (um orfao de 18 MB nao merece aviso).
#   Entre 3 e 4 GB livres conta como VERDE (so regista).
#
# NUNCA TOCA: a app Claude Desktop (ponte da Claude.ai), os ouvintes "remote-control",
# sessoes com actividade (CPU a mexer) nos ultimos 15 min, o Chrome, o WhatsApp,
# servidor_cerebro.py, motor-bora, ponte do Dipsy, nem nada que nao esteja nas regras acima.
#
# "Parado" = o processo gastou menos de 2 s de CPU desde que comecou a ser vigiado nesse
# estado. O guardiao guarda isto em estado.json entre corridas.
#
# MODOS
#   -DryRun                 mede e diz o que faria, nao mata nada, nao avisa, nao grava estado
#   -ForcarNivel VERMELHO   finge esse nivel (para provar as regras)
#   -ResumoDiario           grava ja o resumo do dia no e2e_log
#   -SemAviso               nunca manda Telegram
#
# SO ASCII NESTE FICHEIRO (o Windows PowerShell 5.1 le .ps1 sem BOM como ANSI).

param(
    [switch]$DryRun,
    [ValidateSet('', 'VERDE', 'AMARELO', 'VERMELHO')][string]$ForcarNivel = '',
    [switch]$ResumoDiario,
    [switch]$SemAviso,
    [int]$FecharParadasHoras = 12
)

$ErrorActionPreference = 'Continue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$logF = Join-Path $base 'log.txt'
$estadoF = Join-Path $base 'estado.json'
$cfg = $null
try { $cfg = Get-Content (Join-Path $base 'config.json') -Raw | ConvertFrom-Json } catch {}

# letras com acento sem as escrever no ficheiro (ver nota ASCII acima)
$a_ = [char]0xE1; $o_ = [char]0xF3; $c_ = [char]0xE7; $at = [char]0xE3; $e_ = [char]0xE9

$agora = Get-Date
$acoes = New-Object System.Collections.ArrayList
$fechados = 0
$mbFechados = 0

function Diz($m) {
    try {
        if ((Test-Path $logF) -and ((Get-Item $logF).Length -gt 1MB)) {
            Move-Item $logF (Join-Path $base 'log.1.txt') -Force
        }
        $pre = if ($DryRun) { '[DRY] ' } else { '' }
        Add-Content -LiteralPath $logF -Value ("[{0}] {1}{2}" -f $agora.ToString('yyyy-MM-dd HH:mm:ss'), $pre, $m) -Encoding UTF8
    } catch {}
}

function Medir {
    $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    [pscustomobject]@{
        LivreMB  = [int]$m.AvailableMBytes
        CommitMB = [int]($m.CommittedBytes / 1MB)
        LimiteMB = [int]($m.CommitLimit / 1MB)
        CommitPct = [int]$m.PercentCommittedBytesInUse
    }
}

# ---------- estado entre corridas ----------
$estado = $null
try { if (Test-Path $estadoF) { $estado = Get-Content $estadoF -Raw | ConvertFrom-Json } } catch {}
if (-not $estado) { $estado = [pscustomobject]@{} }
foreach ($campo in 'procs', 'ultimoAviso', 'vermelhoSeguidos', 'emuOciosoDesde', 'dia', 'conta', 'episodioAvisado') {
    if (-not ($estado.PSObject.Properties.Name -contains $campo)) { $estado | Add-Member -NotePropertyName $campo -NotePropertyValue $null }
}
if (-not $estado.procs) { $estado.procs = [pscustomobject]@{} }
if (-not $estado.conta) { $estado.conta = [pscustomobject]@{ VERDE = 0; AMARELO = 0; VERMELHO = 0; libertadoMB = 0; fechados = 0; avisos = 0; minLivreMB = 999999 } }

# ---------- fotografia dos processos ----------
$wmi = @(Get-CimInstance Win32_Process)
$ps = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) { $ps[[int]$p.Id] = $p }
$porId = @{}
foreach ($w in $wmi) { $porId[[int]$w.ProcessId] = $w }
$filhos = @{}
foreach ($w in $wmi) {
    $pp = [int]$w.ParentProcessId
    if (-not $filhos.ContainsKey($pp)) { $filhos[$pp] = New-Object System.Collections.ArrayList }
    [void]$filhos[$pp].Add([int]$w.ProcessId)
}

function Inicio($id) { try { return $ps[$id].StartTime } catch { return $null } }
function Cpu($id) { try { return [double]$ps[$id].CPU } catch { return 0 } }
function PrivMB($id) { try { return [int]($ps[$id].PrivateMemorySize64 / 1MB) } catch { return 0 } }
function Chave($id) { $s = Inicio $id; if ($s) { return "$id-" + $s.Ticks } else { return "$id-0" } }

# minutos que o processo esta parado (menos de 2 s de CPU desde a marca)
$novosProcs = [pscustomobject]@{}
function Parado($id) {
    $k = Chave $id
    $cpu = Cpu $id
    $marca = $estado.procs.$k
    if ($marca -and (($cpu - [double]$marca.cpu) -lt 2)) {
        $desde = [datetime]$marca.desde
    } else {
        $desde = $agora
        $marca = [pscustomobject]@{ cpu = $cpu; desde = $agora.ToString('o') }
    }
    if (-not ($novosProcs.PSObject.Properties.Name -contains $k)) {
        $novosProcs | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]@{ cpu = $marca.cpu; desde = ([datetime]$desde).ToString('o') })
    }
    return [int](($agora - [datetime]$desde).TotalMinutes)
}

function Arvore($id) {
    $lista = New-Object System.Collections.ArrayList
    $fila = New-Object System.Collections.Queue
    $fila.Enqueue($id)
    while ($fila.Count -gt 0) {
        $x = $fila.Dequeue()
        [void]$lista.Add($x)
        if ($filhos.ContainsKey($x)) { foreach ($f in $filhos[$x]) { if (-not $lista.Contains($f)) { $fila.Enqueue($f) } } }
    }
    return $lista
}

$protegido = 'servidor_cerebro|motor-bora|whatsapp|\\\.dsh\\|ponte\.py|proxy\.py|remote-control|guardiao-ram|WindowsApps\\Claude_|chrome\.exe|tailscale'

function EhClaudeCode($w) { return ($w.Name -eq 'claude.exe' -and $w.CommandLine -match '@anthropic-ai\\claude-code') }

function Fechar($id, $porque) {
    $w = $porId[$id]
    $mb = 0
    foreach ($x in (Arvore $id)) { $mb += (PrivMB $x) }
    $linha = "{0} pid={1} ({2} MB) - {3}" -f $w.Name, $id, $mb, $porque
    if ($DryRun) {
        [void]$acoes.Add("fecharia $linha")
    } else {
        & taskkill.exe /T /F /PID $id 2>&1 | Out-Null
        [void]$acoes.Add("fechei $linha")
        $script:fechados++
        $script:mbFechados += $mb
    }
}

# ---------- medir e decidir o nivel ----------
$antes = Medir
$nivel = 'VERDE'
if ($antes.LivreMB -lt 3072 -or $antes.CommitPct -gt 85) { $nivel = 'AMARELO' }
if ($antes.LivreMB -lt 1536 -or $antes.CommitPct -gt 92) { $nivel = 'VERMELHO' }
if ($ForcarNivel) { $nivel = $ForcarNivel }

# a vigia de "parado" corre sempre, para que o amarelo/vermelho ja tenham historico
$candidatos = $wmi | Where-Object { $_.Name -in 'node.exe', 'claude.exe', 'bash.exe', 'cmd.exe', 'java.exe', 'dart.exe', 'dartaotruntime.exe' }
foreach ($w in $candidatos) { [void](Parado ([int]$w.ProcessId)) }

if ($nivel -in 'AMARELO', 'VERMELHO') {
    # 1) orfaos: o pai ja morreu (ou o PID foi reaproveitado por outro mais novo)
    foreach ($w in ($wmi | Where-Object { $_.Name -in 'node.exe', 'claude.exe', 'bash.exe', 'cmd.exe' })) {
        $id = [int]$w.ProcessId
        if ($w.Name -eq 'claude.exe' -and -not (EhClaudeCode $w)) { continue }
        $pai = $porId[[int]$w.ParentProcessId]
        $orfao = (-not $pai)
        if ($pai -and (Inicio ([int]$pai.ProcessId)) -and (Inicio $id) -and ((Inicio ([int]$pai.ProcessId)) -gt (Inicio $id))) { $orfao = $true }
        if (-not $orfao) { continue }
        $arv = Arvore $id
        $linhas = ($arv | ForEach-Object { $porId[$_].CommandLine }) -join ' '
        if ($linhas -match $protegido) { continue }
        $min = 99999
        foreach ($x in $arv) { if ($porId[$x] -and $porId[$x].Name -ne 'conhost.exe') { $min = [Math]::Min($min, (Parado $x)) } }
        if ($min -ge 15) { Fechar $id "orfao parado ha $min min" }
    }

    # 2) daemons do Gradle/Kotlin e servidor do Dart parados
    foreach ($w in ($wmi | Where-Object { $_.Name -eq 'java.exe' -and $_.CommandLine -match 'GradleDaemon|KotlinCompileDaemon' })) {
        $min = Parado ([int]$w.ProcessId)
        if ($min -ge 10) { Fechar ([int]$w.ProcessId) "daemon Gradle/Kotlin parado ha $min min" }
    }
    foreach ($w in ($wmi | Where-Object { $_.Name -in 'dart.exe', 'dartaotruntime.exe' -and $_.CommandLine -match 'language-server|analysis_server' })) {
        $min = Parado ([int]$w.ProcessId)
        if ($min -ge 30) { Fechar ([int]$w.ProcessId) "servidor de analise do Dart parado ha $min min" }
    }

    # 3) emulador: desliga se o ecra dele dorme ha 30 min e nao ha build a correr
    $emu = $wmi | Where-Object { $_.Name -like 'qemu-system*' }
    $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if ($emu -and (Test-Path $adb)) {
        $build = $wmi | Where-Object { ($_.Name -eq 'java.exe' -and $_.CommandLine -match 'GradleDaemon|GradleWrapperMain|GradleMain') -or ($_.CommandLine -match 'flutter_tools|flutter\.bat"? (run|test|drive|build)') }
        $acordado = $true
        try {
            $pw = & $adb -e shell dumpsys power 2>$null | Select-String 'mWakefulness='
            if ($pw -and ($pw.ToString() -match 'Asleep|Dozing')) { $acordado = $false }
        } catch {}
        if ($acordado -or $build) {
            $estado.emuOciosoDesde = $null
        } else {
            if (-not $estado.emuOciosoDesde) { $estado.emuOciosoDesde = $agora.ToString('o') }
            $minE = [int](($agora - [datetime]$estado.emuOciosoDesde).TotalMinutes)
            if ($minE -ge 30) {
                if ($DryRun) { [void]$acoes.Add("desligaria o emulador (ecra a dormir ha $minE min)") }
                else { & $adb -e emu kill 2>&1 | Out-Null; [void]$acoes.Add("desliguei o emulador (ecra a dormir ha $minE min)"); $fechados++; $estado.emuOciosoDesde = $null }
            }
        }
    } else { $estado.emuOciosoDesde = $null }
}

if ($nivel -eq 'VERMELHO') {
    # 4) fuga de memoria do Claude Code e sessoes paradas ha muitas horas
    foreach ($w in ($wmi | Where-Object { EhClaudeCode $_ })) {
        if ($w.CommandLine -match 'remote-control') { continue }
        $id = [int]$w.ProcessId
        $min = Parado $id
        $mb = PrivMB $id
        if ($mb -ge 4096 -and $min -ge 20) { Fechar $id "fuga de memoria: $mb MB e parado ha $min min (retoma com claude --resume)"; continue }
        if ($FecharParadasHoras -gt 0 -and $min -ge ($FecharParadasHoras * 60)) { Fechar $id "sessao parada ha $([int]($min/60)) h (retoma com claude --resume)" }
    }
}

# ---------- medir de novo ----------
if ($fechados -gt 0) { Start-Sleep -Seconds 3 }
$depois = Medir
$libertou = 0
if ($fechados -gt 0) { $libertou = [Math]::Max(0, $depois.LivreMB - $antes.LivreMB) }

# quem mais come (para o registo e o aviso), com nomes que o Danilo reconhece
$nomes = @{ claude = 'Claude'; chrome = 'Chrome'; node = 'ajudantes do Claude'; ChatGPT = 'ChatGPT'; svchost = 'Windows'; qemu = 'emulador'; java = 'Gradle'; MsMpEng = 'antivirus do Windows'; 'mc-fw-host' = 'McAfee' }
$grupos = Get-Process -ErrorAction SilentlyContinue | Group-Object { ($_.Name -replace '^qemu-system.*', 'qemu') } | ForEach-Object {
    $n = $_.Name; if ($nomes.ContainsKey($n)) { $n = $nomes[$n] }
    [pscustomobject]@{ N = $n; MB = [int](($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB) }
} | Sort-Object MB -Descending | Select-Object -First 4
$top = ($grupos | ForEach-Object { "{0} {1:N1} GB" -f $_.N, ($_.MB / 1024) }) -join ', '

$resumoAcoes = if ($acoes.Count) { $acoes -join ' ; ' } else { 'nada a fazer' }
Diz ("{0} livre={1}MB commit={2}% ({3}/{4}MB) | {5} | libertou={6}MB | top: {7}" -f $nivel, $antes.LivreMB, $antes.CommitPct, $antes.CommitMB, $antes.LimiteMB, $resumoAcoes, $libertou, $top)

# ---------- aviso ao Danilo (so no vermelho real) ----------
if ($nivel -eq 'VERMELHO') { $estado.vermelhoSeguidos = 1 + [int]$estado.vermelhoSeguidos } else { $estado.vermelhoSeguidos = 0; $estado.episodioAvisado = $false }

$desdeAviso = 99999
if ($estado.ultimoAviso) { $desdeAviso = [int](($agora - [datetime]$estado.ultimoAviso).TotalMinutes) }
$querAvisar = ($nivel -eq 'VERMELHO') -and ([int]$estado.vermelhoSeguidos -ge 2 -or $ForcarNivel) -and ($desdeAviso -ge 30) -and
              ((-not $estado.episodioAvisado) -or ($mbFechados -ge 300) -or ($desdeAviso -ge 180))

if ($querAvisar -and -not $SemAviso) {
    $feito = if ($acoes.Count) { "Fiz isto: " + (($acoes | ForEach-Object { ($_ -replace ' pid=\d+', '') -replace ' - ', ', ' }) -join '; ') + "." } else { "N${at}o havia nada parado para fechar, por isso n${at}o mexi em nada." }
    $msg = "Guardi${at}o da RAM: o PC est${a_} com pouca mem${o_}ria, s${o_} {0:N1} GB livres. Quem mais come: {1}. {2} Se continuar assim, fecha separadores do Chrome que n${at}o est${a_}s a usar." -f ($depois.LivreMB / 1024), $top, $feito
    if ($DryRun) {
        Diz "avisaria o Danilo: $msg"
    } else {
        $ok = $false
        try {
            if ($cfg -and (Test-Path $cfg.bash) -and (Test-Path $cfg.ponte_telegram)) {
                $saida = & $cfg.bash $cfg.ponte_telegram $msg 2>&1 | Out-String
                if ($saida -match 'texto: enviado') { $ok = $true }
                Diz ("aviso pela ponte do porteiro: " + (($saida -replace '\s+', ' ').Trim()))
            }
            if (-not $ok -and $cfg -and (Test-Path $cfg.gritar_do_pc)) {
                $saida = & $cfg.bash $cfg.gritar_do_pc $msg 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0) { $ok = $true }
                Diz ("aviso direto do PC (reserva): " + (($saida -replace '\s+', ' ').Trim()))
            }
        } catch { Diz "aviso falhou: $($_.Exception.Message)" }
        if ($ok) { $estado.ultimoAviso = $agora.ToString('o'); $estado.episodioAvisado = $true; $estado.conta.avisos = 1 + [int]$estado.conta.avisos }
    }
}

# ---------- resumo diario no e2e_log ----------
function GravarE2E($passo, $estadoTxt, $detalhe) {
    if (-not $cfg) { return $false }
    $corpo = @{ fluxo = 'guardiao-ram'; passo = $passo; estado = $estadoTxt; detalhe = $detalhe; device = 'pc-danilo'; run_id = 'guardiao-ram' } | ConvertTo-Json -Compress
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($cfg.supabase_url + '/rest/v1/e2e_log') -TimeoutSec 20 `
            -Headers @{ apikey = $cfg.publica; Prefer = 'return=minimal' } -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($corpo))
        return ($r.StatusCode -eq 201)
    } catch { Diz "e2e_log falhou: $($_.Exception.Message)"; return $false }
}

$hoje = $agora.ToString('yyyy-MM-dd')
$c = $estado.conta
if (-not $DryRun) {
    if ($estado.dia -and $estado.dia -ne $hoje) {
        $det = "Dia {0}: verde={1} amarelo={2} vermelho={3} corridas; menor livre={4} MB; fechados={5}; avisos={6}." -f $estado.dia, $c.VERDE, $c.AMARELO, $c.VERMELHO, $c.minLivreMB, $c.fechados, $c.avisos
        if (GravarE2E 'resumo-diario' 'ok' $det) { Diz "resumo do dia gravado no e2e_log" }
        $estado.conta = [pscustomobject]@{ VERDE = 0; AMARELO = 0; VERMELHO = 0; libertadoMB = 0; fechados = 0; avisos = 0; minLivreMB = 999999 }
        $c = $estado.conta
    }
    $estado.dia = $hoje
    if (-not $ForcarNivel) { $c.$nivel = 1 + [int]$c.$nivel }
    $c.fechados = [int]$c.fechados + $fechados
    $c.libertadoMB = [int]$c.libertadoMB + $libertou
    $c.minLivreMB = [Math]::Min([int]$c.minLivreMB, $antes.LivreMB)
    if ($ResumoDiario) {
        $det = "Ate agora em {0}: verde={1} amarelo={2} vermelho={3} corridas; menor livre={4} MB; fechados={5}; avisos={6}; agora livre={7} MB, commit {8}%." -f $hoje, $c.VERDE, $c.AMARELO, $c.VERMELHO, $c.minLivreMB, $c.fechados, $c.avisos, $depois.LivreMB, $depois.CommitPct
        if (GravarE2E 'resumo-diario' 'ok' $det) { Diz "resumo pedido gravado no e2e_log" }
    }
    $estado.procs = $novosProcs
    try { $estado | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $estadoF -Encoding UTF8 } catch { Diz "nao gravei o estado: $($_.Exception.Message)" }
}
exit 0
