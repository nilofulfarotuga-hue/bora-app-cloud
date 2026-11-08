# dipsy.ps1 - abre o Dipsy pronto a falar: pagina de conversa no navegador (porta 3080, so neste PC) e a ponte do Telegram.
# Chamado pelo DIPSY.cmd do Ambiente de Trabalho. Codigo nosso, missao C-liga (30/10/2026).
# Motor gratis (Kilo e, de reserva, Gemini): nunca segredos; dados de clientes so quando a tarefa precisar e nunca em massa.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'DIPSY'
$dsh = 'C:\Users\danil\.dsh'
$repo = 'C:\BoraLocal\projetosflutter\bora_app'
$cred = Join-Path $dsh 'secrets\telegram-dipsy.token'
$ponte = Join-Path $dsh 'telegram\ponte.py'
$pidWeb = Join-Path $dsh 'telegram\dipsy-web.pid'

function Linha([string]$t = '') { Write-Host $t }
function PortaAOuvir([int]$p) { return [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) }

Clear-Host
Linha '=============================================='
Linha '   DIPSY a abrir... (um momento)'
Linha '=============================================='
Linha

# credencial anonima publica da piscina gratis da Kilo (nao e segredo), lida do ficheiro ao lado
$nomeVar = 'KILO_' + 'ANON_' + 'KEY'
[Environment]::SetEnvironmentVariable($nomeVar, (Get-Content (Join-Path $dsh 'kilo-anonima.txt') -Raw).Trim(), 'Process')

# auto-cura: o AGENTS.md do dsh tem de ser o MESMO ficheiro que o CLAUDE.md global (hardlink)
$global = 'C:\Users\danil\.claude\CLAUDE.md'; $ligado = Join-Path $dsh 'AGENTS.md'
if (@(fsutil hardlink list $global 2>$null).Count -lt 2) {
  Remove-Item $ligado -Force -ErrorAction SilentlyContinue
  cmd /c mklink /H $ligado $global | Out-Null
}

# 1) Telegram: liga a ponte (uma so instancia) se ja houver bot
$linhaTelegram = 'O Telegram ainda não está ligado (falta criar o bot).'
if (Test-Path $cred) {
  if (-not (PortaAOuvir 47831)) {
    $pw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
    if (-not $pw) { $pw = (Get-Command python.exe).Source }
    Start-Process -FilePath $pw -ArgumentList ('"' + $ponte + '"') -WindowStyle Hidden
    Start-Sleep -Seconds 4
  }
  $nomeBot = ''
  try { $tk = (Get-Content $cred -Raw).Trim(); $nomeBot = (Invoke-RestMethod -Uri ('https://api.telegram.org/bot' + $tk + '/getMe') -TimeoutSec 15).result.username } catch { } finally { $tk = $null }
  if (PortaAOuvir 47831) {
    $linhaTelegram = if ($nomeBot) { "Telegram: fala com @$nomeBot (só tu consegues, mais ninguém)." } else { 'Telegram: ligado.' }
  } else { $linhaTelegram = 'O Telegram não arrancou. Diz ao Claude Code.' }
}

# 2) conversa no navegador (porta 3080, so neste PC)
# 08/11/2026 (m3): a internet do Dipsy passa toda pelo proxy local com registo (depois da ponte, que fala direto com o Telegram)
. 'C:\Users\danil\.dsh\proxy\ligar-proxy.ps1'
# o servidor abre sozinho o navegador com um endereco que traz uma chave nova (sem ela a pagina dá 401);
# por isso, se ja houver um servidor a correr, fecha-se e abre-se outro, para o navegador abrir sempre com a chave certa
$velho = Get-NetTCPConnection -State Listen -LocalPort 3080 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($velho) { & taskkill /PID $velho.OwningProcess /T /F 2>$null | Out-Null; Start-Sleep -Seconds 2 }
$exe = Join-Path $env:APPDATA 'npm\dsh.cmd'
$argsWeb = 'web --port 3080'
# 01/11/2026: motor = Claude Sonnet pelo porteiro da VPS (senha só na memória do processo). Se a VPS não responder
# em 8 s, a página abre já com a reserva grátis do PC (Kilo Nemotron).
$senha = ''
try { $senha = ([IO.File]::ReadAllText((Join-Path $dsh 'secrets\porteiro.token'))).Trim() } catch { }
[Environment]::SetEnvironmentVariable('DIPSY_PORTEIRO', $senha, 'Process')
$porteiroVivo = $false
try { Invoke-RestMethod -Uri 'http://100.120.181.115:8792/saude' -Headers @{ 'X-Porteiro-Token' = $senha } -TimeoutSec 8 | Out-Null; $porteiroVivo = $true } catch { }
$senha = $null
if (-not $porteiroVivo) { $argsWeb += ' --patch "' + (Join-Path $dsh 'reserva-kilo-nemotron.patch.yml') + '"' }
if ($env:DIPSY_SEM_NAVEGADOR) { $argsWeb += ' --no-open' }   # DIPSY_SEM_NAVEGADOR so serve para testes
$p = Start-Process -FilePath $exe -ArgumentList $argsWeb -WorkingDirectory $repo -WindowStyle Hidden -PassThru
Set-Content -Path $pidWeb -Value $p.Id -Encoding ASCII
$fim = (Get-Date).AddSeconds(150)
while (-not (PortaAOuvir 3080) -and (Get-Date) -lt $fim) { Start-Sleep -Seconds 2 }
$webOk = PortaAOuvir 3080

Clear-Host
Linha '=============================================='
Linha '   DIPSY está pronto'
Linha '=============================================='
Linha
if ($webOk) {
  Linha ' 1. No navegador abriu a página do Dipsy (se não vires, procura o separador novo).'
  Linha '    Escreve lá o que queres, como falas com uma pessoa.'
} else {
  Linha ' 1. A página do Dipsy não abriu. Diz ao Claude Code.'
}
Linha " 2. $linhaTelegram"
Linha '    Podes escrever-lhe de qualquer lado, e mandar fotos.'
Linha
Linha $(if ($porteiroVivo) { ' Motor: Claude Sonnet (pelo servidor). No Telegram: /opus para o melhor, /motor para ver o crédito.' } else { ' Motor: grátis (o servidor não respondeu agora; o Claude volta quando ele responder).' })
Linha ' O Dipsy sabe: ler e escrever ficheiros do projeto, ver o ecrã e fotos,'
Linha ' consultar a base de dados, ler o teu email da Bora e fazer rascunhos,'
Linha ' auditar o nosso site e guardar trabalho no git depois de passar no Juiz.'
Linha ' Tem internet com registo (categorias; sítio novo pergunta-te no Telegram).'
Linha ' Antes de mexer em dinheiro, publicar, enviar ou apagar, pergunta-te no Telegram: sim ou não.'
Linha
Linha ' PARA PARAR O DIPSY: carrega numa tecla nesta janela.'
Linha

# espera uma tecla; depois para a pagina e o Telegram
while (-not $Host.UI.RawUI.KeyAvailable) { Start-Sleep -Milliseconds 400 }
[void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
Linha ' A parar o Dipsy...'
if (Test-Path $pidWeb) {
  $id = [int](Get-Content $pidWeb -Raw)
  & taskkill /PID $id /T /F 2>$null | Out-Null
  Remove-Item $pidWeb -Force -ErrorAction SilentlyContinue
}
$dono = Get-NetTCPConnection -State Listen -LocalPort 47831 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dono) { Stop-Process -Id $dono.OwningProcess -Force -ErrorAction SilentlyContinue }
Linha ' Dipsy parado. Para voltar, abre o DIPSY outra vez.'
Start-Sleep -Seconds 3
