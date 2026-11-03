---
id: memoria-claude-ai-prompt-favor-diferenca-mbway-2026-11-03
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-03
zona: verde
confianca: alta
estado: atual
---

# Prompt Favor com compra a mais: MB Way da diferença (03/11 13:35)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-favor-diferenca-mbway-2026-11-03`, origem `claude.ai`, atualizada em 2026-11-03T13:32:24.795496+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt favor diferenca mbway 2026 11 03 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5 (mexe em dinheiro) · PORTA: app Claude no PC do Danilo, separador Code, "Este computador", pasta bora_app (repo bora-app-cloud), modo "Ignorar permissões". SESSÃO NOVA (não usar a sessão da Boom).
MISSÃO: favor-diferenca-mbway-2026-11-03 (e2e_log fluxo = favor-diferenca-mbway-2026-11-03, um passo por bloco)
Entra pelo orquestrador CEO-AI (.claude/skills/ceo-ai/) e pela skill protocolo-missao-bora; antes de abrir sites, skill navegadores-e-contas. Lê no livro (claude_ai_memoria): erros-aprendidos, regras-do-danilo, stripe-duas-contas e esta página. git pull origin autonomous-night-2026-04-29 primeiro.

AUTORIZAÇÃO (Danilo, 03/11/2026 13:22, texto literal): "Sim, eu autorizo. E já chega a notificação para ele lá, explica direitinho como que é, o que que tá faltando, fala que eu comprei 3 pellets e ele tem que fazer o pagamento, senão não consegue entregar. Vai logo, vê logo, eu autorizo, vai, mano." Foi a resposta a: mandar ao Divan o MB Way da diferença e mudar o fluxo do Favor com compra a mais, publicando nas 3. NÃO muda preços nem taxas.

O QUE ACONTECEU: Favor b72c4f2c (cliente Divan, "3 pallets de lareira", pago por MB Way). Orçou 6 €; pagou 13,21 € (6,01 € de taxa + 7,20 € de margem da compra). Compra real 17,97 € (3 × 5,99). O estafeta não carregou em "pedir mais orçamento" antes de comprar; finalize_errand_purchase marcou errand_budget_status='disputed' e devolveu charge_extra_cents=0, e o ecrã do estafeta mandou cobrar ZERO. Faltavam 10,77 €.

JÁ FEITO PELA CLAUDE.AI POR MCP (passar para o repo IGUAL ao que está no ar):
R1. Edge Function nova favor-cobrar-diferenca (v1, verify_jwt=true, só chamadas do servidor): pede o MB Way no servidor ao telefone do MB Way do pagamento original (padrão provado do cleaning-request-payment). metadata kind='errand_extra', pedido_id, user_id — SEM order_id de propósito: com order_id, um MB Way recusado faria o webhook pôr payment_status='failed' no pedido principal. Tem action 'status'. Ir buscar o código no ar, gravar em supabase/functions/favor-cobrar-diferenca/ e passar a usar _shared/chaves.ts e _shared/stripe_contas.ts sem mudar o comportamento.
R2. Migrations favor_mbway_pede_diferenca_20261103 e favor_mbway_texto_virgulas_20261103: finalize_errand_purchase, quando é MB Way e a compra passa o que o cliente já pagou, chama favor-cobrar-diferenca + notify-client + _push_in_app_notification e devolve charge_extra_cents = valor pedido e mbway_diferenca_pedida=true. Cópia da versão antiga em bkp_fn_finalize_errand_purchase_20261103. Gravar as duas em supabase/migrations.
R3. MB Way de 10,77 € já pedido ao Divan (pi_3UXhgcGWwQxC9wR21TaxkZPl, conta empresa) e aviso enviado. NÃO repetir.

O QUE FAZER:
A — Webhook (_shared/stripe_webhook_core.ts, vale para as duas contas). Porquê: hoje um PI kind='errand_extra' cai em "pagamento sem etiqueta" e o pedido nunca fica acertado. Ramo novo ANTES dos ramos draft_id/order_id. succeeded → no pedido de metadata.pedido_id: extra_charge_amount = valor, extra_charge_settled_at = agora, extra_charge_settled_via = 'mbway_diferenca', errand_budget_status = 'approved' se estava 'disputed' ou 'pending'; ledger se o pedido principal regista (ver post_order_to_ledger); aviso ao estafeta ("O cliente pagou a diferença") e ao admin. payment_failed/canceled → só avisos ("o cliente não pagou a diferença"), NUNCA mexer no payment_status do pedido. Idempotente por event.id. Se o Divan já tiver pago quando chegares, acertar o b72c4f2c à mão da mesma forma.
B — Fluxo ANTES de comprar (igual à Glovo/Uber). Porquê: o estafeta não pode ter de adivinhar. No ecrã do estafeta de um Favor com compra, botão claro "O preço é maior do que o orçado" → escreve o total → errand_request_budget_increase passa a: MB Way → pede logo a diferença por MB Way (favor-cobrar-diferenca) em vez do botão "autorizar" na app; cartão → o cliente aprova na app e cobra-se no cartão guardado off_session (padrão cobrar-diferenca-peso, com idempotência); dinheiro → o cliente aprova na app e o ecrã mostra o novo total a receber em mão. O estafeta vê "À espera que o cliente pague X €" e só recebe "Pago, podes comprar" depois do webhook; se o cliente recusar → "O cliente não aceitou: compra só até Y € ou cancela o Favor". O cliente vê na app o que falta, porquê, e o estado do MB Way.
C — Bug do charge-extra. Porquê: aprovações nunca cobraram. finalize_errand_purchase (caminho aprovado) chama charge-extra com {amount_cents}, mas a função espera {amount} em euros e só cria um PI sem o confirmar. MB Way já está coberto pelo R2; para cartão trocar pelo caminho off_session do B. Procurar outros sítios que chamem charge-extra do mesmo jeito (ex.: pending_charges dos sacos) e REPORTAR.
D — Ecrã do estafeta depois do talão: mostrar "Falta receber X € — pedido MB Way enviado ao cliente" e o estado (à espera / pago / recusado), nunca zero.
E — Painel admin (PT-BR, termos técnicos explicados entre parênteses): na ficha do pedido e em Operação do dia, lista "Diferenças de Favor" com valor, estado do MB Way/cartão, botão "reenviar pedido MB Way" (tentativa+1) e "Bora assume a diferença".
F — Testes: unitários das contas; webhook com evento simulado; e2e com pagamento em DINHEIRO (regra do Danilo). Nenhuma cobrança real de teste.
G — Publicar nas 3 (Play Store, App Store/TestFlight, web) e provar nas 3. O CI incrementa o versionCode, não mexer. Enviar para o servidor: git push origin autonomous-night-2026-04-29.

Outros erros encontrados pelo caminho: REPORTA, não corrige calado. Dinheiro: só o que está aqui.
Relatório no fim em texto corrido ("fiz isto, falta isto") no e2e_log e no livro (página digest-favor-diferenca-mbway-2026-11-03).
/ctx doctor
/ctx stats

ADENDO 1 (03/11 13:35, depois de o Danilo já ter colado a missão):
1. O MB Way pedido ao Divan EXPIROU sem pagar (pi_3UXhgcGWwQxC9wR21TaxkZPl ficou em requires_payment_method, "latest payment attempt expired"). O MB Way dá poucos minutos. Fazer: na app do cliente, botão "Pagar a diferença" que manda um MB Way novo (tentativa+1) sempre que o anterior expirou ou falhou, com o aviso "tens poucos minutos para aprovar na app MB Way"; o webhook (kind errand_extra, payment_failed/canceled) avisa o cliente "o pedido MB Way expirou, carrega em Pagar a diferença"; o ecrã do estafeta mostra "expirou" e um botão "reenviar".
2. A tabela orders tem a regra orders_extra_charge_settled_via_check que só deixa 'wallet', 'cash' ou 'none'. O bloco A ('mbway_diferenca') ia falhar, e o cobrar-diferenca-peso grava 'cartao_peso' (vai falhar quando o interruptor for ligado). Alargar a regra (mbway_diferenca, mbway_direto, cartao_peso, cartao_diferenca) numa migration e REPORTAR outros valores que o código use.
3. Caso do Divan FECHADO pela Claude.ai às 13:31 por ordem do Danilo: o Divan paga os 10,77 € por MB Way direto ao Danilo. Pedido b72c4f2c entregue (sem código PIN: o Danilo esqueceu-se de o pedir), extra_charge_amount 10,77 acertado com via 'cash' (por causa da regra do ponto 2; depois de alargar, mudar para 'mbway_direto'), errand_budget_status 'approved', talão admin_paid sem reembolso (estafeta = Danilo). Ganho 5,01 €, comissão 1,00 €, tokens e fatura gerados pela entrega normal. Não voltar a mexer além da etiqueta.
4. Entregar sem código: quando o estafeta se esquece do PIN, o painel admin precisa de "Marcar entregue sem código" com motivo obrigatório e registo no admin_audit_log. Ver se já existe; se não, criar.
