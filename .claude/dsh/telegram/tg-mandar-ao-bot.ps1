# tg-mandar-ao-bot.ps1 - prova real: manda UMA mensagem do Telegram do PC (conta do Danilo) a um bot NOSSO
# (@dipsy_bora_bot ou @BoraHermesbot), espera e lê as últimas mensagens da conversa por UIA. Nunca escreve tokens.
# Missão infra-claude-tudo-2026-11-01 (provas B2/B3/B4). Uso:
#   powershell -File tg-mandar-ao-bot.ps1 -Bot dipsy_bora_bot -Texto "responde só OK" -EsperaSeg 90
param([Parameter(Mandatory)][ValidateSet('dipsy_bora_bot', 'BoraHermesbot')][string]$Bot,
      [Parameter(Mandatory)][string]$Texto, [int]$EsperaSeg = 90, [int]$Ultimas = 6, [switch]$SoLer)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FrenteTg2 {
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
$A = [System.Windows.Automation.AutomationElement]
function Janela {
  $p = (Get-Process Telegram -ErrorAction SilentlyContinue | Select-Object -First 1).Id
  if (-not $p) { return $null }
  $c = New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $p)
  foreach ($w in $A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $c)) {
    $r = $w.Current.BoundingRectangle
    if ($w.Current.ClassName -match 'MainWindow' -and $r.Width -gt 500 -and $r.Height -gt 400) { return $w }
  }
  return $null
}
function AFrente($j) {
  $h = [IntPtr]$j.Current.NativeWindowHandle
  if ([FrenteTg2]::IsIconic($h)) { [void][FrenteTg2]::ShowWindow($h, 9) }
  [FrenteTg2]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [FrenteTg2]::keybd_event(0x12,0,2,[UIntPtr]::Zero)
  [void][FrenteTg2]::SetWindowPos($h, [IntPtr](-1), 0,0,0,0, 0x0003); [void][FrenteTg2]::SetWindowPos($h, [IntPtr](-2), 0,0,0,0, 0x0003)
  [void][FrenteTg2]::BringWindowToTop($h); [void][FrenteTg2]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 700
  return ([FrenteTg2]::GetForegroundWindow() -eq $h)
}
function Mensagens($j) {
  $cl = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::List)
  foreach ($l in $j.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cl)) {
    if ($l.Current.Name -eq 'Mensagens') { return @($l.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) }
  }
  return @()
}
function Composer($j) {
  # ha dois campos "Escrever mensagem..." (um escondido): o certo e o que tem o foco do teclado
  $ce = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $todos = @($j.FindAll([System.Windows.Automation.TreeScope]::Descendants, $ce) | Where-Object { $_.Current.Name -match 'Escrever|Write|Message' })
  $foco = $todos | Where-Object { $_.Current.HasKeyboardFocus } | Select-Object -First 1
  if ($foco) { return $foco }
  return ($todos | Select-Object -Last 1)
}
function Limpa([string]$t) { return ($t -replace '\d{8,10}:[A-Za-z0-9_-]{30,}', '[token]' -replace '\s+', ' ').Trim() }

Start-Process "tg://resolve?domain=$Bot" | Out-Null
Start-Sleep -Seconds 3
$j = Janela
if (-not $j) { Write-Host 'SEM_JANELA_DO_TELEGRAM'; exit 2 }
if (-not $SoLer) {
  $antes = @(Mensagens $j).Count
  if (-not (AFrente $j)) { Write-Host 'NAO_CONSEGUI_POR_A_FRENTE'; exit 3 }
  $e = Composer $j
  if ($e) { try { $e.SetFocus() } catch {} }
  [System.Windows.Forms.Clipboard]::SetText($Texto); Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 150
  [System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 600
  [System.Windows.Forms.Clipboard]::Clear()
  $v = $null; $e = Composer $j
  if ($e) { try { $v = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch {} }
  if ($v -ne $Texto) { Write-Host "CAMPO_NAO_TEM_O_TEXTO (tem: '$v')"; exit 4 }
  [void](AFrente $j); [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Write-Host ("ENVIADO a @{0} as {1}: {2}" -f $Bot, (Get-Date -Format 'HH:mm:ss'), $Texto)
  $fim = (Get-Date).AddSeconds($EsperaSeg)
  while ((Get-Date) -lt $fim) { Start-Sleep -Seconds 5 }
}
$j = Janela
$ms = @(Mensagens $j)
Write-Host "== ultimas $Ultimas mensagens da conversa com @$Bot =="
$ms | Select-Object -Last $Ultimas | ForEach-Object { Write-Host ('- ' + (Limpa $_.Current.Name).Substring(0, [Math]::Min(400, (Limpa $_.Current.Name).Length))) }
