# guardiao-cerebro.ps1 — mantem o servidor-cerebro do WhatsApp (porta 8790) sempre vivo.
# Corrido pela tarefa agendada CerebroWhatsAppBora (ao ligar o PC e de 2 em 2 min).
$ErrorActionPreference = 'SilentlyContinue'
$dir     = 'C:\BoraLocal\Desktop-PC-antigo\ferramentas\whatsapp-loja'
$pythonw = 'C:\Users\danil\AppData\Local\Programs\Python\Python312\pythonw.exe'

$aOuvir = Get-NetTCPConnection -LocalPort 8790 -State Listen -ErrorAction SilentlyContinue
if (-not $aOuvir) {
  Start-Process -FilePath $pythonw -ArgumentList 'servidor_cerebro.py' -WorkingDirectory $dir -WindowStyle Hidden
}
