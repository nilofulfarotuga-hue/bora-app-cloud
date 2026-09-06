# Ponte de push git — corre como utilizador 'danil' (sessao interativa, credencial GCM valida).
# O executor headless (utilizador 'hermes') so consegue commit local (wincredman exige sessao
# interativa p/ persistir/ler credenciais). Esta tarefa agendada publica o que ja foi commitado.
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\danil\Desktop\projetosflutter\bora_app'
$logDir = Join-Path $repo '.claude\.ai\hermes\push-bridge'
$log = Join-Path $logDir 'push-bridge.log'
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Set-Location $repo
$branch = (git rev-parse --abbrev-ref HEAD).Trim()

# Start-Process com redirect a ficheiro evita o NativeCommandError que o PowerShell 5.1
# gera quando se faz 2>&1 direto sobre stderr de um exe nativo (git escreve o "branch -> branch" no stderr mesmo em sucesso).
$stdout = Join-Path $env:TEMP 'bora-push-stdout.txt'
$stderr = Join-Path $env:TEMP 'bora-push-stderr.txt'
$p = Start-Process -FilePath git -ArgumentList @('push', 'origin', $branch) -WorkingDirectory $repo `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$out = (Get-Content $stdout -Raw -ErrorAction SilentlyContinue) + (Get-Content $stderr -Raw -ErrorAction SilentlyContinue)
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Add-Content -Path $log -Value "[$ts] branch=$branch exitcode=$($p.ExitCode)"
Add-Content -Path $log -Value $out.Trim()
Add-Content -Path $log -Value '---'
