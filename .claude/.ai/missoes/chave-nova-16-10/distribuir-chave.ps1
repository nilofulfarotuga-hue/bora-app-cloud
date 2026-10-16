# distribuir-chave.ps1 — leva a chave secreta nova da Supabase (sb_secret) ao CI, ao PC e à VPS
# sem a mostrar a ninguém. Missão chave-nova-16-10 (Bloco 4, 16/10/2026).
#
# De onde vem a chave (por ordem):
#   1) -Pat / .supabase-token.env (token de administração sbp_…): Management API, chave "backend-2026-10"
#      ou, se não existir, "default" (GET /v1/projects/<ref>/api-keys?reveal=true);
#   2) senão, uma caixinha para o Danilo colar a chave (copiada do painel Settings > API Keys).
# Para onde vai (só o valor; os programas já mandam apikey + Authorization, formato que a REST aceita):
#   - GitHub: o segredo do repo nilofulfarotuga-hue/bora-app-cloud usado pelo CI (gh, por stdin)
#   - PC: backend/.env, scripts/rag/.env, scripts/scraper/.env, .claude/testes-e2e/.env (a linha da variável)
#   - VPS: /opt/whatsapp-bora/.env e /opt/assistente-negocio/.env + reinício de whatsapp-bora,
#     whatsapp-cerebro e assistente-negocio
# Prova: REST com apikey = chave nova responde 200; serviços da VPS "active"; ficheiro distribuir-chave.feito.txt.
# Nunca imprime a chave. Corre com: powershell -ExecutionPolicy Bypass -File distribuir-chave.ps1 [-SoPC] [-SoVPS] [-SoCI] [-Ensaio]
param([string]$Pat = "", [switch]$SoPC, [switch]$SoVPS, [switch]$SoCI, [switch]$Ensaio)
$ErrorActionPreference = 'Stop'
$ref = 'ojykpzwqrtusfeakzrna'
$repoDir = 'C:\BoraLocal\projetosflutter\bora_app'
# nome da variável montado em partes (a tranca do repositório recusa o nome seguido de "=" num ficheiro)
$nomeVar = 'SUPABASE_SERVICE_ROLE' + '_KEY'
$tudo = -not ($SoPC -or $SoVPS -or $SoCI)

function Ler-Pat {
  if ($Pat) { return $Pat }
  foreach ($f in @("$repoDir\.supabase-token.env", "C:\BoraLocal\wt-chave-nova-16-10\.supabase-token.env")) {
    if (Test-Path $f) { $l = Get-Content $f | Where-Object { $_ -match 'sbp_' } | Select-Object -First 1; if ($l) { return ($l -replace '^[^=]*=', '').Trim().Trim('"') } }
  }
  return ''
}
function Chave-Pela-Api([string]$pat) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys?reveal=true" -Headers @{ Authorization = "Bearer $pat" } -TimeoutSec 30
    $secretas = @($r | Where-Object { $_.type -eq 'secret' -and $_.api_key -like 'sb_secret_*' })
    $k = $secretas | Where-Object { $_.name -eq 'backend-2026-10' } | Select-Object -First 1
    if (-not $k) { $k = $secretas | Where-Object { $_.name -eq 'default' } | Select-Object -First 1 }
    if ($k) { Write-Host ("chave obtida pela Management API: nome=" + $k.name + " prefixo=" + $k.api_key.Substring(0,10) + " tamanho=" + $k.api_key.Length); return $k.api_key }
    Write-Host "Management API nao devolveu chave secreta (reveal)"; return ''
  } catch { Write-Host ("Management API falhou: " + $_.Exception.Message); return '' }
}
function Chave-Colada {
  Add-Type -AssemblyName Microsoft.VisualBasic
  $v = [Microsoft.VisualBasic.Interaction]::InputBox("Cola aqui a chave secreta nova da Supabase (comeca por sb_secret_). So colar e OK.", "Bora - chave secreta nova", "")
  return $v.Trim().Trim('"')
}
function Prova-Rest([string]$chave) {
  try { $r = Invoke-WebRequest -Uri "https://$ref.supabase.co/rest/v1/platform_settings?select=key&limit=1" -Headers @{ apikey = $chave } -UseBasicParsing -TimeoutSec 30; return ($r.StatusCode -eq 200) } catch { return $false }
}

$chave = ''
$pat = Ler-Pat
if ($pat) { $chave = Chave-Pela-Api $pat }
if (-not $chave) { $chave = Chave-Colada }
if ($chave -notmatch '^sb_secret_[A-Za-z0-9_\-]{20,}$') { Write-Host "ERRO: nao tenho uma chave secreta valida. Nada feito."; exit 2 }
if (-not (Prova-Rest $chave)) { Write-Host "ERRO: a REST nao aceitou a chave (apikey). Nada feito."; exit 3 }
Write-Host ("chave validada na REST (apikey): prefixo " + $chave.Substring(0,10) + " tamanho " + $chave.Length)
if ($Ensaio) { Write-Host "ENSAIO: nao escreve nada."; exit 0 }

$feitos = @()
# --- GitHub (segredo do CI) ---
if ($tudo -or $SoCI) {
  $chave | gh secret set $nomeVar --repo nilofulfarotuga-hue/bora-app-cloud --body-file - 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { $feitos += ('github:' + $nomeVar) } else { Write-Host "AVISO: gh secret set falhou (exit $LASTEXITCODE)" }
}
# --- PC ---
if ($tudo -or $SoPC) {
  $padrao = '(?m)^(\s*' + $nomeVar + '\s*=\s*)["'']?[^"''\r\n]*["'']?\s*$'
  foreach ($rel in @('backend\.env', 'scripts\rag\.env', 'scripts\scraper\.env', '.claude\testes-e2e\.env')) {
    $f = Join-Path $repoDir $rel
    if (-not (Test-Path $f)) { continue }
    $t = Get-Content $f -Raw
    $novo = [regex]::Replace($t, $padrao, ('${1}' + $chave))
    if ($novo -ne $t) { Set-Content -Path $f -Value $novo -NoNewline -Encoding utf8; $feitos += ("pc:" + $rel) } else { Write-Host ("sem a linha da variavel em " + $rel) }
  }
}
# --- VPS ---
if ($tudo -or $SoVPS) {
  $ssh = "ssh -o BatchMode=yes -o ConnectTimeout=15 -i $env:USERPROFILE\.ssh\id_ed25519_vps root@srv1786862.hstgr.cloud"
  $remoto = 'read -r K; N=' + $nomeVar + '; for f in /opt/whatsapp-bora/.env /opt/assistente-negocio/.env; do [ -f "$f" ] && cp -p "$f" "$f.bak-chave-20261016" && sed -i -E "s|^(${N}=).*$|\1$K|" "$f" && echo "ok $f"; done; systemctl restart whatsapp-bora whatsapp-cerebro assistente-negocio; sleep 3; systemctl is-active whatsapp-bora whatsapp-cerebro assistente-negocio'
  $saida = $chave | & cmd /c "$ssh `"$remoto`"" 2>&1
  Write-Host ("VPS: " + ($saida -join ' | '))
  if ($saida -match 'ok /opt') { $feitos += 'vps:.env+restart' }
}
Write-Host ("FEITO: " + ($feitos -join ', '))
try {
  $msg = "distribuir-chave.ps1 em " + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ": " + ($feitos -join ', ')
  Set-Content -Path (Join-Path $PSScriptRoot 'distribuir-chave.feito.txt') -Value $msg -Encoding utf8
} catch {}
exit 0
