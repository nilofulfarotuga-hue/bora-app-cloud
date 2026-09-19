---
id: aprovador-vermelho-2026-07-10
tipo: relatorio
origem: [aprovador-vermelho, loop-noturno-executor]
data: 2026-07-10
zona: verde
confianca: auto
---

# Aprovador-Vermelho — corrida manual 2026-07-10

Corrida única, manual, sobre a fila de propostas pendentes (incl. o pedido de **E2E completo de todos os fluxos**). Auditado em `admin_audit_log` (id `2ce145cf-cea6-4f35-a3a2-bc580589c17c`).

## Fila lida (real)
- `robot_suggestions` → **4 itens `status=nova`** (todos N3, sev 5).
- Fila do carteiro (Córtex `orquestracao`) → 22 ordens, **nenhuma em `zona_vermelha`**.
- A "proposta E2E completo" **não é uma linha de fila** — vinha dentro da ordem-mãe (`ordem-20260710224257-1915`); triada como proposta conceptual.

## Balde A — leitura/teste (AUTO-APROVADO)
| Item | Decisão | Motivo |
|---|---|---|
| **proposta-E2E-completo-todos-fluxos** | ✅ APROVADA | Suite usa **só contas de teste** (`teste-*@bora.app`, "NUNCA produção/Stripe"); único fluxo com dinheiro (`delivery-mercado-cash`) é **cash, máx €40, sem charge Stripe**; `db_checks` sobre `orders`/`ledger_entries` são **read-only**; TVDE é `manual_2_devices` e o runner **não o corre**. Não toca lógica de dinheiro nem escreve saldo. |

**Total Balde A auto-aprovado: 1.**

## Balde B — dinheiro/zona protegida (FICA PARA O DANILO — não aprovado)
Resumo de 2 linhas por item:

1. **`e8aabbcd`** — Pedido preso propõe intervir/reatribuir → mexe no **dispatch (🔴)**. Risco: regressão no matching/reatribuição.
2. **`9996b1fe`** — Auto-reatribuição com TTL → altera lógica do **dispatch_engine (🔴)**. Risco: regressão no matching.
3. **`abeca5d7`** — Otimizar `_appointment_cron_auto_no_show` → função que **afeta cobrança de no-show (🔴)**. Risco: cobrar/liberar slot errado.
4. **`268aad47`** — Otimizar `bora_dispatch_maintenance` → função de **dispatch (🔴)**. Risco: regressão no despacho.

**Total Balde B para o Danilo: 4.** Ficam `status=nova`, intocados. Regra aplicada: dúvida → Balde B; nenhum é leitura pura.

`platform_settings`: `aprovador_vermelho_auto_baldeA = true`, `robot_b_enabled = true`.

## Aviso do Telegram — CONFIRMADO A FUNCIONAR ✅
Enviada 1 mensagem de teste real via VPS (`hermes send -t telegram`, container `hermes-agent-fvnc-hermes-agent-1`). Resposta: **"Sent to telegram home channel (chat_id: 6731890157)"**, exit 0. Canal operacional de novo.

## E2E completo — ARRANCADO ✅ (porque o aprovador aprovou)
- Lançado `loop-noturno.py` (single-device, device cliente `RZGYB1XQD2P`; ambos os telemóveis ligados no adb).
- **PID 16664**, arrancou limpo: `CICLO 1 → ['smoke-login-cliente', 'login-estafeta', 'delivery-mercado-cash']` (TVDE marcado MANUAL-2-DEVICES, não bloqueia).
- Progresso/resultado vão para `.claude/.ai/knowledge/inbox/e2e-resultados-2026-07-10.md` + `resultados-2026-07-10.json` + vídeos em `gravacoes/2026-07-10/`.
- Parar a meio: criar ficheiro `PARAR` em `.claude/testes-e2e/`.

## Contagens finais
- Balde A auto-aprovados: **1** (E2E).
- Balde B para o Danilo: **4** (N3 dispatch/no-show).
- Telegram: **OK**. E2E: **a correr**.

## Notas honestas
- Não alterei nenhuma lógica de dinheiro; **sem git commit/push**.
- Os 4 Balde B não geraram row nova — continuam `nova`, aguardam ato humano.
