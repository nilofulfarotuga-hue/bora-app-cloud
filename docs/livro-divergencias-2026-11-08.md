# Livro — contradições encontradas e o que vale agora (missão M7, 08/11/2026)

Fiz isto: li o livro (tabela `public.claude_ai_memoria`, 585 páginas) nas páginas de regras, Stripe, check-in, TVDE, Mercadona, tokens e reservas, as cópias da memória da Claude.ai e os digests de novembro. Também li o `CLAUDE.md` (seção 10), o `docs/contexto/03-regras-de-negocio.md` e os agentes em `.claude/agents/`. Conferi no banco o que está valendo (`platform_settings`, `restaurants`, `orders`, `tvde_rides`, `users`).

Regra usada: vale a ordem mais recente do Danilo, com data. Nada foi apagado nem reescrito: só acrescentei linhas "SUPERADO em ..." no fim das páginas que não são cópia da Claude.ai. Não mexi em `erros-aprendidos` nem em `regras-do-danilo`. Não fiz commit nem push.

Resultado: 14 contradições. Acrescentei 15 linhas em 9 páginas (lidas de volta depois de gravar, cada uma aparece uma vez só).

Páginas onde acrescentei linha: `regras-checkin-v2-2026-10-30`, `adendo-9-checkin-escada-premios-2026-10-29`, `meta-anuncios-2026-10-30-textos`, `tokens-metade-do-saldo-2026-10-14`, `digest-2026-10-05-dinheiro-bloco-a-aplicado`, `livro-hermes-soul-detalhe` (2 linhas), `digest-2026-11-01-fechar-tudo-claude-ai`, `stripe-duas-contas`, `livro-claude-md-detalhe` (6 linhas).

Páginas que não editei porque são geradas sozinhas: `livro-indice` e `livro-resumo`. Elas copiam a `regras-do-danilo` e a `erros-aprendidos`, então se corrigem quando essas duas forem corrigidas.

---

## 1. Qual conta da Stripe usar

- **Página A** — `livro-areas-stripe-connect` (cópia da Claude.ai, nota antiga): "Conta Stripe da plataforma: acct_1T8MFaGlT3R2jCYp". O `CLAUDE.md` seção 10 (15/10) e a `livro-claude-md-detalhe` (arquivo de 23/10) dizem: "A Stripe está no nome dele: não mexer."
- **Página B** — `stripe-duas-contas` (01/11 a 03/11): a conta da EMPRESA `acct_1UX67LGWwQxC9wR2` serve para todas as categorias. A PESSOAL `acct_1T8MFaGlT3R2jCYp` ficou só para o Bora Motorista. O interruptor passou para "empresa" em 02/11.
- **Prova no banco**: `stripe_conta_nao_tvde = "empresa"`. Entre 04/11 e 08/11, todos os 8 pedidos pagos com cartão ou MB Way caíram na conta da empresa. Só 1 caiu na pessoal, no dia 03/11.
- **O que vale**: a Stripe da empresa para tudo. A pessoal era só do TVDE, que fechou em 04/11.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`. Ficou pendente para a Claude.ai (cópia `livro-areas-stripe-connect`) e para o repositório (`CLAUDE.md`, seção 10).

## 2. Quem paga a taxa da Stripe nas lojas parceiras

- **Página A** — `livro-areas-stripe-connect` (cópia, nota antiga sem data): "Quer que a TAXA de transferência/Stripe seja cobrada ao PARCEIRO e ao ESTAFETA".
- **Página B** — `livro-areas-stripe-connect-parte3` (14/09): a Goola não paga taxa nenhuma, e o Gilberto (Ouro e Prata) paga só a taxa de transferência. A `decisao-precos-iva-parceiros-2026-10-28` (28/10) diz: "a loja não paga nada e recebe o preço de balcão". A `analise-fiscal-bora-2026-11-03` diz: "a taxa da Stripe é gasto da Bora". Nas barbearias, o barbeiro recebe o valor do serviço menos a taxa da Stripe (regra de 14/09).
- **O que vale**: nos restaurantes parceiros (Boom, Goola, Sabores), a loja não paga nada e a taxa da Stripe é custo da Bora. Nas barbearias, a taxa sai do valor do barbeiro.
- **O que fiz**: ficou pendente para a Claude.ai marcar a linha antiga como superada. Pendente também para o Danilo (ver a lista de decisões no fim): quem paga as taxas do repasse Connect da empresa.

## 3. Ouro e Prata (Gilberto) como "próximo parceiro"

- **Página A** — `livro-areas-stripe-connect` (cópia): "PRÓXIMO PASSO REAL: cadastrar o 1º parceiro de verdade (Gilberto da ouro-e-prata)". A descrição da página também diz "Goola e Ouro e Prata por preencher".
- **Página B** — `regras-do-danilo`, seção 8: "Ouro e Prata está FORA (não promover)". A `erros-aprendidos` de 22/10 diz o mesmo. Em 04/11 o Connect da empresa foi pensado só para a Boom, a Goola e a Sabores (`livro-areas-stripe-connect-parte3`).
- **O que vale**: a Ouro e Prata está fora.
- **O que fiz**: pendente para a Claude.ai.

## 4. Bora Motorista (TVDE) fechado

- **Página A** — vários lugares:
  - `digest-2026-11-01-fechar-tudo-claude-ai` (01/11): "TVDE FECHA a 02/11 06:00 ... e depois vai apagar tudo do TVDE".
  - `erros-aprendidos`, linha de 02/11: "DESLIGADO desde 02/11/2026 06:00 (tvde_passageiros_enabled=false)".
  - `stripe-duas-contas` (03/11): "TVDE continua na conta pessoal".
  - `docs/contexto/03-regras-de-negocio.md`: "Estado atual: ABERTO pra todos".
  - `CLAUDE.md`, seção 10: regras do TVDE (fila inteligente) como se ainda estivessem valendo.
  - Cópias `livro-areas-tvde-*` (vertical, historico, reserva-agendada): não falam do fecho.
- **Página B** — `digest-2026-11-04-fechar-bora-motorista` (04/11): fechado com o interruptor `tvde_app_visivel`, nenhum código apagado, reabre pelo painel. A cópia `livro-areas-tvde-operador-proprio` (04/11) diz: "fechado de vez até haver licença".
- **Prova no banco**: `tvde_app_visivel = false` (04/11). Nenhum usuário com `tvde_access`. A tabela `tvde_rides` tem 339 corridas, intactas. A última corrida foi em 02/11 às 18:30, ou seja, o fecho de 02/11 06:00 não segurou nada. O `tvde_passageiros_enabled` já estava `false` desde 21/10 e não bloqueava.
- **O que vale**: TVDE fechado desde 04/11, sem apagar nada. Só reabre com ordem do Danilo.
- **O que fiz**: acrescentei linha em `digest-2026-11-01-fechar-tudo-claude-ai` e em `stripe-duas-contas`. A linha de 02/11 na `erros-aprendidos` ficou para o Danilo ou a Claude.ai. As cópias do TVDE ficaram para a Claude.ai. No repositório ficaram pendentes `03-regras`, `CLAUDE.md` seção 10 e o agente `estafeta-motorista`. Ver também a decisão nº 1 no fim.

## 5. Tokens do cliente

- **Página A** — o texto antigo "metade do pedido". Hoje ele só aparece registrado como erro (`erros-aprendidos` 14/10 e `livro-resumo`). A página `tokens-metade-do-saldo-2026-10-14` ainda dizia que 4 pedidos antigos tinham "possível reembolso, precisa do vai do Danilo".
- **Página B** — a regra de 14/10 e 15/10: o cliente usa no máximo METADE DO VALOR dos tokens que tem. Em 15/10 o Danilo mandou não devolver nada aos 4 clientes (`livro-areas-tokens-cliente`, `CLAUDE.md` seção 10). Em 01/11 repetiu: "decisões de dinheiro antigas: esquecer, não devolver nada a ninguém".
- **Prova no banco**: `token_balance_max_use_pct = 50` (14/10) e `token_payment_max_pct = 50`. Os dois limites valem juntos.
- **O que vale**: metade do saldo de tokens, com o teto de 50% do pedido por cima. Os 4 pedidos antigos não são reembolsados.
- **O que fiz**: acrescentei linha em `tokens-metade-do-saldo-2026-10-14`. Nenhuma página fora das cópias usa "metade do pedido" como regra atual.

## 6. Margem e pré-autorização nos não-parceiros

- **Página A** — `docs/contexto/03-regras-de-negocio.md` e `livro-claude-md-detalhe`: "Buffer MB Way ... × 1.2 — NUNCA ×1.15". A cópia `livro-areas-precos-catalogo-nao-parceiro` (08/09): "DECISÃO FINAL ... margem passa a 15% + 3% = 18%".
- **Página B** — `erros-aprendidos` e `livro-areas-precos-catalogo-nao-parceiro` (25/10): "não-parceiro cobra-se EXATAMENTE o preço da app, sem margem", e o multiplicador passou de 1.15 para 1.0. Em 11/10 ele disse: "hoje cobra 15% sobre o produto".
- **Prova no banco**: `non_partner_payment_buffer_multiplier = 1.0`. A função `quote_order_pricing` usa `COALESCE(v_markup, 0.15)`, e as 23 lojas não-parceiras têm `app_markup_pct` vazio, ou seja, ficam com 15%.
- **O que vale**: o preço na app é o balcão mais 15% já incluídos, e a pré-autorização não leva margem (×1.0). O "sem margem" de 25/10 fala da pré-autorização, não dos 15%.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`. Pendente no repositório (`03-regras`). Pendente para a Claude.ai: marcar a linha dos 18% como superada.

## 7. Taxa de serviço do não-parceiro

- **Página A** — `regras-do-danilo`, seção 8 (23/10, mexida em 31/10): "NÃO-PARCEIRO: preço base + 15% incluído, taxa €2,50 fixa". O `03-regras` diz "Fee cliente €2,50 fixo", e a `livro-claude-md-detalhe` diz o mesmo.
- **Página B** — a cópia `livro-areas-precos-catalogo-nao-parceiro`. Em 08/09, decisão dele: "taxa de serviço fixa de 0,99 € ... em vez dos 2,50 €". Em 11/10: "+ 0,99 € de serviço + 2,50 € de entrega". A `lojas-takeaway-precos` (29/10) avisa que o servidor cobra 0,99 €, mas a tela de pagamento ainda mostra 2,50 € por causa de uma constante no `pricing_service.dart`, que é zona protegida.
- **Prova no banco**: `non_partner_service_fee_cents = 99` e `non_partner_service_fee_strikethrough_cents = 250` (os 2,50 € aparecem só riscados).
- **O que vale**: 0,99 € de taxa de serviço, mais a entrega (2,50 € até 4 km). A frase da `regras-do-danilo` parece misturar a taxa de serviço com a taxa de entrega.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`. Ficou pendente corrigir a `regras-do-danilo` (Danilo ou Claude.ai) e o `03-regras` (repositório). O erro da tela já estava reportado e não mexi nele.

## 8. Ganho do estafeta no não-parceiro

- **Página A** — `regras-do-danilo`, seção 8, e `03-regras`: "€3,80 + €0,20/km + €0,80 + 30% do lucro líquido Bora".
- **Página B** — `decisao-ganho-estafeta-nao-parceiro-2026-10-29` (29/10, 17:36): os 0,80 € só entram em compras de mercado, e os 30% são calculados sem a taxa de pedido pequeno nem o saco. Palavras dele: "a matemática fica desse jeito ... do jeito que paga o Valdemir".
- **O que vale**: a conta que o sistema faz hoje (decisão de 29/10). Não mexer sem ordem nova dele.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`. Pendente corrigir a `regras-do-danilo` e o `03-regras`.

## 9. Prêmios do check-in

- **Página A**:
  - `CLAUDE.md`, seção 10 (15/10): "NÃO FAZER: ... prémios do check-in".
  - `adendo-9-checkin-escada-premios-2026-10-29` (29/10): prêmios nos dias 10, 15 e 30, um por sequência.
  - `regras-checkin-v2-2026-10-30` (30/10): "ESCADA GRANDE ... 45 dias" mais uma escada pequena mensal.
  - `meta-anuncios-2026-10-30-textos`: "aos 10, 15 e 30 dias seguidos há prémios".
- **Página B** — a cópia `livro-areas-bora-todo-dia`. Em 04/11 às 09:58 ele disse "vai" para a escada de 30 dias, que "substitui a escada de 45 dias de 30/10". Os digests `digest-2026-11-04-checkin-*` mostram como ficou: intervalo de 30 dias entre prêmios, 7 degraus de produto ligados e 6 degraus de desconto desligados.
- **Prova no banco**:
  - `checkin_rewards = [5,5,10,10,15,15,40]`.
  - `checkin_premio_intervalo_dias = 30`.
  - Prêmios ligados nos dias 8, 11, 12, 13, 14, 17, 18, 19, 20, 28 e 30; os 6 degraus de desconto estão com `ativo: false`.
  - `checkin_marco_texto` (04/11): "Levantas quando quiseres, um a cada 30 dias, e a sequência recomeça".
- **O que vale**: a escada de 30 dias. Os tokens diários continuam. Os prêmios vão do dia 8 ao dia 30, e o cliente leva no máximo um a cada 30 dias.
- **O que fiz**: acrescentei linha em `regras-checkin-v2-2026-10-30`, `adendo-9-checkin-escada-premios-2026-10-29` e `meta-anuncios-2026-10-30-textos`. Pendente no repositório (`CLAUDE.md` seção 10) e para a Claude.ai (a descrição da cópia `livro-areas-bora-todo-dia` ainda diz "10/15/30 dias").
- **Achado no servidor (só reportado, não mexi)**: `checkin_escada_texto` (29/10) ainda tem o texto antigo ("Se levantares, a sequência volta ao dia 1"). Ele não contradiz o texto novo, mas sobrou.

## 10. Reservas: como se dividem os €3

- **Página A** — o agente `.claude/agents/parceiro-servicos.md`: "pré-pagamento €3 (€0,50 Bora + €2,50 parceiro) e desconto de chegada €2". O Cérebro, em `.claude/.ai/knowledge/permanente/episodica/decisoes.md`: "€3 sinal → €0,50 Bora + €2,50 parceiro".
- **Página B** — `regras-do-danilo`, seção 8, e `03-regras`: €3 pagos antes; quando o cliente chega, €2 para o parceiro e €1 para a Bora. A `analise-fiscal-bora-2026-11-03` diz o mesmo. Na `erros-aprendidos` de 27/10: é o parceiro que decide se cobra sinal.
- **Prova no banco**: `reservation_prepayment_cents = 300`, `reservation_partner_payout_cents = 200`, `reservation_bora_service_cents = 100`. Os 0,50 € / 2,50 € vêm das marcações de barbearia, e lá o sinal acabou em 03/08 e os 0,50 € acabaram em 14/09. No banco, `appointment_deposit_bora_cut_cents = 0` e `appointment_deposit_partner_cut_cents = 0`, mas as descrições dessas chaves ainda dizem "0,50 EUR" e "2,50 EUR".
- **O que vale**: reserva de mesa custa €3, divididos em €2 para o parceiro e €1 para a Bora, só quando o parceiro liga o sinal. Marcação de serviço não tem sinal de €3, e o barbeiro recebe o valor menos a taxa da Stripe.
- **O que fiz**: pendente no repositório (o agente e o Cérebro; o Cérebro só o `bibliotecario-cerebro` pode mexer). Pendente acrescentar na `regras-do-danilo` "quando o parceiro liga o sinal".

## 11. Reembolso de cancelamento: o antigo 80/20

- **Página A**:
  - `livro-claude-md-detalhe`: "split 80% saldo livre + 20% tokens (60d)".
  - `livro-hermes-soul-detalhe`: "o split 80/20 da carteira".
  - `digest-2026-10-05-dinheiro-bloco-a-aplicado`: "fora da graça, split 80/20".
  - A cópia `livro-areas-bora-app`: "wallet (80/20 split)".
  - No repositório: o agente `pagamentos-wallet` ("split 80/20"), `.claude/.ai/knowledge/business-rules/wallet.md` §17.3, `.claude/.ai/business_rules.md` linha 1417 e a skill `refund-assistant` (na `skills-indice`).
  - O `CLAUDE.md` seção 10 (15/10) ainda diz "Reembolso ao meio original ... interruptor DESLIGADO".
- **Página B** — `regras-do-danilo`, seção 8 (regra de 29/10, confirmada em 31/10 às 06:44): o cliente escolhe. Carteira Bora devolve 100% em saldo livre; a outra opção é o estorno total pelo mesmo meio de pagamento.
- **Prova no banco**: `wallet_split_free_pct = 1.0`, desde 28/10 ("esquece esse negocio de 80% e 20%"). Não achei um interruptor de "meio original" no `platform_settings`, então isso fica para confirmar no código.
- **O que vale**: o cliente escolhe entre carteira (100%) e estorno total.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`, `livro-hermes-soul-detalhe` e `digest-2026-10-05-dinheiro-bloco-a-aplicado`. Pendente para a Claude.ai (`livro-areas-bora-app`) e no repositório.

## 12. Gorjeta

- **Página A** — `livro-hermes-soul-detalhe`: "o da gorjeta (80% estafeta / 20% Bora)".
- **Página B** — `digest-2026-10-30-gorjetas-claude-ai` (30/10, 13:40): a Bora não ganha nada com gorjeta. No carrinho e em dinheiro, a gorjeta vai inteira. Paga depois por cartão ou MB Way, vai menos a taxa exata da Stripe.
- **Prova no banco**: existe a coluna `tips.liquido_prestador_cents`.
- **O que vale**: a regra de 30/10. O `business_rules.md` §4.5 do repositório já foi corrigido (linha 288).
- **O que fiz**: acrescentei linha em `livro-hermes-soul-detalhe`.

## 13. "Toda sessão termina com o envio para o servidor" contra o modo automático seguro

- **Página A** — `regras-do-danilo`, seção 7: "Toda sessão de código acaba com o envio para o servidor (git push origin autonomous-night-2026-04-29)". A `livro-resumo` copia essa frase. O `AGENTS.md` diz "Claude Code — mãos no PC: código, Chrome, emulador, publicar".
- **Página B** — `digest-2026-11-05-modo-automatico-seguro` (05/11 e 06/11; o Danilo clicou em ATIVAR em 05/11 às 20:37 e de novo em 06/11): "nenhuma sessão do Claude Code envia para o ramo principal nem faz deploy: publica o Claude.ai". O `CLAUDE.md` global, seção 4, diz o mesmo.
- **O que vale**: o modo automático seguro. O trabalho vai para um ramo `ai/...` com pedido de revisão, e quem publica é a Claude.ai.
- **O que fiz**: pendente para o Danilo ou a Claude.ai corrigir a `regras-do-danilo` seção 7 (o próprio digest já pede isso). A `livro-resumo` se corrige sozinha depois disso. Pendente no repositório o `AGENTS.md`.

## 14. Mercadona parada

- **Página A** — `CLAUDE.md`, seção 10 (15/10): "Mercadona parada até 'vamos reabrir a loja'". A `livro-claude-md-detalhe` diz o mesmo.
- **Página B** — `digest-2026-11-01-mercadona-reaberta` (01/11): a loja abriu como "Mercadona · Beleza e Higiene", com 543 produtos fotografados.
- **O que vale**: reaberta só com beleza e higiene. Os outros produtos ficam escondidos, sem apagar.
- **O que fiz**: acrescentei linha em `livro-claude-md-detalhe`. Pendente no repositório (`CLAUDE.md` seção 10). A página `mercadona-reabrir-loja` e a cópia da Claude.ai já têm a parte de 01/11.

---

## Correções para a Claude.ai fazer na memória dela

1. `livro-areas-stripe-connect`:
   - Marcar como superada a "Conta Stripe da plataforma: acct_1T8MFaGlT3R2jCYp". Desde 01/11 e 02/11 tudo vai para a empresa `acct_1UX67LGWwQxC9wR2`.
   - Marcar como superada a frase "taxa cobrada ao PARCEIRO e ao ESTAFETA". Agora é regra por loja: os restaurantes parceiros não pagam nada (28/10).
   - Marcar como superado o "PRÓXIMO PASSO REAL: Gilberto". A Ouro e Prata está fora desde 22/10, e o Connect da empresa de 04/11 é para Boom, Goola e Sabores.
   - Atualizar a descrição da página ("Goola e Ouro e Prata por preencher").
2. `livro-areas-precos-catalogo-nao-parceiro`: marcar a "DECISÃO FINAL 15% + 3% = 18%" de 08/09 como superada pela de 11/10. O servidor usa 15%.
3. `livro-areas-bora-app`: trocar "wallet (80/20 split)" pela escolha do cliente (carteira 100% ou estorno total).
4. Cópias do TVDE (`livro-areas-tvde-vertical` e as partes 2 a 4, `livro-areas-tvde-historico`, `livro-areas-tvde-reserva-agendada` e as outras `livro-areas-tvde-*`): pôr no topo que o Bora Motorista está fechado desde 04/11 (`tvde_app_visivel = false`, ninguém com `tvde_access`) até haver licença. A `tvde-historico` ainda diz "abrir a TODOS".
5. `livro-areas-bora-todo-dia`: a descrição diz "marcos com prémios (10/15/30 dias)". Hoje é a escada de 30 dias, com prêmios do dia 8 ao 30.
6. `regras-do-danilo` (página da Claude.ai, eu não mexi):
   - Seção 7: trocar "Toda sessão de código acaba com o envio" pelo modo automático seguro de 05/11.
   - Seção 8, não-parceiro: a taxa de serviço é 0,99 €, não 2,50 €.
   - Seção 8, ganho do estafeta no não-parceiro: a conta de 29/10 (0,80 € só em mercado; 30% sem a taxa de pedido pequeno nem o saco).
   - Seção 8, reservas: "€3 quando o parceiro liga o sinal".
   - Seção 2: o TVDE está fechado.
7. `erros-aprendidos`, linha de 02/11 ("TVDE ... DESLIGADO desde 02/11/2026 06:00 (tvde_passageiros_enabled=false)"): está errada. Houve corridas até 02/11 às 18:30, e o fecho real foi em 04/11, por `tvde_app_visivel` e `users.tvde_access`. A linha de 04/11 já conta isso em parte. Sugiro acrescentar uma linha nova no fim, sem apagar a antiga.

## Correções no repositório (fora do livro, não feitas nesta missão)

- `CLAUDE.md`, seção 10:
  - "NÃO FAZER: prémios do check-in": superado pela escada de 30 dias de 04/11.
  - "NÃO FAZER: preços dos mercados": em 23/10 ele mandou igualar preços ao Glovo, só para cima. Isso está na cópia da Claude.ai; não conferi no banco.
  - "A Stripe está no nome dele: não mexer": superado pelas duas contas.
  - "Mercadona parada": reabriu em 01/11.
  - "TVDE: fila inteligente": o TVDE está fechado.
  - "Reembolso ao meio original ... DESLIGADO": vale a escolha do cliente.
- `docs/contexto/03-regras-de-negocio.md`: fee de €2,50 (o certo é 0,99 €); ganho do estafeta (vale a conta de 29/10); buffer ×1.2 (o certo é 1.0); "TVDE ABERTO pra todos" (está fechado).
- `AGENTS.md`: "Claude Code ... publicar". Com o modo automático, quem publica é a Claude.ai.
- `.claude/agents/parceiro-servicos.md`: €0,50 + €2,50. O certo é €2 parceiro + €1 Bora nas reservas, e sem sinal nas marcações.
- `.claude/agents/pagamentos-wallet.md`: "split 80/20".
- `.claude/agents/estafeta-motorista.md`: trata o TVDE como uma vertical ativa.
- Cérebro, que só o agente `bibliotecario-cerebro` pode mexer: `.claude/.ai/knowledge/business-rules/wallet.md` §17.3 (80/20), `.claude/.ai/knowledge/permanente/episodica/decisoes.md` (€0,50 + €2,50) e `.claude/.ai/business_rules.md` linha 1417 (80/20).
- Skill `refund-assistant`: a descrição fala em "split wallet 80% / tokens 20%".
- Servidor (só reportado): as descrições de `appointment_booking_fee_cents` e de `appointment_deposit_*_cut_cents` ainda dizem 0,50 € e 2,50 €, mas os valores estão em 0. O `checkin_escada_texto` tem o texto de 29/10.

## Decisões que só o Danilo pode dar

1. **TVDE: apagar ou só deixar fechado?** Em 01/11 ele disse "depois vai apagar tudo do TVDE". Em 04/11 disse "fechado de vez até haver licença", e a missão guardou tudo para poder reabrir. Hoje está fechado e nada foi apagado. Apagar dados de produção precisa de ordem explícita dele.
2. **Quem paga as taxas do repasse automático (Connect) das lojas parceiras.** Numa nota antiga sem data ele queria a taxa da Stripe cobrada ao parceiro e ao estafeta. Em 28/10 decidiu que "a loja não paga nada e recebe o preço de balcão". Em 04/11 mandou ligar o repasse automático na Stripe da empresa para Boom, Goola e Sabores. Falta ele confirmar que a Bora também assume as taxas do repasse Connect.
