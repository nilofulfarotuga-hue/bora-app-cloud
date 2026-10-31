# rea-bora.ps1 - corre o REA 6.8.0 que JA esta instalado (cache do npx, a mesma copia do Claude Code), sem npm e sem downloads.
# Codigo nosso, missao C-liga (30/10/2026). So para o que e NOSSO: a guarda do Dipsy confere os alvos antes de correr.
# Uso: powershell -NoProfile -File C:\Users\danil\.dsh\rea-bora.ps1 doctor
#      powershell -NoProfile -File C:\Users\danil\.dsh\rea-bora.ps1 capture-web-screenshot https://boraguarda.com/
$env:PATH = 'C:\Users\danil\.rea-node\node-v24.22.1-win-x64;' + $env:PATH
$rea = 'C:\Users\danil\AppData\Local\npm-cache\_npx\da7caeae9db9c589\node_modules\rea-agents\scripts\rea.mjs'
if (-not (Test-Path $rea)) { Write-Output 'REA nao encontrado na cache do npx; pede ao Claude Code para o reinstalar.'; exit 2 }
& node $rea @args
exit $LASTEXITCODE
