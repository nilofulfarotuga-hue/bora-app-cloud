# vigia_chave_claude.ps1 — missao motor-claude 31/10/2026 (caminho provado a 30/10 com o token do Dipsy).
# O Danilo cria a chave na Console (workspace "Robos Bora") e carrega em "Copy". Este vigia:
#   1) apanha da area de transferencia um texto sk-ant-api... (nunca o imprime nem o grava no PC);
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
    if ($t -match '^\s*(sk-ant-api\S{20,})\s*$') { $k = $Matches[1]; break }
    Start-Sleep -Seconds 2
}
if (-not $k) { Write-Output "sem chave na area de transferencia em $Minutos min"; exit 3 }
Write-Output ("chave apanhada (tamanho {0}); a validar com chamada minima" -f $k.Length)
$h = @{ 'x-api-key' = $k; 'anthropic-version' = '2023-06-01' }
$b = '{"model":"claude-haiku-5-5","max_tokens":1,"thinking":{"type":"disabled"},"output_config":{"effort":"low"},"messages":[{"role":"user","content":"ok"}]}'
$st = 0
try {
    $r = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers $h -ContentType 'application/json' -Body $b -UseBasicParsing -TimeoutSec 30
    $st = [int]$r.StatusCode
} catch {
    if ($_.Exception.Response) { $st = [int]$_.Exception.Response.StatusCode } else { $st = -1 }
}
Write-Output "validacao: HTTP $st"
if ($st -ne 200) { [System.Windows.Forms.Clipboard]::Clear(); $k = $null; exit 4 }
if ($Destino -eq 'vps') { $var = 'CLAUDE_ROBOS_API_KEY'; $f = '/opt/segredos/claude.env' } else { $var = 'ANTHROPIC_API_KEY'; $f = '/opt/segredos/claude-app.env' }
$cmd = "umask 077; install -d -m 700 /opt/segredos; cat > $f.tmp && chmod 600 $f.tmp && mv $f.tmp $f && echo gravado $f com `$(wc -c < $f) bytes"
if ($Destino -eq 'vps') { $cmd += ' && systemctl restart motor-bora && sleep 8 && systemctl is-active motor-bora && curl -s http://127.0.0.1:8792/porteiro | head -c 300' }
("{0}={1}`n" -f $var, $k) | & ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -o BatchMode=yes root@srv1786862.hstgr.cloud $cmd
[System.Windows.Forms.Clipboard]::Clear()
$k = $null
Write-Output 'area de transferencia limpa'
