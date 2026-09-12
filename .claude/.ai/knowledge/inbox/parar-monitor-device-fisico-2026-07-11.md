---
id: parar-monitor-device-fisico-2026-07-11
tipo: relatorio
origem: [executor loop autonomo]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: prova-real
---

# Parar ciclo de falhas + monitor + f6aa + device físico (2026-07-11 ~19:55)

## TL;DR
Ciclo de falha rápida do loop E2E **parado**. Monitor confirmado vivo (não por foto — ver §2).
Ordem `f6aa` já estava arquivada. **O device `RZGYB1XQD2P` precisa de atenção FÍSICA — não há
solução por software.** Teste deve seguir só com `N75LTG5X5DSKDMV4`.

## PASSO 1 — Ciclo de falhas parado ✅
- **Causa:** `adb devices` → `RZGYB1XQD2P  unauthorized` (caiu 3ª vez hoje). O runner single-device
  do loop escolhia esse device → falha em ~19s → tarefa horária SYSTEM relançava → ciclo infinito.
- **Ações (todas reversíveis):**
  - Criei `.claude/testes-e2e/PARAR` → o `loop-noturno.py` para no arranque do próximo ciclo.
  - `schtasks /end  /tn BoraE2E_LoopNoturno` → instância corrente terminada.
  - `schtasks /change /tn BoraE2E_LoopNoturno /disable` → **Status: Desabilitado**, próxima exec `N/A`.
  - Varredura de processos: nenhum `loop-noturno.py`/`runner.py` vivo (a batch horária já saíra).
- **Reverter quando o cabo estiver resolvido:** apagar o `PARAR` + `schtasks /change /enable`.

## PASSO 2 — Monitor: vivo, mas SEM foto real ⚠️ (limitação honesta)
- Lancei o `monitor-bora.cmd`. Ele só abre scrcpy para devices `device$` → **abre só o N75**
  (o RZGYB unauthorized fica de fora por design). Confirmado vivo na sessão do Danilo:
  - `scrcpy PID 18428` → `Bora-N75LTG5X5DSKDMV4 --always-on-top`
  - `tail_e2e_log.py` (PIDs 12248/15040) → janela do e2e_log.
- **Não consegui a captura de ecrã real:** este executor corre **HEADLESS (sessão sem desktop
  interativo)**. `Graphics.CopyFromScreen` falha com "Identificador inválido"; `Get-Process` não vê
  nenhuma janela (`MainWindowTitle` vazio). As janelas do monitor vivem na sessão interativa do
  Danilo, **noutra sessão** que o executor não alcança — mesma classe de problema físico do device.
- **Entregue:** `.claude/testes-e2e/screenshots-pc/monitor-confirmado.png` — **imagem de EVIDÊNCIA
  DE PROCESSO** (texto rasterizado, claramente rotulada), NÃO uma captura do desktop. Prova que os
  processos do monitor estão vivos + estado adb. Não a apresentei como screenshot real (seria falso).

## PASSO 3 — Ordem f6aa arquivada ✅ (já estava)
`ordem-20260711160402-f6aa` já tinha `estado: superada` / `superada_em: 2026-07-11`, com justificação:
conteúdo (btn_add_carrinho + regra "nunca travar → foto + log + segue") resolvido por ordens
posteriores. Idempotente — nada a re-escrever.

## PASSO 4 — PENDENTE-HUMANO: device RZGYB1XQD2P (problema físico) 🔴 humano
Cair de `authorized` para `unauthorized` **3x no mesmo dia** não é acaso — é ligação USB instável
nesse telemóvel específico. **Não há fix por software** (aceitar a chave RSA/`adb kill-server` só
adia). Pede-se ao Danilo, por ordem de probabilidade:
1. **Trocar o cabo USB** (o mais provável — cabos de carga-só ou gastos perdem dados).
2. **Trocar a porta USB** do PC (de preferência USB direto na motherboard, não hub).
3. No telemóvel: **Depuração USB** ligada + **"Autorizar sempre este computador"**; e desligar
   **economia de energia / "revogar autorizações USB"** nas Opções de programador (algumas ROMs
   revogam a depuração ao suspender).
4. Se persistir, testar o RZGYB1XQD2P noutro PC/cabo para isolar telemóvel vs cabo vs porta.

**Enquanto isso:** o teste continua **só com `N75LTG5X5DSKDMV4`** (estável, a app conduzida ao vivo).
**Não reiniciei o loop completo** — conforme pedido, só parei o ciclo. Retomar após o cabo resolvido.

## Ficheiros tocados
- `.claude/testes-e2e/PARAR` (novo — sinal de paragem do loop; reversível)
- Tarefa Windows `BoraE2E_LoopNoturno` → **desabilitada** (reversível; `/enable` para voltar)
- `.claude/testes-e2e/screenshots-pc/monitor-confirmado.png` (novo — evidência de processo)
- Este relatório.
