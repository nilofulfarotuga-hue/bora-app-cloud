# criar-bot.ps1 - acompanha a conversa do Danilo com o BotFather no Telegram do PC e, quando o bot nasce, le o token por
# codigo (UIA, so no PC), valida-o na API do Telegram (so pelo codigo HTTP e pelo nome do bot), guarda-o em
# ~/.dsh/secrets/telegram-dipsy.token (so o utilizador le) e NUNCA o escreve em ecra, log ou chat.
# Enquanto espera, escreve (sem enviar) o nome e o utilizador do bot no campo de mensagem, para o Danilo so ter de carregar
# em Enviar. Codigo nosso, missao C-liga (30/10/2026).
param([int]$EsperaMin = 180)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FrenteTg {
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
  public static double OciosoSeg() { LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i); GetLastInputInfo(ref i); return ((uint)Environment.TickCount - i.dwTime) / 1000.0; }
}
"@
$pasta = 'C:\Users\danil\.dsh'
$ficheiroToken = Join-Path $pasta 'secrets\telegram-dipsy.token'
$log = Join-Path $pasta 'telegram\criar-bot.log'
function Log([string]$m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 's'), $m) -Encoding UTF8 }
$reToken = '\d{8,10}:[A-Za-z0-9_-]{35}'

function JanelaTelegram {
  $pid2 = (Get-Process Telegram -ErrorAction SilentlyContinue | Select-Object -First 1).Id
  if (-not $pid2) { return $null }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $pid2)
  foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)) {
    $r = $w.Current.BoundingRectangle
    if ($w.Current.ClassName -match 'MainWindow' -and $r.Width -gt 500 -and $r.Height -gt 400) { return $w }
  }
  return $null
}
function MensagensDaConversa($janela) {
  # a lista chamada "Mensagens" e a conversa aberta (a "Chats" e a lista das conversas)
  $condLista = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::List)
  foreach ($l in $janela.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condLista)) {
    if ($l.Current.Name -eq 'Mensagens') {
      return @($l.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition))
    }
  }
  return @()
}
function PoeAFrente($janela) {
  $h = [IntPtr]$janela.Current.NativeWindowHandle
  if ([FrenteTg]::IsIconic($h)) { [void][FrenteTg]::ShowWindow($h, 9) }
  [FrenteTg]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [FrenteTg]::keybd_event(0x12,0,2,[UIntPtr]::Zero)
  [void][FrenteTg]::SetWindowPos($h, [IntPtr](-1), 0,0,0,0, 0x0003); [void][FrenteTg]::SetWindowPos($h, [IntPtr](-2), 0,0,0,0, 0x0003)
  [void][FrenteTg]::BringWindowToTop($h); [void][FrenteTg]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 600
  return ([FrenteTg]::GetForegroundWindow() -eq $h)
}
function Escreve([string]$texto, $janela) {
  if ([FrenteTg]::OciosoSeg() -lt 4) { return $false }       # o Danilo esta a escrever: nao atropelo
  if (-not (PoeAFrente $janela)) { return $false }
  [System.Windows.Forms.Clipboard]::SetText($texto); Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 150
  [System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 500
  [System.Windows.Forms.Clipboard]::Clear()
  return $true
}

if (Test-Path $ficheiroToken) { Log 'ja existe um token guardado; nada a fazer'; exit 0 }
$jan = JanelaTelegram
if (-not $jan) { Log 'sem janela do Telegram'; exit 2 }
$antigos = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in (MensagensDaConversa $jan)) { foreach ($x in [regex]::Matches($m.Current.Name, $reToken)) { [void]$antigos.Add($x.Value) } }
Log "arrancou; tokens antigos na conversa: $($antigos.Count) (ignorados); espera ate $EsperaMin min"

$nomes = @('dipsy_bora_bot', 'dipsy_boraapp_bot', 'dipsy_guarda_bot', 'dipsy_bora_pc_bot', 'dipsy_bora_1030_bot')
$tentativa = 0; $jaEscreveu = @{}
$limite = (Get-Date).AddMinutes($EsperaMin)
while ((Get-Date) -lt $limite) {
  Start-Sleep -Seconds 3
  try {
    $jan = JanelaTelegram
    if (-not $jan) { continue }
    $msgs = MensagensDaConversa $jan
    if (-not $msgs -or $msgs.Count -eq 0) { continue }
    # 1) token novo?
    foreach ($m in $msgs) {
      foreach ($x in [regex]::Matches($m.Current.Name, $reToken)) {
        if ($antigos.Contains($x.Value)) { continue }
        $tok = $x.Value
        $codigo = 0; $usuario = ''
        try { $r = Invoke-RestMethod -Uri ("https://api.telegram.org/bot" + $tok + "/getMe") -TimeoutSec 20; $codigo = 200; $usuario = $r.result.username } catch { $codigo = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 } }
        if ($codigo -eq 200) {
          [IO.File]::WriteAllText($ficheiroToken, $tok, (New-Object Text.UTF8Encoding($false)))
          & icacls $ficheiroToken /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
          Log "TOKEN GUARDADO (tamanho $($tok.Length), getMe HTTP 200, bot @$usuario); ficheiro $ficheiroToken"
          $tok = $null
          exit 0
        } else { Log "token novo rejeitado pela API (HTTP $codigo); continuo a esperar"; [void]$antigos.Add($x.Value) }
      }
    }
    # 2) o que pede o BotFather agora? (ultima mensagem da conversa)
    $ultima = $msgs[$msgs.Count - 1].Current.Name
    $chave = $ultima.Substring(0, [Math]::Min(80, $ultima.Length))
    $texto = $null
    if ($ultima.Substring(0, [Math]::Min(24, $ultima.Length)) -notmatch 'BotFather') { continue }   # a ultima e do Danilo: nada a escrever
    if ($ultima -match 'How are we going to call it|choose a name for your bot') { $texto = 'Dipsy Bora' }
    elseif ($ultima -match 'choose a username for your bot|pick a username|Now let.s find a good name') { $texto = $nomes[[Math]::Min($tentativa, $nomes.Count - 1)] }
    elseif ($ultima -match 'already taken|username is invalid|must end in') { $tentativa++; $texto = $nomes[[Math]::Min($tentativa, $nomes.Count - 1)] }
    if ($texto -and -not $jaEscreveu.ContainsKey($chave)) {
      if (Escreve $texto $jan) { $jaEscreveu[$chave] = 1; Log "escrevi (sem enviar) no campo de mensagem: '$texto'" }
    }
  } catch { Log ("erro no ciclo: " + $_.Exception.Message.Substring(0, [Math]::Min(120, $_.Exception.Message.Length))) }
}
Log 'tempo esgotado sem token novo'
exit 3
