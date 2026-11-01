# Revisão de código — Casa & Manutenção · Peso ao quilo · Compra sem conta · Online sem aprovação · Série de limpeza

> Revisão SÓ DE LEITURA feita a 2026-11-01 (sessão Claude Code na nuvem, Fable 5.1) sobre o repo
> `bora-app-cloud` (ramo com o commit `38f0f2c`) e o Supabase `ojykpzwqrtusfeakzrna` (só SELECT,
> `pg_get_functiondef`, `cron.job`, `platform_settings`, logs). Nada foi alterado.
> Ordens do Danilo (01/11/2026): itens 14 (Casa), 15 (peso ao quilo), 39 (Finalizar do
> convidado), 12 (estafeta não aprovado online, lado da app) e 13 (série de limpeza, lado da app).
>
> Cada achado tem ficheiro:linhas, gravidade (ALTA / MÉDIA / BAIXA) e a correção proposta.
> Este ficheiro alimenta a missão do Claude Code no PC do Danilo (corrigir → `flutter analyze`
> → `flutter test` → publicar nas 3 plataformas). ⚠️ Os achados marcados **DINHEIRO** mexem em
> regra de preço/limite: preparar e pedir o "autorizo" com data antes de aplicar.

## Resumo em números

| Área | Achados | ALTA | MÉDIA | BAIXA |
|---|---|---|---|---|
| 1. Casa & Manutenção | 15 | 5 | 7 | 3 |
| 2. Peso ao quilo | 7 | 0 | 4 | 3 |
| 3. Compra sem conta (Finalizar) | 4 | 1 | 2 | 1 |
| 4. Estafeta não aprovado online | 4 | 1 | 2 | 1 |
| 5. Série de limpeza (app) | 4 | 0 | 3 | 1 |
| **Total** | **34** | **7** | **18** | **9** |

Estado real no servidor (01/11 ~20:00 UTC), verificado por SELECT:
- `casa_enabled=false`, `casa_testadores=[]`, `casa_valores_autorizados.autorizado=false`,
  `max_cash_amount_cents=4000`, `casa_bora_pct=15`, todas as 20 definições `casa_*` presentes.
- 86 funções `casa_*`/`_casa_*`/`admin_casa_*` aplicadas (partes 01–05). Crons `casa_tick` (cada
  minuto) e `casa_acertos_semanais` (segunda 04:20) ativos.
- `casa_profissionais` = 0 linhas, `casa_pedidos` = 0, `casa_ofertas` = 0 (nunca foi testado em
  produção).
- Edge Functions: `notify-handyman` **NÃO está publicada** (não aparece em `list_edge_functions`);
  `sessao-convidado` **NÃO está publicada**; `cobrar-diferenca-peso` está (v1).
- `weight_adjust_enabled=true`, `weight_adjust_card_charge_enabled=false`, `weight_adjust_max_pct=0.3`;
  `order_weight_adjustments` = 0 linhas (nenhum ajuste real ainda).
- `visitantes_sem_conta=true`, `sessao_convidado_ativa=false`.
- Produtos ao quilo marcados: Auchan 705, Intermarché 222, Continente 204, Pingo Doce 54, Lidl 0,
  Mercadona 0. Peças ao quilo (`preco_kg`): Auchan 16, Intermarché 16, Continente 0.

---

## 1. CASA & MANUTENÇÃO (categoria `handyman`)

### O que está bem (não mexer)
- Servidor: modelo "tudo por função SECURITY DEFINER, escrita direta revogada" está coerente
  (`casa_01` §7, linhas 401–485). Estados, rotação de ofertas com 2 voltas, convites a orçar,
  extras, chat com `pode_contactar`, cancelamento por escalões, confirmação automática às 24 h,
  lembretes 24 h/2 h, alerta de preso, caducidade de documentos — tudo existe e está ligado ao
  `casa_tick` (molde da Limpeza cumprido, regra 1.15).
- App: `casa_models.dart` espelha o CHECK dos estados; `CasaStore`/`HandymanStore` nunca
  rebentam a ler; wizard rola até ao campo em falta (regra 1.2); idempotência por chave; fotos
  depois do pedido sem travar o pedido; "1 laranja por ecrã": os ecrãs da Casa têm **0** laranja
  dominante (verde como primário) — aceitável.
- Painel: `admin_casa_*` cobre ver/editar/banir/configurar/exportar/auditar (todas as RPC do
  `casa_05` têm chamador, salvo `admin_casa_ofertas`), em PT-BR, com tradução dos erros
  `conformidade_incompleta`/`atividade_por_aprovar`/`documento_em_falta`
  (`lib/screens/admin/admin_casa_comum.dart:512–519`). Entrada no menu em
  `admin_menu_registry.dart:885–891`.
- Testes já existentes: `test/casa_cliente_regras_test.dart` (regras puras, 50+ casos),
  `test/casa_cliente_ecras_test.dart`, `test/casa_profissional_ecras_test.dart`,
  `test/casa_profissional_store_test.dart`, `test/admin_casa_painel_test.dart`,
  `test/casa_integracao_{destinos,documentos,ligacoes,papeis}_test.dart`.

### Achados

**C1 — ALTA — A candidatura do profissional falha no passo "dados legais": o servidor recusa o papel `handyman`.**
- App: `lib/screens/handyman/handyman_apply_screen.dart:268–279` chama `_legal.save('handyman')`
  → `lib/services/legal_fields_service.dart:34–43` (roles inclui `'handyman'`) → RPC
  `provider_update_legal_fields(p_role:'handyman')`.
- Servidor (produção, `pg_get_functiondef`): `IF p_role NOT IN ('driver','partner','cleaner',
  'washer','provider') THEN RAISE EXCEPTION 'invalid_role'` — não tem ramo para
  `casa_profissionais`. Fonte no repo: `supabase/migrations/20260923131328_ronda_d3_conformidade_prestadores.sql:136`.
- Efeito: a candidatura grava (a RPC `casa_candidatura` corre antes), mas o Danilo vê sempre o
  aviso "toca em Enviar candidatura para gravar os dados fiscais" e o IBAN, data de nascimento e
  autocertificação **nunca chegam** a `casa_profissionais`.
- Correção: migração nova que acrescenta o ramo `ELSIF p_role = 'handyman' THEN UPDATE
  public.casa_profissionais c SET legal_name/nif/address/iban/birth_date/dsa_self_certified_at/
  dsa_self_cert_version ... WHERE c.user_id = v_uid RETURNING to_jsonb(c)` e mete `'handyman'` na
  lista do `IF`. Teste: `flutter test test/casa_integracao_documentos_test.dart` + prova por
  SELECT em `casa_profissionais` depois de uma candidatura real.

**C2 — ALTA — Aprovar o profissional no painel vai rebentar com `conformidade_incompleta` e/ou `atividade_por_aprovar`.**
- `supabase/migrations/20261031060526_casa_01_papel_e_tabelas.sql:170–174` liga a
  `casa_profissionais` os gatilhos `fn_atividade_antes_de_ativar` e `fn_conformidade_antes_de_ativar`.
- Em produção `conformidade_ativacao_obrigatoria=true` e `provider_atividade_obrigatoria=true`
  (corte 2026-10-21 09:02). O gatilho de conformidade exige nome, NIF de 9 dígitos, morada,
  IBAN `PT`+23, data de nascimento (salvo NIF a começar por 5/6/7/9) e autocertificação — que por
  C1 nunca ficam gravados. O gatilho de atividade exige `provider_atividade.atividade_status =
  'aprovada'` para linhas criadas depois do corte (toda a `casa_profissionais` é nova).
- Estado do Danilo (nilofulfaro@gmail.com, `503a2e09-…`): `atividade_status='por_enviar'`;
  `drivers` dele sem IBAN/data de nascimento/autocertificação.
- Correção (sem mexer em dinheiro): (a) C1; (b) o Danilo envia o comprovativo de atividade pela
  app (`ComprovativoAtividadeScreen`) e o painel aprova-o em "Comprovativo de atividade"
  (`admin_provider_atividade_decidir`); (c) só depois `admin_casa_decidir_profissional(p_id,
  'aprovar')`. Alternativa de emergência só por ordem dele: `provider_atividade_obrigatoria=false`
  / `conformidade_ativacao_obrigatoria=false` (afeta TODOS os prestadores — não recomendo).

**C3 — ALTA — O comprovativo de atividade não conhece a Casa (quem só é profissional da Casa não consegue enviar).**
- Produção: `_provider_atividade_papeis`, `_provider_atividade_nif_conhecido`,
  `_provider_atividade_ultima_candidatura` só leem `drivers/cleaners/washers/service_providers`
  (fonte: `supabase/migrations/20261020193036_c_provider_atividade.sql:121–143`).
  `provider_atividade_enviar` levanta `nao_e_prestador` e `provider_atividade_get` devolve
  `e_prestador=false` para uma conta só-handyman.
- Para o Danilo não bloqueia (é estafeta), mas o ecrã depois da candidatura
  (`handyman_apply_screen.dart:273`) mostra "não és prestador" a qualquer outro candidato e o
  gatilho C2 nunca deixa aprovar.
- Correção: migração que acrescenta `UNION ALL SELECT 'casa' FROM casa_profissionais c WHERE
  c.user_id = p_uid AND c.approval_status <> 'rejected'` às três funções, e `casa_profissionais`
  na lista de `admin_conformidade_legal` (hoje só driver/partner/cleaner/washer/provider).

**C4 — ALTA — Edge `notify-handyman` não está publicada: nenhum push da Casa chega a ninguém.**
- `supabase/functions/notify-handyman/index.ts:14–16` diz "NÃO publicado"; `list_edge_functions`
  confirma. `_casa_notificar` (`casa_02b_funcoes_base.sql:60–65`) faz `net.http_post` para
  `/functions/v1/notify-handyman` → 404 silencioso (fica só o aviso in-app via
  `_push_in_app_notification`).
- Agrava com C5. Correção: `supabase functions deploy notify-handyman` (verify_jwt=true, como
  `notify-washer`), e provar com `select * from notification_failures where source like
  '_casa_notificar%'` vazio + um push real a chegar ao emulador.

**C5 — ALTA — O tempo real do profissional não vê a oferta (RLS) — fica só a sondagem de 30 s.**
- `lib/stores/handyman_store.dart:649–665`: canal `casa_pedidos` "sem filtro: a RLS já limita".
  Mas a política `casa_pedidos_participantes` (`casa_01:431–434`) só deixa ver `client_user_id` ou
  `profissional_id` — a oferta vive em `offer_profissional_id` com `profissional_id` NULL, por isso
  o evento UPDATE da oferta **não passa** pelo realtime. Quem salva é o `Timer.periodic(30 s)`
  (`handyman_store.dart:661–664`) → `loadOffers` → `IncomingJobAlert` (linha 386).
- Com C4 por publicar, o profissional só sabe da oferta até 30 s depois, e só com a app aberta.
- Correção (uma das duas): (a) política de leitura extra em `casa_pedidos` para
  `offer_profissional_id IN (SELECT id FROM casa_profissionais WHERE user_id = auth.uid())`
  (lê-se o pedido inteiro, incluindo a morada — contra a decisão "zona, não a porta"; só aceitar se
  o Danilo o quiser); ou (b) manter a sondagem mas baixar para 10 s enquanto há ofertas por
  responder e publicar C4 (recomendo b).

**C6 — MÉDIA — DINHEIRO — Limite de 40 € em dinheiro + "só dinheiro" tornam metade do catálogo impossível de pedir.**
- `casa_03_cliente.sql:78–79` (criar: cartão/MB Way → `pagamento_cartao_indisponivel`; dinheiro
  > `max_cash_amount_cents` → `dinheiro_acima_do_limite`), `:192–195` (aceitar orçamento: o
  mesmo), `:241–243` (extra). O limite é a chave GLOBAL das entregas (4000).
- Catálogo (`casa_01:97–127`): "Quadros, prateleiras…" e "Pequena reparação" 20 €/h até 8 h
  (> 2 h já não passa), "Cortar relva" mínimo 2 h = 40 € (3 h não passa), "Pendurar TV" 30 € × 2
  não passa, "Montar um móvel" 25 € × 2 não passa. Todos os serviços de **orçamento** (montagem
  grande, mudanças, mato, eletricidade, gás, pladur, pintura) ficam presos: o orçamento típico
  passa 40 € e `casa_aceitar_orcamento` recusa — a app já deixa o botão "Aceitar" cinzento
  (`lib/screens/client/casa/casa_pedido_screen.dart:159–172` via `casaMetodoPorDefeito`).
- Correção (PROPOSTA, precisa do "autorizo"): chave própria `casa_max_cash_cents` (ex.: 30000)
  lida em `casa_config()`, `casa_criar_pedido`, `casa_aceitar_orcamento`, `casa_responder_extra`,
  e `CasaConfig.maxCashCents` passa a ler `casa_max_cash_cents`. Sem decisão, a Casa só serve
  para trabalhos até 40 €.

**C7 — MÉDIA — Taxa de cancelamento a dinheiro nunca é cobrada nem paga ao profissional.**
- `casa_03_cliente.sql:341–354` calcula `cancel_fee_cents` (metade/total) e `:369–396` grava-a;
  mas a Casa é só dinheiro (`payment_status='unpaid'`), e `casa_calcular_acerto`
  (`casa_04:440–472`) só soma pedidos `estado='confirmado'`. O profissional que já ia a caminho
  ("chegou") não recebe nada; a Bora não cobra nada.
- Correção: ou o acerto passa a somar `cancel_fee_cents` dos pedidos `cancelado` com
  `profissional_id` não nulo (parte do profissional a definir — DINHEIRO, pedir "autorizo"), ou
  o texto da simulação (`casa_pedido_screen.dart:361–364`) deixa de prometer um custo que não se
  cobra. Decisão do Danilo.

**C8 — MÉDIA — Extrato do profissional ao contrário: `aReceber` nunca é verdadeiro.**
- `lib/stores/handyman_store.dart:1077`: `aReceber => !direcao.contains('bora') && …`. As
  direções do servidor são `bora_to_handyman` | `handyman_to_bora` | `zero` (`casa_01:387`) —
  as duas contêm "bora". Em `handyman_ganhos_screen.dart:162,179` o acerto em que a Bora paga
  aparece como "a pagar ao Bora".
- E `handyman_ganhos_screen.dart:99` mostra "A receber no acerto: -3,00 €" quando
  `a_receber_cents` é negativo (`casa_04:418–419`; em dinheiro é sempre ≤ 0).
- Correção: `aReceber => direcao == 'bora_to_handyman'`; na linha 99, se negativo mostrar
  "A pagar ao Bora: 3,00 €". Teste novo em `test/casa_profissional_store_test.dart`.

**C9 — MÉDIA — Mensagens de erro do profissional caem na frase genérica.**
- `lib/stores/handyman_store.dart:782–829` (`casaErroTexto`) não traduz `oferta_expirada`,
  `profissional_ocupado`, `extra_por_responder`, `oficio_por_aprovar`, `preco_invalido`,
  `motivo_em_falta`, `conta_bloqueada`, `nome_em_falta`, `oficios_em_falta`, `invalid_role`
  (confirmado por grep: nenhum destes existe em `lib/` para a Casa). Aceitar uma oferta que
  expirou mostra "Não foi possível concluir".
- Correção: acrescentar os ramos (PT-PT, uma frase cada); teste de tabela no
  `casa_profissional_store_test.dart`.

**C10 — MÉDIA — O profissional só recebe pedidos se tiver disponibilidade gravada e nunca de si próprio.**
- `_casa_elegiveis` (`casa_02b:221–246`) exige `_casa_disponivel` (linha de `casa_disponibilidade`
  no dia da semana a cobrir [início, fim]; trabalho que passa da meia-noite = indisponível,
  `:206`) e `c.user_id <> b.client_user_id` (`:235`).
- Para o Danilo testar: a candidatura tem de levar horários (`handyman_apply_screen` → `_slots`)
  e o pedido-teste tem de sair de OUTRA conta (ex.: `boraappbora@gmail.com` como cliente e
  `nilofulfaro@gmail.com` como profissional). Não é bug; é o que falta saber para o teste.
- Correção opcional: no ecrã pendente/aprovado do profissional, aviso "Sem horários não recebes
  trabalhos" quando `perfil.disponibilidade` está vazia (`handyman_home_screen.dart:509–560`).

**C11 — (sem número próprio) — Texto do aviso de peso com cartão: ver P2 na área 2 — não conta aqui.**

**C12 — MÉDIA — Pedido de orçamento sem o Danilo como testador: a categoria nem aparece.**
- `_casa_visivel()` (`casa_02b:4–9`) = `casa_enabled` OU testador OU admin. Com
  `casa_enabled=false` e `casa_testadores=[]`, só o admin vê. Para o teste a dinheiro com cliente
  numa conta normal, meter o uuid do cliente em `casa_testadores` pelo painel (Definições →
  `casa_testadores`, `admin_casa_guardar_definicao`). Pedidos de testador nascem `is_test_order=true`
  e **ficam fora do acerto** (`casa_04:455`) — bom para provar sem dinheiro.

**C13 — MÉDIA — Para LIGAR a sério falta o "autorizo" dos valores.**
- `casa_criar_pedido` (`casa_03:67–68`) recusa `valores_por_autorizar` a quem não é testador;
  `casa_calcular_acertos_todos` (`casa_04:480`) devolve `ignorado` sem autorização.
- Passo do Danilo (único): no painel → Casa → Definições → "Autorizar valores" com um texto que
  contenha "autorizo" (`admin_casa_autorizar_valores`, `casa_05:747–775`), depois o interruptor
  (`admin_casa_interruptor`). A ordem certa: C1→C3 → candidatura → comprovativo → aprovar pessoa
  → aprovar cada ofício (`admin_casa_decidir_oficio`) → autorizar valores → ligar.

**C14 — BAIXA — Foto sobe sempre com extensão `.jpg` mesmo quando é PNG/WebP.**
- `lib/stores/casa_store.dart:389–400`: `mime` certo mas `caminho = …/problema_<ms>.jpg`. Abre
  na mesma (o balde guarda o content-type), mas é inconsistente. Correção: usar `$extensao`.

**C15 — BAIXA — Convite a orçar diz "Vê as fotos" antes de as fotos existirem.**
- As fotos sobem DEPOIS do `casa_criar_pedido` (`casa_pedido_wizard_screen.dart:347–360`); o
  convite sai dentro da RPC (`casa_03:98–100` → `_casa_convidar` → texto em
  `casa_02b:348–350`). Com `casa_minhas_ofertas` a ler as fotos ao vivo (`casa_04:173–174`) o
  profissional acaba por as ver; só o texto do aviso chega antes. Correção: tirar "Vê as fotos e"
  do corpo, ou atrasar o convite 60 s (bloco 2 do `casa_tick` já reconvida).

**C16 — BAIXA — Paridade admin: dois buracos pequenos.**
- `admin_casa_ofertas` (`casa_05:593–606`) não tem chamador em `lib/screens/admin/admin_casa_*`
  (o detalhe do pedido já traz `ofertas`) — casca sem fio (regra 1.5), apagar ou ligar.
- Não existe "criar pedido pelo painel" (regra 1.10 "criar"). Aceitável nesta fase; registar.

---

## 2. PESO AO QUILO (§59)

### O que está bem
- Servidor `estafeta_ajustar_peso` (produção): verifica interruptor, loja não-parceira, estafeta
  atribuído, estado `driverAccepted|pickedUp`, `products.variable_weight`, limite ±30 % com
  CEIL/FLOOR, mesma margem da linha, UPSERT em `order_weight_adjustments`, sino + push
  `order_weight_adjusted`. A app replica a conta do intervalo sem vírgula flutuante
  (`lib/services/peso_variavel_estafeta_service.dart:113–118`) e lê a resposta de forma pura
  (`:217–228`). RLS de `order_weight_adjustments` cobre cliente, estafeta (por `user_id` e por
  `drivers.id`) e admin.
- Talão `finalizar_talao_nao_parceiro` (produção): dinheiro → soma `v_weight_delta_cents` ao
  `cash_total_due` e ao `final_total`; cartão/MB Way mais barato → carteira
  (`storeshopping_v2_peso_variavel`); mais caro → `bora_assume` (com `weight_adjust_card_charge_
  enabled=false`); ajuste de produto "Não há" ignorado; `settled_via` gravado por linha.
- Lista de compras do estafeta: `lib/screens/driver_map_screen.dart:3023–3055` (repõe ajustes ao
  reabrir, abre a folha ao tocar no preço), `:3258–3292` (linha ajustada = total da etiqueta;
  previsão da conta a dinheiro com a diferença do cliente). Cliente: selo "Preço aproximado"
  (`lib/widgets/bora/peso_variavel_nota.dart:38–41`, cartões `bora_product_card.dart:120`,
  `market_product_card.dart:205`, carrinho `cart_screen.dart:174`), ficha e linhas "Ajustado ao
  peso" no acompanhamento e no detalhe (`lib/widgets/ajustes_peso_pedido.dart`,
  `order_tracking_screen.dart:745`, `order_details_screen.dart:140`). Painel:
  `admin_ajustes_peso_screen.dart`, interruptor/filtro no catálogo, chaves nas definições.
  Gatilhos `trg_products_zzz_peso_variavel_novo` e `trg_products_zzz_peca_ao_quilo` ativos.
- Testes: `test/peso_variavel_cliente_test.dart`, `test/peso_variavel_estafeta_test.dart`,
  `test/venda_ao_peso_jilo_prova_test.dart`, `test/venda_ao_peso_mais_abre_detalhe_test.dart`,
  `test/weight_portions_test.dart`.

### Achados

**P1 — MÉDIA — O total do pedido no ecrã do cliente só muda no talão; entre o ajuste e o talão o cliente vê "Ajustado ao peso 7,14 € → 9,06 €" mas o total antigo.**
- `estafeta_ajustar_peso` não toca em `orders.final_total` (só o talão, depois). A app mostra as
  linhas (`ajustes_peso_pedido.dart:95–96`) ao lado do total da encomenda sem a diferença.
- Correção na app (sem dinheiro): no `AjustesPesoLista` acrescentar uma linha final "Diferença:
  +1,92 € (entra no total final à entrega)" somando `delta_client_cents` das linhas; para
  dinheiro, legenda "Pagas o valor final ao estafeta".

**P2 — MÉDIA — Cartão/MB Way: o aviso diz "Novo total: X" mas a Bora assume (o cliente não paga mais).**
- Texto do aviso em `estafeta_ajustar_peso` (produção): `'… Novo total: %s.'` com `v_novo_total =
  final_total + Σ delta` — vale para dinheiro; com cartão/MB Way e
  `weight_adjust_card_charge_enabled=false` o talão marca `bora_assume` e `final_total` não muda.
  O cliente lê que vai pagar mais e não paga; se a diferença for negativa, recebe a carteira sem
  o aviso o dizer.
- Correção (servidor, uma migração; só texto): se `payment_method <> 'cash'`: positivo → "O
  peso real saiu mais caro; a diferença fica por conta do Bora"; negativo → "Saiu mais barato: a
  diferença vai para a tua carteira Bora no fim". Na app, a mesma frase na `AjustesPesoLista`
  conforme `order.paymentMethod`.

**P3 — MÉDIA — Melancia do Continente ficou com o preço da balança de um pedido, não com preço ao quilo.**
- `products` `cont-5050572` "Melancia Poucas Sementes Continente" `price=9.06`, `preco_kg=NULL`,
  `peso_medio_kg=NULL`, `variable_weight=true`. É exatamente o 9,06 € da balança do pedido
  48669acf (4,136 kg × 2,19 €/kg). A regra 7 do §59 (preço do quilo × peso médio) só foi aplicada
  ao Auchan e ao Intermarché (migração `20261031222024`, 16+16 produtos; Continente 0).
- Correção (dados, é a regra já autorizada): `UPDATE products SET preco_kg=2.19,
  peso_medio_kg=4 WHERE id='cont-5050572'` (o gatilho reescreve `price=8.76` e o nome "(~4 kg)"),
  e varrer as outras melancias/melões do Continente e do Pingo Doce com o mesmo gatilho.
  Prova: `select id,name,price,preco_kg,peso_medio_kg from products where name ilike 'melancia%'`.

**P4 — MÉDIA — Lidl e Mercadona sem nenhum produto ao quilo (0 de 697 e 0 de 8115).**
- §59 ponto 1 diz "ficam de fora até as secções estarem certas". Para o teste do Danilo só
  Continente/Auchan/Intermarché/Pingo Doce servem. Registar para não se perder.

**P5 — BAIXA — Limite ±30 % numa peça única (melancia) obriga a "Não há".**
- Uma melancia de 4 kg previstos a 5,6 kg (+40 %) é recusada (`fora_do_limite`), e o estafeta
  não pode "tirar uma peça": a mensagem da app (`peso_variavel_estafeta_service.dart:131–136`)
  manda pesar outra vez ou marcar "Não há". Para peças ao quilo (`preco_kg IS NOT NULL`) o limite
  podia ser ±50 % — DINHEIRO, decisão do Danilo. Se não, pelo menos a mensagem deve dizer
  "escolhe uma peça mais perto de N kg".

**P6 — BAIXA — Recibo do cliente: as linhas de ajuste não aparecem no PDF/recibo fiscal.**
- `AjustesPesoPedido` só está no acompanhamento e no detalhe; `client_billing_screen.dart` e o
  recibo por e-mail (Edge `notify-purchase-finalized`) não levam "Ajustado ao peso". Correção:
  juntar as linhas de `order_weight_adjustments` ao corpo do recibo (servidor) — fora do âmbito
  do teste a dinheiro.

**P7 — BAIXA — `AjustePesoEstafeta.daTabela` ignora linhas sem `product_id` string** (`peso_variavel_estafeta_service.dart:37–39`) — correto, só registar que `products.id` é TEXT (ids tipo `cont-…`) e o talão compara `x->>'original_item_id' = a.product_id` como texto: confirmar na app do talão que `original_item_id` leva o `productId` (e não o uuid da linha) — se levar outro valor, o "Não há" nunca anula o ajuste.

### O que está por arrumar para o Danilo testar A DINHEIRO (pedido real)
1. P3 (dados da melancia do Continente) — 1 UPDATE + varredura.
2. P1 + P2 (textos/linha de diferença) — app e um texto no servidor.
3. Conta: pedido real no Continente, a dinheiro, com 1 produto ao quilo (ex.: "Banana Continente",
   `cont-2597619`, 0,24 €/un.) — a diferença entra no `cash_total_due`; prova com
   `select * from order_weight_adjustments where order_id='…'` (`settled_via='dinheiro'`) e
   `select cash_total_due, final_total from orders where id='…'`.

---

## 3. COMPRA SEM CONTA — botão "Finalizar" (item 39, visto 26/10)

### Causa raiz (com evidência)
- Em 26/10 o visitante (`AuthStore.isVisitante`, sem `currentClient`) carregava em "Finalizar
  pedido" e `garantirContactoDoCliente` devolvia `false` em silêncio:
  `lib/screens/complete_profile_screen.dart` (versão anterior a 28/10, visível em
  `git show 6f9e2d4 -- lib/screens/complete_profile_screen.dart`):
  `final client = …currentClient; if (client == null) return false;` — e no carrinho
  `lib/screens/cart_screen.dart:733–735` `if (!contactoOk) return;`. Nenhum ecrã, nenhum aviso,
  nenhuma chamada ao servidor — "não faz nada".
- Isto NÃO depende da Edge `sessao-convidado` (que não existe em produção e tem o interruptor
  `sessao_convidado_ativa=false`): sem sessão, o visitante navega na mesma e o bloqueio é só no
  checkout. `query_logs` (24 h): zero chamadas a `sessao-convidado` — consistente.

### Estado do conserto
- **Corrigido no código a 28/10** (commit `6f9e2d4`, "juntar(melhorias-paridade-2026-10-26)"):
  `complete_profile_screen.dart:183–197` agora abre `ClientLoginScreen(voltarAoChamador: true)`
  por cima e, ao entrar/criar conta, `pop(true)` (`client_login_screen.dart:468–473`,
  `:383–384`) e volta ao mesmo carrinho.
- **Publicado**: Android versionCode 703 (01/11 03:04, e2e_log `fecho-pendentes-2026-10-31/BF-android`,
  commit `57010f13` inclui o 28/10). **Não há prova** de iPhone nem de web para este conserto
  (o registo só fala do AAB) — fica na lista de testes.
- Teste existente: `test/visitante_e_convidado_test.dart:27` ("Finalizar sem conta abre Entrar ou
  criar conta e volta ao carrinho") — é teste de texto/estrutura, não de widget.

### Achados

**G1 — ALTA — Falta a prova nas 3 plataformas e um teste de widget que reproduza o toque.**
- Criar `test/visitante_finalizar_abre_login_test.dart`: `CartScreen` com `AuthStore` em modo
  visitante e 1 item → tap em "Finalizar pedido" → `expect(find.byType(ClientLoginScreen),
  findsOneWidget)`. No emulador: Android + web (`flutter run -d chrome`) + iPhone (TestFlight).

**G2 — MÉDIA — Depois de entrar, o `TermsGate` do cliente novo fica por baixo do carrinho.**
- `lib/main.dart:1385–1390`: com `client != null` a raiz passa a `TermsGate(child:
  ClientMainScreen)`; o carrinho e o pagamento continuam empurrados por cima, por isso o cliente
  acabado de criar paga sem ver os termos até voltar à home. Correção: em
  `garantirContactoDoCliente`, depois do `pop(true)`, chamar o mesmo portão
  (`TermsGate.garantirAceite(context)` ou equivalente) antes de devolver `true`.

**G3 — MÉDIA — `sessao-convidado` referida na app mas inexistente no servidor.**
- `lib/auth/auth_store.dart:641–658` chama `functions.invoke('sessao-convidado')` quando
  `sessao_convidado_ativa=true`. Hoje está `false` e a função não existe: se alguém ligar o
  interruptor no painel (`admin_platform_settings_screen.dart:112`), passa a haver um 404 em cada
  arranque (engolido, mas ruído). Correção: ou publicar `supabase/functions/sessao-convidado`
  (depois de rever `test/visitante_e_convidado_test.dart:60`), ou esconder o interruptor do
  painel enquanto a função não estiver no ar.

**G4 — BAIXA — Botão "Finalizar" fica cinzento sem dizer porquê quando falta o agendamento.**
- `cart_screen.dart:724–727`: `onPressed: null` se `cartStore.agendamentoEmFalta`
  (`cart_store.dart:408–410`). Há um cartão de agendamento no ecrã, mas o botão mudo contraria a
  regra 1.2. Correção: manter ativo e, ao tocar, rolar até ao cartão e dizer "Escolhe a hora".

---

## 4. ESTAFETA NÃO APROVADO NÃO PODE FICAR ONLINE (lado da app)

### Como a app liga o online hoje
- Entregas: `lib/screens/driver_home_screen.dart:1007–1013` (Switch) → `_handleOnlineToggle`
  (`:387–478`) → `OrderStore.toggleDriverAvailability` (`lib/stores/order_store.dart:466–472`) →
  `DriverStore.toggleAvailability` (`lib/stores/driver_store.dart:305–317`): muda `driver.isOnline`
  **localmente primeiro**, depois `updateDriverOnlineStatus` (`:524–554`) faz `UPDATE drivers SET
  is_online … WHERE user_id` e **engole qualquer erro** (`catch → debugPrint`).
- TVDE: `lib/screens/driver/tvde/tvde_driver_home_screen.dart:578` usa o mesmo
  `toggleAvailability` (já pergunta antes ao servidor, `:563–576`, mas só a conformidade TVDE).
- Verificação de aprovação: só pela cache local `AuthStore.currentDriverStatus`
  (`driver_home_screen.dart:903–906`, `tvde_driver_home_screen.dart:886–887`), refrescada em
  `_enforceEffectiveStatus` (`driver_home_screen.dart:514–551`) — e `pending` passa sem bloquear
  (`:551`).
- Batimento: `HeartbeatService` (`lib/services/heartbeat_service.dart:87`, `:233`,
  `:331`) manda `driver_heartbeat`/`p_is_online:true` e o servidor "põe online quem bate com GPS
  vivo" — segunda porta para ficar online sem o botão.

### Achados / patch

**O1 — ALTA — O botão fica verde mesmo quando o servidor recusar.**
- Quando o gatilho novo do servidor forçar `is_online=false` (ou levantar erro) para
  `approval_status <> 'approved'`, `updateDriverOnlineStatus` não lê a resposta e
  `toggleAvailability` já pôs `driver.isOnline=true`: o estafeta vê "Online", o heartbeat arranca,
  o serviço em segundo plano arranca, e nunca recebe nada.
- Patch: `driver_store.dart:524–554` passa a `Future<bool>`: `final row = await _client.from(
  'drivers').update({'is_online': isOnline}).eq('user_id', driverId).select('is_online,
  approval_status').maybeSingle();` → se `row == null || row['is_online'] != isOnline` devolve
  `false`; apanhar `PostgrestException` com `message` a conter `nao_aprovado`/`not_approved`/
  `approval` e devolver `false` com o código. `toggleAvailability` (`:305–317`) passa a `Future<bool>`,
  só muda `driver.isOnline` DEPOIS do servidor dizer sim (revert em falha) e devolve o motivo.
  `_handleOnlineToggle` (`driver_home_screen.dart:459–460`) e o TVDE (`:578–585`) mostram a
  mensagem e NÃO arrancam heartbeat/serviço se `false`.

**O2 — MÉDIA — Mensagem a mostrar quando o servidor recusar (PT-PT, texto corrido).**
- "A tua conta ainda não está aprovada. Só podes ficar online depois de a equipa Bora aprovar a
  candidatura — avisamos-te por notificação." (pending) / "A tua candidatura não foi aprovada.
  Fala com o suporte." (rejected) / "A tua conta está suspensa." (suspended). Colocar num
  helper único `mensagemOnlineRecusado(String? codigo)` em `lib/utils/` e usar nos dois ecrãs
  (regra "uma porta só").

**O3 — MÉDIA — O heartbeat não deve pôr online quem não está aprovado (lado da app).**
- `heartbeat_service.dart:87/233/331`: antes de arrancar o batimento com `p_is_online:true`,
  confirmar `AuthStore.currentDriverStatus == approved` (o servidor também vai travar, mas a app
  deixa de bater para nada). Patch pequeno: `if (status != DriverStatus.approved) return;` no
  `start()`.

**O4 — BAIXA — `_enforceEffectiveStatus` deixa `pending` passar sem repor o ecrã.**
- `driver_home_screen.dart:551`: se o admin passar um aprovado a `pending`, a cache
  `refreshApprovalStatus` (`:524`) já reconstrói o portão (`:903–906`); confirmar com um teste
  de widget que, com `currentDriverStatus=pending`, o Switch `driver_online_toggle` não existe.

---

## 5. SÉRIE DE LIMPEZA (lado da app)

### Como a app lista hoje
- Cliente: `lib/stores/cleaning_store.dart:184–202` lê **todas** as reservas do cliente e separa
  por `status.isActive` por marcação (`cleaning_models.dart:68`) — certo: filtra por marcação,
  não por série.
- Profissional: `lib/stores/cleaner_store.dart:160–185` (ofertas `status='scheduled'` por
  `offer_cleaner_id`; agenda por `cleaner_id` + estados ativos) e `:400–415` (histórico) — também
  por marcação.
- Série: só o botão "Parar recorrência" (`lib/screens/client/cleaning/cleaning_tracking_screen.dart:
  227–262`, `:457–462`) → `cancel_cleaning_series`. A app **não sabe** se a série já está parada
  (`cleaning_recurrence_stops` tem RLS ligada e 0 políticas: ninguém a lê) nem mostra as
  próximas datas (o servidor só cria a próxima reserva 7 dias antes, `generate_recurring_bookings`).

### Dados reais (01/11)
- Série `ec94e24f…` (semanal, Mayra): completed, completed, cancelled_no_cleaner, **cancelled_client
  (31/10, pelo cliente, uma só limpeza)**. Não há linha em `cleaning_recurrence_stops`, mas o
  gerador (`generate_recurring_bookings`, produção) faz `CONTINUE WHEN v_last.status =
  'cancelled_client' AND cancelled_by IN ('client','admin')` → a série morreu sem o cliente ter
  pedido. É do servidor (o outro agente), mas a app contribuiu: o diálogo de "Cancelar limpeza"
  não diz que é só esta e não oferece ver a série.

### Achados / patch

**S1 — MÉDIA — Mostrar o estado da série e a próxima data na marcação recorrente.**
- `cleaning_tracking_screen.dart:457–462`: com `b.isRecurring`, acrescentar por cima do botão uma
  linha "Série semanal · próxima: <scheduled_at + 7/14 dias, hora de Lisboa>" e, se a série estiver
  parada, "Série parada" em vez do botão. Precisa de o servidor expor `series_stopped` (RPC
  `my_cleaning_series(p_group_id)` ou coluna calculada) — pedir ao agente do servidor; na app,
  `CleaningBooking` ganha `seriesStopped` (default false) e `CleaningStore.seriesState(groupId)`.

**S2 — MÉDIA — "Cancelar limpeza" numa reserva da série tem de dizer "só esta".**
- `cleaning_tracking_screen.dart` (diálogo de `_cancel`): texto "Cancelas só esta limpeza; a série
  continua na próxima data" quando `b.isRecurring`, com segundo botão "Parar a série toda" que
  chama `_pararSerie`. Assim o cliente não cancela a última por engano a pensar que parou a série
  (e o servidor, depois do conserto, deixa de matar a série).

**S3 — MÉDIA — Lista "Os meus pedidos" não agrupa a série.**
- `lib/screens/client/cleaning/*` (lista): marcações da mesma `recurrenceGroupId` aparecem soltas,
  sem indicação "semanal · próxima". Patch: selo `b.recurrenceLabel` no cartão
  (`cleaning_models.dart:217–219` já dá o texto) e ordenação por `scheduled_at` ascendente nas
  ativas.

**S4 — BAIXA — Profissional: a agenda não distingue a série.**
- `cleaner_store.dart:160–185`/ecrã do cleaner: acrescentar o mesmo selo "semanal/quinzenal" e
  "cliente habitual" quando `requested_cleaner_id == me.id` (a série repete a mesma profissional,
  `generate_recurring_bookings` usa `COALESCE(cleaner_id, requested_cleaner_id)`).

---

## TESTES A CORRER NO PC

### `flutter test` existentes (todos têm de ficar verdes depois das correções)
```
flutter test test/casa_cliente_regras_test.dart test/casa_cliente_ecras_test.dart \
  test/casa_profissional_ecras_test.dart test/casa_profissional_store_test.dart \
  test/admin_casa_painel_test.dart test/casa_integracao_destinos_test.dart \
  test/casa_integracao_documentos_test.dart test/casa_integracao_ligacoes_test.dart \
  test/casa_integracao_papeis_test.dart \
  test/peso_variavel_cliente_test.dart test/peso_variavel_estafeta_test.dart \
  test/venda_ao_peso_jilo_prova_test.dart test/venda_ao_peso_mais_abre_detalhe_test.dart \
  test/weight_portions_test.dart test/visitante_e_convidado_test.dart
```
E antes de tudo `python .claude/juiz/anti_trapaca.py` + `flutter analyze`.

### Testes a CRIAR
1. `test/casa_acerto_direcao_test.dart` — C8: `CasaAcerto(direcao:'bora_to_handyman').aReceber == true`,
   `'handyman_to_bora' == false`, `'zero' == false`; ecrã de ganhos com `a_receber_cents=-300`
   mostra "A pagar ao Bora: 3,00 €".
2. `test/casa_erros_profissional_test.dart` — C9: tabela de códigos → frase PT-PT (nenhuma cai
   na genérica).
3. `test/visitante_finalizar_abre_login_test.dart` — G1 (widget: tap em "Finalizar pedido" como
   visitante abre `ClientLoginScreen` com `voltarAoChamador`).
4. `test/driver_online_recusado_test.dart` — O1/O2: `DriverStore.toggleAvailability` com cliente
   Supabase falso que devolve `is_online=false` → `driver.isOnline` fica false e a mensagem é a
   de "conta ainda não aprovada"; com `currentDriverStatus=pending` o Switch
   `driver_online_toggle` não existe (O4).
5. `test/limpeza_serie_textos_test.dart` — S1/S2: cartão recorrente mostra "próxima: <data>" e
   o diálogo de cancelar diz "só esta".
6. `test/peso_ajuste_lista_diferenca_test.dart` — P1/P2: `AjustesPesoLista` com dois ajustes
   mostra a linha de diferença e a frase certa por método de pagamento.

### Emulador / provas reais (depois de publicar nas 3 plataformas)
Casa (duas contas: cliente = boraappbora@gmail.com em `casa_testadores`; profissional =
nilofulfaro@gmail.com):
1. Candidatura do profissional com horários (seg–dom 09–20), CC + seguro, ofícios montagem e
   fixação → prova: linha em `casa_profissionais` com IBAN/data/autocertificação (C1) e
   `casa_profissional_oficios` pending.
2. Comprovativo de atividade enviado e aprovado no painel (C2) → aprovar pessoa → aprovar os
   dois ofícios → `admin_casa_resumo` sem pendentes.
3. Cliente pede "Pendurar televisão" (30 €, dinheiro) para daqui a 3 h → oferta toca no
   profissional (push, C4) em < 30 s → aceitar → "Estou a caminho" → "Cheguei" → "Iniciar" →
   pedir extra 5 € → cliente aceita → foto depois → "Concluir" → cliente confirma → avalia 5★ →
   profissional avalia o cliente. Prova: `casa_pedido_eventos` com a cadeia inteira,
   `casa_pedidos.estado='confirmado'`, `total_cents=3500`, `comissao_cents` (0 na promoção dos
   primeiros, `sem_comissao_ate`), `payment_status='cash_pending'`.
4. Cliente pede "Montagem grande ou cozinha" (orçamento) → convite chega → profissional envia
   orçamento 35 € → cliente aceita a dinheiro → confirmar que acima de 40 € o botão explica (C6).
5. Cancelar um pedido aceite a 1 h da hora → simulação mostra "custa o total" → ver C7.
6. Painel: reatribuir, marcar teste, forçar conclusão, resolver disputa, exportar CSV, calcular
   acerto da semana (com valores autorizados) e marcar pago.
7. Notificações: `select * from notification_failures where source like '_casa%'` vazio.

Peso: pedido real Continente a dinheiro com 1 produto ao quilo (ver secção 2) + ver no cliente a
linha "Ajustado ao peso" e o total final à porta.

Convidado: Android, web (Chrome) e iPhone — abrir como "Sou Cliente", pôr 1 produto, "Finalizar"
→ entra o ecrã de login, criar conta, voltar ao carrinho e pagar a dinheiro.

Online: conta de estafeta `pending` → sem Switch; conta aprovada → Online; admin passa a
`suspended` → próximo toque devolve mensagem e botão fica cinzento (depois do gatilho do servidor).

Série: criar limpeza semanal a dinheiro, cancelar só a primeira → a seguinte continua a aparecer
(depois do conserto do servidor) e o cartão diz "próxima: <data>".
