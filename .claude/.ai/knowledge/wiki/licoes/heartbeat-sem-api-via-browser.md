---
tema: licao · escopo: loops/autonomia · estado: atual · atualizado: 2026-07-11
id: heartbeat-sem-api-via-browser
tipo: licao
zona: verde
---

# O loop fecha-se pelo agente que CLICA, sem custo de API

## Problema
O Claude.ai é a cabeça que decide a próxima ordem do loop de orquestração, mas é
**cego ao estado** enquanto ninguém lhe contar: uma ordem que chega a estado final
(aprovada / travada / zona_vermelha / cancelada) ou um teste novo não o acordam. A
forma óbvia — chamar a API do Claude a cada mudança — **custa dinheiro**, e o Danilo
não quer pagar API nenhuma.

## Insight
Já existe um agente que devolve resultado ao Claude.ai **sem API**: o
`browser-operador` (Claude in Chrome, sessão Pro do Danilo, já pareado). Em vez de
*chamar* o Claude.ai, ele **abre um chat e escreve**. O loop fecha-se pela mão que
já clica — custo de API = zero.

## Mecanismo (`heartbeat-browser`, 🟢 Core)
1. **Gatilho + anti-spam** — `.claude/scripts/heartbeat-browser.py` (schtask PC `*/10`):
   lê um *watermark barato* (assinatura das ordens em estado final na fila local +
   último `e2e_log`/`orders` por SELECT anon). Só escreve `pending.trigger` quando
   algo avança. Primeira corrida **semeia sem disparar** (o backlog atual não é novidade).
2. **Ação** — o browser-operador vê `pending.trigger`, abre `claude.ai/new` (**chat
   NOVO** — mais seguro que reusar o chat longo do Danilo, que pode travar), na **conta
   certa** (regra dos 2 browsers: o perfil com a sessão do Danilo logada), cola a
   **frase fixa**, envia, fecha, e move o trigger para `consumidos/`.

## Regras que evitam estragar
- **Anti-spam de 2 camadas:** (1) o script só dispara em mudança real; (2) o operador
  consome o trigger. Sem mudança → **0 chats** (nunca encher o Danilo de chats vazios).
- **Chat NOVO, nunca o chat longo** do Danilo (menos risco de travar).
- **Nunca fazer login** numa conta sem sessão já ativa (regra do `HERMES_CHROME.md`):
  se nenhum browser tem o claude.ai do Danilo logado, **abortar** e deixar o trigger.
- **Fonte que degrada não dispara sozinha:** se o SELECT ao Supabase falhar (rede/RLS),
  a fonte fica vazia e é ignorada — não gera falso positivo.
- Read-only do lado do gatilho; a frase é benigna e o Claude.ai tem os seus guardrails
  (Trava / Juiz / kill switch). **Reversível:** apagar o schtask desliga tudo.

## Armadilha encontrada (2026-07-11)
`python` **não está no PATH** do ambiente (headless corre como user `hermes`;
`LOCALAPPDATA`/`HOME` apontam para hermes — ver `agent-memory`). O interpretador do
Danilo está em `C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe`.
O schtask usa esse caminho **completo**, não `python`.

Relacionado: [[executor-vivo-mas-tarefa-pesada-esgota-tentativas]] ·
[[observabilidade-e2e-tempo-real]] · [[ponte-loop-nao-devolve-output]]
