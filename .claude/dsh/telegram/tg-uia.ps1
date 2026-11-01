# tg-uia.ps1 - passos pequenos no Telegram do PC por UIA (infra-claude-tudo 01/11/2026, criar o grupo Bora Bastidores).
# -Listar: mostra botoes/menus/campos visiveis (sem o conteudo das conversas). -Carregar "Nome": invoca/clica o elemento.
# -Escrever "texto": cola no campo com o foco. -Tecla "{ENTER}": envia uma tecla.
param([switch]$Listar, [string]$Carregar, [string]$Escrever, [string]$Tecla, [int]$Indice = 0, [switch]$Enviar)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class TgUia {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
}
"@
$A = [System.Windows.Automation.AutomationElement]
$p = [int](Get-Process Telegram | Select-Object -First 1).Id
$c = New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $p)
$janelas = @($A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $c))
function Frente($w) { $h = [IntPtr]$w.Current.NativeWindowHandle; [TgUia]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [TgUia]::keybd_event(0x12,0,2,[UIntPtr]::Zero); [void][TgUia]::SetForegroundWindow($h); Start-Sleep -Milliseconds 400 }
$tipos = 'Button|MenuItem|Edit|CheckBox|ListItem|Hyperlink|Text'
$todos = @()
foreach ($w in $janelas) {
  foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
    $t = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
    if ($t -match $tipos -and -not $e.Current.IsOffscreen) { $todos += [pscustomobject]@{ Tipo = $t; Nome = $e.Current.Name; El = $e; Jan = $w } }
  }
}
if ($Listar) {
  Write-Host ("janelas: " + $janelas.Count)
  $todos | Where-Object { $_.Tipo -ne 'Text' -and $_.Tipo -ne 'ListItem' } | ForEach-Object { $r = $_.El.Current.BoundingRectangle; "{0} '{1}' @{2},{3}" -f $_.Tipo, $_.Nome, [int][Math]::Max(0,[Math]::Min(9999,$r.X)), [int][Math]::Max(0,[Math]::Min(9999,$r.Y)) } | Select-Object -First 60
}
if ($Carregar) {
  $alvo = @($todos | Where-Object { $_.Nome -eq $Carregar })[$Indice]
  if (-not $alvo) { $alvo = @($todos | Where-Object { $_.Nome -like "*$Carregar*" })[$Indice] }
  if (-not $alvo) { Write-Host "NAO_ACHEI '$Carregar'"; exit 3 }
  Frente $alvo.Jan
  $feito = $false
  try { $alvo.El.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $feito = $true } catch {}
  if (-not $feito) { try { $alvo.El.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle(); $feito = $true } catch {} }
  if (-not $feito) { $r = $alvo.El.Current.BoundingRectangle; [void][TgUia]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)); Start-Sleep -Milliseconds 150; [TgUia]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [TgUia]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
  Write-Host "CARREGUEI '$($alvo.Nome)' ($($alvo.Tipo))"
  Start-Sleep -Milliseconds 900
}
if ($Escrever) {
  [System.Windows.Forms.Clipboard]::SetText($Escrever); Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 700
  [System.Windows.Forms.Clipboard]::Clear(); Write-Host "ESCREVI '$Escrever'"
}
if ($Tecla) { [System.Windows.Forms.SendKeys]::SendWait($Tecla); Start-Sleep -Milliseconds 700; Write-Host "TECLA $Tecla" }
if ($Escrever -and $Enviar) {   # so carrega em Enter se o campo com o foco tem EXATAMENTE o texto
  $v = $null
  foreach ($w in $janelas) {
    $ce = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $ce)) {
      if ($e.Current.HasKeyboardFocus) { try { $v = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch {} }
    }
  }
  if ($v -eq $Escrever) { [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 800; Write-Host 'ENVIADO' } else { Write-Host "NAO_ENVIEI (campo: '$v')" }
}
