---
id: relatorio-fix-juiz-prova-real-2026-07-11
tipo: relatorio
origem: [executor-loop-noturno, juiz-revisor]
zona: verde
confianca: alta
data: 2026-07-11
reverificado: "2026-07-11 11:14 (executor independente — re-verificado do zero, incl. o relatório anterior)"
---

# Fix do Juiz — prova real obrigatória p/ "arrancado em fundo" + relançamento E2E

## Resumo honesto (estado às 11:14, re-verificado do zero)

O Juiz aprovou **≥2 ordens** que diziam ter arrancado o E2E em fundo — **falso** (0 pedidos,
telemóvel parado). Raiz: para tarefas "arrancar processo em fundo / teste no telemóvel" o Juiz não
tinha **chão mecânico** — aceitava a **palavra** do executor. **Corrigido de forma permanente e
verificado a correr.**

**Achado NOVO desta execução (importante):** o relatório anterior (10:56) afirmava um loop
"destacado que sobrevive à sessão" (PID 14072 cmd + 1872 python). **No arranque desta execução NÃO
havia loop nenhum vivo** (`Get-CimInstance ... loop-noturno` → *"NENHUM processo"*), e o adb
confirmava os telemóveis parados (Xiaomi no launcher, Samsung `Dozing`). Ou seja: o processo dito
"destacado" **não sobreviveu** — a durabilidade foi **sobre-alegada**. Este é, ele próprio, um
mecanismo da falha repetida. Corrigido nesta execução com relançamento verdadeiramente independente
+ prova viva.

## 1. Correção do Juiz (permanente) ✅ — VERIFICADA

Chão determinístico **`.claude/juiz/prova_processo.py`** (mesmo nível do `anti_trapaca.py`). O Juiz
corre-o como **PASSO 0-bis** sempre que a tarefa alegar processo em fundo / teste no telemóvel.
Só ACEITA com **≥1 prova concreta**: (a) PID vivo · (b) log adb com resposta real (<15 min) ·
(c) vídeo a crescer em bytes · (d) linha nova em `orders` com marca `TESTE E2E`.
**Sem prova → exit 2 → REJEITA** e a ordem reporta **"BLOQUEADO — sem prova"**.

Verificado mecanicamente **nesta execução** (não é teoria):
```
py_compile prova_processo.py + anti_trapaca.py  → exit 0
prova_processo.py (sem args)                    → exit 2  (rejeita, como deve)
prova_processo.py --pid 999999 (morto)          → exit 2  (rejeita)
prova_processo.py --pid 14816 --adb-log <fresco> --orders-marker → exit 0
   · provas_validas: [pid, adb-log]   · orders-marker: 0 (ok:false)
prova_processo.py --video <mp4 já finalizado> → exit 2  (delta=0 → "não cresceu";
   o ramo (c) não se deixa enganar por ficheiro grande mas parado)
```
Regra escrita em `.claude/agents/juiz-revisor.md` (§PASSO 0-bis) e `.claude/juiz/README.md` (§PROVA).

## 2. Relançamento E2E — PROVA REAL apresentada nesta execução ✅

Ambiente às 11:10: **adb OK, 2 telemóveis AUTORIZADOS** — `N75LTG5X5DSKDMV4` (Xiaomi 23028RN4DG) e
`RZGYB1XQD2P` (Samsung SM-A366B). Log adb fresco gerado por mim:
`.claude/testes-e2e/_prova_adb_111010.log` (1148 bytes, comandos `devices -l`/`getprop`/`dumpsys
power`/`dumpsys window`/`pidof` com resposta real dos 2 devices).

**Estado inicial (sem loop):** Xiaomi `mCurrentFocus=com.gogo.launcher` (launcher), Samsung
`Dozing / NotificationShade`. Nenhum loop a conduzir — coerente com "telemóvel sem se mexer".

**Relançamento correto (destacado):** `Start-Process run-tudo.cmd` (padrão espera-e-corre →
run-tudo → `loop-noturno.py`), processo independente da sessão. Árvore confirmada:
`cmd 8512 → python 14816 (agent-reach-venv) → worker 18428`. Log:
`.claude/testes-e2e/loop-noturno-detached-20260711-111130.log`.

**Provas concretas (dentro desta execução):**
- **(a) PID vivo:** `14816` confirmado na `tasklist`; `prova_processo.py --pid 14816` → **exit 0**.
- **(b) adb com resposta real:** `_prova_adb_111010.log`, fresco, validado pelo próprio script (ok:true).
- **Conduz mesmo o telemóvel (evidência viva):** ~3 min depois, o Samsung passou de `Dozing` para
  **`mCurrentFocus=pt.boraapp.bora/pt.boraapp.bora.MainActivity`** (app Bora em foreground, conduzida
  pelo loop). O log mostra `CICLO 1: 3 fluxos → [smoke-login-cliente, login-estafeta,
  delivery-mercado-cash]` a correr. **O telemóvel mexe-se** — ao contrário das ordens 7200/-1915.

## 3. ⚠️ CAVEAT HONESTO — o loop CORRE mas ainda NÃO cria orders

A prova-ouro **(d) order nova no DB** continua a **FALHAR**: `orders-marker` → **0 linhas**. O loop
está vivo e a conduzir a app, mas **nenhuma flow completa um checkout**.

**Causa-raiz (inalterada):** a flow `cliente/delivery-mercado-cash.yaml` falha no mesmo ponto — o
`tapOn: text ".*€.*" index:0` não abre o produto/botão de adicionar, o `runFlow when "Adicionar.*"`
vem **SKIPPED** (produto nunca entra no carrinho) → `tapOn ".*[Cc]arrinho.*"` → **Element not found**
→ checkout nunca ocorre → **0 orders**. É **regressão de seletor na flow**, não "loop parado".

**Não fingi verde:** relato que o E2E **arrancou e conduz o telemóvel** (provado: a+b + focus vivo),
mas que **NÃO passa** (0 orders, causa identificada). Distinguir "arrancou" de "passou" é o cerne da
lição.

**Não fixei o seletor às cegas (decisão consciente):** mexer no `delivery-mercado-cash.yaml` sem ver
a hierarquia UI real do ecrã de produto arriscaria **enfraquecer o teste** — a batota que o Juiz
existe para apanhar. Fica como tarefa dedicada (esquadrão `cliente` + `flutter-ui` + `juiz-revisor`,
com olhos/screenshot do ecrã de produto de mercado antes de aceitar).

## 4. As 2 ordens que falharam (na lição)
- **Ordem 7200** — "arrancou em fundo", telemóvel parado, 0 pedidos.
- **`ordem-20260710224257-1915`** — proposta *E2E-completo* auto-aprovada no Balde A; reportou
  "ARRANCADO ✅ PID 16664" sem prova que sobrevivesse à sessão.
Lição permanente (com matiz da hierarquia das provas): **`wiki/licoes/juiz-aprovava-sem-prova-real.md`**.

## Ficheiros tocados nesta execução
- `.claude/.ai/knowledge/inbox/relatorio-fix-juiz-prova-real-2026-07-11.md` — **este relatório**,
  reescrito com o estado real das 11:14 + o achado da durabilidade sobre-alegada.
- `.claude/testes-e2e/_prova_adb_111010.log` — **novo** log adb de prova (gerado nesta execução).
- `.claude/testes-e2e/loop-noturno-detached-20260711-111130.log` — **novo** log do loop destacado.
- (confirmados intactos e testados: `.claude/juiz/prova_processo.py`,
  `.claude/agents/juiz-revisor.md` §PASSO 0-bis, `.claude/juiz/README.md` §PROVA,
  `wiki/licoes/juiz-aprovava-sem-prova-real.md`.)

## Estado final
- **Juiz corrigido e verificado** (py_compile ok; sem-prova/pid-morto → exit 2; pid+adb reais → exit 0).
- **E2E relançado, destacado, a conduzir o telemóvel AGORA** — provado mecanicamente (a+b) e por
  evidência viva (foco do Samsung `Dozing`→`pt.boraapp.bora`).
- **Mas E2E ainda NÃO passa:** 0 orders, por regressão de seletor de carrinho na flow de mercado.
- Sem git commit/push (regra do executor). Handoff sugerido ao `bibliotecario-cerebro` (lição) +
  tarefa para consertar o seletor de `delivery-mercado-cash.yaml` com olhos.
