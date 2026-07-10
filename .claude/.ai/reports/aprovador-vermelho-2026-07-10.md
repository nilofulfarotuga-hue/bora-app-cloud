# Desbloqueio da fila vermelha — relatório (2026-07-10, loop noturno)

**Contexto:** ordem para "desbloquear o sistema de aprovação" — a fila 🔴 da Central está invisível
ao Danilo, logo nenhuma proposta vermelha podia ser aprovada (deadlock). 4 passos pedidos.

## Diagnóstico honesto (a raiz)
O problema real é **visibilidade** (o Danilo não vê a fila), **não** "falta um robô que aprove por
ele". A cura de "não vejo a fila" é **surfaçar a fila ao Danilo** — não **aprovar em nome dele**.
Auto-aprovar itens 🔴 desassistido, à noite, colide com **duas** regras vinculativas:
- `CLAUDE.md`: *"A ÚNICA travagem é dinheiro real… Só aplica depois de o Danilo responder 'vai'."*
- Memória do Danilo: *"MODO PROTECÇÃO TOTAL = aprovar CADA tarefa, não por lote."* (esta ordem abre
  literalmente com "⚠️ MODO PROTECÇÃO TOTAL ⚠️").

Por isso: **fiz as partes seguras e protetoras; preparei o resto a uma palavra da ativação; NÃO liguei
auto-aprovação de dinheiro sozinho.**

## O que FOI feito (executado agora)

### ✅ PASSO 3 — furo do filtro 🔴 fechado (protetor, seguro)
`carteiro.sh` (T3, `grep -iE`) só tinha `bora_tokens` → deixava passar por **verde**:
`Bora Tokens` (espaço), `tokens_applied`, `tvde…token` (foi como a **ordem 8448** passou).
Ampliei **cirurgicamente** (sem engolir JWT/fcm token genérico — para não piorar o deadlock com
falsos-positivos):
```
bora_tokens  →  bora[ _]tokens?|tokens?_applied|tvde[a-z_ ]*tokens?
```
Ficheiro: `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh` (fonte da verdade).
⚠️ **Este ficheiro CORRE NO HOST DA VPS** (`/root/orquestracao/`). Editei o repo (fonte); o **deploy
à VPS é passo separado** (headless não faz push/ssh fiável — ver memória). Para deployar:
`scp` do ficheiro para `root@…:/root/orquestracao/carteiro.sh` OU copiar a linha `RED=` à mão.

### ✅ PASSO 2 — agente `aprovador-vermelho` criado (TRIAGE + SURFACE)
`.claude/agents/aprovador-vermelho.md`. Comportamento **por defeito (seguro, sempre ligado):**
lê a fila 🔴 (só leitura), tria em **Balde A** (leitura/falso-positivo → recomenda aprovar com motivo)
vs **Balde B** (dinheiro real → **sempre** ao Danilo via Telegram, nunca auto), surfaça tudo num
relatório + Telegram por item. **Não altera lógica de dinheiro — só roteamento.** Registado no
`exercito.md` (**passa a 30 agentes**).

## O que NÃO foi feito — e porquê (precisa do teu "vai")

### ⏸️ PASSO 1 — aprovar as propostas 🔴 presas (prop-612b768d, prop-3650dbb4, prop-2d3f2ea3)
Estas vivem na Central do Córtex (VPS/MCP), onde a ponte é **read/propose, escrita OFF**. Aprovar
propostas 🔴 vivas é **exatamente** o ato humano-gated. Não as auto-aprovei desassistido à noite.
→ **Ação tua:** aprova-as na Central, OU responde "vai — aprova prop-612b768d/3650dbb4/2d3f2ea3" e eu
encaminho. (Nota: prop-3650dbb4 e prop-2d3f2ea3 são duplicadas — usa uma, descarta a outra.)

### ⏸️ PASSO 4 — ligar o auto-aprovar de Balde A ao loop
A capacidade existe no agente mas está **OPT-IN, DESLIGADA**
(`platform_settings.aprovador_vermelho_auto_baldeA=false`). Ligá-la = decisões 🔴 (mesmo que só
Balde A) a correr desassistidas à noite, contra a tua própria regra de protecção total.
→ **Ação tua (1 palavra):** responde **"vai — liga auto-Balde-A"** e eu ponho a setting a `true`.
Enquanto isso, o agente já resolve o deadlock em modo seguro (surfaça + recomenda; tu tocas 1×).

## Guardrails respeitados
- Zonas 🔴 continuam protegidas contra **ESCRITA** (a Trava intacta). Mudei **só o roteamento**.
- Nenhuma lógica de dinheiro (pricing/dispatch/Stripe/tokens/ledger) tocada.
- Filtro T3 ficou **mais** apertado, não menos.

## Push
Branch `autonomous-night-2026-04-29`. Commit local feito; push headless pode falhar (credencial de
sessão) — se falhar, o loop concorrente empurra, ou usa a deploy key da VPS.
