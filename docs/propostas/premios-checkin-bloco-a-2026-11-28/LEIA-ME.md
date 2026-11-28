# Prémios do check-in — Bloco A no servidor · PROPOSTA

⚠️ **ISTO MEXE EM DINHEIRO.** Pronto e provado num Postgres local; **nada aplicado em produção** por esta
sessão. Quem aplica é a Claude.ai, por MCP. Autorização do Danilo: 26/11/2026 13:00 (caso Divan: o prémio
de 2 h de limpeza não foi descontado). Missão: página do livro `prompt-premios-checkin-2026-11-26`.

Fica em `docs/propostas/` (e não em `supabase/migrations/`) por causa da bora-tranca. Depois de aplicada,
copiar para `supabase/migrations/<versão>_premios_checkin_bloco_a.sql` com a versão que o servidor der.

## O que faz (os 8 pontos)

1. `checkin_premio_cents` e `checkin_vale_id` em `cleaning_bookings` e `carwash_bookings`.
2. `p_checkin_vale_id` (opcional, último parâmetro) em `create_cleaning_booking` e `create_carwash_booking`:
   valida dono, tipo, `por_usar` e validade. O prémio vale 2 h × `cleaning_hourly_cents` (Standard: a
   Profunda e a Pós-obras pagam a diferença) ou o preço da lavagem só por fora, e nunca mais do que o total
   da 1.ª visita. O cliente paga `total − prémio`; a profissional ou o lavador ganha o mesmo de sempre; a Bora
   fica com `taxa − prémio`. O vale fica `usado` com o id da marcação. Resto 0 no cartão ou MB Way → método
   `premio` (pago, a profissional é chamada); resto de 1 a 49 cêntimos no cartão ou MB Way → recusado
   (`checkin_premio_resto_so_dinheiro`).
3. `client_checkin_premio_marcar_limpeza/lavagem` (as assinaturas ficam iguais) passam a chamar o create com
   o vale. Se sobrar resto (ex.: deslocação), a limpeza vai em dinheiro: este caminho não tem passo de pagamento.
4. O vale volta ao cancelar com **qualquer** meio de pagamento (`payment_method = 'premio' OR checkin_vale_id IS NOT NULL`).
5. Série: a limpeza seguinte de uma série paga pelo prémio nasce em dinheiro, ao preço da série. Sem isto o
   gerador partia na guarda do `premio`.
6. Guarda de escrita direta: os campos do prémio, e o dinheiro de uma marcação com prémio, só mudam pelas
   funções do servidor.
7. `client_checkin_premio_servico_para_usar('limpeza'|'lavagem')` → `{vale_id, horas, valor_cents, valido_ate, titulo}`
   ou null, para o banner da app.
8. Reserva do Divan `ffa77ebf`: passa para `checkin_premio_cents = 2400` + `checkin_vale_id = 05053050-…`,
   com `recurring_discount_cents = 0` e **sem mudar valores** (24 € / 40,80 € / −16,80 €). Antes faz o backup
   em `bkp_cleaning_bookings_divan_20261128`. Só corre se a reserva ainda não estiver feita nem paga e se o
   vale estiver ligado a ela; se não, escreve um NOTICE e não faz nada.

As funções saem do texto mais recente do repo, já com o #60 e o telemóvel obrigatório: `create_cleaning_booking`
de `20261119200000` (equipa) e `create_carwash_booking` de `20260827103000`. As mudanças estão escritas por um
gerador com substituições conferidas uma a uma. A assinatura velha (17 parâmetros) larga-se com
`DROP … IF EXISTS`, como em 19/11, para não ficarem duas versões ambíguas. A app antiga continua a funcionar.
As funções internas ficam fechadas a PUBLIC, anon e authenticated; as da app ficam abertas a authenticated e fechadas a anon.

## Provas (28/11/2026, Postgres 16 local com as migrações do repo e os privilégios por defeito do Supabase)

- `migracao.sql` aplica sem erros, e uma segunda vez também (idempotente).
- `provas.sql` dá **13/13 PROVA_OK**:
  - caso Divan: 24 € cliente, 40,80 € profissional, −16,80 € Bora, vale usado a 24 € e com custo de 20,40 €;
  - outros casos: um vale = um uso, cancelar devolve o vale, Profunda paga 9,60 € de 33,60 €, 2 h no cartão pagas pelo prémio, resto abaixo de 50 cêntimos só em dinheiro, lavagem (por fora → 0 €; completa → 8 €), "Os meus prémios › Usar", série seguinte em dinheiro (21,60 €, com o desconto semanal de sempre), vale de outro cliente e expirado recusados, banner, guarda e permissões, migração do Divan sem mudar valores.
- À parte: com UPDATE dado a authenticated, a escrita direta em `checkin_premio_cents` é recusada pela guarda
  (`checkin_premio_marcacao_so_pelo_servidor`).
- O ensaio local simula 4 peças que as migrações do repo não criam aqui: `public.users`, `client_addresses`, `restaurants`
  (para `_checkin_vale_json`) e `_alerta_quem`/`tem_aparelho`.

## Depois (app, painel, robô)

App: "Usar o meu prémio" no resumo da limpeza e da lavagem (`p_checkin_vale_id`), a linha "Prémio do check-in −24,00 €"
e o tracking. Painel: o prémio em cada marcação. Robô do suporte: como se usa. Testes. Fica para a fase seguinte, como pedido.
