# tg-grupo-enviar.ps1 - escreve UMA linha no grupo "Bora Bastidores" do Telegram do PC (conta do Danilo) e envia.
# So envia se a janela aberta for o grupo e o campo tiver o texto. Missao infra-claude-tudo 01/11/2026 (B6).
param([Parameter(Mandatory)][string]$Texto)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class FrG { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); }
"@
$A = [System.Windows.Automation.AutomationElement]
$p = [int](Get-Process Telegram | Select-Object -First 1).Id
$c = New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $p)
$w = @($A::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $c)) | Where-Object { $_.Current.Name -like '*Bastidores*' } | Select-Object -First 1
if (-not $w) { Write-Host 'SEM_JANELA_DO_GRUPO'; exit 2 }
$h = [IntPtr]$w.Current.NativeWindowHandle
[FrG]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [FrG]::keybd_event(0x12,0,2,[UIntPtr]::Zero); [void][FrG]::ShowWindow($h, 9); [void][FrG]::SetForegroundWindow($h); Start-Sleep -Milliseconds 600
if ([FrG]::GetForegroundWindow() -ne $h) { Write-Host 'TELEGRAM_NAO_FICOU_A_FRENTE'; exit 3 }
$ce = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
$alvo = $null; foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $ce)) { if ($e.Current.Name -match 'Escrever' -and -not $e.Current.IsOffscreen) { $alvo = $e } }
$alvo.SetFocus(); Start-Sleep -Milliseconds 300
[System.Windows.Forms.Clipboard]::SetText($Texto); [System.Windows.Forms.SendKeys]::SendWait('^a'); [System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 700; [System.Windows.Forms.Clipboard]::Clear()
$n = $alvo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value.Length
if ($n -lt [Math]::Max(1, $Texto.Length - 4) -or [FrG]::GetForegroundWindow() -ne $h) { Write-Host "NAO_ENVIEI (campo com $n letras)"; exit 4 }
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 1200
if ($alvo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value.Length -gt 0) { [System.Windows.Forms.SendKeys]::SendWait('{ESC}{ENTER}'); Start-Sleep -Milliseconds 800 }
Write-Host ("ENVIADO no grupo: " + $Texto)
