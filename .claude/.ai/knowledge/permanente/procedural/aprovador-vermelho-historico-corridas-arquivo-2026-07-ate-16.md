---
tema: aprovador-vermelho-historico-corridas-arquivo · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-21
---

# Aprovador-Vermelho — histórico de corridas (arquivo: 2026-07-10 até 2026-07-16)

> Partido de `aprovador-vermelho-historico-corridas.md` em 2026-07-21 pelo `bibliotecario-cerebro`
> (checagem #8 do protocolo — o ficheiro principal tinha chegado a 24123 bytes, ~24 KB). Estas
> corridas cobrem lotes **já todos fechados/decididos** pelo Danilo (ver marcas `estado: superado`
> em cada linha) — mantidas aqui só para histórico/auditoria, não para triagem ativa. Para o
> conhecimento durável de triagem (regras Balde A/B) ver `aprovador-vermelho-triagem.md`; para as
> corridas recentes (2026-07-18 em diante) ver `aprovador-vermelho-historico-corridas.md`.

## Histórico de corridas (arquivado)
| Data | Tipo | Resultado |
|---|---|---|
| 2026-07-10 | manual (gatilho: pedido de E2E completo) | 1 Balde A auto-aprovado (proposta E2E, contas de teste, cash ≤€40); 4 Balde B (`e8aabbcd`, `9996b1fe`, `abeca5d7`, `268aad47`) ficam `nova` |
| 2026-07-11 | loop ligado (cron `*/10` + campainha) | 5 Balde A auto-aprovados (`d2c7d63e`, `e417545f`, `d2838a6e`, `75728e8b`, `f755edbe`); 6 Balde B ficam `nova` (2 novos + 4 conhecidos) |
| 2026-07-12 | FALLBACK 30MIN (item mais antigo parado ≥30min) | 6 `nova` lidos; 1 auto-aprovado Balde A (`670a4840` = `_cron_check_orphan_orders`); 5 mantidos `nova` (Balde B reconfirmado — `admin_audit_log` ação `robot_suggestion_baldeB_reconfirmado`, entrada consolidada) |
| 2026-07-12 19:40 UTC → 2026-07-13 (contínuo) | FALLBACK 30MIN, reconfirmações 9-13 (corridas 7a-15a documentadas em `inbox/aprovador-vermelho-2026-07-13-{7a..15a}-corrida.md`) | 0 itens novos, 0 Balde A em todas as corridas; mesmo lote de 5 Balde B (`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`) reconfirmado com prova reavaliada do zero a cada corrida — **13ª reconfirmação** verificada nesta consolidação por SELECT direto em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`: `id=276a64f6-bdd2-4f02-9491-fbaa19537cf1`, `created_at=2026-07-13 05:49:40 UTC`, `COUNT=13`, `MAX(reconfirmacao_numero)=13`, sequência 9→13 em `created_at` estritamente crescente; ver também `.claude/.ai/reports/aprovador-vermelho-2026-07-13-13a-corrida.md`); fila `robot_suggestions status='nova'` recontada em 5 (COUNT direto, mesma corrida de verificação); teto de 30 mencionado como risco de deadlock **NÃO atingido** (13/30). Nota: ficheiros de corrida mais recentes (14a-15a, ainda por consolidar) podem narrar numeração diferente da soma acima; a 13a corrida foi confirmada consistente com a DB nesta consolidação (Balde B nunca é promovido sozinho; ver Anomalia no ficheiro principal). **estado: superado (por linha 2026-07-16 abaixo)** — este lote de 5 foi finalmente decidido (rejeitado) pelo Danilo em 2026-07-14, fora desta janela de reconfirmações; não é mais o conteúdo da fila `nova`. |
| 2026-07-16 | FALLBACK 30MIN (item `nova` mais antigo parado ~33h) | **Lote antigo de 5 Balde B FECHADO**: confirmado por SELECT direto que `268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3` estão todos `status='rejeitada'`, `reviewed_at='2026-07-14 05:33:09 UTC'`, motivo individual por item (zona protegida dispatch/depósito) — já não em `nova`, não reconfirmar mais. Fila `nova` recontada: **9 itens, todos genuinamente novos** (job periódico 2026-07-14 21:07 → 2026-07-16 05:59 UTC, categorias catálogo/performance/marcações/operação_pedidos/teste-circuito). Triagem: **7 Balde A auto-aprovados** (`6a38f26a`, `f25a38c1`, `f0651a3c`, `1097b4a4`, `bfe65453`, `b91ec56b`, `1242c17e`; `aprovador_vermelho_auto_baldeA=true` confirmado; status final `aprovada` reverificado por SELECT); **2 Balde B ficam para o Danilo** (`8c9e9d08` = otimizar `_appointment_cron_auto_no_show`; `20248533` = reduzir no-show citando "políticas de depósito"); status final `nova` reverificado por SELECT). Fila `nova` final = 2 (confirmado por COUNT direto). Relatório completo: `.claude/.ai/reports/aprovador-vermelho-2026-07-16-fallback30min.md`. |

## Ver também
- `permanente/procedural/aprovador-vermelho-historico-corridas.md` — log corrida-a-corrida ATIVO (2026-07-18 em diante).
- `permanente/procedural/aprovador-vermelho-triagem.md` — conhecimento de triagem (regras Balde A/B, funções cron conhecidas, anomalias, mecanismos de aprovação/aviso).
