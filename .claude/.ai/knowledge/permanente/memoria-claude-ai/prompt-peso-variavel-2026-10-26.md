---
id: memoria-claude-ai-prompt-peso-variavel-2026-10-26
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-26
zona: verde
confianca: alta
estado: atual
---

# PROMPT missão peso variável (26/10/2026) — para o Claude Code do PC

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-peso-variavel-2026-10-26`, origem `claude-ai`, atualizada em 2026-10-26T13:15:24.297316+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt peso variavel 2026 10 26 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️
run_id: peso-variavel-2026-10-26 · fluxo e2e_log: peso-variavel-2026-10-26 · data: 26/10/2026
PORTA: Claude Code no PC do Danilo (sessão "bora-app", pasta bora_app) — a única porta; outros motores só como trabalhadores por dentro (skill distribuir-trabalho), nunca em dinheiro.
MOTOR: Opus 5.5 (é dinheiro: preço ao cliente, carteira, cartão). Sem fallback para motor mais fraco nos blocos 1, 5 e 6.
Invoca primeiro o orquestrador CEO-AI (.claude/skills/ceo-ai/). Segue a skill protocolo-missao-bora. Lê PADRAO_BORA.md e .claude/.ai/business_rules.md (§57 Venda ao peso) antes de planear.

AUTORIZAÇÃO DO DANILO (literal, com data): 26/10/2026 às 10:16 (Lisboa), na conversa com a Claude.ai — "Autorizo." — dada à proposta "produtos de peso variável": o estafeta toca no preço e escreve o valor da etiqueta da balança; o cliente paga o valor final com a mesma margem do produto (se pesar menos, paga menos); limite de 30% para cima ou para baixo; notificação ao cliente; dinheiro cobra o valor novo; cartão cobra a diferença depois no mesmo cartão; MB Way, se subir, a Bora assume; se descer, volta para a carteira; painel admin com tudo; produtos acrescentados pelo estafeta passam a levar a margem de não-parceiro; consertar o "cobrar diferença no cartão" que não cobra de verdade. Esta autorização vale SÓ para esta missão.

PORQUÊ (palavras do Danilo, 26/10 09:40, a fazer um pedido do Continente): "pediu 4 bananas… o estafeta tem que ter a opção de trocar o preço… pesa, aí ele tem que colocar o preço final… se ele clicasse nesse valor, ele poderia trocar o valor pelo valor que ele vai pagar… tem que ver todo o fluxo para chegar lá para o cliente, pagar final, chegar a notificação que o preço alterou por causa que é por quilo… frutas, legumes, carnes". Padrão copiado da Deliveroo (Variable Weight Items: mais leve devolve, mais pesado cobra, fora do intervalo recusa e o estafeta pesa outra vez ou tira o produto) e da Uber Eats (preço por peso em carne, peixe e fruta).

O QUE JÁ ESTÁ FEITO NO SERVIDOR (pela Claude.ai, por MCP, 26/10 13:05–13:11 Lisboa) — NÃO REFAZER:
- Migrações em produção: 20261026130514 peso_variavel_a_estrutura_2026_10_26 · 20261026130940 peso_variavel_b_talao_2026_10_26 · 20261026131049 peso_variavel_c_marcar_produtos_2026_10_26. O SQL exacto está em supabase_migrations.schema_migrations.statements (lê de lá, não reescrevas de cabeça).
- products.variable_weight (boolean, default false) — "peso variável" nos mercados. NÃO é o sold_by_weight (porções de 200 g dos parceiros, §57). 1159 produtos marcados: Auchan 692, Continente 197, Intermarché 216, Pingo Doce 54 (regras no comentário da migração C).
- platform_settings (categoria storeshopping): weight_adjust_enabled=true · weight_adjust_max_pct=0.30 · weight_adjust_card_charge_enabled=false.
- Tabela order_weight_adjustments (um por pedido+produto; RLS só leitura: admin, o cliente do pedido, o estafeta do pedido; escrita só pelas funções).
- RPC estafeta_ajustar_peso(p_order_id text, p_product_id text, p_real_base_cents int) → jsonb. p_real_base_cents = TOTAL da etiqueta para a linha toda (ex.: as 4 bananas juntas), em cêntimos, preço de caixa. Devolve ok=true com estimado_caixa_cents, real_caixa_cents, estimado_cliente_cents, novo_cliente_cents, diferenca_cents, diferenca_total_pedido_cents, novo_total_estimado_cents, minimo_cents, maximo_cents, cliente_avisado; ou ok=false com erro ∈ desligado | loja_parceira | tipo_de_pedido | compra_ja_fechada | produto_sem_peso_variavel | produto_fora_do_pedido | preco_estimado_invalido | valor_invalido | fora_do_limite (traz minimo_cents/maximo_cents). Pode chamar-se outra vez para corrigir (substitui). Avisa o cliente sozinha (sino in_app_notifications kind 'order_weight_adjusted' + push notify-client type 'order_weight_adjusted') sempre que o valor muda. Novo preço ao cliente = real × (cliente previsto ÷ caixa previsto) — a mesma margem da linha.
- finalizar_talao_nao_parceiro aplica os ajustes ao fechar a compra: dinheiro → entra no valor a cobrar; MB Way/cartão → mais barato vai para a carteira (refund_credit_free, motivo storeshopping_v2_peso_variavel), mais caro → cartão guardado só se weight_adjust_card_charge_enabled (chama a Edge Function cobrar-diferenca-peso, que AINDA NÃO EXISTE) senão a Bora assume; produto ajustado e depois marcado "Não há" é ignorado. Produtos acrescentados ("Adicionar produto") passam a ir ao cliente com non_partner_markup_pct (antes iam ao preço da caixa e no cartão nem eram cobrados). Resposta nova: weight_delta_cents, added_client_cents, weight_wallet_credit_cents, card_extra_cents, absorbed_cents.
- Admin: admin_list_weight_adjustments(p_dias, p_limit) e admin_set_variable_weight(p_product_id, p_on, p_reason) (com admin_audit_log).
- Provas já feitas em transação desfeita, com o pedido real 11926093 (Continente, dinheiro): banana 4 un. etiqueta 1,20 € → cliente 1,12 € → 1,40 €; frango 6,50 € recusado (máx. 6,18); frango 4,50 € → 5,47 → 5,17; ovos recusados (sem peso variável); talão a dinheiro deu 38,25 € = 35,59 + 0,10 saco + 6,88 Faisão com margem − 4,30 frisante "Não há" − 0,02 peso; MB Way: +6,86 a Bora assume, carteira +4,30; só peso a −0,02 → carteira +0,02; cartão com interruptor ligado → extra 6,86 e chamada a cobrar-diferenca-peso; banana ajustada e depois "Não há" → ignorado_nao_ha; repetir o talão não aplica duas vezes.
- Existe uma cópia de teste public._talao_peso_teste já FECHADA a todos (sem EXECUTE). Apaga-a (DROP FUNCTION) no bloco 1 — o gate do MCP da Claude.ai não deixou.

O QUE VAIS MEXER E PORQUÊ: ecrã da lista de compras do estafeta (lib/screens/driver_map_screen.dart e lib/services/talao_nao_parceiro_service.dart) para o estafeta escrever o valor da balança; cartões/detalhe/carrinho/pedido do cliente para o "preço aproximado" e a linha ajustada; painel admin (PT-BR) para ver/ligar/configurar; Edge Function nova cobrar-diferenca-peso e o caminho antigo de cobrar diferença no cartão (OrderStore.processExtraCharge → PaymentService.chargeExtra → charge-extra), que cria um PaymentIntent sem cartão e sem confirmar e logo marca o pedido como pago — não cobra nada. Outro erro que encontres pelo caminho: REPORTA no e2e_log e no relatório, não corrijas calado.

BLOCO 0 — Reconhecimento (≤15 min)
- Lê no livro (claude_ai_memoria): erros-aprendidos, regras-do-danilo, livro-indice, livro-areas-produtos-peso-variavel e o digest mais recente. Últimas 200 linhas do e2e_log.
- Estado dos ramos locais por enviar de 25/10: envio-nome-cliente-valor-caixa-2026-10-25 (por cima de 7d5d0b34 do sem-margem) e o do botão-chamar-estafeta; e o ramo melhorias-paridade-2026-10-26 (worktree ../bora-melhorias). NÃO mexas neles.
- Cria worktree ../bora-peso com ramo peso-variavel-2026-10-26 a partir de envio-nome-cliente-valor-caixa-2026-10-25 (mexe no mesmo ecrã do estafeta; assim não há choque). RAM: medir antes (portão 800 MB para compilar, 3 GB para emulador).
- .claude/.ai/provas/peso-variavel-2026-10-26/ESPEC.md (objetivo, quem usa, fronteiras, decisões acima). Plano de 5 linhas no e2e_log (passo 00-plano).

BLOCO 1 — Servidor no repo (sem mudar nada em produção)
- Cria em supabase/migrations/ os 3 ficheiros com as versões de produção e o SQL exacto de schema_migrations.statements.
- DROP FUNCTION public._talao_peso_teste(text,text,integer,jsonb,integer) por migração (nova, com data) e prova por SELECT que já não existe.
- Prova por SELECT: pg_get_functiondef de finalizar_talao_nao_parceiro e estafeta_ajustar_peso igual ao ficheiro; anon sem EXECUTE; 1159 produtos com variable_weight.
- business_rules.md: §57 ponto 6 passa a remeter para a secção nova "§58 — PESO VARIÁVEL NOS MERCADOS (26/10/2026)" com a regra acima, a fórmula, o limite, os meios de pagamento e a cicatriz (pedido 11926093). Atualiza docs/contexto/03-regras-de-negocio.md e a página business-rules do livro.

BLOCO 2 — App do estafeta (lista de compras dos não-parceiros) — critério de feito: teste de widget verde + golden atualizado + prova no emulador
- Ao abrir a lista, ler products.variable_weight dos productId do pedido (uma consulta com in) e order_weight_adjustments do pedido (para repor o estado depois de reabrir a app).
- Nas linhas com peso variável: etiqueta pequena "peso variável" e o preço (o de caixa, como hoje) com lápis. Tocar abre folha "Quanto custou na etiqueta da balança?" com campo numérico em euros (vírgula), o valor previsto e o intervalo aceite (mínimo–máximo). Texto de ajuda: "Escreve o total da etiqueta desta linha (ex.: as 4 bananas juntas)."
- Confirmar chama estafeta_ajustar_peso. ok → a linha mostra o valor real e o previsto riscado + "ajustado ao peso", fica marcada Comprado, "Total estimado na caixa" atualiza. fora_do_limite → "Diferença grande. Pesa outra vez (tira ou põe uma peça) ou marca Não há." com mínimo e máximo. compra_ja_fechada/outros → mensagem clara em PT-PT. Botão desligado enquanto envia (toque duplo), rede caída → mensagem e tentar de novo, nunca engolir o erro.
- Lojas parceiras: lista continua só de leitura (sem lápis).
- O valor a cobrar a dinheiro no fim continua a vir da resposta do servidor (cash_total_due_cents); confirma que o ecrã usa esse valor e mostra a linha "Ajuste de peso" quando weight_delta_cents ≠ 0.

BLOCO 3 — App do cliente — critério de feito: testes verdes + prova no emulador e na web
- Onde os produtos são carregados, incluir variable_weight no modelo. Cartão, detalhe e carrinho: nota pequena "Preço aproximado · o valor final depende do peso" só nesses produtos. Nada de mudar o fluxo de compra (continua "4 bananas").
- Ecrã do pedido e recibo do cliente: linha ajustada "ajustado ao peso: 1,12 € → 1,40 €" lida de order_weight_adjustments (RLS já deixa o cliente ler os seus). O recibo segue a regra de 25/09 (produtos que levou, ao preço final).
- Notificação type 'order_weight_adjusted': o encaminhador de notificações abre o pedido; o sino já recebe o registo.

BLOCO 4 — Painel admin (PT-BR, com termos técnicos explicados entre parênteses)
- Ecrã novo "Ajustes de peso" (admin_list_weight_adjustments): pedido, loja, cliente, produto, previsto → real (caixa e cliente), diferença, pagamento, como foi acertado (dinheiro / carteira / cartão pendente / cartão cobrado / Bora assume / sem diferença / ignorado "Não há"), estafeta, quando; filtro por dias; exportar CSV; abrir o pedido.
- Catálogo: interruptor "Peso variável" por produto (admin_set_variable_weight, pede motivo) e filtro "Peso variável".
- Definições: weight_adjust_enabled, weight_adjust_max_pct, weight_adjust_card_charge_enabled visíveis e editáveis no editor de definições existente, com explicação.
- Detalhe do pedido (admin): mostrar os ajustes de peso desse pedido.

BLOCO 5 — Cartão (⚠️ DINHEIRO, zona vermelha) — fica pronto mas DESLIGADO
- Lê a implementação, não confies no nome: confirma se OrderStore.finalizePurchaseV2 (RPC antiga finalize_storeshopping_purchase) ainda é chamado por algum ecrã. Se não é: marca como obsoleto e tira o "marcar como pago" do processExtraCharge. Se é: corrige para não marcar pago sem pagamento confirmado. Relata com prova.
- Edge Function nova cobrar-diferenca-peso: POST {order_id, amount_cents}; só aceita o servidor (_shared/keys.ts exigirCallerOk, chave secreta); só para pedidos pagos com cartão cujo cartão ficou guardado (customer + payment_method do pagamento original); PaymentIntent off_session + confirm, idempotency key "peso_<order_id>"; sucesso → orders.final_total += valor, extra_charge_settled_at, extra_charge_settled_via='cartao_peso', order_weight_adjustments.settled_via='cartao_cobrado', push ao cliente; falha (sem cartão guardado, authentication_required) → settled_via='bora_assume' + alerta admin (notify_admin_event). verify_jwt declarado de propósito.
- NÃO ligues weight_adjust_card_charge_enabled. Testes de pagamento do Danilo são SEMPRE a dinheiro; cartão não se testa com cartão real. Nos últimos 60 dias houve 0 pedidos a cartão (34 dinheiro, 29 MB Way). No relatório: como se liga e como se vigia o primeiro pedido real.
- Bloco por último: se o limite da sessão apertar, este é o que fica para continuação (CONTINUAR-peso-variavel-2026-10-26.md).

BLOCO 6 — Provas (dinheiro primeiro em rollback, depois real; testes de pagamento SEMPRE a dinheiro)
- python .claude/juiz/anti_trapaca.py · flutter analyze limpo · flutter test verde (incluir test/golden/estafeta_lista_compras_test.dart atualizado e testes novos do bloco 2 e 3).
- Emulador (só com ≥3 GB livres, um de cada vez, emulator -avd emdia35 -no-snapshot-save, fechar no fim): pedido de teste a DINHEIRO no Continente com "Banana Continente" ×4 e "Bifes de Frango Continente (emb. 680 gr (aprox.))" com a conta demo de cliente; como estafeta: banana 1,20 → o cliente recebe a notificação e vê a linha ajustada; 9,99 no frango é recusado com o intervalo; fechar o talão; o valor a cobrar bate com a conta. Capturas em provas/. Cancelar/limpar o pedido de teste pelos caminhos oficiais.
- Verificar nas 3 plataformas: Android (emulador), web (build local ou Cloudflare de pré-visualização se existir), iPhone (o que der no CI da publicação semanal; anotar o que fica para lá).
- Um revisor que não escreveu o código lê o diff dos blocos 2–5 (SIM/NÃO).

BLOCO F — Fecho (obrigatório, mesmo com o contexto a acabar)
- NÃO enviar para o servidor (push) agora: regra do Danilo de 25/10 — as 3 plataformas publicam UMA vez por semana (sábado/domingo). Deixa o ramo peso-variavel-2026-10-26 pronto e regista-o na lista da publicação semanal (.claude/.ai/inbox/publicacao-semanal.md; cria se não existir) com a ordem de juntar: 25/10 nome-cliente/sem-margem → peso-variavel → melhorias-paridade (avisa se houver conflito previsível em ficheiros comuns).
- Relatório .claude/.ai/reports/OPUS-2026-10-26-peso-variavel.md (acessos no topo; o que NÃO foi feito logo a seguir; bloco a bloco com prova; secção "⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO"; "PARA O DANILO" só o que só ele pode fazer). Cópia em C:\Users\danil\Desktop\Bora\prompts\ junto com este prompt (PROMPT_peso_variavel_2026-10-26.md) — registo no Obsidian.
- Digest digest-2026-10-26-peso-variavel em claude_ai_memoria; e2e_log passo "fim"; Telegram em 6 linhas pela ponte (feito, por confirmar, o que precisa do Danilo).
- Achados para REPORTAR (não corrigir sem ordem): order_purchase_items_v2.original_item_id é uuid mas os ids de produto são texto ('cont-…') e ficam NULL; finalizar_talao_nao_parceiro devolve cash_total_due_cents também em MB Way/cartão; catálogos com produtos na secção errada (ex.: "Tinta de Choco" em Peixaria, "Lasanha" em Frutas & Legumes); o que mais encontrares.
- Telemetria da skill protocolo-missao-bora. Termina com /ctx doctor e /ctx stats.

CARTA DE AUTONOMIA (inteira)
- Decides sozinho. Nunca terminas o turno à espera. Um bloco preso mais de 15 min → linha no e2e_log com a causa real e passa-se ao seguinte.
- Nada de perguntas ao Danilo. O que só ele pode fazer (pagar, senha, clique de autorização, decisão legal) fica anotado e é pedido UMA vez no fim, pelo Telegram, com a página já aberta.
- "Feito" só com prova material: saída literal, SELECT de volta, código HTTP, ficheiro lido. Proibido "assumido", "deve estar", "provavelmente".
- Zonas protegidas (dispatch_engine, pricing_service.dart, finalizePurchase, bora_tokens, webhook Stripe, RLS de orders/wallets/ledger) só com ordem explícita nesta missão (dada acima para o talão, a carteira do peso e a cobrança no cartão) e com teste real; o relatório leva "⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO" com a lista do que foi aplicado e como se reverte.
- Caminhos oficiais, nunca UPDATE directo em orders, drivers, wallets, ledger_entries, bora_tokens, payouts, platform_settings financeiros. Pedidos a estafetas só por ops_reassign_order / ops_release_order_driver.
- Os hooks da Trava mandam; não se contornam. O que a Trava bloquear resolve-se por MCP (apply_migration) e regista-se em docs/TRANCAS.md.
- Toda migração aplicada em produção fica no repo com o SQL exacto e o timestamp de produção; nunca se reaplica o que já está no ar.
- Outra janela em paralelo (melhorias-paridade) não toca no teu worktree e tu não tocas no dela. Commits por caminhos explícitos (nunca git add -A).
- Sem push fora do bloco de publicação (e esta missão não publica — vai na semanal).
- Apps em PT-PT, painel admin em PT-BR, relatórios em português simples para ser ouvido em voz. Toda a feature tem correspondência no painel admin.
- Navegadores sempre pelo deviceId (skill navegadores-e-contas); nunca sair de contas; login só em último recurso.
- Lei do pré-voo antes de cada bloco; duas falhas iguais → muda de abordagem.

