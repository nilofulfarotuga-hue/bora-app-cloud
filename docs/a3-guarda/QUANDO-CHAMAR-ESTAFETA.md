# "Quando chamamos o estafeta?" — entrega (17/11/2026)

Missão `a3-parte2-quando-chamar-17-11` (caixa_guardados 115), pedido do Danilo 17/11 05:06,
ordem trazida pela Claude.ai. Registo passo a passo no `e2e_log`, fluxo
`a3-parte2-quando-chamar-17-11`. Ramo `ai/2026-11-17-quando-chamar-estafeta`.

## O que muda

Nas lojas que **não são de comida** (categoria principal `store`, `festas`, `pharmacy`,
`supermarket`, `beauty` — a A3 é `store`), ao aceitar um pedido de entrega a loja vê
"Quando chamamos o estafeta?" com 10 min, 15 min, 20 min, 30 min, 1 h, 2 h, 3 h,
Amanhã (1 dia), 2 dias e "Escolher dia e hora" (calendário + relógio 24 h, até 14 dias, só
dias e horas em que a loja está aberta). Restaurantes de comida ficam como estavam.

- Até 2 h dentro do horário: o servidor guarda os minutos como hoje (estafeta chamado em
  aceite + minutos − 8).
- 3 h, amanhã, 2 dias, dia e hora: guarda a hora prometida (`orders.ready_at_promised`) e o
  despacho chama o estafeta 8 min antes dessa hora (a antecedência de sempre).
- Se uma opção rápida cair com a loja fechada (ex.: "2 dias" a um domingo), passa para a
  primeira hora em que a loja abre — e a folha mostra o dia e a hora antes de tocar.
- Pedido aceite: "Mudar quando fica pronto" com as mesmas opções (sem "Tirar"); o cliente
  recebe aviso da hora nova.
- Cliente: "Fica pronto sexta, 20/11, às 15:00" no acompanhamento e na barra do pedido
  (em vez de "Chega em ~2900 min"); aviso quando a hora muda e quando o estafeta é chamado.
- Painel admin (PT-BR): linha "Pronto em" nos pedidos com botão "Mudar hora", coluna
  `pronto_em` no CSV, filtro "Agendados pela loja" e o interruptor
  `parceiro_quando_chamar_ligado` em Definições (nasce ligado; desligado, as lojas voltam aos
  minutos e o servidor recusa marcar dias, mas os pedidos já marcados continuam à hora).
- Se uma opção curta cair na pausa ou depois de fechar (ex.: "30 min" às 12:45 na A3), passa
  para a hora em que a loja abre, e o botão mostra essa hora.
- Corrigido pelo caminho: a A3 não conseguia aceitar pedidos (tem festas como categoria
  extra e o painel mandava-a para `festas_accept`, que exige festas como principal).

## Para a Claude.ai, por esta ordem

1. **Provar a migração** (a trava do PC não deixou: ler o cofre, DROP e escrita direta em
   `orders`, mesmo em transação desfeita). Numa só chamada:
   `begin;` + `supabase/migrations/20261117130000_quando_chamar_estafeta.sql` +
   `supabase/tests/quando_chamar_estafeta_test.sql`. Tem de acabar em
   `ERROR: RESULT {"falhas": 0, "casos": 22, ...}` (o erro desfaz tudo). Correr numa hora
   calma: a prova corre também as varreduras gerais (despacho, órfãos, demo) e prende essas
   linhas uns segundos. Pressupõe `a3cliente@bora.app` fora das contas demo (confirmado a
   17/11) e `partner_auto_dispatch_after_minutes` > 0 (está 5).
2. **Aplicar a migração** (`apply_migration`, nome `quando_chamar_estafeta`). Faz backup das
   5 funções em `bkp_fn_*_20261117`; o cabeçalho diz como desfazer.
3. **Só depois juntar o ramo** e deixar o CI publicar (Play, Apple, web). Se a app sair antes
   da migração, "3 h / amanhã / 2 dias / dia e hora" falham ao aceitar (os minutos funcionam).
4. Teste real na `a3-guarda` (loja escondida, pagamento em dinheiro, nada cobrado nem
   estafeta real): com `a3cliente@bora.app` fazer 2 pedidos; com `a3teste@bora.app` aceitar
   um com "2 dias" e outro com "Escolher dia e hora" → sexta 15:00. Ver no cliente
   "Fica pronto…", no admin o filtro "Agendados pela loja", e que nenhum é chamado antes da hora.

## O que se viu (2.5) — nada cancela um pedido aceite que fica dias em preparação

- `bora_dispatch_maintenance` / `dispatch_fases_sweep`: só mexem em `callingDriver` (e em
  `created` com pagamento por pagar). Em preparação, nada.
- Pagamentos: cartão e MB WAY dos pedidos são cobrados na hora (sem captura manual); não há
  nada a expirar aos 7 dias. Dinheiro: sem prazo.
- `_cron_check_orphan_orders` dava alarme falso de "pedido órfão" ao admin — corrigido.
- `mover_pedidos_demo` fechava os pedidos de TESTE 6 h depois de criados (o teste "2 dias"
  da A3 morria) — agora conta 6 h a partir da hora prometida. Pedidos reais não passam por aqui.
- `robot_observe` (Robô B) conta como "preso" qualquer pedido em preparação com mais de 2 h:
  só observação; reportado, não mexido.
- Restaurantes: o botão "Fica pronto às…" (modo ocupado) promete "o estafeta é chamado a
  tempo" mas o despacho ignora essa hora nos restaurantes. Não mexido (zona protegida;
  proposta C6 de 29/10 em `docs/propostas/missao-geral-2026-10-28/C6_modo_ocupado/`).

## Notas do revisor (contexto limpo) que ficaram por fazer

- Os textos novos do cliente ("Fica pronto…", "Hora marcada pela loja.") não passam pelo
  `.tr`: quem usa a app em inglês vê-os em português.
- O servidor não confere o horário da loja para `p_pronto_em` (só a app o faz).
- Um restaurante com o modo ocupado e "fica pronto às" a mais de 1 h passa a ver o dia e a
  hora no cliente; o despacho dos restaurantes continua a ignorar essa hora (proposta C6).

## Testes

- `test/quando_chamar_estafeta_test.dart`: regra das lojas, textos de Lisboa (inverno e
  verão), as 9 opções, pausa/sábado/domingo, calendário, o que o cliente vê, a folha no
  ecrã (opções, calendário, erro na pausa) e o botão "Mudar quando fica pronto".
- `supabase/tests/quando_chamar_estafeta_test.sql`: servidor em transação desfeita (A3 com
  2 dias e sexta 15:00, 16 dias recusado, despacho espera, chama a 7 min com aviso, espera a
  9 min, restaurante igual a hoje, sem alarme de órfão, teste vive além das 6 h, textos e
  permissões).
- Flutter não correu no PC (modo leve): `flutter analyze` e `flutter test` correm no CI do
  pedido de revisão (job `build-ios` / simulador). Só se confirmou a sintaxe com `dart format`.
