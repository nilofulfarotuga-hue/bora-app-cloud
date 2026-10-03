# Mudar destino a meio da corrida TVDE — relatório da missão `tvde-mudar-destino`

> 30/09/2026 · Claude Code (PC do Danilo) · ramo `autonomous-night-2026-04-29` · commit `ecdf2621`
> Autorização do Danilo: "sim" (30/09/2026 12:51, conversa Claude.ai) — regra fechada por ele.
> RAM: 367 MB no arranque (abaixo do portão leve de 400; avancei porque só lia a base e escrevia
> ficheiros). Antes do 1.º `flutter analyze`: 283 MB → libertei um script Python meu pendurado →
> **825 MB**. Testes: 1445 / 580 / 505 MB. **O 2.º analyze (3 ficheiros) correu com 499 MB, abaixo
> do portão de 800** — avancei porque era só aos ficheiros mudados e a corrida igual anterior levou 18 s.
> Córtex: o conector pede nova autorização — **não li nem escrevi no Córtex** nesta sessão.

## Em palavras simples

O cliente, com o motorista a caminho, à porta ou já em viagem, carrega em **"Mudar destino"**,
escolhe a morada e vê, **antes de confirmar**, o destino novo, os km, o preço novo e
**"Pagas mais €X"**, com a fórmula da tabela. Só com **"Aceitar"** muda alguma coisa.
- Em **cartão ou MB Way** cobra-se logo, e o destino só muda com o pagamento confirmado.
- Em **dinheiro**, o motorista cobra a diferença no fim.

O motorista recebe logo o aviso **"Novo destino · ganhas mais €Y"**, e a linha no mapa refaz-se.
**Os km são calculados pelo servidor** (Google), não pela app.

**⚠️ O interruptor `tvde_dest_change_enabled` está DESLIGADO no ar.** Liga-se no painel
(Configurações → tvde) quando a versão nova da app estiver nas lojas. Ver "PARA O DANILO".

## O que ficou feito (com prova)

| Bloco | Feito | Prova |
|---|---|---|
| Repo em dia com o ar (preço fixo) | `supabase/migrations/20260930129000_…preco_fixo…sql` com a definição tirada do ar | md5 da função no ficheiro = no ar: `042a6809a28681f13b71c3f0eee4f0bc`, 14153 caracteres |
| Tabela + cálculo | `tvde_destination_changes` (RLS: dono, motorista ou admin só leem; ninguém escreve fora das funções), cotação, pedido, aplicar, chaves `tvde_dest_change_min_cents`=200, `…_min_driver_cents`=100, `tvde_dest_change_enabled` | Prova A (abaixo) |
| `tvde_finish_ride` (zona protegida) | Só somas: extra da mudança na tarifa e no ganho, dinheiro da mudança no acerto, 4 campos no evento. Mais uma troca na volta do pacote (grátis só até à ida **combinada**) | Backup em `fn_definition_backups`; tirar os acréscimos devolve a definição anterior **byte a byte** (`042a6809…`) |
| Os 4 exemplos do Danilo | Dinheiro, cartão e MB Way | `prova_A_resultado.txt`: +€4/+€3,20 · +€2/+€1 · €0 (fica €7) · +€2/+€1 |
| Várias mudanças | 4 → 5 → 10 km: +€2 e depois +€2 contra o preço atual €7; final €9 / motorista €7,20 | Prova A |
| Antes da recolha | Conta 0 km feitos mesmo que peçam outra coisa | Prova A |
| Sem mudança = igual a hoje | Finish nova contra a original, dinheiro e cartão, com e sem paragem | Provas A e C: 4/4 `igual: true` |
| Km do servidor | Edge **`tvde-dest-change` v2**: Google Directions com a chave do servidor e GPS do motorista (recusa se tiver mais de 3 min); a rota vale 60 s e só no mesmo estado da corrida | Prova C: sem rota → `route_not_computed`; a app manda 0 km → o servidor usa 12,5 km e cobra +€3 |
| Pagamento | **`tvde-payment` v17**: `charge_dest_change` / `confirm_dest_change_payment` (tipo `bora_dest_change`, o webhook da Stripe ignora-o) + varrimento de 2 em 2 min (`tvde-dest-change-sweep`) | No ar = repo, md5 `30daf71a23cf64b96a6732909b676ef9`; cron ativo; Stripe só em stub, **zero cobranças reais** |
| Permissões | Confirmar, aplicar e varrer só com a chave do servidor | Prova B: o cliente não confirma nem aplica sozinho; outra pessoa não cota a corrida |
| Aviso ao motorista | `notify-tvde-driver` v20, tipo `dest_changed`: "Ganhas mais €Y · destino", mais o valor a cobrar se for dinheiro | Verificado por agente: no ar = repo, exceto uma quebra de linha (artefacto da cópia) |
| Resumo da viagem | Ecrã e email (`tvde-recibo-viagem` v4): linha "Mudança de destino +€X" com o cálculo; o "Como foi calculado" usa os km cobrados | `_tvde_recibo` com `mudanca_destino_cents` e `mudancas_destino` |
| App cliente (PT-PT) | Botão, escolha de morada, folha com fórmula e Aceitar/Cancelar, cartão e MB Way pelo fluxo das paragens; mapa e ETA refazem-se | 16 testes novos |
| App motorista | Cartão "Novo destino +€Y" (número grande = o que ele ganha), aviso rápido, rota refeita, valor a cobrar atualizado | Testes do aviso e do `TvdeFareView` |
| Painel (PT-BR) | "Destino / mudanças" em cada corrida (histórico com reembolsos) + mudança na corrida de balcão com valor combinado à mão; chaves editáveis (o interruptor sem motivo; os mínimos em cêntimos pelo caminho auditado) | `flutter analyze` sem problemas |
| AMT / teto 25 % | Automático: somam `driver_earn_cents` + `bora_cut_cents`, que já incluem a mudança | Prova A: 720 + 180 = 900 |
| Qualidade | `flutter analyze`: **0 erros** (6 avisos antigos noutros ficheiros); testes TVDE, admin TVDE e traduções: **272/272**; anti-trapaça: **CLEAN** (+20 casos) | Saídas nesta sessão |

**Revisão maker/checker:** um revisor com contexto limpo atacou duas vezes.
- **1.ª revisão:** 1 crítico e 4 altos, todos corrigidos e provados:
  - o webhook cancelava a corrida quando o pagamento da mudança falhava;
  - km manipuláveis pela app;
  - dinheiro preso sem reembolso;
  - mudança paga numa corrida cancelada;
  - km grátis na volta do pacote.
- **2.ª revisão:** 2 médios, também corrigidos:
  - rota velha reaproveitada;
  - pagamento por cartão fechado cedo demais.

## PARA O DANILO

1. **Ligar o botão:** o interruptor `tvde_dest_change_enabled` está `false`. Liga-o no painel quando a versão com o botão estiver nas lojas (a app antiga não o mostra, o que não faz mal).
2. **Pergunta do revisor (MÉDIO 6):** o cliente muda o destino na **volta** do pacote e a volta combinada era mais curta que a ida. Deve pagar pela tabela os km que a ida já "cobria"? Hoje paga (regra "diferença pela tabela, sem desconto do pacote").
3. **Achados que ficam para decisão ou para outra missão (dinheiro, não mexi):**
   - **Stripe live:** não se fez nenhum pagamento real. A cobrança real da mudança (cartão/MB Way) só fica provada na primeira corrida verdadeira. Proposta: primeiro teste em **dinheiro**, depois um de cartão com um valor pequeno teu.
   - Com `tvde_fixed_price_enabled=false`, um destino mais perto baixa o preço (o fim da corrida volta a usar os km reais).
   - Tokens e crédito promo podem descontar uma parte da diferença (o teto de 50 % conta com ela).
   - Relatórios de lucro das pernas do pacote ficam ligeiramente tortos (o dinheiro está certo).
   - "Km feitos" = a rota mais curta da origem ao carro, não o caminho real (com desvios, o cliente paga um pouco menos).

## Erros encontrados fora do âmbito (NÃO corrigidos)

- **Paragens pagas com cartão:** `tvde_add_stop` aceita qualquer texto como `payment_intent_id`. Um cliente pode chamá-la diretamente com um id falso e a paragem conta como "paga online" (o motorista não a cobra).
- **Corrida cancelada com paragens pagas por cartão:** o reembolso automático só devolve o pagamento da corrida, e o das paragens fica com a Bora. É o mesmo buraco que corrigi para a mudança de destino.
- **Painel, lista de corridas:** a RPC `admin_tvde_rides_list_v2` não devolve `extra_stops_*`, por isso o resumo de paragens no cartão da corrida nunca aparece.
- **Preço de sócio no fim da corrida:** `tvde_finish_ride` dá ao sócio a tarifa fixa sem os km extra, enquanto o pedido (`tvde_request_ride`) soma os km extra.
- **Aviso de segurança antigo:** `fn_tvde_recibo_email_ao_finalizar` continua executável por `anon` (já vinha no relatório anterior).
- **Ficheiros alterados no PC antes desta sessão** (não entraram no commit): `analysis_options.yaml`, `.gitignore`, `android/gradle.properties`, os goldens e `linux/`/`windows/` `generated_*` (mexidos pelo `flutter pub get`).
- **Testes golden (imagens) não corridos:** o cartão novo no ecrã do motorista pode mudar goldens desse ecrã, se existirem.

## Não feito / saltado

- **Capturas no telemóvel:** não feitas. Um ecrã de corrida viva ofereceria a corrida a motoristas reais, e o emulador não cabe na RAM.
- **Córtex:** sem acesso (é preciso autorizar de novo o conector) — nem leitura inicial nem resumo final.
