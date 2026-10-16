# pedir-token-supabase.ps1 — caixinha no PC para o Danilo colar o token de administração
# da Supabase (sbp_…, 7 dias). Missão chave-nova-16-10 (16/10/2026).
#
# O token é o ÚNICO passo que só ele pode dar (gera-se na página de tokens da conta dele).
# Com ele, as Edge Functions publicam-se a partir do disco (CLI --use-api), sem copiar à mão.
# Guarda em .supabase-token.env (ignorado pelo git) no repo principal e na worktree da missão.
# Não imprime o token em lado nenhum. Valida-o na Management API antes de o guardar.

Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

$destinos = @(
  "C:\BoraLocal\projetosflutter\bora_app\.supabase-token.env",
  "C:\BoraLocal\wt-chave-nova-16-10\.supabase-token.env"
)
$titulo = "Bora - token da Supabase"

for ($tentativa = 1; $tentativa -le 5; $tentativa++) {
  $tok = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Cola aqui o token da Supabase (comeca por sbp_).`n`nE so colar e carregar em OK. Mais nada.",
    $titulo, "")
  if ([string]::IsNullOrWhiteSpace($tok)) {
    [System.Windows.Forms.MessageBox]::Show("Ficou sem token. Quando quiseres, abre outra vez a caixinha (atalho no ambiente de trabalho: COLAR-TOKEN-SUPABASE).", $titulo) | Out-Null
    exit 2
  }
  $tok = $tok.Trim().Trim('"').Trim("'")
  if ($tok -notmatch '^sbp_[A-Za-z0-9_\-]{16,}$') {
    [System.Windows.Forms.MessageBox]::Show("Isso nao parece um token (tem de comecar por sbp_). Tenta outra vez.", $titulo) | Out-Null
    continue
  }
  $ok = $false
  try {
    $r = Invoke-WebRequest -Uri "https://api.supabase.com/v1/projects" -Headers @{ Authorization = "Bearer $tok" } -UseBasicParsing -TimeoutSec 25
    $ok = ($r.StatusCode -eq 200)
  } catch { $ok = $false }
  if (-not $ok) {
    [System.Windows.Forms.MessageBox]::Show("A Supabase nao aceitou este token. Confirma que copiaste o token inteiro e tenta outra vez.", $titulo) | Out-Null
    continue
  }
  foreach ($d in $destinos) {
    Set-Content -Path $d -Value "SUPABASE_ACCESS_TOKEN=$tok" -Encoding ascii
  }
  $marca = "C:\BoraLocal\wt-chave-nova-16-10\.claude\.ai\missoes\chave-nova-16-10\token-recebido.txt"
  Set-Content -Path $marca -Value ("token recebido e validado em " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding ascii
  [System.Windows.Forms.MessageBox]::Show("Token guardado e a funcionar. Obrigado - podes fechar isto.", $titulo) | Out-Null
  exit 0
}
[System.Windows.Forms.MessageBox]::Show("Cinco tentativas sem token valido. Fica para depois.", $titulo) | Out-Null
exit 3
