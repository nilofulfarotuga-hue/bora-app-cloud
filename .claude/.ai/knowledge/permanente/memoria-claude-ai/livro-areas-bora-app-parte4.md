---
id: memoria-claude-ai-livro-areas-bora-app-parte4
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App multi-vertical platform — architecture, verticals, business rules, and protected zones (parte 4 de 4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-bora-app-parte4`, origem `claude-ai`, atualizada em 2026-10-23T05:43:22.407467+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas bora app parte4 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/bora-app.md, parte 4 de 4), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

- ✅ CORREÇÃO COMPLETA no mesmo dia (16/08, depois de o Valdemir continuar a não VER o pedido): a app do estafeta identifica-se por **auth.uid() = drivers.user_id**. PROVA nos edge_logs: o telemóvel dele pede `orders?current_driver_offer_id=eq.e355fde0…` e `assigned_driver_id=eq.e355fde0…` (user_id), enquanto o dispatch-engine gravava `drivers.id`. Logo a oferta nunca aparecia no ecrã dele E `driver_accept_offer` (exige current_driver_offer_id = auth.uid()) rejeitaria sempre.
- CONVENÇÃO FIXADA: **user_id manda em tudo o que a app vê/aceita** (assigned_driver_id, current_driver_offer_id, driver_id, créditos/tokens/saldo); `drivers.id` fica só para `tried_driver_ids` e matching interno. Corrige também a nota anterior de que assigned_driver_id devia levar drivers.id — a RLS é que estava errada, não a app.
- FEITO por MCP: (1) migration `fix_rls_orders_update_driver_aceita_user_id_2026_08_16` — policy `orders_update_driver` passa a aceitar drivers.id OU drivers.user_id (estava só id, alinhada agora com orders_select_driver); (2) pedido 4db5882d… passou a assigned_driver_id/driver_id = user_id do Valdemir; (3) `dispatch-engine` **v59** deployed (deploy nº 61, verify_jwt=false) — `current_driver_offer_id` passa a levar drivers.user_id, e exclusão/reset de ciclo/contagem de pedidos ativos aceitam os DOIS formatos (helpers driverKeys/offerKeyFor), sem tocar em pricing, TTL, claim ou rotação.
- PROVADO por SQL com a identidade dele (set role authenticated + jwt sub=e355fde0…): SELECT devolve o pedido e UPDATE é permitido (teste em transação com rollback).
- "TESTE" no ecrã do Valdemir (16/08): o pedido NÃO estava marcado como teste (is_test_order=false, dados 100% reais, selo TESTE só existe no painel admin). O que ele viu é um BOTÃO mal-nomeado do app do estafeta: driver_home_screen.dart tem TextButton 'Teste' na AppBar (~l.722) + _FloatingIconButton tooltip 'Teste' (~l.1070), e partner_dashboard_screen.dart outro (~l.627) — todos chamam _handleTestMode que na verdade TROCA DE PERFIL (logout do papel). Perigo real: estafeta toca nele a meio da entrega e é deslogado. Aberta ordem no loop `ordem-20260816152556-4f7c` (zona verde): renomear para 'Trocar perfil', ícone swap_horiz, diálogo de confirmação PT-PT, sem mexer na lógica.
- DESCOBERTA ÚTIL: o repo `nilofulfarotuga-hue/bora-app-cloud` é PÚBLICO — a Claude.ai consegue clonar por HTTPS na sandbox e ler o Flutter diretamente (git clone --depth 1 --branch autonomous-night-2026-04-29). Investigação de UI já não depende do executor. (Vale levantar ao Danilo se o repo devia ser privado.)
- Pedido McDonald's de 16/08 14:32 (4c95c1d1…): era da mesma dona Isabel (Isabel Rebelo, 968045045, mesma morada) — 20 Chicken McNuggets + molho maionese e alho, 13,65€, dinheiro. Cancelado pelo SISTEMA às 14:52 (dispatch_max_total_with_drivers_exceeded, 20 min sem aceitação) — foi vítima do bug do notify-driver: o Valdemir nunca foi chamado e o Danilo não pegou.
- CASO "13,09" (16/08): a dona Isabel pagou 12,09€ do pedido + 1,00€ de dívida anterior (orders.debt_collected_cents=100; wallet cobra dívida em cash na entrega via fn_apply_client_debt_settlement_on_cash_delivery). A dívida veio da taxa de cancelamento before_dispatch (1€, grace 180s) do pedido Auchan 369dc7b8 das 14:25, que ELA cancelou às 14:29 com razão "não há estafetas" — vítima do bug do notify-driver. DECISÃO Danilo (regra nova): cancelamento por falta de estafetas não cobra nada.
- FEITO por MCP: (1) +1,00€ na carteira dela (wallet_credit_generic kind admin_grant — kinds válidos: cashback/referral/admin_grant); (2) o 1€ cobrado em cash ficou com o Valdemir sem débito → cash_adjustment do pedido 4db5882d atualizado 0,80→1,80 e saldo dele 4,43→3,43; (3) `cancel_fee_before_dispatch_cents` 100→0 em platform_settings (implementa a regra; reversível; igual Uber/Glovo — antes de estafeta aceitar não cobra).
- 🐞 BUGS SISTÉMICOS achados p/ [[auditoria-pagamentos]]: (a) dívida cobrada em cash é marcada paga na wallet mas NUNCA debita o estafeta que a recolheu (fica com o € na mão sem registo); (b) ledger_entries cash_adjustment do 4db5882d saiu -6,03 (devia -0,80) — fórmula do ledger divergente; ledger é APPEND-ONLY (guard), correção foi por linha compensatória +4,23 ref correcao_16ago.
- Entrega 4db5882d confirmada: tokens/saldo/talão caíram na chave CERTA (user_id) — ganho 5,23€, talão 6,06€ reembolsado, comissão Bora 2,50€.

Missão app leve + bateria (2026-08-24, ordem do Danilo)
- [stated] Danilo mandou aplicar ao aplicativo TODO de produção (cliente, parceiro E estafeta) uma varredura de peso, velocidade e consumo de bateria, ao nível do que Uber e Glovo fazem — "vai a fundo". Prompt FABLE entregue (PROMPT_app_leve_bateria_FABLE_2026-08-24.md): item 0 = loja de categoria festas nunca mostra "Fechado" (mostra "Aceita encomendas"); depois medir antes, portar para produção os cortes de assets já provados no branch festas-preview (ícone 1,7 MB→33 KB, imagens de categoria 5 MB→527 KB), varrer todos os assets das 3 apps, e GPS adaptativo do estafeta (forte só em corrida, DESLIGADO offline), envio por lotes, push em vez de poll, com prova no telemóvel por USB e corrida de teste em dinheiro para garantir que o dispatch continua a ver o estafeta. Estado: EXECUTADA 24/08 — em produção: AAB 86,5→80,1 MB (cortes de assets), envio de posição mín. 5 s (salto >30 m fura), distanceFilter 5 m em corrida; o resto do padrão Uber/Glovo já existia. FICOU POR FAZER (adb a zero, telemóvel nunca ligado por USB): medições no aparelho (arranque a frio, dumpsys/batterystats, corrida de teste) e ligar R8/shrinkResources/tree-shake — exigem o cabo USB ligado na próxima sessão.
FINAL WRITE
- [stated] REGRA NOVA (2026-08-24): LOCALIZAÇÃO NUNCA TRAVA — na app cliente (Android, iPhone e web), GPS negado/desligado nunca impede pedidos: o cliente escreve a morada à mão (campo de pesquisa em primeiro plano), pode navegar sem endereço nenhum (ordenação padrão sem distância), endereço só é exigido no checkout de ENTREGA (recolha nunca exige), "Localização actual" é atalho opcional e a morada escrita fica guardada. Motivo dele: cliente que não sabe mexer acha que a app está quebrada. Entregue como adendo ao prompt FABLE (0-B: preview da Keli entra direto nas Festas sem ecrã de endereço; 0-C: regra em produção).
FINAL WRITE


