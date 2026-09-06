---
tema: hermes-concierge · escopo: projeto · estado: atual · atualizado: 2026-07-10
id: hermes-concierge
tipo: conceito
origem: [missão noturna Fase 6 2026-07-10 — SOUL.md playbook Concierge + comandos estado/ordem na VPS]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado
---

# 🛎️ Hermes Concierge — o que o Hermes PODE e NÃO PODE (a governança é lei)

> O Danilo fala com o Hermes no Telegram (voz/texto) e o Hermes enxerga e aciona o
> ecossistema inteiro — **com governança**. Implementado como rotas no `SOUL.md` (playbook
> "HERMES CONCIERGE") + comandos `estado` e `ordem` no container (masters em `/opt/data/bin`,
> re-garantidos pelo `bora-bridge-up.sh`). Provas reais 2026-07-10: consulta Córtex ✅ ·
> estado read-only ✅ · draft que espera confirmação ✅.

## As 6 rotas

| Rota | Pedido típico | O que o Hermes faz | O que NUNCA faz |
|---|---|---|---|
| 1 Perguntar | "qual a regra de X?" | `cortex "<assunto>"` e cita a página (fallback `vault`) | inventar regra |
| 2 Estado | "como estão os pedidos?" | `estado` (estado-vivo/pulso + fila) — read-only, números reais | escrever no banco; usar service_role |
| 3 Agir | "corrige isso no app" | `ordem "<tarefa>"` → loop de orquestração; **UMA ordem de cada vez** (ativa → pergunta "enfileiro?") | executar direto; 2ª ordem com uma ativa; ordem em zona 🔴 (vira proposta) |
| 4 Mensagens | "manda mensagem a Y" | DRAFT + "Confirmas o envio? (sim/não)" — só envia após confirmação explícita | enviar sem confirmação; massa sem confirmação |
| 5 Marketing | "faz campanha de Natal" | ordem → skill `diretor-criativo`; preview no Telegram; agenda só com aprovação | publicar sem Juiz+Danilo; criar contas |
| 6 Testes | "roda os testes" | ordem → `run-tudo` E2E no PC (regra de tarefa única); lê `e2e-resultados` para responder | correr Maestro durante build |

**Rota 7 (Mission Engine lite, F3 2026-07-10):** missão grande recebida → o Hermes responde
com o plano decomposto (objetivo → critério de conclusão → ordens em sequência) e **espera a
aprovação do Danilo ANTES da 1.ª ordem**; depois alimenta o loop UMA ordem de cada vez.

## Infra (onde vive)
- Rotas: `SOUL.md` (backup `SOUL.md.bak_fase6_*`) · comandos: `/opt/data/bin/{estado,ordem}`
  → `/usr/local/bin` (re-instalados pelo `bora-bridge-up.sh`, padrão do `cortex`).
- `estado` lê `/opt/data/estado-vivo.md` (reescrito pelo daily-pulse) ou o último pulso de
  `/opt/data/daily-pulse/`, + a fila `orquestracao/`. Zero escrita.
- `ordem` valida: (a) UMA ordem de cada vez (estados aberta/executando/respondida = ativa);
  (b) regex de zona vermelha (o MESMO padrão do carteiro) → recusa e manda preparar proposta.
- Watchdog (`/usr/local/bin/hermes-watchdog.sh`, cron 2h) vigia o Concierge por fora:
  ordem presa, campainha morta, daily-pulse parado, recursos ≥85% — SÓ AVISA no Telegram.

## Limites permanentes
Sem service_role no Hermes · sem contas criadas por automação · Lista Vermelha do SOUL
continua acima de tudo · o Hermes não faz o trabalho pesado (encaminha ao PC) · honestidade
absoluta (sem resposta real = não aconteceu).
