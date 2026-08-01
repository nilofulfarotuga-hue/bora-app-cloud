# ADB pós-cabo — diagnóstico 2026-07-14

## Contexto
E2E falhou de novo no `reset-role-screen.yaml` (reconnect x2, última falha 06:04 UTC),
mesmo depois de o Danilo ter ligado os cabos USB dos telemóveis. Tarefa: diagnosticar e
corrigir agora.

## Passo 1 — `adb devices`
```
adb devices -l
List of devices attached
```
**Vazio.** Nem `device`, nem `unauthorized`, nem `offline` — zero linhas. Isto é diferente
de um problema de autorização (que apareceria como `unauthorized`); é ausência total de
enumeração USB.

## Passo 2 — `adb kill-server` + `adb start-server`
Reiniciei o servidor adb e corri `adb devices` outra vez. Continuou vazio. Descarta
daemon adb preso/travado como causa.

## Passo 3 — verificação ao nível do Windows (PnP/USB)
```powershell
Get-PnpDevice -PresentOnly -Class USB,WPD,USBDevice,AndroidUsbDeviceClass
```
Resultado: **só 4 dispositivos genéricos presentes** (2× "USB Composite Device" — webcam/
periférico, o Host Controller, e o Root Hub). **Nenhum telemóvel Android está presente.**

Ao olhar o histórico completo (`Get-PnpDevice` sem `-PresentOnly`), aparecem várias entradas
"Redmi A2", "SAMSUNG Mobile USB Composite Device", "SAMSUNG Android ADB Interface" — mas
**todas com Status = `Unknown`**, ou seja, são entradas de ligações passadas, não uma ligação
ativa agora.

## Conclusão
Isto **não é** o popup de autorização USB por aceitar no ecrã (esse caso mostraria
`unauthorized` no `adb devices`, e o dispositivo apareceria como presente no Windows com
Status OK). O sinal aqui é mais grave: **o Windows não está a ver nenhum telemóvel ligado
fisicamente**, apesar de o Danilo dizer que ligou os cabos.

Causas prováveis, por ordem de probabilidade:
1. **Cabo é só-carga** (sem linhas de dados) — muito comum em cabos genéricos/de carregador.
2. Cabo não está bem encaixado numa das pontas (telemóvel ou PC).
3. Ligado a uma porta/hub USB que não chega a este PC (hub sem alimentação, extensão, etc).

Não há nada que o adb ou o Maestro consigam corrigir por software — é preciso confirmar a
ligação física.

## PRECISA DE AÇÃO MANUAL
Sim. Pedido concreto ao Danilo:
1. Confirmar que o cabo usado é um **cabo de dados** (não só de carga) — idealmente o cabo
   original do telemóvel.
2. Reencaixar bem as duas pontas (telemóvel e porta USB do PC).
3. Se possível, testar outra porta USB do PC.
4. Depois de reencaixar, o popup de "Permitir depuração USB?" deve aparecer no ecrã do
   telemóvel — nesse caso sim, precisa que o ecrã esteja desbloqueado para tocar em "Permitir".

Assim que houver sinal físico (`adb devices` a listar `device` ou `unauthorized`), o próximo
ciclo do loop deve repetir os passos 3–5 do pedido original (kill/start-server, confirmar
ecrã desbloqueado + app aberta, disparar `reset-role-screen.yaml`).

---
**ADB DEVICES:** nenhum dos 2 aparelhos detetado (lista vazia, nem "device" nem "unauthorized" nem "offline") · **PRECISA DE AÇÃO MANUAL:** sim — confirmar cabo de dados bem ligado nas duas pontas (o Windows não vê nenhum telemóvel fisicamente ligado agora)
