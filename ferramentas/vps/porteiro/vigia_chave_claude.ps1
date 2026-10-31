# vigia_chave_claude.ps1 — missao motor-claude 31/10/2026 (caminho provado a 30/10 com o token do Dipsy).
# O Danilo cria a chave na Console (workspace "Robos Bora") e carrega em "Copy". Este vigia:
#   1) apanha da area de transferencia um texto sk-ant-api... ou sk-ant-usr... (a Console nova, desde
#      31/10/2026, da chaves ligadas a conta com o prefixo usr) — nunca o imprime nem o grava no PC;
#   2) valida-o com UMA chamada minima ao claude-haiku-5-5 (max_tokens 1);
#   3) grava-o na VPS por stdin (nunca na linha de comando): -Destino vps -> /opt/segredos/claude.env
#      (CLAUDE_ROBOS_API_KEY, lido pelo porteiro do Motor Bora, que e reiniciado); -Destino app ->
#      /opt/segredos/claude-app.env (ANTHROPIC_API_KEY, para o passo PUBLICAR o pôr nos segredos das Edge Functions);
#   4) limpa a area de transferencia.
# NUNCA poe ANTHROPIC_API_KEY nas variaveis do PC (partia o Claude Code do Danilo).
# Uso:  powershell -NoProfile -STA -File vigia_chave_claude.ps1 -Destino vps   [-Minutos 30]
param([ValidateSet('vps', 'app')][string]$Destino = 'vps', [int]$Minutos = 30)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$k = $null
$fim = (Get-Date).AddMinutes($Minutos)
while ((Get-Date) -lt $fim) {
    try { $t = [System.Windows.Forms.Clipboard]::GetText() } catch { $t = '' }
    if ($t -match '^\s*(sk-ant-(?:api|usr)\S{20,})\s*$') { $k = $Matches[1]; break }
    Start-Sleep -Seconds 2
}
if (-not $k) { Write-Output "sem chave na area de transferencia em $Minutos min"; exit 3 }
Write-Output ("chave apanhada (tamanho {0}); a validar com chamada minima" -f $k.Length)
$h = @{ 'x-api-key' = $k; 'anthropic-version' = '2023-06-01' }
# max_tokens 1024: o minimo que _shared/claude.ts usa para estes modelos (abaixo disso a API pode dar 400).
$b = '{"model":"claude-haiku-5-5","max_tokens":1024,"thinking":{"type":"disabled"},"output_config":{"effort":"low"},"messages":[{"role":"user","content":"ok"}]}'
$st = 0; $erro = ''
try {
    $r = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers $h -ContentType 'application/json' -Body $b -UseBasicParsing -TimeoutSec 30
    $st = [int]$r.StatusCode
} catch {
    if ($_.Exception.Response) {
        $st = [int]$_.Exception.Response.StatusCode
        try { $erro = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch { }
    } else { $st = -1; $erro = $_.Exception.Message }
}
Write-Output "validacao: HTTP $st"
if ($st -ne 200) {
    if ($erro) { Write-Output ('erro da API: ' + ($erro -replace 'sk-ant-\S+', '[chave]').Substring(0, [Math]::Min(300, $erro.Length))) }
    # So uma chave recusada (401/403) sai da area de transferencia; noutro erro fica la para tentar de novo.
    if ($st -eq 401 -or $st -eq 403) { [System.Windows.Forms.Clipboard]::Clear() }
    $k = $null; exit 4
}
if ($Destino -eq 'vps') { $var = 'CLAUDE_ROBOS_API_KEY'; $f = '/opt/segredos/claude.env' } else { $var = 'ANTHROPIC_API_KEY'; $f = '/opt/segredos/claude-app.env' }
$cmd = "umask 077; install -d -m 700 /opt/segredos; cat > $f.tmp && chmod 600 $f.tmp && mv $f.tmp $f && echo gravado $f com `$(wc -c < $f) bytes"
if ($Destino -eq 'vps') { $cmd += ' && systemctl restart motor-bora && sleep 8 && systemctl is-active motor-bora && curl -s http://127.0.0.1:8792/porteiro | head -c 300' }
("{0}={1}`n" -f $var, $k) | & ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -o BatchMode=yes root@srv1786862.hstgr.cloud $cmd
if ($Destino -eq 'app') {
    # 31/10/2026: tambem nos segredos das Edge Functions (o _shared/claude.ts le ANTHROPIC_API_KEY).
    # A CLI so aceita o valor na linha de comando ou num .env: vai num ficheiro de uma pasta nova do
    # %TEMP% do utilizador, que e esvaziado e apagado logo a seguir.
    $sb = Get-ChildItem "$env:LOCALAPPDATA\npm-cache\_npx\*\node_modules\@supabase\cli-windows-x64\bin\supabase.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $sb) { Write-Output 'sem CLI da Supabase: segredo das Edge Functions por pôr' }
    else {
        $dir = Join-Path $env:TEMP ('sb-segredo-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $tmp = Join-Path $dir 'claude.env'
        try {
            [IO.File]::WriteAllText($tmp, ("ANTHROPIC_API_KEY={0}`n" -f $k))
            & $sb secrets set --env-file $tmp --project-ref ojykpzwqrtusfeakzrna --agent no 2>&1 |
                ForEach-Object { "$_" -replace 'sk-ant-\S+', '[chave]' }
        } finally {
            if (Test-Path -LiteralPath $tmp) { [IO.File]::WriteAllText($tmp, ''); Remove-Item -LiteralPath $tmp -Force }
            Remove-Item -LiteralPath $dir -Force
        }
        Write-Output "ficheiro temporario apagado: $(-not (Test-Path -LiteralPath $dir))"
    }
}
[System.Windows.Forms.Clipboard]::Clear()
$k = $null
Write-Output 'area de transferencia limpa'
