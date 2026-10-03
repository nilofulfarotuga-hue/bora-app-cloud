---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — Corrida 2026-07-19 ~11:52 UTC (gatilho: pedido do orquestrador)

## Contexto do gatilho
O pedido citava "pelo menos 4 itens novos, mais recente created_at=2026-07-19T11:07:12". Ao consultar
`robot_suggestions` (status='nova') nesta corrida (11:52:17 UTC), esse snapshot já estava desatualizado:
os 4 itens tinham sido decididos por execução concorrente **antes** desta corrida começar (ver
"Confirmado por SELECT" abaixo) — mesmo padrão já registado na 5ª corrida (~11:32 UTC) em
`permanente/procedural/aprovador-vermelho-triagem.md`. Fila real no momento da triagem: **2 itens `nova`**.

## Itens já decididos antes desta corrida (confirmados por SELECT, não decididos por mim)
| id | título | dedup_key | status final | quem/quando |
|---|---|---|---|---|
| `88bebaed-7e1f-4c0c-916a-b8756f078106` | Marcar produtos sem foto para revisão manual | `catalogo:produtos-sem-foto-revisao` | `aprovada-emerson` | agente (Balde A), 11:20:14 UTC |
| `86dc8990-a964-421a-85cc-329fb45a0591` | Marcar produtos sem categoria para revisão manual | `catalogo:produtos-sem-categoria-revisao` | `aprovada-emerson` | agente (Balde A), 11:20:16 UTC |
| `01a67895-05fc-4a07-8b98-0bdef3f1c1a2` | Investigar e otimizar queries lentas de cron (v3) | `infra:otimizar-queries-cron-lentas-v3` | `aprovada` | **Danilo** (`robot_approve_plan`, JWT admin real), 11:09:00 UTC |

## Balde A (leitura/falso-positivo) — nesta corrida: 0
Nenhum item Balde A ficou por decidir nesta corrida (os 2 catálogo já tinham sido auto-aprovados antes).

## Balde B (dinheiro real — precisa do Danilo): 2, ambos reconfirmados (não novos)
| id | título | motivo | reconfirmação nº |
|---|---|---|---|
| `77c31fff-0330-4981-813a-f2268c6f7bbe` | Investigar e otimizar queries lentas de cron | Item agrupado: `_cron_check_orphan_orders`(A) + `_cron_check_ghost_drivers`(A) + `_appointment_cron_auto_no_show`(**B sempre** — decide reter/devolver depósito de cliente no-show). Regra de item agrupado (confirmada 2026-07-18/19): item inteiro cai em Balde B, sem aprovação parcial. | 8ª |
| `29ea4b41-1e28-420e-a7d3-2995c335d7e5` | Investigar e otimizar queries lentas de cron (v2) | Mesmo padrão agrupado, mesma evidência (top-3 queries lentas), dedup_key `-v2`. | 6ª |

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico (ou decide diretamente
na Central `AdminRobotSuggestionsScreen` / `robot_approve_plan`).

## Ações desta corrida
- Telegram enviado com sucesso (bridge SSH PC→VPS, `Sent to telegram home channel`, chat_id `6731890157`).
- `admin_audit_log`: 2 novas entradas `robot_suggestion_baldeB_reconfirmado`
  — `c6779597-8ac9-41c7-b260-3a4afe05e523` (`77c31fff`) e `ce3659e5-c5d4-4ba3-9a3d-a4c298fa0856`
  (`29ea4b41`), ambas `created_at=2026-07-19 11:53:25.958198 UTC`, confirmadas por `RETURNING` da INSERT.
- Zero alteração de lógica de negócio, RPC, migration ou código sensível.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **ligado** (confirmado por conhecimento prévio;
não houve item Balde A nesta corrida para reconfirmar o valor por SELECT direto).

## Nada ambíguo / nada bloqueado por falta de permissão nesta corrida.
