# ligar-proxy.ps1 — missão m3-dipsy-acesso-total-2026-11-08.
# Usado pelos lançadores (dipsy.ps1, dsh-missao.ps1) com ". ligar-proxy.ps1": arranca o proxy do Dipsy se não estiver
# vivo e põe, SÓ neste processo, as variáveis que mandam o dsh (e tudo o que ele lança) pelo proxy com registo.
# Chamar DEPOIS de arrancar a ponte do Telegram (a ponte fala com o Telegram direto, nunca pelo proxy).
$proxyPy = 'C:\Users\danil\.dsh\proxy\proxy.py'
function ProxyVivo { try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 47900); $c.Close(); return $true } catch { return $false } }
if (-not (ProxyVivo)) {
  $pw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
  if (-not $pw) { $pw = (Get-Command python.exe).Source }
  foreach ($k in 'HTTPS_PROXY','HTTP_PROXY','https_proxy','http_proxy','ALL_PROXY','NO_PROXY') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
  Start-Process -FilePath $pw -ArgumentList ('"' + $proxyPy + '"') -WindowStyle Hidden
  for ($i = 0; $i -lt 20 -and -not (ProxyVivo); $i++) { Start-Sleep -Milliseconds 500 }
}
$script:proxyOk = ProxyVivo
foreach ($k in 'HTTPS_PROXY','HTTP_PROXY','https_proxy','http_proxy') { [Environment]::SetEnvironmentVariable($k, 'http://127.0.0.1:47900', 'Process') }
[Environment]::SetEnvironmentVariable('NODE_USE_ENV_PROXY', '1', 'Process')   # o fetch do Node também passa pelo proxy
foreach ($k in 'NO_PROXY','no_proxy') { [Environment]::SetEnvironmentVariable($k, 'localhost,127.0.0.1,::1,100.120.181.115,bora-vps.tail41776c.ts.net', 'Process') }
