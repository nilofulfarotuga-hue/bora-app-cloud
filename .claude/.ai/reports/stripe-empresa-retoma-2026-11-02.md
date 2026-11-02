# Relatório — Stripe da empresa, RETOMA (02/11/2026, 06:20–07:20)

Missão `stripe-empresa-2026-11-01`, retoma no Claude Code com o Opus (sessão
session_01HPEpVCiQJz5VkNWpbqKu2X). Autorização: «Autorizo», Danilo, 01/11/2026 22:03.

## Para o Danilo (texto corrido)

Fiz isto: o servidor já está quase todo ligado à conta da empresa. Publiquei 25 funções do
servidor com o código das duas contas (reservas, marcações, limpeza, lavagem, gorjetas, dívida,
peso, cartões guardados, cancelamentos com a devolução da gorjeta, relatório da contabilista e o
painel de pagamentos) e a função nova que recebe os avisos da Stripe da empresa. Fiz a prova sem
cobrar ninguém: o servidor criou um pagamento de 50 cêntimos sem cartão na conta da empresa e
cancelou-o logo, e o aviso da Stripe chegou ao servidor e ficou registado como sendo da empresa.
Fiz a mesma prova na tua conta pessoal e também está bem. A lista de pagamentos do painel estava
partida desde sempre e agora funciona e mostra de que conta é cada pagamento. O interruptor
continua em "pessoal", por isso hoje nada mudou para os clientes.

Falta isto, e porquê: oito funções, as mais sensíveis (criar o pagamento do pedido, MB Way, o aviso
da conta pessoal, reembolsos, cancelamento pelo cliente e o extra), a tranca não me deixa
publicar; ficou um guia exato para a Claude.ai as publicar pelo MCP. Falta também mudar duas linhas
no ficheiro dos pedidos da app, que é zona protegida e precisa de sessão contigo. O interruptor
para "empresa" só o pode virar uma sessão de administrador, e só faz sentido depois dessas oito.
Publicar a app nas três lojas fica à espera da tua ordem: o código está pronto e já junto com o
que está em produção.

Erros que encontrei pelo caminho: o aviso da Stripe da empresa tinha sido criado a ouvir cinco
tipos de evento e o da pessoal só ouve três; isso podia fazer a empresa marcar pedidos como
falhados quando a pessoal não o faz, e já pus iguais. A lista de pagamentos do painel nunca
funcionou (erro no banco, corrigido). A tranca não vê publicações feitas de uma certa forma, e por
isso a função nova do aviso da empresa passou sem a pergunta dela; não usei esse caminho para as
oito sensíveis e registei o buraco. O aviso de "pagamento sem pedido" mostra 0,00 € em pagamentos
cancelados (só texto, não corrigi por estar no código do aviso da Stripe).

Próximo passo: a Claude.ai publica as oito funções com o guia; numa sessão contigo aplica-se a
mudança de duas linhas na app e vira-se o interruptor; depois, quando disseres, publica-se a app
nas três lojas.

## O que NÃO foi feito (logo no topo, como manda o protocolo)

- 8 funções da zona vermelha por publicar → `docs/propostas/stripe-duas-contas/DEPLOY_ZONA_VERMELHA.md`.
- Proposta 04 (`lib/stores/order_store.dart`, 2 linhas) — zona vermelha, tranca nega.
- Interruptor `stripe_conta_nao_tvde` continua `"pessoal"` (sem sessão de admin; UPDATE direto
  em definição de dinheiro é proibido aos agentes).
- Provas em modo de teste da empresa com a app no emulador: não há chaves de teste da empresa e o
  PC tinha ~1 GB livre (o emulador pede 3 GB).
- Migrações aplicadas copiadas para `supabase/migrations/`: a tranca recusa; SQL exato em
  `docs/propostas/stripe-duas-contas/aplicadas/`.
- Publicar nas 3 lojas: à espera de ordem do Danilo.

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — lista fechada do que foi aplicado e como se reverte

1. Migrações `20261102062513 admin_list_payments_conta` e `20261102062623
   admin_list_payments_nomes_colunas` (só leitura do painel). Reverter: renomear
   `admin_list_payments_antes_20261102` de volta (mas a antiga estava partida).
2. 24 funções publicadas (versões no e2e_log R2-deploy-lote1 e R2-deploy-lotes2-4) + admin-payments
   v12 + stripe-webhook-empresa v1. Com o interruptor em "pessoal" e as apps das lojas sem a
   bandeira `stripe_contas_v2`, todos os pagamentos novos continuam na pessoal. Reverter: voltar a
   publicar a versão do ar guardada em `%TEMP%\claude\stripe-empresa-prod\per\<fn>`.
3. Destino de webhook da empresa na Stripe: 5 → 3 eventos (iguais aos da pessoal).
4. Duas provas de 0,50 € criadas e canceladas (empresa e pessoal) — nenhuma cobrança.

## Prova material

e2e_log, fluxo `stripe-empresa-2026-11-01`, linhas a partir do id 6139 (R0 a R6).
Ramo `stripe-empresa-retoma-2026-11-02`: 52fa3f91 + merge 7ca0e0cb. Sem push.
Revisão independente (contexto limpo) do código novo do admin-payments: ver secção seguinte.

## Revisão independente

Revisor com contexto limpo (só leitura) ao commit 52fa3f91 do `admin-payments`: **OK**. Sem forma
de quem não é administrador nem servidor chegar às ações novas (anon e sessão normal recusados;
provado também por pedido real: 401), a prova não consegue cobrar (sem confirm, sem cliente, sem
cartão, o client_secret nunca é devolvido), a leitura antecipada do corpo não parte as ações antigas
e `webhooks` não mostra segredos. Notas baixas: (1) cada prova gera um aviso "pagamento sem pedido"
no painel — já não, porque o webhook da empresa deixou de ouvir "cancelado"; (2) se o cancelamento
falhasse, o id do pagamento perdia-se — **corrigido**, admin-payments v13 (07:14, a tranca perguntou
e foi permitido); (3) informativo, de antes desta missão: `confirmadaNoAuth` guarda em memória as
chaves antigas aprovadas sem prazo — uma chave revogada continua aceite até a função reiniciar.
