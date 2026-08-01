# =============================================================================
#  PONTE BORA :: setup de permissoes do user 'hermes' (idempotente)
#  Correr COMO ADMINISTRADOR para garantir 0 falhas:
#     powershell -ExecutionPolicy Bypass -File setup-permissions.ps1
#
#  Da ao 'hermes' o acesso minimo para a ponte funcionar:
#   - traverse ate ao config-dir e executar o Claude Code (npm global do danil)
#   - ler/gravar a config/credenciais partilhadas (.claude)
#   - editar o projeto Bora (worker faz code/build/git)
#   - ler os scripts da ponte (produtividade-ia)
#  Opcional: -InstallTestKey instala chave SSH danil->hermes p/ testes locais.
# =============================================================================
param([switch]$InstallTestKey)
$ErrorActionPreference = 'Continue'

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "AVISO: nao estas como Admin. A maioria dos grants funciona (danil e dono)," -ForegroundColor Yellow
    Write-Host "       mas alguns ficheiros protegidos podem falhar. Ideal: correr como Admin." -ForegroundColor Yellow
}

function Grant([string]$path,[string]$perm,[switch]$Recurse){
    if(-not (Test-Path $path)){ Write-Host "  (salta, nao existe) $path" -ForegroundColor DarkGray; return }
    if($Recurse){ icacls $path /grant "hermes:(OI)(CI)($perm)" /T /C | Out-Null }
    else        { icacls $path /grant "hermes:($perm)"            | Out-Null }
    Write-Host ("  OK {0}  [{1}{2}]" -f $path,$perm,$(if($Recurse){' /T'}else{''})) -ForegroundColor Green
}

Write-Host "Permissoes hermes:" -ForegroundColor Cyan
# Traverse pela arvore de perfil ate aos alvos
Grant "C:\Users\danil"                                              "RX"
Grant "C:\Users\danil\AppData"                                     "RX"
Grant "C:\Users\danil\AppData\Roaming"                             "RX"
Grant "C:\Users\danil\Desktop"                                     "RX"
Grant "C:\Users\danil\Desktop\projetosflutter"                     "RX"
# Executar o Claude Code (instalacao npm global do danil)
Grant "C:\Users\danil\AppData\Roaming\npm"                         "RX" -Recurse
# Config + credenciais partilhadas (ler config, gravar refresh do token)
Grant "C:\Users\danil\.claude"                                     "M"  -Recurse
# Projeto Bora (o worker edita codigo / faz build / git)
Grant "C:\Users\danil\Desktop\projetosflutter\bora_app"           "M"  -Recurse
# Scripts da ponte
Grant "C:\Users\danil\Desktop\produtividade-ia"                   "RX" -Recurse

if ($InstallTestKey) {
    Write-Host "Chave SSH danil->hermes ..." -ForegroundColor Cyan
    $key = "C:\Users\danil\.ssh\id_ed25519_hermes"
    if (-not (Test-Path $key)) { & ssh-keygen -t ed25519 -f $key -N '""' -q }
    $pub = (Get-Content "$key.pub" -Raw).Trim()
    $hssh = "C:\Users\hermes\.ssh"; New-Item -ItemType Directory -Force -Path $hssh | Out-Null
    $ak = Join-Path $hssh "authorized_keys"
    if (-not (Test-Path $ak) -or -not (Select-String -Path $ak -SimpleMatch $pub -Quiet)) { Add-Content -Path $ak -Value $pub }
    icacls $ak /inheritance:r | Out-Null
    icacls $ak /grant "hermes:F" "SYSTEM:F" "Administrators:F" | Out-Null
    Write-Host "  Testar: ssh -i $key hermes@100.71.105.7 whoami" -ForegroundColor Green
}

Write-Host "`nFEITO." -ForegroundColor Green
