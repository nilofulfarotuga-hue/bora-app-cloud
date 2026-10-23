---
id: memoria-claude-ai-livro-areas-contas-claras
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Missão "contas claras" (20/09) — extratos de dinheiro compreensíveis para estafetas, motoristas, parceiros e o Danilo, estilo Uber/Glovo; e o bug-raiz das duas verdades da carteira. Ler antes de mexer em saldo, extrato, reembolso ou acerto

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-contas-claras`, origem `claude-ai`, atualizada em 2026-10-23T05:41:30.871683+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas contas claras · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/contas-claras.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: contas-claras
description: Missão "contas claras" (20/09) — extratos de dinheiro compreensíveis para estafetas, motoristas, parceiros e o Danilo, estilo Uber/Glovo; e o bug-raiz das duas verdades da carteira. Ler antes de mexer em saldo, extrato, reembolso ou acerto
sources: [cowork]
aliases: [contas claras, extrato, matemática do dinheiro, duas verdades da carteira, histórico de corridas]
---

- [stated] 20/09 mandou fazer varredura à matemática toda do dinheiro porque não lhe bate certo e está confuso. Quer, detalhado: o histórico das corridas dele, o que o Bora lhe deve, o que ele deve ao Bora, e o que recebeu em dinheiro. "Nada mais, nada menos"
- [stated] Tem de ficar claro e fácil para as QUATRO pontas, não só para ele: estafetas, motoristas, parceiros e ele próprio
- [stated] Referência que fixou: ir ver como o Uber e o Glovo mostram os extratos e fazer igual ou melhor
- [stated] 20/09 confirmou que PAGOU os 8,20 € ao Valdemir por MB Way (talão do McDonald's, pedido 9cba3644)

## Bug-raiz achado por mim 20/09 (SELECT, não suposição)
- Há DUAS verdades para a carteira e não conversam: `wallet_transactions` é o histórico que a pessoa lê, e `client_wallets.free_balance_cents` é o saldo que a app mostra (é o que a `wallet_get_balance` devolve)
- A `admin_mark_receipt_paid` insere a linha no histórico e NUNCA soma ao saldo. O mesmo aconteceu num reembolso de artigos em falta. Consequência: o histórico promete dinheiro que o saldo não tem — é isto que faz as contas parecerem erradas
- Medido em toda a base: só 2 casos reais, o resto bate certo. Valdemir histórico 8,20 contra saldo 0 (já corrigido). Isabel Rebelo histórico 4,09 contra saldo 1,00 — os 3,09 € do reembolso de artigos em falta do pedido 7d80dec9 (25/08)
- [stated] 20/09 ele FECHOU o caso da Isabel: "já está tudo certo, não precisa fazer nada" — ela não tem nada a receber, não voltar a levantar isto
- FEITO por mim por MCP 20/09: estorno de -8,20 na carteira do Valdemir (kind `adjustment`, chave `estorno_mbway_reimb_b89e66d2`) a dizer que foi pago por MB Way fora da app. Histórico e saldo ficaram os dois a 0, verificado por SELECT. O talão fica `admin_paid`, que está certo
- ARMADILHA a não repetir: somar `wallet_transactions` toda de uma vez dá número errado — as linhas `refund_credit_tokens` são TOKENS, não saldo livre; a conta certa exclui esse tipo. Foi isso que me fez ver desacerto em 4 pessoas quando só havia 2
- Ligações: o acerto semanal vive em [[fecho-semanal]]; a auditoria de pagamentos de agosto em [[auditoria-pagamentos]]; o talão do estafeta em [[talao-nao-parceiro]]

## Prompt e execução — 20/09
- PROMPT REGISTADO: `PROMPT_contas_claras_2026-09-20.md`, entregue 20/09 como ficheiro, MOTOR OPUS, PORTA Claude Code, SESSÃO NOVA pasta bora-app-cloud ramo autonomous-night-2026-04-29, fluxo e2e `contas-claras-2026-09-20`. Blocos: B0 mapa do dinheiro · B1 uma verdade só + talão com dois caminhos · B2 extrato do estafeta/motorista (depois de ir ver Uber Driver e Glovo) · B3 extrato do parceiro · B4 extrato do Danilo no painel admin · B5 vigia que grita quando histórico ≠ saldo · B6 painel e fecho. Proibido mexer em preços, comissões ou despacho; histórico nunca se reescreve
- ⚠️ SUPERA o bug-raiz acima — **já está corrigido, não voltar a diagnosticar nem a dizer que existe**. Verificado por mim com SELECT a 20/09: o saldo passou a ser calculado do histórico por gatilhos em `wallet_transactions` (`_wallet_tx_before_insert` cria a carteira, tranca e preenche `balance_after_cents` excluindo os tipos de token; `_wallet_tx_sync_balance` recalcula `client_wallets`), e `_wallet_tx_append_only` impede UPDATE/DELETE — corrige-se só com linha nova. Toda a gente bate certo; só a Isabel fica de fora, de propósito
- Talão com os DOIS caminhos no ar: `admin_mark_receipt_paid` (credita a carteira) e `admin_mark_receipt_paid_external` (marca pago por fora, não credita), com colunas `reimbursement_method`/`external_paid_at`/`external_reference`
- FEITO por mim por MCP 20/09 (migration `contas_claras_refund_split_idempotente_2026_09_20`): a `wallet_credit_refund_split` passou a ter chave de idempotência por pedido — era isto que deixou a Dayane receber o mesmo reembolso 7 vezes a 12/09. A trava do PC recusa DDL nessa função (MONEYFN), por isso o executor deixou o SQL em `platform_settings.staged_contas_claras_20260920` e eu apliquei daqui, que é o caminho combinado. Provado em rollback: 1.ª chamada 800 cêntimos livres + 400 tokens, 2.ª devolve `already_applied` e credita zero; nada ficou na base
- LIÇÃO 20/09, minha: disse-lhe que a sessão "continua a trabalhar" a partir de uma linha do e2e_log de há 4 minutos, e ele estava a olhar para a janela parada. Linha recente no log NÃO prova sessão viva — ou se prova de outra maneira, ou diz-se que não se sabe
- O executor terminou o turno à espera de mim no ponto em que a trava recusou a função de dinheiro, contra a carta de autonomia. Continuação entregue como texto para a MESMA janela, a dizer o que já estava aplicado para ele não repetir

FINAL WRITE

## 20/09 à noite — o TVDE passou a entrar no acerto semanal (feito por mim, MCP)
- [stated] 20/09 ele deu o "vai" por escrito e mandou resolver sem voltar a perguntar: "é resolver direito, dessa vez", "com é dinheiro, nós não podemos errar". Disse também que o que passou, passou — o que tem de fechar exato é a SEMANA QUE FECHA HOJE
- CAUSA PROVADA: a `compute_driver_settlement` só lia `public.orders` (entregas) + conversões de tokens. As corridas de `tvde_rides` não entravam em lado nenhum, por isso quem conduzia nunca era pago nem cobrado pelo acerto
- SEGUNDO BURACO, pior e que ninguém tinha visto: a `close_previous_week_settlements` só percorria quem tinha ENTREGAS na semana. Quem só fez corridas não tinha sequer linha de acerto criada — era o caso da Erika esta semana, ia ficar de fora e nunca seria paga
- REGRA APLICADA (a mesma das entregas): corrida paga por cartão/MB Way → a Bora recebeu, deve o ganho ao motorista; corrida paga a dinheiro → o motorista já recebeu do passageiro, devolve a parte da Bora. Colunas novas no acerto: `tvde_rides_count`, `tvde_earnings`, `tvde_cash_received`
- MIGRAÇÕES: `contas_claras_tvde_colunas_acerto_2026_09_20`, `contas_claras_tvde_entra_no_acerto_semanal_2026_09_20`, `contas_claras_fecho_inclui_quem_so_fez_tvde_2026_09_20`, mais a `contas_claras_b2_prestador_semana_em_curso_2026_09_20` (invólucro só de leitura da previsão da semana, provado: acertos 10 antes e 10 depois)
- NÚMEROS DA SEMANA 14-20/09, simulados e desfeitos: Valdemir 1 entrega + 13 corridas, ganho 57,00 (52,00 corridas + 5,00 entrega), 40,00 recebidos em mão, a Bora deve-lhe **17,00** (o acerto dizia 5,00 antes). Erika 1 corrida MB Way, a Bora deve-lhe **4,00**, e antes não tinha acerto nenhum
- A linha do próprio Danilo desta semana já estava `paid`, e o `ON CONFLICT ... WHERE status NOT IN ('paid','received')` nunca reescreve uma linha paga — por isso as 15 corridas dele não entraram nela. É conta do dono, não afeta terceiros; só entra se ele puser a linha de volta a pendente
- DEFEITO DE DADOS que fica apontado: 13 das 41 corridas a dinheiro de toda a história não têm tarifa gravada (`final_fare_cents` e `est_fare_cents` a zero), por isso não há como saber quanto o motorista recebeu em mão nessas. Desta semana só afeta corridas do próprio Danilo — as do Valdemir e da Erika estão completas. Corrigir a gravação da tarifa na app; o que passou não se reescreve
- NÃO adiantei o fecho de propósito: a semana só acaba às 23:00 UTC de domingo e ainda podiam entrar corridas. O cron `close-weekly-settlements` (segunda 00:05 UTC) corre já com a correção
- VERIFICADO ponta a ponta no `extrato_prestador` do Valdemir (com o JWT dele simulado por `set_config`): semana com 14 trabalhos, 5700 cêntimos, 5200 de corridas e 500 de entrega, e o talão a dizer "Reembolso pago por MB Way a 19/09"
- A `auto_payout_pending` (segunda 03:00) NÃO se alimenta destes acertos — trabalha sobre `user_balance_snapshots`/`ledger_entries`. Esta correção não dispara pagamento automático nenhum
- Relatório entregue: `RELATORIO-acerto-tvde-2026-09-20.md`

## 21/09 madrugada — ERRO MEU, apanhado pelo executor e corrigido antes do fecho
- ⚠️ SUPERA a linha acima sobre "tarifa em falta". A regra que eu apliquei a 20/09 às 21h — quando a tarifa está a zero, deduzir tarifa = ganho + corte — **estava ERRADA e cobrava dinheiro que nunca existiu**. Tarifa a zero nem sempre é dado em falta: nas VOLTAS de pacote (`is_return_leg`, com `roundtrip_credit_id`) e nas corridas de PLANO o zero é o valor CERTO, porque o passageiro já pagou na ida ou no plano e na volta o motorista não recebe nada em mão. A `tvde_finish_ride` grava de propósito só as paragens em `final_fare_cents`; o preço do pacote vive em `tvde_roundtrip_credits.paid_cents`
- Dimensão do erro, medida pelo executor e confirmada por mim: 13 corridas erradas, **68,00 € cobrados a mais ao Danilo**. No Valdemir os erros anulavam-se, por isso os 17,00 € dele estiveram sempre certos. Nenhuma das corridas a zero era de balcão — a minha suspeita de "balcão" também estava errada
- CORREÇÃO APLICADA por mim por MCP a 21/09 00:5x (migration `contas_claras_b8_acerto_le_dinheiro_em_mao_2026_09_21`), minutos antes do fecho das 00:05 UTC: o acerto deixou de deduzir e passa a ler `tvde_rides.cash_in_hand_cents`, gravado por gatilho diferido pela regra única `tvde_ride_cash_in_hand` (a mesma regra do saldo), com backfill 65/65. O campo do JSON passou a chamar-se `tvde_sem_dinheiro_em_mao_gravado`
- NÚMEROS FINAIS da semana 14-20/09, com âncora dentro da semana: Valdemir 13 corridas, 52,00 de ganho, 40,00 em mão, **17,00** a receber (não mudou). Erika **4,00**. Danilo 16 corridas, 62,00 de ganho, 25,00 em mão, 43,52 — com a minha regra errada dava 34,00 em mão
- ARMADILHA DO FUSO a não repetir: depois das 23:00 UTC de domingo o `now()` já cai na semana SEGUINTE e a `compute_driver_settlement(uid, now(), false)` devolve tudo a zero. Para ver a semana que fechou, âncora dentro dela (o cron faz isso com `now() - 1 day`)
- LIÇÃO MINHA, a que mais importa desta noite: inferi uma regra de negócio ("tarifa = ganho + corte") a partir de um padrão estatístico — batia em 42 de 47 registos — e tratei-a como verdade sem ler a função que GRAVA o valor (`tvde_finish_ride`). Padrão nos dados não é regra de negócio. Em dinheiro, antes de deduzir um valor em falta, ler o código que o escreve e perceber PORQUE está vazio

## 21/09 manhã — o recibo semanal estava errado e ele apanhou-o a ler o e-mail
- [stated] 21/09 recebeu o e-mail do fecho 13/09-20/09 e disse que estava errado: "só tá falando das entregas... tá faltando as corridas de motorista". Tinha razão
- CAUSA 1 (o número dele): a linha do acerto dele estava `status='paid'` desde **19/09 23:52:06**, marcada 6 segundos depois de ser criada, sem referência, sem nota e **sem nenhum movimento em `driver_transactions`** — foi um clique de teste, não um pagamento. Por estar paga, o `ON CONFLICT ... WHERE status NOT IN ('paid','received')` impediu o fecho das 00:05 de lhe entrar as 16 corridas. Reaberta por mim com a nota escrita na própria linha e recalculada: **6,52 → 43,52 €**. Recibo reenviado só a ele
- CAUSA 2 (o recibo de toda a gente): a `weekly_closeout_compile` não tinha **linha de corridas** — o ganho TVDE ia escondido dentro de "Entregas". O Valdemir recebeu "Entregas x1 — 57,00 €" tendo feito 1 entrega e 13 CORRIDAS; a Erika recebeu "Entregas x0 — 4,00 €". Faltava também a parcela dos reembolsos, e o dinheiro em mão aparecia a SOMAR quando é para devolver
- REGRA QUE FICA: **as linhas do recibo somam o saldo da semana ao cêntimo**. Ordem: Entregas · Corridas · Compras que adiantou do bolso · Tokens convertidos · Dinheiro que recebeu em mão (devolve à Bora, a subtrair). Linha a zero não aparece. Provado nos 4 sujeitos da semana
- `driver_weekly_settlements` ganhou a coluna `total_reimbursements`: o valor já entrava no net mas era deitado fora, e era por isso que as linhas nunca somavam (14,73 € de 43,52 € no caso dele)
- VIGIA NOVO na `close_previous_week_settlements`: quando a linha está paga e o valor recalculado é diferente, escreve em `admin_audit_log` (`fecho_linha_travada_valor_diferente`) e manda aviso ao admin. **Nunca corrige sozinho.** Provado em rollback nos dois sentidos: base sã = 0 avisos, desacerto plantado = 1 aviso
- Migrações 21/09: `contas_claras_b9_acerto_guarda_reembolsos_2026_09_21`, `contas_claras_b9_recibo_mostra_corridas_2026_09_21`, `contas_claras_b9_recibo_acentos_ptpt_2026_09_21`, `contas_claras_b9_fecho_grita_linha_travada_2026_09_21`
- Valdemir e Erika NÃO levaram segundo e-mail: o total deles estava certo, só o detalhe é que era confuso. O detalhe guardado ficou corrigido e o motivo escrito em `weekly_digest_log.email_error`; o botão "Reenviar recibos" manda a versão corrigida se ele quiser
- [stated] 21/09 confirmou: o ÚNICO MB Way que tinha feito ao Valdemir era o dos 8,20 € do talão — o acerto era coisa à parte
- [stated] 21/09 à tarde PAGOU o acerto da semana 14-20/09 ao Valdemir (17,00 €) e à Erika (4,00 €). Marquei as duas linhas como pagas e os comprovativos saíram por email, confirmados `sent`. Falta pagar à **Goola Açaí: 10,90 €, MB Way +351 911 519 501** (linha `pending`), e o acerto dele próprio (43,52 €) continua `pending`

## 21/09 — varredura da matemática do dinheiro (pedida por ele)
- CONTAS DELE: batem. O adiantamento de 14,73 € no Wells confere ao cêntimo com o talão (OCR leu 14,73, `receipt_match` true), e o acerto devolve-lho certo — ganhou 5,41, recebeu 18,32 em mão, adiantou 14,73, fica +1,82 a favor dele
- CORRIDAS DE BALCÃO: entram certas. A corrida de 10 € do Valdemir (19/09, ACTION → General Pinto Monteiro) dá-lhe 4 € e desconta os 6 € da Bora no acerto. Os 40 € que ele levou em mão em 7 corridas a dinheiro estão todos descontados. Total da semana dele: 52 ganhos − 40 em mão + 5 da entrega = 17,00 €
- ⚠️ FUGA 1 — TAXA DE PEDIDO PEQUENO NUNCA É COBRADA: `small_order_fee_enabled` está ligado e são 139 cêntimos, a `quote_order_pricing` mete a taxa no total do cliente, mas a `finalize_storeshopping_purchase` recalcula `final_total` e `cash_total_due` SEM ela (`v_final_total_cents := bought + added + bag + delivery + service`, sem small_order). Em 5 pedidos desde 27/08 faltam exatamente 1,39 € em cada: **6,95 € perdidos**. NÃO corrigi — mexe no que o cliente paga, é zona de preço
- ⚠️ ERRO MEU, desmentido por SELECT antes de eu mexer: eu disse que os 15% não eram reaplicados ao preço corrigido. **FALSO — a margem está sempre aplicada.** Em 54 linhas de pedidos não-parceiros desde 01/08 a margem vai de 13% a 60%; no próprio pedido Wells 12,81 → 14,73 são +14,99%. O `catalog_price_gap_cents` NÃO é a margem, é a diferença entre o talão e o preço base. Não há nada a corrigir nessa frente
- A perda de 1,82 € no Wells veio do **CATÁLOGO DESATUALIZADO**: o produto estava a 12,81 € quando na loja custava 14,63 €, e os 15% de margem foram todos comidos pela diferença. O robot `catalog_price_update_from_receipt` já subiu o produto para 14,63 (só sobe sozinho, descer fica pendente — regra do Danilo de 05/09) e o alerta `catalog_price_gap` já tinha disparado. O sistema funcionou
- GANHO DA BORA na semana 14-20/09: **30,01 €** — 29,00 das corridas (corte da Bora em 30 corridas, já inclui os 2,00 dos 4 pacotes ida-volta) e 1,01 das 3 entregas (−1,82 no Wells, +1,04 na Goola, +1,79 na do Valdemir). Sem limpezas, serviços nem lavagens nessa semana
- LIÇÃO: uma trava que recusa em silêncio é pior do que não ter trava. A regra "não se reescreve uma semana paga" estava certa; o que faltava era ela DIZER que recusou

## 21/09 — correções aplicadas (ele deu o "vai": "tudo que você vê aí de errado tem que arrumar")
- FEITO `contas_claras_b10_taxa_pedido_pequeno_nao_desaparece_2026_09_21`: a `finalize_storeshopping_purchase` passa a somar `orders.small_order_fee` ao `final_total`/`cash_total_due`. Lê o valor que o cliente JÁ aceitou, não recalcula — recalcular podia cobrar mais do que o orçamento, e isso seria decisão de preço. O gatilho `orders_aa_small_order_fee` é BEFORE INSERT, por isso não há dupla soma. Provado em rollback no pedido real do Wells: 18,32 → 19,71
- FEITO `contas_claras_b11_vigia_pedido_no_vermelho_2026_09_21`: gatilho `orders_zz_alerta_no_vermelho` só em não-parceiros. Ao passar a `delivered` faz cliente − mercadoria − estafeta; se der ≤ 0 avisa o admin (`notify_admin_event`, tipo `pedido_no_vermelho`). Nunca corrige. Provado em rollback nos dois sentidos: pedido com lucro = 0 avisos, pedido Wells = 1 aviso com −1,82 €
- LIÇÃO, a segunda vez em dois dias: outra vez quase inventei uma regra de negócio a partir de um número (achei que a margem não era aplicada porque 12,81 → 14,73 batia certo com o total do talão — era coincidência). Desta vez verifiquei ANTES de mexer, com um SELECT sobre 54 linhas. É essa a ordem certa: medir a regra em toda a base antes de lhe chamar bug

## Prompt entregue 21/09 — fecho da missão
- `PROMPT_contas_claras_fecho_2026-09-21.md`, ficheiro, MOTOR FABLE (ou OPUS se o Max já não existir), PORTA Claude Code, SESSÃO NOVA, pasta bora-app-cloud, ramo autonomous-night-2026-04-29, run_id `contas-claras-20260921`
- Blocos: C0 ler o servidor primeiro · C1 pôr o repo igual (as 7 migrações de 20-21/09, com as duas de substituição de texto escritas por extenso) · C2 painel admin (colunas TVDE + reembolsos, botão de reabrir acerto com motivo, avisos novos, reenviar recibos) · C3 extrato na app com as mesmas parcelas do recibo, Flutter sem fazer contas · C4 taxa de pedido pequeno visível ao cliente no checkout · C5 só reportar: as duas contas Danilo e o vigia do vermelho nos parceiros · C6 autoteste verde, push, relatório
- Leva a regra nova dele (dizer o que se mexe, reportar o que for fora de scope) e a lista do que JÁ está resolvido para não voltar a ser diagnosticado
- [stated] 21/09: ele próprio vai pagar o Valdemir e a Erika e avisa-me quando pagar, para eu marcar a linha como paga e mandar o recibo

## 21/09 manhã — o executor achou que a MINHA correcção da taxa era só metade
- CONFIRMADO por mim com SELECT nos 5 pedidos: em TODOS, `price` e `customer_total` = subtotal + entrega + serviço + sacos, **sem os 1,39**. A taxa nunca entra no total da encomenda
- A raiz é a `create_order`, não o fecho da compra: só a `quote_order_pricing` (ecrã do carrinho) soma a taxa. O gatilho `fn_small_order_fee` só ajusta `price` pela diferença loja−global, assumindo que a global já vem em `price` — e não vem
- A minha correcção B10 (`finalize_storeshopping_purchase`) só apanha quem passa pelo fecho da compra. **Os pedidos de PARCEIRO não passam** (`is_purchase_finalized` = false nos dois da Goola), por isso continuam a mostrar 1,39 ao cliente e a não cobrar
- Ou seja: o cliente vê a taxa no carrinho (`cart_screen:400`) e paga MENOS do que viu. Quem perde é a Bora
- A correcção certa é na `create_order` (zona vermelha) + tirar da `fn_small_order_fee` a suposição de que a global já está no preço. Deixei isso ao executor, que tem o repo, o Flutter e o autoteste — não é para hot-patch por MCP
- [stated] 21/09 as duas contas dele: `c9fccf85` = nilofulfarotuga@gmail.com, é a conta do DONO (painel, compras, passageiro de TVDE); `4f61dd31` = boraappbora@gmail.com, é a conta que TRABALHA (motorista/estafeta). Ficam separadas de propósito — fundir partiria ~60 colunas. A 20/09 entrou por engano na app de estafeta e ficou uma candidatura `pending` para rejeitar
- LIÇÃO: corrigi o sintoma onde o vi (o fecho da compra) sem seguir a parcela até à origem (a criação da encomenda). Em dinheiro, ao achar uma parcela em falta, seguir o caminho todo: quem a calcula, quem a grava, quem a soma ao que o cliente paga — e confirmar que TODOS os tipos de pedido passam por lá

## 21/09 tarde — buraco da taxa fechado na origem (C7)
- O executor corrigiu o gatilho `fn_small_order_fee` (contrato novo: quem insere DECLARA em `small_order_fee` o que já pôs no preço, e o gatilho só acrescenta a diferença da loja) mas a Trava do PC recusa DDL que nomeie a `create_order`. Deixou a proposta em `platform_settings.staged_contas_claras_20260921_c7` e eu apliquei por MCP — é o caminho combinado para zona vermelha
- APLICADO `contas_claras_c7_create_order_cobra_taxa_pedido_pequeno_2026_09_21`: 5 âncoras guardadas sobre o corpo vivo. A taxa GLOBAL entra em `v_customer_total` logo a seguir aos dois ramos de pricing, por isso o tecto da carteira, o `charge_total`, o estado de pagamento, o buffer e o `price` já a levam; vai declarada na coluna do INSERT (sem dupla contagem) e devolvida no JSON
- PROVA em rollback com a própria `create_order` e o quote lado a lado: parceiro Goola 13,87 = 13,87 (taxa 1,39); não-parceiro Wells 8,66 = 8,66 (taxa 1,39); acima do mínimo taxa 0 e nada muda. **O caso do parceiro é o que a minha correcção da manhã não apanhava**
- Valor da taxa (139) e mínimo (1500) intocados; os 5 pedidos antigos intocados
- ⚠️ ACHADO DE LADO, não mexido: `platform_settings.mbway_enabled` está **FALSE** desde 21/09 12:20 UTC, com `mbway_disabled_message` activa — qualquer pedido por MB Way é recusado pelo `guard_mbway_disabled`. Pode ser intencional; fica apontado

