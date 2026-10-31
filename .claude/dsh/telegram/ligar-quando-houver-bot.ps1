# ligar-quando-houver-bot.ps1 - espera que o vigia criar-bot.ps1 guarde a credencial do bot e, nesse instante, liga a ponte
# Telegram <-> Dipsy (escondida, uma so instancia). Codigo nosso, missao C-liga (30/10/2026).
param([int]$EsperaMin = 300)
$cred = 'C:\Users\danil\.dsh\secrets\telegram-dipsy.token'
$log = 'C:\Users\danil\.dsh\telegram\criar-bot.log'
$limite = (Get-Date).AddMinutes($EsperaMin)
while ((Get-Date) -lt $limite) {
  if (Test-Path $cred) {
    Start-Sleep -Seconds 3
    $pw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
    if (-not $pw) { $pw = (Get-Command python.exe).Source }
    Start-Process -FilePath $pw -ArgumentList '"C:\Users\danil\.dsh\telegram\ponte.py"' -WindowStyle Hidden
    Add-Content -Path $log -Value ("[{0}] credencial do bot encontrada: ponte do Telegram ligada" -f (Get-Date -Format 's')) -Encoding UTF8
    exit 0
  }
  Start-Sleep -Seconds 5
}
exit 3
