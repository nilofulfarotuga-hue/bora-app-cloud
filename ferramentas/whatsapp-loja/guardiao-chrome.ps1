# guardiao-chrome.ps1 — a porta do PC e o WhatsApp Web no Chrome (perfil Default, onde a extensao
# Vigia esta carregada). Corrido pela tarefa agendada WhatsAppWebBora: ao iniciar sessao e de 10 em
# 10 min. Se nao houver Chrome a correr, abre-o no WhatsApp Web, escondido atras do resto.
# Armadilha provada a 01/09: schtasks grava DisallowStartIfOnBatteries=true por omissao e este
# portatil trabalha a bateria -> a tarefa fica "em fila" para sempre. A tarefa e criada ja com
# AllowStartIfOnBatteries + DontStopIfGoingOnBatteries + StartWhenAvailable.
$ErrorActionPreference = 'SilentlyContinue'
$exe = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$log = Join-Path $PSScriptRoot 'guardiao-chrome.log'
$temChrome = Get-Process chrome -ErrorAction SilentlyContinue
if (-not $temChrome) {
  Start-Process -FilePath $exe -ArgumentList @('--profile-directory=Default','--no-first-run','https://web.whatsapp.com')
  Add-Content $log ("{0} chrome estava fechado -> aberto no WhatsApp Web" -f (Get-Date -Format s))
}
