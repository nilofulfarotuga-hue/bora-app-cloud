# Relatório — `heartbeat-browser`: fechar o loop SEM API paga (2026-07-11)

## O que se montou
Mecanismo que fecha o loop de orquestração **sem custo de API**, usando o agente que
já clica — `browser-operador` (Claude in Chrome, sessão Pro do Danilo, já pareado) —
como a ponte que devolve o resultado ao Claude.ai.

### Peça 1 — gatilho + anti-spam (feito e testado)
`.claude/scripts/heartbeat-browser.py` — detetor PC-side (schtask `*/10`):
- Lê um **watermark barato**: assinatura das ordens em estado **final** na fila local
  (`orquestracao/*.md`, estados `aprovada|travada|zona_vermelha|cancelada`) + último
  `e2e_log` e `orders` por **SELECT anon** (PostgREST). Fonte que falha degrada em
  silêncio (não gera falso positivo).
- **Só** escreve `pending.trigger` quando algo avança. 1ª corrida **semeia sem disparar**.
- Modos: `--status`, `--dry`, `--force`. Nunca imprime segredos (lê a key de `.env` em runtime).

### Peça 2 — ação do browser-operador (spec escrita)
`.claude/.ai/hermes/heartbeat-browser/browser-operador.md`: quando existe
`pending.trigger` → abrir `claude.ai/new` (**chat NOVO**), na **conta certa** (regra
dos 2 browsers: o perfil com a sessão do Danilo logada), colar a **frase fixa**,
enviar, fechar, e mover o trigger para `consumidos/`. Nunca faz login sem sessão ativa.

**Frase fixa (verbatim, no trigger):** "Bora Loop automatico: puxa o contexto do Bora
pela tua memoria e Cortex, verifica o estado das ordens (cortex_ler) e dos testes
(SELECT em orders e e2e_log no Supabase), e age no que for preciso - dispara a proxima
ordem se algo travou ou ficou incompleto, ou responde que esta tudo ok se nao ha nada
pendente. So avisa o Danilo se for importante ou decisao de dinheiro."

## Teste (1x)
Corri a sequência no PC (venv python; base do Danilo confirmada em `...Python312`):
1. **seed** → silêncio (estado semeado). ✅
2. **`--dry`** → "sem mudanca — silencio" (anti-spam confirmado). ✅
3. **`--force`** → `pending.trigger` escrito com a **frase exata** (verificado no ficheiro). ✅

O detetor lê mesmo `e2e_log` (id 355) e `orders` via anon key — leitura viva a funcionar.

**Não executei o clique real no claude.ai:** sou executor headless e não tenho ferramenta
para conduzir a extensão interativa Claude-in-Chrome (é essa, por design, a ponte — não eu).
O `pending.trigger` está **staged** com a frase pronta; o envio ao vivo é o passo do
browser-operador. Como o schtask ainda não está instalado e nenhum operador está a vigiar,
não há risco de spam.

## Ativar (2 passos, reversíveis)
1. `.claude/.ai/hermes/heartbeat-browser/instalar-schtask.cmd` → regista o cron PC `*/10`
   (usa o python completo do Danilo, pois `python` não está no PATH). Desligar:
   `schtasks /Delete /TN "Bora-heartbeat-browser" /F`.
2. Pôr o browser-operador a vigiar `pending.trigger` (spec no `browser-operador.md`).

## Ficheiros tocados
- **novo** `.claude/scripts/heartbeat-browser.py` (gatilho + anti-spam)
- **novo** `.claude/.ai/hermes/heartbeat-browser/browser-operador.md` (spec da ação)
- **novo** `.claude/.ai/hermes/heartbeat-browser/instalar-schtask.cmd` (cron PC `*/10`)
- **novo** `.claude/.ai/hermes/heartbeat-browser/{state.json, pending.trigger, heartbeat-browser.log}` (artefactos do teste)
- **novo** `.claude/.ai/knowledge/wiki/licoes/heartbeat-sem-api-via-browser.md` (lição)
- **edit** `.claude/.ai/knowledge/permanente/semantica/loops.md` (loop 🟢 heartbeat-browser + nota)
- **novo** este relatório

## Verificação 2ª passagem (2026-07-11, executor noturno)
Re-corri o gatilho para confirmar que continua vivo e sem regressões:
- `--status` → watermark **agora == guardado** (`orders_final f65b7b9…`, `e2e_latest 355`,
  `db_orders_latest 947a903…`) e `trigger_pendente=true` (o trigger do `--force` continua staged). ✅
- `--dry` → "sem mudança de estado — silêncio" (anti-spam camada 1 confirmado). ✅
- Leitura viva confirmada: o SELECT anon lê mesmo `e2e_log` (id 355) e `orders`. ✅
- Criei a pasta **`consumidos/`** (com `.gitkeep`) — o destino que faltava para a **anti-spam
  camada 2** (o operador move `pending.trigger` → `consumidos/consumido-<ISO>.trigger` após enviar).

**Continua por fazer (inerente ao design):** o **clique real** no `claude.ai`. É o passo
interativo do `browser-operador` (Claude-in-Chrome, sessão Pro do Danilo) — não há ferramenta
headless que conduza a extensão, e é essa exatamente a ponte. O gatilho→trigger está provado
mecanicamente (frase verbatim já no `pending.trigger`); falta só instalar o schtask `*/10` e pôr
o operador a vigiar `pending.trigger`.

## Notas
- Não fiz commit nem push (regra do executor). Ficheiros staged localmente.
- Zona **verde**: read-only sobre estado; não toca dinheiro/dispatch/tokens/RLS. Sem Lista Vermelha.
