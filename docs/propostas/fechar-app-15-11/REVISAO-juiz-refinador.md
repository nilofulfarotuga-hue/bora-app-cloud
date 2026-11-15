# Revisão do ramo `ai/2026-11-15-fechar-app` — Juiz e Refinador (15/11/2026, 00:05)

Revisor com contexto limpo, só leitura, sobre `3bb21b46..HEAD`. Não correu dart nem flutter (PC em modo leve): o que diz sobre Dart vem de leitura.
Zonas proibidas: sem alterações (`pricing_service.dart`, `lib/dispatch`, `order_store.dart`, `stripe-webhook`, `client-cancel-order`, `create-mbway-payment-intent`).

## BLOQUEIA (não juntar o ramo sem isto)

1. **MB WAY: "tenta outra vez" com o pedido antigo ainda vivo na app do banco — pode pagar duas vezes.**
   `lib/screens/payment_method_screen.dart:1730-1752`. O `client-cancel-order` não cancela o pagamento na Stripe, e o `stripe-webhook` (linhas 391-455) reativa um pedido cancelado por `payment_failed` se o dinheiro entrar depois. Agora o cliente fica no ecrã com o carrinho e o convite para repetir: se aceitar os dois pedidos na app MB WAY, ficam dois pedidos pagos.
   Correção de fluxo: guardar o id do último pedido MB WAY; antes de criar outro (e ao voltar à app) ler esse pedido; se estiver pago ou já não cancelado, limpar o carrinho e abrir esse pedido. Juntar à frase "se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá".
   Correção de raiz (zona de dinheiro, só proposta): o `client-cancel-order` cancelar o pagamento na Stripe quando o motivo é `payment_failed`.

## CONSERTAR

2. Carrinho cheio depois de pagar — `payment_method_screen.dart:1696, 1744, 1756`. O carrinho só se limpa depois de dois `if (!mounted) return;`. Se o Android matar a app enquanto o cliente aprova no MB WAY, ou o ecrã sair da pilha, o carrinho volta inteiro com o pedido pago. Guardar a marca "pedido MB WAY à espera: id" e limpar no arranque/ao voltar; limpar antes do `!mounted`.
3. Pedido agendado vira "para agora" na 2.ª tentativa — `cart_store.dart:1767-1770` com `agendar_pedido_service.dart:565, 581`. O `gravarEscolha` apaga a hora escolhida mas com `manterCarrinho` o carrinho fica. Em produção há 3 pedidos agendados em 30 dias. Não apagar a escolha com `manterCarrinho`; apagar em `limparDepoisDoPedido()`.
4. A mensagem tapa o botão de pagar durante 9 s — `payment_method_screen.dart:1734-1739, 1746-1750`. Mostrar o motivo num cartão dentro da lista ou num diálogo com "Tentar outra vez" / "Escolher outro meio".
5. Botão ativo antes de o pedido antigo estar cancelado — `payment_method_screen.dart:1730` contra `1740, 1751`. Manter `_isProcessing` ligado até o cancelamento responder.
6. Frases novas do MB WAY perderam o inglês — `lib/utils/mensagem_mbway.dart:13-54`. Passar pelo `.tr` e juntar a `lib/l10n/strings_en.dart` (chaves antigas órfãs nas linhas 3501 e 3683).
7. Vigia dos pedidos presos: vai avisar de 10 em 10 min e contar agendados como presos — `ferramentas/vps/vigia_pedidos.py:107, 113, 140`. Chave só com id e estado; filtro com `scheduled_for` vazio ou já passado.
8. Proposta 8e deixa margens e notas internas ao alcance dos robôs — `8e_robos_sem_notas_internas.PROPOSTA.sql`, função `_conhecimento_para_clientes`. Dos 37 trechos de `business_rules`: 4 falam de markup oculto, 4 de comissão, 1 de lucro, 2 de senha. Usar lista de secções permitidas (ou coluna "público") e rever os 2 trechos com "senha".
9. `CarregamentoUnico` pode ficar preso para sempre — `lib/services/carregamento_unico.dart:53-62, 77-85`. `marcado` é `late final` e é lido dentro da própria função antes de ser atribuído (`LateInitializationError`). Calcular a espera uma só vez fora da função ou usar `Completer`. Hoje é código sem uso na app; passa a contar quando o patch do `order_store` entrar.
10. Robô do talão — `ocr-receipt/talao_regras.ts:37-42, 76-81`; `index.ts:182`. (a) Basta uma palavra comum de 4+ letras para dizer "mesma loja" (pizza, sushi, house, burger, sabores, kebab repetem-se nas 31 lojas): tratar como genéricas as palavras que aparecem em 2+ lojas. (b) `store_check` e `lines_check` não são lidos em `lib/`: falta a linha em `lib/screens/admin/admin_receipts_screen.dart`.
11. Testes que passam sem provar — `test/mbway_falha_mantem_carrinho_test.dart:83-135` (só procura texto no código; usar o `OrderStoreFalso` de `test/agendar_mercados_test.dart`); `test/catalogo_grande_cursor_test.dart:44-75` (testa uma regra escrita no próprio teste; provar o ciclo real com `MockClient`).
12. "Acesso negado" do painel manda sair e entrar mas não dá botão — `admin_dashboard_screen.dart:315-342`. Botão "Sair dessa conta"; decidir pela sessão e não pelo e-mail (conta por telemóvel vê "ainda não entrou").

## NOTAS

13. O Bloco 2 ainda não está ligado: `driver_main_screen.dart:271-276` não passa `haMaisNoServidor` nem `aoPedirMaisAntigas`; o `CarregamentoUnico` só é usado nos testes. No patch do `order_store`: usar `Future.wait` nos dois pedidos; o canal ao vivo traz o histórico inteiro mas as páginas contam de 20 em 20 desde o princípio; um `await loadOrders()` logo a seguir a outro espera mais 2 s.
14. `restaurant_store.dart:174, 641`: `loadProductsFromSupabase` não limpa o `_storeCursor`; limpar na linha 641. O ganho vem do índice novo, não do cursor.
15. `tirarLinhasRepetidas` (`talao_regras.ts:147-168`) pode tirar uma unidade verdadeira num "leve 2 pague 1" (não muda totais).
16. `ferramentas/vps/lembretes_danilo.py:100-104, 195` ainda recusa textos com o nome do dono (a pista `lembretes_lane.py` ficou bem).
17. Texto: "MBWay" no diálogo (`payment_method_screen.dart:2123-2131`) e "MB WAY" nas mensagens; depois de pago aparece "Pedido criado. A aguardar confirmação de pagamento." (linha 1853); a frase do 409 contradiz-se; com MB WAY desligado (503) dizer só "escolhe outro meio".
18. Migrações: `20261115023000` confere com produção (179 tabelas `bkp_`, 20 sem proteção); tabelas novas voltam a nascer abertas. `20261115020100`: as 10 tarefas existem e estão ativas. `20261115020000` e `20261115021000` batem.
19. Pré-existente: `lib/services/auth_admin_service.dart:28-31` também aceita `user_metadata.bora_role`, que o próprio utilizador pode escrever.

## O que já foi corrigido depois desta revisão (15/11, até às 04:40)

- 1 a 6, 11 (MB WAY) e nota 17: commits `c9ff9945`, `9d3ad594`, `f60aa274`, `37246ea7`. Provado no CI (corrida 43664403934, 3589 testes).
- 7 (vigia): `229d0f7c`. 9 (CarregamentoUnico) e 14 (cursor do catálogo): `19e0444e`.
- 8 (proposta 8e): refeita com lista fechada; das regras do negócio só passam "20. GDPR" e "23. CHAT". A prova própria da proposta recusa texto sensível numa secção permitida. Prova local: 41 certos, 4 estragos apanhados.
- 10a (talão, palavras de tipo de comida): `ad491df0`.
- Nota 16 (`ferramentas/vps/lembretes_danilo.py`): deixou de deixar de fora os itens com o nome do dono e de recusar enfileirar; 7 testes novos, 5 falham com o código antigo. Na VPS copiar PRIMEIRO `lembretes_lane.py` e só depois este.
- Nota 19: visto no servidor (só leitura) que `is_admin()` e `_admin_op_guard()` só olham para `app_metadata` e que nenhuma política usa `user_metadata`; o risco fica na casca do painel. Achado à parte: `log_admin_action` está aberta a qualquer conta com sessão (`e2e_log` 9013).
- Por fazer: 10b (o painel mostrar o motivo do talão), 12 (botão de sair no "Acesso negado"), o 2.º teste do catálogo (11) e as notas 13, 15 e 18.

## O que o revisor correu

`deno test` do talão: 14 certos. `python -m unittest` em `ferramentas/vps`: 4 certos; `test_lembretes_lane`: 6 certos (em `ferramentas/assistente-negocio` há 2 falhas em `test_restaurante.py`, que esta missão não tocou). Provas PGlite: 3d 37, 3h 38, 3f 39, 3g 33, 8e 26, todas sem falhas. 9 leituras só-SELECT em produção.

## O que não foi verificado

Compilação e execução dos testes Dart; tipos do `ocr-receipt/index.ts`; quanto tempo o pedido fica válido na app MB WAY depois dos 120 s; se o vale do check-in e o saldo da carteira do primeiro pedido são libertados a tempo da segunda tentativa.
