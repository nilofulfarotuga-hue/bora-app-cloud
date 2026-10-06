---
name: pc-sempre-ligado
description: Manter o PC do Danilo a trabalhar 24 h sem quedas de sessão, extensão do Chrome ou alarmes falsos da VPS. Usar quando uma sessão cai ("Não foi possível alcançar"), a extensão desliga, o vigia diz que a VPS morreu, ou o PC fica lento. Diz o que já está aplicado, como se verifica, e o que falta.
metadata:
  criada: 2026-10-06
  missao: quatro-blocos-06-10
---

# PC sempre ligado

A causa-mãe das quedas é **memória comprometida esgotada**, não suspensão nem rede. O diagnóstico
completo (com provas) está em [DIAGNOSTICO-2026-10-06.md](DIAGNOSTICO-2026-10-06.md). Esta skill diz o
que ficou **aplicado** e como se confirma.

## Aplicado a 06/10/2026

| # | O quê | Onde | Como se verifica |
|---|---|---|---|
| 1 | Sessão agendada "Em Dia — pedir o «sim» do dia" presa a "correr" desde 02/10 foi interrompida (bloqueava a tarefa e a atualização da app) | app Claude (`stop_session`) | `list_sessions` → nenhuma sessão `isRunning:true` com `lastActivityAt` de há dias |
| 2 | Sessão remota órfã (`cse_01Fi4d…`, 615 MB + servidores) fechada; as outras 5 sessões do serviço remoto ficaram (tinham atividade hoje) | processos | `Get-CimInstance Win32_Process` filhos do `claude rc --name bora-app` |
| 3 | **Ollama:** o Cérebro do WhatsApp (PC e VPS) pedia `keep_alive: "30m"` → passou a `"2m"`; modelo descarregado | `C:\BoraLocal\Desktop-PC-antigo\ferramentas\whatsapp-loja\cerebro\modelos.py`, `atendimento.py` (cópias `.bak-keepalive-20261006`); VPS `/opt/whatsapp-bora/cerebro/modelos.py` | `ollama ps` → modelo só aparece até 2 min depois de uma chamada |
| 4 | **Túnel do Ollama** (usado pelo Motor Bora e pela `cadeia_prova` na VPS) mantém-se; a VPS passou a largar ligações mortas em ~90 s, o que liberta a porta 11434 | VPS `/etc/ssh/sshd_config.d/90-clientalive.conf` (`ClientAliveInterval 30`, `ClientAliveCountMax 3`) | na VPS `sshd -T \| grep clientalive`; `curl http://172.16.1.1:11434/api/tags` → 200 |
| 5 | **Vigia da VPS:** 3 tentativas com 1 min de intervalo antes de declarar "morta"; guarda o erro do `ssh` | `orquestracao/vigia-vps.sh` | `~\.bora\vigia-vps.log` mostra `tentativas=N` e `erro=…` |
| 6 | **Serviços de Controlo Remoto** (`claude rc` bora-app e em-dia) passam a arrancar **escondidos**, fora do Windows Terminal; registo roda acima de 50 MB | `C:\BoraLocal\QG\claude-rc-bora-watchdog.ps1`, `claude-rc-emdia-watchdog.ps1` (cópias `.bak-20261006`) | processo `powershell … claude rc` sem separador no Terminal |
| 7 | **Terminal de 12,8 GB:** aloja o serviço remoto do Bora (e as sessões remotas dentro dele). O vigia reinicia-o **uma vez, entre as 04:00 e as 04:59**, só se o Terminal passar de 3 GB **e** nenhuma sessão remota gastar 20 s de CPU em 10 min | `claude-rc-bora-watchdog.ps1` | `C:\BoraLocal\QG\claude-rc-bora-watchdog.log` → linha "noite: …"; ensaio: `$env:RC_TESTE_NOITE='1'` |
| 8 | **Host nativo da extensão:** a cada 30 min, se o binário instalado for diferente do da versão atual da app, fecha-se o host e copia-se o novo (resolve o EBUSY depois da atualização) | `claude-rc-bora-watchdog.ps1` | registo "host nativo atualizado para a versão …" |
| 9 | Energia confirmada: em corrente nunca suspende (suspensão = 0, ecrã = 0). A suspensão de 02/10 foi por bateria (cabo). Nada mudado | `powercfg` | `powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE` → AC 0 |

## Não aplicado (e porquê)

- **Exceções do Poupador de memória do Chrome:** o Windows recusa escrever em
  `HKCU\Software\Policies` sem administrador, e fechar o Chrome perdia os separadores (arranca com
  "página nova", não reabre). Ficou pronto [chrome-excecoes-poupador.reg](chrome-excecoes-poupador.reg):
  duplo clique → "Sim" no aviso do Windows → reabrir o Chrome. "Continuar em segundo plano" já está
  ligado por omissão.
- **Atualização da app Claude 2.19675.1:** aplica-se sozinha quando nenhuma sessão estiver a
  trabalhar (o atualizador adia enquanto houver trabalho). Era a sessão presa (#1) que a bloqueava
  desde 02/10. Confirmar: `Get-AppxPackage Claude` → versão 2.19675.x.
- **Guardião de git** (`.claude/hooks/`): a pasta está trancada nas permissões; só o Danilo altera.

## Verificação rápida (copiar e correr)

```powershell
(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes
$os=Get-CimInstance Win32_OperatingSystem; ($os.TotalVirtualMemorySize-$os.FreeVirtualMemory)/1MB   # GB comprometidos
(Get-Process WindowsTerminal -EA SilentlyContinue | Measure-Object PagedMemorySize64 -Sum).Sum/1GB
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" ps
Get-AppxPackage Claude | Select-Object Version
Get-Content C:\BoraLocal\QG\claude-rc-bora-watchdog.log -Tail 3
```

Valores de 06/10: antes RAM 1653 MB livres / 49,7 GB comprometidos / Ollama 5,5 GB carregado;
depois 2388 MB / 43,8 GB / Ollama vazio. Terminal 12,9 GB até ao reinício noturno.
