# CONTINUAR — ronda-dinheiro-despacho-2026-10-05

Relatório: `.claude/.ai/reports/2026-10-05-ronda-dinheiro-despacho.md`.
Tudo o que está pronto mas não aplicado vive em `.claude/.ai/missoes/ronda-04-10/pronto/LEIA.md`.

## 0. PRIMEIRO: o código está gravado mas NÃO publicado

O `git push` para o ramo de produção foi recusado pelo classificador de segurança do
Claude Code a 05/10 às 07h43 (como a 04/10). Não se tentou outro caminho. O commit
`5efd2d96` está em `C:/BoraLocal/wt-ronda-05-10`, ramo local
`ronda-dinheiro-despacho-05-10`, um commit em cima de `7615eee7` (versionCode 648).
Só segue com a confirmação expressa do Danilo. Quando seguir: conferir que o remoto
não avançou (se avançou, rebase), empurrar fora de hh:05–09, e acompanhar o CI
(autoteste → build → Play e web).

Enquanto não for publicado: a migração `20261005061548` já está aplicada em produção
mas o ficheiro dela só existe neste commit; e a app publicada mostra a mensagem
genérica (não a nova) quando o parceiro toca em "Chamar estafeta".

## 1. Motor de despacho v62 — precisa da Trava aberta (só o Danilo abre)

Proposta completa e simulada (14 de 14) em `pronto/dispatch-engine-v62/`. Aplicar =
copiar `index.v62.PROPOSTA.ts` para `supabase/functions/dispatch-engine/index.ts`,
publicar com `verify_jwt=false`, provar (403 sem token e com a chave pública; 200 por
`invoke_dispatch_engine`; registos com "N candidatos"), commit do ficheiro.
Antes de aplicar, voltar a conferir o ar contra o repo (ver memória
`verificar-edge-no-ar-antes-de-deploy`): a 05/10 o ar era a v61 = ficheiro do repo.

## 2. Fecho do "parceiro chama estafeta" — missão própria, depois ligar o interruptor

Análise e números em `pronto/LEIA.md` §4. Funções a tratar: `post_order_to_ledger`,
`apply_order_financial_split`, `order_driver_reimbursement` / `apply_driver_cash_settlement`,
extractos do parceiro e fecho semanal. Provar em transacção desfeita com um pedido de
10 € de balcão (certo: loja deve 4,00 à Bora, estafeta recebe 4,00, Bora 0).
Só depois: `dispatch_parceiro_chama_estafeta_ligado = true` (painel, Configurações → dispatch).

## 3. Missões da ronda que nunca arrancaram e não têm texto

`dinheiro-entregas` e `admin-dinheiro`: não há enunciado no repo nem na base (os
`achados/*.md` perderam-se; as missões ficaram na conversa da Claude.ai). A Claude.ai
tem de as escrever em `.claude/.ai/missoes/ronda-04-10/` para alguém as poder executar.

## 4. Restos pequenos (ver `pronto/LEIA.md` §2, §3 e §5)

- Favor: função própria para o dinheiro da paragem em casa (ficheiro trancado).
- `pricing_service.dart`: só arrumação do valor de reserva (2,50 → 0,99).
- Festas: o orçamento conta o saco (`festas_money_patch` por aplicar desde 25/08).
- "Deixar à porta" + dinheiro: guarda no servidor para pedidos forjados.
- Rascunhos de pagamento: tirar o botão de excluir ou dar-lhe função própria.
- Sinal com segredo: exigir `is_online`; mais tarde fechar o `driver_heartbeat_by_id` a quem não tem sessão.
- Carrinho abandonado: decidir se o aviso respeita "só quem aceitou promoções" antes de ligar.

## 5. Da ronda, fora de dinheiro e despacho (não tocado)

- `_notify_partner_status_change` chama o `notify-partner` com a chave pública → 403
  (os avisos de mudança de estado ao parceiro não saem; já falhavam antes com 400).
- `log_admin_action` aceita qualquer utilizador autenticado.
- Apagar os dois ecrãs mortos do parceiro (`restaurant_dashboard_screen.dart`,
  `partner_reservations_screen.dart`) e fechar as 2 linhas antigas de `cortex_red_proposals`.
- O push `carrinho_abandonado` devia abrir o carrinho ao tocar.

## 6. Só se prova no aparelho

- Estafeta com a app em segundo plano: o sinal continua a bater (com segredo; e com o
  caminho antigo se o segredo falhar) — ver `drivers.last_heartbeat_at` e
  `driver_heartbeat_segredos.usado_em`.
- Cliente: "Deixar à porta" com cartão e MB Way ponta a ponta; o estafeta vê o aviso e
  a foto fica gravada.

## 7. Handoff para o Cérebro (por entregar ao `bibliotecario-cerebro`)

Não foi entregue a 05/10 porque o que ele escrevesse ficava por publicar com o resto.
Quem empurrar este commit entrega os quatro blocos.

```
HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-skip-ci-no-commit-de-cima.md
conteudo: A marca [skip ci] no commit de CIMA de um push salta o build do push inteiro,
  mesmo que os commits de baixo tragam código. A 05/10/2026 o commit do relatório ia
  com a marca por cima do commit de código 5efd2d96; foi corrigido antes de empurrar.
  Só se põe a marca quando TODOS os commits do push são só-documentos.
```

```
HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: projeto
tema-alvo: permanente/semantica/zonas-protegidas.md
conteudo: O "autorizo tudo" do Danilo é a ordem, não a chave. A 05/10/2026, com essa
  ordem dada na conversa, a Trava do PC continuou a proibir editar e publicar o
  dispatch-engine e editar pricing_service.dart (já tinha sido assim a 08/09), e o
  git push para produção foi recusado pelo classificador do Claude Code (como a 04/10).
  O que se faz: tudo o que não está trancado, o resto pronto em
  .claude/.ai/missoes/<ronda>/pronto/ com prova, e a palavra pedida uma vez no fim.
```

```
HANDOFF → bibliotecario-cerebro
tipo: bug
escopo: projeto
tema-alvo: permanente/episodica/bugs-resolvidos.md
conteudo: (ABERTO) "Parceiro chama estafeta" — post_order_to_ledger e
  apply_order_financial_split lançam o pedido como pedido normal de parceiro em dinheiro;
  as regras 2.4.1 dizem que o estafeta paga o total à loja. 10 € de balcão: loja +12,57 a
  mais, estafeta −10. Interruptor dispatch_parceiro_chama_estafeta_ligado=false desde
  05/10/2026 (migração 20261005061548). Zero pedidos existiam.
```

```
HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-apagar-sem-politica-devolve-204.md
conteudo: Um DELETE pelo PostgREST numa tabela com RLS e sem política de apagar devolve
  204 e apaga ZERO linhas, sem erro. O painel "apagava" rascunhos de pagamento há meses
  sem apagar nenhum (payment_drafts só tem política de leitura; medido a 05/10/2026).
  Pedir sempre de volta o que saiu (.select('id')) antes de dizer "apagado" ou registar
  na auditoria.
```
