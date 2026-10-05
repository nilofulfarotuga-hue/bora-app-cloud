# Ronda 04/10 — Bloco B (dinheiro no painel) — relatório

Ramo: `ronda-04-10-bloco-b` (feito a partir de `autonomous-night-2026-04-29`, 8108952c). Sem push.
Memória do PC: 313 MB antes do primeiro `flutter analyze` (abaixo dos 800). Avancei só com
`analyze` dos ficheiros tocados, sem compilar a app; antes dos testes medi de novo: 1500 MB, e
corri só os ficheiros de teste dos ecrãs tocados (não a suíte inteira).

## Migrações aplicadas em produção (versão real = nome do ficheiro em supabase/migrations)
| versão | nome |
|---|---|
| 20261005085326 | ronda0410_b1_uma_funcao_marcar_pago |
| 20261005090241 | ronda0410_b2_demo_fora_e_barbearias |
| 20261005090504 | ronda0410_b4_acerto_pago_congelado |
| 20261005090747 | ronda0410_b5_fechos_margem_e_lembretes |
| 20261005090912 | ronda0410_b7_auditoria_creditos_e_reembolso_tvde |
| 20261005091403 | ronda0410_b9_semana_lisboa_e_csv |

Todas provadas antes numa transação desfeita (DO … RAISE 'PROVA …') e lidas de volta depois.

## 1. Uma só função de marcar pago/recebido — FEITO
- `admin_set_settlement_state` é a única que escreve pago/recebido. Passam a chamá-la, com a mesma
  assinatura: `admin_mark_settlement_paid` (já chamava), `admin_marcar_acerto_pago`,
  `admin_set_settlement_status`, `admin_set_partner_settlement_status`,
  `admin_mark_carwash_settlement_paid`, `admin_mark_cleaner_settlements_paid`,
  `admin_mark_appointment_payouts_paid`. `admin_unmark_settlement` e `admin_reabrir_acerto` fazem o
  contrário (voltar a pendente) e ficaram como estavam.
- A função única já não volta a carimbar uma linha já paga/recebida/cancelada.
- Achado grave: `log_admin_action(texto)` escrevia numa tabela `admin_logs` que não existe e calava o
  erro — nenhuma marcação de pago deixava rasto. Passa a escrever em `admin_audit_log`.
- Erro antigo corrigido: "Acerto por pessoa" marcava "pago" quem DEVIA à Bora; agora fica "recebido".
- Painel: confirmação com NOME e VALOR em Acertos da semana (antes era um toque sem pergunta),
  Lavagens, Acertos estafeta/parceiro e Reembolso TVDE. Contas claras, Acerto por pessoa, Barbearias,
  Limpeza e Créditos de parceiro já mostravam nome e valor.
- Prova: estafeta +14,68 € → pago com auditoria; repetir → 0 linhas; estafeta −0,53 € → "recebido";
  marcar "pago" quem deve → recusado; 7 linhas em admin_audit_log.

## 2. Demonstração fora — FEITO
Contas claras, Ganho do dia, Acerto por pessoa, Vigia (diário e lista) e KPIs usam o critério que
já existia (`is_demo_user/driver/restaurant/provider/order/subject`; `%@bora.app` não é demo).
Prova (antes → depois): KPI pedidos 90 dias 46 → 40; ticket 28 → 27; Contas claras "devem à Bora"
2 → 1; saldo dos estafetas 89,02 € → 68,77 €.

## 3. Contas claras com barbearias — FEITO
Repasses de barbearia (`appointment_payouts`) entram nas saídas pagas, em "a Bora deve" e em
"devem à Bora", com botão (função única). Prova: 1 repasse pago de barbearia passou a aparecer.

## 4. Recálculos não reescrevem semanas pagas — FEITO (gatilho aditivo)
As funções de recálculo de estafeta e parceiro são protegidas pela Trava, por isso a regra foi
para um gatilho em todas as tabelas de acerto e no resumo semanal: numa semana paga/recebida só
mudam notas, referência e método; o resto volta ao que estava e fica registo. Reabrir continua a
funcionar. Prova: tentar pôr 999 € numa semana paga → ficou 4,00 € com 1 registo; resumo 999 € →
ficou 400; depois de reabrir, recalcula normal.

## 5. Fechos sem 1.15 cravado — FEITO
`_fecho_pedidos` e `admin_monthly_closeout` leem `non_partner_markup_pct` (já existia, 0,15;
sem a chave usa 0,15). Prova: fecho de setembro igual ao de antes; com 0,20 numa prova desfeita, muda.

## 6. Barbearias: "pago na app" só com pagamento real — PARCIAL
- Feito: métricas das barbearias só contam o valor cheio com pagamento real (`full_payment_pi`); o
  parceiro dizer "pagou na app" já não põe o estado "pago" sem pagamento (`partner_complete_appointment`).
  Hoje há 1 marcação nessa situação.
- Bloqueado pela Trava: o cálculo do repasse (`compute_provider_weekly_payout`).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
  Proposta: `feito/pc-B-PROPOSTA-barbearia-pago-na-app-real.sql`.

## 7. Auditoria — FEITO
`admin_mark_partner_credits_paid` e `admin_tvde_refund_ride` escrevem em `admin_audit_log`. A
primeira verificava admin por metadados que o próprio utilizador pode mudar; agora usa
`is_admin()`. Acerto de parceiros manda a semana de Lisboa em UTC (`toUtc`).

## 8. Tokens, cron e lembretes — PARCIAL
- Feito: um só cron a limpar o histórico do cron (ficou o 94; saiu o 64). Os lembretes já comparam
  com a hora de Lisboa; a configuração passou a recusar hora fora de 0–23 e dias fora de 1–7.
- Bloqueado pela Trava: semana de Lisboa no tecto de tokens (`driver_convert_tokens`).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
  Proposta: `feito/pc-B-PROPOSTA-tokens-semana-lisboa.sql`.

## 9. Lisboa, CSV, menu, ecrã velho — FEITO
- Hora de Lisboa em 9 ecrãs de dinheiro.
- Achado: o Acerto por pessoa cortava a semana em UTC (o acerto de 28/09 aparecia como 21/09) e o
  botão das Contas claras não marcava nada (0 linhas). Corrigido; prova: 0 → 1 linha.
- CSV com ';', BOM e aspas certas; Contas claras, extratos e dívidas TVDE descarregam em vez de copiar.
- Menu "Dinheiro e acertos" com 5 entradas; o resto em "Mais dinheiro" (continua na busca).
- `admin_weekly_settlements_screen.dart` apagado (0 usos).

## Provas
- `flutter analyze` dos ficheiros tocados: sem erros nem avisos.
- `flutter test` de 5 ficheiros de teste: todos passaram (+49); o teste golden do painel passou.
- `anti_trapaca.py --base HEAD~2`: limpo.
- Teste golden do menu mudou de propósito ("Tokens" e "Cartões" estão agora em "Mais dinheiro").

## Não feito / para o Danilo
- Itens 6 e 8 (parte): as 2 propostas acima esperam o teu "vai".
- O digest para os outros motores (`claude_ai_memoria`) fica para quem fecha a ronda.
