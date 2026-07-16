# Ponte de push git — corre como utilizador 'danil' (sessao interativa, credencial GCM valida).
# O executor headless (utilizador 'hermes') so consegue commit local (wincredman exige sessao
# interativa p/ persistir/ler credenciais). Esta tarefa agendada publica o que ja foi commitado.
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\danil\Desktop\projetosflutter\bora_app'
$logDir = Join-Path $repo '.claude\.ai\hermes\push-bridge'
$log = Join-Path $logDir 'push-bridge.log'
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Set-Location $repo
$branch = (git rev-parse --abbrev-ref HEAD 2>&1).Trim()
$out = git push origin $branch 2>&1 | Out-String

Add-Content -Path $log -Value "[$ts] branch=$branch"
Add-Content -Path $log -Value $out.Trim()
Add-Content -Path $log -Value '---'
