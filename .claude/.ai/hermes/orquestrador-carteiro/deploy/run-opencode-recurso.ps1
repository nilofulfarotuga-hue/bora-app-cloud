# run-opencode-recurso.ps1 — recurso do carteiro quando o plano Claude esgota (23/10/2026).
#
# Substitui o antigo "--motor-go" do run-claude-loop.cmd, que punha o claude.exe a falar com o
# plano OpenCode Go. O Danilo decidiu NAO renovar o Go (chave expirada a 23/10). Agora o recurso e'
# o OpenCode (o programa, gratis) com ferramentas, por uma de duas fontes:
#   omniroute/agentes            -> o OmniRoute da VPS pelo Tailscale (Gemini, NVIDIA, OpenRouter, ...)
#   opencode/glm-5.3-flash-free  -> modelo gratis do proprio OpenCode Zen (so funciona DENTRO do OpenCode)
# NAO mexe no Claude Code: nada de ANTHROPIC_BASE_URL (regra da missao omniroute-23-10).
#
# Uso (pelo ssh do carteiro, tarefa em base64 no STDIN, como o run-claude-loop.cmd --b64stdin):
#   powershell -NoProfile -ExecutionPolicy Bypass -File run-opencode-recurso.ps1 -Modelo omniroute/agentes
param([string]$Modelo = "omniroute/agentes")

$permitidos = @("omniroute/agentes", "opencode/glm-5.3-flash-free", "opencode/deepseek-v4.1-flash-free")
if ($permitidos -notcontains $Modelo) { Write-Output "RECURSO-MODELO-RECUSADO: $Modelo"; exit 5 }

# Caminhos REAIS, nunca pelo Desktop: C:\Users\danil\Desktop\produtividade-ia e' uma juncao e numa
# sessao ssh o Windows recusa atravessa-la ("ponto de montagem nao fidedigno", medido 23/10/2026).
$PROJ = "C:\BoraLocal\projetosflutter\bora_app"
$LOG = "C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\recurso-opencode.log"

$b64 = ([Console]::In.ReadToEnd()).Trim()
if (-not $b64) { Write-Output "RECURSO-SEM-TAREFA: o STDIN veio vazio"; exit 4 }
$b64 = $b64 + ("=" * ((4 - $b64.Length % 4) % 4))   # o pc-loop-go tira o padding '='
$tarefa = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))

$dir = Join-Path $env:TEMP "orq-recurso"
New-Item -ItemType Directory -Force $dir | Out-Null
$f = Join-Path $dir ("tarefa-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".md")
$guarda = "Estas a correr como EXECUTOR de recurso de um loop autonomo do Bora (headless, sem canal com o Danilo). " +
  "Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA facas git commit nem git push (a menos que a tarefa peca). " +
  "Se a tarefa comecar com [PROPOSE-ONLY], prepara tudo mas NAO apliques. PARA e responde so 'CONFIRMACAO NECESSARIA: <o que>' se tocar " +
  "Stripe/pagamentos/precos/comissoes/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger. Nunca imprimas segredos. " +
  "No fim escreve uma linha 'MARCO: <o que ficou feito>' por cada fase e um RESULTADO conciso em portugues."
[IO.File]::WriteAllText($f, $guarda + "`n`n--- TAREFA ---`n" + $tarefa, (New-Object Text.UTF8Encoding $false))

Add-Content -LiteralPath $LOG -Value ("[{0}] recurso :: modelo={1} tarefa={2}" -f (Get-Date -Format s), $Modelo, $f)
Write-Output "##BORA-MOTOR##: $Modelo"
# A mensagem vem ANTES do -f: o -f aceita varios ficheiros e engolia a mensagem como ficheiro.
& opencode run -m $Modelo --auto --dir $PROJ "Executa a tarefa do ficheiro anexo, do principio ao fim, com as tuas ferramentas." -f $f 2>&1 |
  ForEach-Object { ("$_" -replace "`e\[[0-9;]*m", "") }
$rc = $LASTEXITCODE
Add-Content -LiteralPath $LOG -Value ("[{0}] recurso :: fim rc={1}" -f (Get-Date -Format s), $rc)
exit $rc
