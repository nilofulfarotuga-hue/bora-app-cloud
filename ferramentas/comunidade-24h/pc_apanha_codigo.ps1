# Escuta em http://127.0.0.1:8765/ o retorno da autorização do YouTube e guarda a consulta
# (code + state) em C:\BoraLocal\comunidade-24h\codigo-<state>.txt. A VPS vai lá buscá-la
# (yt_oauth.py apanhar) e troca-a no cofre dela. O código sozinho não dá acesso a nada.
# Corre até receber $Quantos retornos ou passar $Minutos.
param([int]$Quantos = 5, [int]$Minutos = 60)

Add-Type -AssemblyName System.Web
$pasta = 'C:\BoraLocal\comunidade-24h'
New-Item -ItemType Directory -Force $pasta | Out-Null
$ouvinte = New-Object System.Net.HttpListener
$ouvinte.Prefixes.Add('http://127.0.0.1:8765/')
$ouvinte.Start()
$fim = (Get-Date).AddMinutes($Minutos)
$recebidos = 0
try {
    while ($recebidos -lt $Quantos -and (Get-Date) -lt $fim) {
        $tarefa = $ouvinte.GetContextAsync()
        while (-not $tarefa.Wait(1000)) { if ((Get-Date) -ge $fim) { break } }
        if (-not $tarefa.IsCompleted) { break }
        $ctx = $tarefa.Result
        $consulta = $ctx.Request.Url.Query.TrimStart('?')
        $state = [System.Web.HttpUtility]::ParseQueryString($consulta)['state']
        if ($state -and $state -match '^[A-Za-z0-9._-]+$') {
            Set-Content -Path (Join-Path $pasta "codigo-$state.txt") -Value $consulta -Encoding ascii -NoNewline
            $recebidos++
            $msg = 'Pronto. Pode fechar este separador.'
        } else {
            $msg = 'Retorno sem state: nada guardado.'
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes("<html><body style='font:20px sans-serif'>$msg</body></html>")
        $ctx.Response.ContentType = 'text/html; charset=utf-8'
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.OutputStream.Close()
        $ctx.Response.Close()
    }
} finally {
    Start-Sleep -Milliseconds 800
    $ouvinte.Stop()
}
"recebidos=$recebidos"
