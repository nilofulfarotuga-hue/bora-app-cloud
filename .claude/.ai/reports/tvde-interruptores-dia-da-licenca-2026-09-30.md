# Dia da licença TVDE — o que se liga, por que ordem, e o que se confirma antes

> 30/09/2026 · agente `compliance-pt` · PT-PT.
> Tudo se faz no painel admin, em **"Conformidade TVDE (IMT/AMT)"**. Por trás está a RPC `admin_tvde_conf_set(chave, valor)`: aceita as chaves da categoria `tvde_conformidade` e as `plataforma_*`, e **regista cada mudança** em `tvde_compliance_events` e no log de admin.
> Regra: **um passo de cada vez**. Só se passa ao seguinte quando a verificação do passo anterior der o resultado esperado, com prova (SELECT ou ecrã).
> Qualquer interruptor volta atrás no mesmo ecrã (pôr `false`). Nenhum apaga dados.

## Passo 0 — Antes de tocar em qualquer interruptor (fora da app)

Nada disto se liga sem estas coisas feitas. São todas do Danilo ou de terceiros:

| # | Pré-condição | Base legal | Como se prova |
|---|---|---|---|
| 0.1 | Estrutura resolvida com advogado: a plataforma **sem interesse** em operadores nem em carros TVDE (contradição C) | art. 12.º n.º 5; art. 20.º n.º 11 | parecer escrito |
| 0.2 | Empresa constituída (pessoa coletiva) com NIPC | art. 16.º | certidão permanente |
| 0.3 | **Licença IMT de plataforma** recebida (ou deferimento tácito a 30 dias úteis, com prova do pedido e da taxa) | art. 17.º n.º 1 | número da licença |
| 0.4 | Minuta do contrato de adesão do passageiro enviada à AMT, e passados 20 dias sem oposição (ou corrigida) | art. 5.º n.os 3–5 | email da AMT ou data de envio + 20 dias |
| 0.5 | Minuta operador ↔ plataforma comunicada à AMT | art. 20.º n.os 8–9 | idem |
| 0.6 | Registo no Livro de Reclamações Eletrónico + adesão a uma entidade RAL | DL 156/2005 art. 5.º-B; Lei 144/2015 art. 18.º | comprovativos |
| 0.7 | Software de faturação certificado contratado (em modo de teste) + parecer do contabilista sobre quem emite a fatura e a taxa de IVA | art. 15.º n.º 8; DL 28/2019 | contrato e chave de teste |
| 0.8 | "Vai" do Danilo para o **preço fixo** (art. 15.º n.º 6), a correção do **teto dos 25 %** (art. 15.º n.º 3) e a **taxa de cancelamento** | arts. 15.º n.os 3 e 6 | mensagem do Danilo |
| 0.9 | Política de privacidade, registo de atividades e avaliação de impacto revistos e publicados | RGPD arts. 13.º, 30.º e 35.º | link na app |

## Passo 1 — Dados da plataforma (não muda comportamento nenhum)

Preencher, por esta ordem: `plataforma_denominacao`, `plataforma_nif` (9 dígitos; a RPC recusa outro formato), `plataforma_sede`, `plataforma_licenca_imt`. Confirmar também `plataforma_nome`, `plataforma_marca`, `plataforma_email_contacto` e `livro_reclamacoes_url`.

- **Porquê:** a página "Sobre o operador da plataforma" (art. 17.º n.º 8), a ficha de fiscalização e o Resumo da viagem deixam de dizer "em constituição".
- **Verificar depois:** abrir a página do operador na app e a ficha de fiscalização de um motorista. Os quatro dados têm de aparecer. `select key, value from platform_settings where key like 'plataforma_%';`

## Passo 2 — Registar os operadores TVDE

No admin, em Operadores: denominação, NIPC, número e validade da licença IMT, contrato assinado. Aprovar só os que têm licença válida.

- **Porquê:** o motorista só pode trabalhar através de um operador licenciado (art. 10.º; art. 14.º n.º 3), e a plataforma tem de o verificar (art. 20.º n.º 5).
- **Verificar antes:** licença do operador na lista do IMT por distrito. Enquanto não houver ligação ao IMT, é a única verificação oficial possível.
- **Verificar depois:** `select denominacao, estado, licenca_imt_validade from tvde_operators;` Todos os aprovados com validade futura.

## Passo 3 — Registar os carros e associá-los aos motoristas

Cada carro: matrícula, marca, modelo, ano, 1.ª matrícula, lugares, elétrico sim ou não, foto, registo IMT, seguro, inspeção, dístico, adaptado sim ou não. Depois, associar cada carro ao motorista (associação nominal).

- **Porquê:** só carros registados no IMT e inscritos pelo operador (art. 12.º n.º 1). O passageiro tem de ver foto, lugares e ano (art. 19.º n.º 1 f)). O comodato exige associação nominal na plataforma (art. 12.º n.os 16–20).
- **Verificar depois:** `select matricula, estado, seguro_validade, inspecao_proxima from tvde_vehicles;` e, no cartão do motorista na app, a foto, os lugares e o ano.

## Passo 4 — Completar cada motorista

Operador, data da carta B (mais de 3 anos, grupo 2), número e validade do CMTVDE, contrato com o operador, fala português, data do curso de atualização, registo criminal.

- **Porquê:** requisitos do art. 10.º e do art. 11.º. Sem isto, o passo 6 bloqueia os motoristas todos. Hoje os 4 motoristas aprovados estão **todos** impedidos: sem operador e sem carro.
- **Verificar depois:** no admin, "Motoristas — conformidade" (`admin_tvde_motoristas_conformidade`). Cada motorista que vai trabalhar tem de ter **zero motivos** de bloqueio. Os avisos (a caducar) podem ficar.

## Passo 5 — Ligar o MESTRE: `tvde_compliance_enforce` = true

- **Porquê:** sem o mestre, nenhum dos outros interruptores faz efeito (`tvde_conf_ativa` exige os dois). Ao ligá-lo, o cron diário passa a **enviar avisos** de documentos a caducar (30 e 7 dias).
- **Verificar antes:** passos 1 a 4 feitos. Os outros interruptores continuam desligados.
- **Verificar depois:** no dia seguinte, `select tipo, count(*) from tvde_compliance_events where at > now() - interval '1 day' group by tipo;` Devem aparecer avisos e mais nada. Despacho igual ao de antes (fazer 1 pedido de teste).

## Passo 6 — Bloqueio: `tvde_compliance_block` = true

- **Porquê:** a plataforma tem de bloquear quem não cumpre (art. 14.º n.º 2). O portão do despacho e o gatilho "ficar online" passam a recusar quem tem motivos.
- **Verificar antes:** lista do passo 4 com zero motivos para quem vai trabalhar. Combinar com o `seguranca` a **revisão humana**: o admin revê cada bloqueio novo e o motorista pode contestar pelas queixas. É a recomendação da CNPD (parecer 2026/37 §129 n)) e o RGPD art. 22.º.
- **Verificar depois:** um motorista de teste com um documento em falta **não consegue** ficar online e vê o motivo. Um motorista em ordem fica online e recebe ofertas.

## Passo 7 — Limite de horas: `tvde_work_limit_enforce` = true (`tvde_work_limit_hours` = 10)

- **Porquê:** máximo de 10 h em 24 h, somando todas as plataformas; a plataforma tem de o garantir (art. 13.º n.os 1–2).
- **Verificar antes:** `tvde_driver_work_log` com pelo menos 24 h de registos contínuos (o cron `tvde-work-log-sweep` a correr de 5 em 5 minutos). Todos os motoristas declararam as horas noutras plataformas no ecrã Conformidade.
- **Verificar depois:** `select public.tvde_driver_horas_total('<user_id>');` bate com o contador na app do motorista. Quem chega ao limite **acaba a corrida em curso** e deixa de receber ofertas.

## Passo 8 — Só pagamento eletrónico: `tvde_electronic_payment_only` = true

- **Porquê:** o pagamento TVDE tem de ser processado pela plataforma e só por meios eletrónicos (art. 15.º n.º 7). Hoje 63 de 116 corridas foram em dinheiro.
- **Verificar antes:** uma corrida real paga por **cartão** e outra por **MB WAY** no TVDE, com a cobrança confirmada no Stripe. Ver se há dívidas de dinheiro de corridas antigas por acertar. Rever a corrida de balcão (tem de passar a ser pedido na app com pagamento eletrónico). Avisar os clientes habituais de que o dinheiro acaba.
- **Verificar depois:** a opção dinheiro desaparece no TVDE. Uma tentativa de pedido com `payment_method = cash` é recusada pelo servidor. **As entregas continuam a aceitar dinheiro.**

## Passo 9 — Opções do cliente: primeiro `tvde_client_options_enabled`, depois `tvde_pref_matching_enforce`

- **Porquê:** escolher motorista que fala português (art. 19.º n.º 1 i)) e carro adaptado (art. 6.º). O primeiro interruptor só **mostra** as opções. O segundo faz o despacho **respeitá-las**.
- **Verificar antes do 2.º:** há pelo menos 1 motorista com `fala_portugues = true` e há a lista de "outros prestadores" (táxis adaptados da Guarda) preenchida para quando não houver carro adaptado. Se ligar o matching sem carros adaptados, quem pede mobilidade reduzida fica sem carro: a app tem de mostrar as alternativas em até 15 minutos (`tvde_mobilidade_espera_min`).
- **Verificar depois:** um pedido de teste com "fala português" só é oferecido a quem fala. Um pedido com mobilidade reduzida tem o **mesmo preço** que um normal.

## Passo 10 — IVA discriminado: `tvde_iva_discriminar` = true

- **Porquê:** a fatura tem de discriminar o IVA (art. 15.º n.º 8). Antes da empresa seria informação falsa.
- **Verificar antes:** NIF e regime de IVA registados; taxa confirmada pelo contabilista (hoje `tvde_iva_transporte_pct` = 6, **não confirmado**).
- **Verificar depois:** o Resumo da viagem e o preço discriminado mostram base + IVA a somar ao cêntimo com o total.

## Passo 11 — Faturação: `tvde_invoicing_provider` (fornecedor) e só depois `tvde_invoicing_enabled` = true

- **Porquê:** fatura eletrónica por software certificado pela AT, com ATCUD e QR (art. 15.º n.º 8; DL 28/2019).
- **Verificar antes:** trocar `stub` pelo fornecedor escolhido e emitir 3 faturas em **modo teste** (`tvde_invoices.modo = 'teste'`). Conferir código da viagem, origem, destino, tempo, distância, IVA e taxa de intermediação.
- **Verificar depois:** a 1.ª corrida real gera `tvde_invoices.estado = 'emitida'` com número e ATCUD, e o passageiro recebe a fatura. No dia 5 do mês seguinte, confirmar a comunicação à AT (DL 198/2012).

## Passo 12 — Preço fixo: `tvde_fixed_price_option_enabled` = true

- **Porquê:** a opção de preço fixo é **obrigatória** (art. 15.º n.º 6). Está no fim só porque ainda não está construída e mexe em dinheiro. **Legalmente, devia estar pronta antes de abrir ao público.**
- **Verificar antes:** "vai" do Danilo, funcionalidade construída e aprovada pelo `juiz-revisor`, e a regra dos 25 % a cumprir também no preço fixo.
- **Verificar depois:** uma viagem com preço fixo e desvio de percurso cobra **exatamente** o preço mostrado.

## Passo 13 — Ligação ao IMT: `tvde_imt_integration_enabled` = true

- **Só quando o IMT publicar a especificação** (portaria do art. 20.º-A n.º 7) e o Bora tiver aderido à plataforma de partilha de dados. Até lá, **fica desligado**. O esqueleto está preparado.

## Nunca ligar

- **`tvde_driver_rates_client_disabled`**: a Lei 59/2026 revogou a proibição de avaliar passageiros e o art. 19.º n.º 2 c) **exige** a avaliação pelos dois lados. Fica desligado para sempre, salvo ordem escrita da AMT ou do IMT.

## Já ligado (não mexer)

- `tvde_amt_report_enabled` = true: o relatório mensal para a AMT é calculado no dia 1 de cada mês. Só calcula, não envia nada. O reporte e o pagamento à AMT (art. 30.º) passam a ser feitos pelo Danilo a partir do primeiro mês com licença.
- O bloqueio de ficar online com documento **expirado** (`motorista_bloqueio_doc_expirado`, de 23/09) já está ativo, independente do mestre.

## Depois do dia da licença (calendário)

| Quando | O quê | Base |
|---|---|---|
| todos os meses, até ao último dia | reporte e pagamento da contribuição AMT (5 % da taxa de intermediação) | art. 30.º |
| todos os meses, dia 5 | e-fatura à AT (se o software não o fizer em tempo real) | DL 198/2012 art. 3.º |
| 15 dias úteis após cada reclamação | resposta à reclamação do Livro | DL 156/2005 art. 5.º-B |
| todos os anos | registo criminal do gerente ao IMT | art. 18.º |
| 31 de janeiro | DAC7 à AT | Lei 36/2023 **[NC]** |
| 10 dias úteis após qualquer mudança | comunicar ao IMT | art. 17.º n.º 14 |
| 6 meses antes do fim da licença | pedir renovação | art. 17.º n.º 13 |
