# Matriz legal TVDE — Bora (Lei 45/2018 na versão da Lei 59/2026)

> Missão `tvde-conformidade-lei-59-2026` · 30/09/2026 · agente `compliance-pt` · PT-PT
> Fonte jurídica: `.claude/.ai/reports/_pesquisa-tvde-lei-59-2026-bruto.md` (texto oficial da Lei 59/2026, DR n.º 164, 25/08/2026).
> Artigos = numeração da **Lei 45/2018 republicada**, salvo "Lei 59/2026, art. X.º". **[NC]** = não confirmado em fonte oficial (fica assim).
> Isto não é parecer de advogado. Antes de pedir a licença, um advogado deve rever as linhas vermelhas.

## Resumo (para ouvir em voz alta)

1. A lei nova está em vigor desde **1 de setembro de 2026** (Lei 59/2026, art. 7.º). O Bora **não tem empresa nem licença** de plataforma TVDE (art. 16.º e 17.º).
2. Mesmo assim já há **116 corridas finalizadas** e **63 pagas em dinheiro**. Sem licença e com dinheiro, isto é o maior risco: coima até 4 500 € em nome próprio ou até 44 000 € para uma empresa (art. 25.º n.º 2).
3. Muito já está construído atrás de interruptores desligados: tempos de trabalho, bloqueio, teto dos 25 %, SOS, queixas, fiscalização, relatório AMT, cartão do motorista.
4. O que falta de verdade quase tudo depende do Danilo ou de terceiros: empresa, licença IMT, contratos à AMT, faturação certificada, ligação ao IMT (ainda sem especificação pública).
5. **Contradição A**: a avaliação do passageiro pelo motorista passou a ser **obrigatória** (art. 19.º n.º 2 c)). O interruptor `tvde_driver_rates_client_disabled` **nunca se liga**.
6. **Contradição B**: a lei obriga a oferecer **preço fixo fechado** para qualquer percurso (art. 15.º n.º 6). Hoje o preço é recalculado no fim pela distância real. É mexer em dinheiro, por isso fica **proposta à espera do "vai"**.
7. **Contradição C**: a plataforma **não pode ter interesse** em operadores nem em carros TVDE (art. 12.º n.º 5 e art. 20.º n.º 11). O plano do Córtex (uma só empresa para o Bora e para o operador TVDE próprio) **choca com isto**. Tem de ir a advogado antes de constituir a empresa.
8. Teto dos 25 %: **5 corridas em 116 passaram** (corrida de balcão com 60 %, 2 pacotes ida-e-volta com 50 %, 2 corridas com paragem com 26,67 %). É preciso corrigir a repartição, e isso é dinheiro: proposta vermelha.
9. Os 4 motoristas TVDE aprovados estão **todos impedidos** pela lei nova: nenhum tem operador nem carro registado.
10. Documentos escritos hoje: minuta do contrato de adesão, política de privacidade, registo de atividades, avaliação de impacto da geolocalização e lista ordenada de interruptores para o dia da licença.

## Contagem

| Estado | Linhas | O que quer dizer |
|---|---|---|
| verde | **17** | Já existe e funciona hoje, ou a lei não se aplica ao Bora |
| amarelo | **48** | Construído mas em prova, pronto atrás de interruptor, ou falta texto/ajuste fácil |
| vermelho | **25** | Falta e impede o lançamento legal, ou há decisão de dinheiro ou de estrutura por tomar |
| **Total** | **90** | |

A checklist do painel admin (`tvde_legal_requirements`, semeada pelo `20260930127000_tvde_conformidade_checklist_seed.sql`) leva **80** destas linhas. Ficaram de fora 10 linhas menores ou já resolvidas: PL-11, MO-09, VE-07, IN-07, IN-11, PR-03, SE-02, IM-06, RG-09 e AC-02.

## As 3 contradições com o pedido original

| | O pedido dizia | A lei publicada diz | Decisão |
|---|---|---|---|
| **A** | Esconder a avaliação do passageiro pelo motorista (antigo art. 19.º n.º 5) | Lei 59/2026, art. 5.º **revogou** a proibição; art. 19.º n.º 2 c) **obriga** a avaliação pelos dois lados | O interruptor `tvde_driver_rates_client_disabled` fica sempre desligado (a descrição na base de dados já diz "NÃO LIGAR", migração `…126000`). Salvaguarda da CNPD: a avaliação não pode virar perfil nem castigo (parecer CNPD 2026/37 §129 m); RGPD art. 22.º). |
| **B** | Preço calculado pela distância real (sistema atual) | Art. 15.º n.º 6: **opção obrigatória de preço fixo predeterminado para qualquer itinerário**, que vincula mesmo que a viagem demore mais | Proposta **vermelha** (mexe no valor cobrado): calcular o preço pela rota no pedido e fechá-lo. Interruptor `tvde_fixed_price_option_enabled` preparado; só se constrói e liga depois do "vai". |
| **C** | Córtex `formalizacao-fiscal-tvde-2026-08-06`: "Uma ÚNICA empresa (unipessoal por quotas) cobre Bora App + TVDE operador próprio" | Art. 12.º n.º 5 e art. 20.º n.º 11: a plataforma **não pode ser proprietária, financiar nem ter interesse direto ou indireto** em veículos TVDE nem em operadores TVDE | **Vermelho, decisão do Danilo com advogado.** Caminhos possíveis: (1) o Bora é só plataforma e trabalha com operadores de terceiros da Guarda (o IMT publica a lista por distrito); (2) o Bora é só operador noutras plataformas; (3) duas empresas separadas. O caminho 3 pode continuar a ser "interesse indireto" se o sócio for o mesmo **[NC — só um advogado ou o IMT o podem dizer]**. |

## Legenda de estado

- **verde**: cumpre hoje, ou a lei não se aplica.
- **amarelo**: feito mas em prova, pronto mas desligado à espera da licença, ou falta pouco.
- **vermelho**: falta e bloqueia, ou precisa de decisão do Danilo (dinheiro ou estrutura), ou depende de terceiros sem data.

"Em prova" = ecrã Flutter que está a ser feito nesta missão e ainda não tem prova material.

---

## 1. Plataforma e licença

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| PL-00 | Não operar TVDE sem licença de plataforma | art. 16.º, 17.º n.º 1; coimas no art. 25.º n.º 2 (250–4 500 € singular / 5 000–44 000 € coletiva); interdição até 2 anos no art. 26.º | 116 corridas finalizadas, 63 em dinheiro, sem licença | Decidir o que acontece às corridas até existir licença | **Danilo decide**: suspender ou pôr o TVDE em modo teste fechado até à licença | vermelho |
| PL-01 | Plataforma tem de ser pessoa coletiva | art. 16.º; art. 17.º n.º 4 | Não há empresa | Constituir sociedade (CAE 62900, 52213 ou 52320 no objeto, segundo a página do IMT) | Danilo + contabilista, depois de resolver a contradição C | vermelho |
| PL-02 | Licença IMT de plataforma (Modelo 30 IMT, taxa de 500 €, deferimento tácito a 30 dias úteis), com situação fiscal e contributiva regularizada, pacto social e registos | art. 17.º n.os 1 e 4 a)–h); página do IMT (regime anterior) | Nada | Pedido completo ao IMT (sec.dsrje@imt-ip.pt) | Depois de PL-01, PL-07, PL-08 e PL-09 | vermelho |
| PL-03 | N.º de registo da marca | art. 17.º n.º 4 | Marca "Bora" em `plataforma_marca`; registo no INPI não verificado nesta missão | Confirmar ou registar a marca | Danilo confirma no INPI | amarelo |
| PL-04 | Capacidade tecnológica demonstrada desde o início (IMT, tempos, RGPD, fiscalizadores, emergência); o transitório dos 120 dias é só para quem já tem licença | art. 17.º-A n.os 1–3; Lei 59/2026, art. 4.º | 4 de 5 alíneas construídas (b, c, d, e); falta a a) | Ligação ao IMT (ver IM-01) | Esperar especificação oficial; o resto fica pronto | vermelho |
| PL-05 | Página pública com os dados do operador da plataforma | art. 17.º n.º 8 (dados dos n.os 4–5) | RPC `tvde_operador_plataforma` + página na app (em prova); dados vazios, aparece "em constituição" | Preencher denominação, NIF, sede e licença | Dia da licença, passo 1 | amarelo |
| PL-06 | Idoneidade dos gerentes; envio anual do registo criminal ao IMT | art. 18.º | Nada | Registo criminal do gerente, todos os anos | Lembrete anual no admin depois da licença | vermelho |
| PL-07 | Plataforma sem interesse direto ou indireto em operadores, carros ou escolas TVDE | art. 12.º n.º 5; art. 20.º n.º 11 | Plano do Córtex: uma empresa para plataforma e operador | Estrutura legal compatível | **Contradição C**: advogado antes de constituir | vermelho |
| PL-08 | Contrato de adesão operador ↔ plataforma (acesso e bloqueio de operadores, motoristas e carros), publicitado, comunicado antes à AMT e mostrado ao motorista na inscrição | art. 20.º n.os 8–10 | Não existe | Minuta para operadores | Redigir (próxima tarefa do `compliance-pt`), rever com advogado, enviar à AMT | vermelho |
| PL-09 | Minuta do contrato de adesão com o passageiro enviada à AMT; a AMT tem 20 dias para mandar corrigir | art. 5.º n.os 2–5; art. 17.º n.º 4 | Minuta escrita hoje (`tvde-minuta-contrato-adesao-2026-09-30.md`) | Preencher marcadores, advogado, envio (canal da AMT não encontrado **[NC]**) | Danilo envia depois de ter empresa | amarelo |
| PL-10 | Serviço só por reserva prévia na plataforma; proibido apanhar na rua | art. 5.º n.os 1 e 6 | A app só pede pela app, **mas existe a "corrida de balcão"** (preço combinado de 10 €) | Garantir que a corrida de balcão é um pedido feito pelo cliente na plataforma antes de começar | Rever o fluxo de balcão com `estafeta-motorista` | amarelo |
| PL-11 | Licença até 5 anos; renovar 6 meses antes; alterações ao IMT em 10 dias úteis | art. 17.º n.os 12–14 | Nada (não há licença) | Datas no admin | Aviso no admin quando houver licença | amarelo |

## 2. Motorista

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| MO-01 | CMTVDE ou certificado de táxi válido | art. 10.º n.os 1 e 3 | Ficha legal de 23/09 guarda o número e a validade; cálculo marca `cmtvde_em_falta` / `cmtvde_caducado` | Confirmação oficial (hoje é o motorista que declara) | Validar pelo IMT quando houver ligação (IM-01) | amarelo |
| MO-02 | Carta B há mais de 3 anos **com averbamento do grupo 2** | art. 10.º n.º 2 a) | `drivers.carta_b_emitida_em` + regra dos 3 anos (`tvde_carta_min_anos`) | Não se pergunta pelo **grupo 2** | Acrescentar a pergunta "carta com grupo 2" (`estafeta-motorista`) | amarelo |
| MO-03 | CMTVDE válido 5 anos; renovação 6 meses antes com curso contínuo de 8 h | art. 10.º n.os 4, 5 e 9 | Validade + aviso aos 30 e 7 dias (`motorista_docs_alerta_diario`); `tvde_curso_atualizacao_em` | Nada de essencial | Manter | verde |
| MO-04 | Número único de registo e fotografia do motorista visíveis ao passageiro | art. 10.º n.º 10; art. 19.º n.º 1 e) | Cartão do motorista com CMTVDE (em prova) | Prova material | Juiz / prova do ecrã | amarelo |
| MO-05 | Idoneidade; quem viveu 6 meses ou mais fora nos últimos 5 anos entrega registo criminal do país onde viveu | art. 11.º | Tipo de documento `registo_criminal` existe | Pergunta "viveu fora de Portugal?" e pedido do registo estrangeiro | `estafeta-motorista` | amarelo |
| MO-06 | Domínio funcional do português verificado no curso inicial | art. 10.º-A; portaria **por publicar [NC]** | `drivers.fala_portugues` (declarado) | Portaria | Aguardar; o curso é do IMT, não da plataforma | amarelo |
| MO-07 | Motorista entra por um operador licenciado; o operador responde por quem não cumpre | art. 10.º; art. 14.º n.º 3 | `drivers.tvde_operator_id`; **os 4 motoristas aprovados não têm operador** | Operadores registados e associados | Ver OP-01 | vermelho |
| MO-08 | Contrato escrito operador–motorista (presunção do art. 12.º do Código do Trabalho) | art. 10.º n.º 2 e), n.os 16–17 | Documento `contrato_operador`; nenhum carregado | Contratos | Operadores entregam; admin aprova | vermelho |
| MO-09 | Motorista leva consigo o certificado | art. 10.º n.os 14–15 | Ficha de fiscalização com QR (23/09) | Nada | Manter | verde |

## 3. Veículo

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| VE-01 | Só carros registados no IMT, inscritos pelo operador; a plataforma atesta os requisitos | art. 12.º n.º 1 | `tvde_vehicles` + aprovação no admin; **0 carros registados** | Carros reais | Operadores registam; admin aprova | vermelho |
| VE-02 | Ligeiro de passageiros, matrícula nacional, até 9 lugares com o condutor | art. 12.º n.º 6 | Regra de lotação (`tvde_vehicle_max_seats` = 9) | Validar o formato da matrícula portuguesa | Pequeno ajuste de validação | amarelo |
| VE-03 | Menos de 10 anos desde a 1.ª matrícula; elétrico puro até 12 | art. 12.º n.º 7 | Regra no cálculo de conformidade (10 / 12) | Nada | Manter | verde |
| VE-04 | Inspeção anual | art. 12.º n.º 8 | `inspecao_proxima` + aviso + motivo de bloqueio | Nada | Manter | verde |
| VE-05 | Seguro de responsabilidade civil que cubra passageiros | art. 12.º n.º 9 | `seguro_validade`; aviso "confirmar seguro de acidentes pessoais" | A referência a acidentes pessoais **saiu** do n.º 9 | Mudar o texto do aviso para "RC com passageiros" (não bloqueia) | amarelo |
| VE-06 | Dístico inamovível do IMT com QR | art. 12.º n.os 2, 10, 13–15; portaria **por publicar [NC]** | Campo `distico_id` | Portaria e modelo do dístico | Aguardar | amarelo |
| VE-07 | Comodato só motorista-dono ↔ operador, com associação nominal no IMT **e na plataforma** | art. 12.º n.os 16–20 | `tvde_driver_vehicle` (associação nominal) | Nada no Bora | Manter | verde |
| VE-08 | Táxi em serviço TVDE: aviso claro ao passageiro; sem faixas BUS | art. 12.º n.º 12; art. 19.º n.º 1 f); art. 2.º n.os 4–8 | Não há campo "é táxi" | Campo + aviso no cartão | `estafeta-motorista` + `flutter-ui` | amarelo |

## 4. Operador TVDE

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| OP-01 | Operador é pessoa coletiva com licença IMT válida | arts. 2.º n.º 1, 3.º; art. 20.º n.º 5 | `tvde_operators` (NIPC, licença, validade, contrato); **0 aprovados** | Operadores reais da Guarda | Danilo contacta operadores; lista do IMT por distrito | vermelho |
| OP-02 | Obrigações próprias do operador (registo criminal anual dos gerentes, sem interesse em escolas) | art. 4.º n.º 4; art. 2.º n.º 9 | Nada (são do operador) | Cláusula no contrato operador ↔ plataforma | Incluir em PL-08 | amarelo |

## 5. Informação ao cliente (art. 19.º)

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| IN-01 | Termos e condições de acesso | art. 19.º n.º 1 a) | Minuta escrita hoje | Publicar na app depois de a AMT não se opor | Dia da licença | amarelo |
| IN-02 | Percurso e mapa digital em tempo real | art. 19.º n.º 1 c) | Mapa do cliente com a posição do carro | Nada | Manter | verde |
| IN-03 | Avaliação da viagem pelo utilizador + botão de queixas | art. 19.º n.º 1 d) | `tvde_rate` do lado do cliente | Nada (queixas em QX-01) | Manter | verde |
| IN-04 | Motorista: n.º único de registo e fotografia | art. 19.º n.º 1 e) | Cartão do motorista (em prova) | Prova material | Juiz | amarelo |
| IN-05 | Carro: fotografia, n.º de registo, matrícula, marca, modelo, lugares, ano de fabrico | art. 19.º n.º 1 f) | Cartão com foto, lugares e ano (em prova); `tvde_ride_vehicle_photo_path` | Prova + aviso de táxi (VE-08) | Juiz | amarelo |
| IN-06 | Termos da emissão da fatura eletrónica | art. 19.º n.º 1 g) | Só "Resumo da viagem" (não é fatura) | Fatura certificada (FA-01) | Depende da empresa | vermelho |
| IN-07 | Opções de serviço de transporte | art. 19.º n.º 1 h) | Viagem, reserva, paragens, ida-e-volta | Nada | Manter | verde |
| IN-08 | Poder escolher motorista que fala português | art. 19.º n.º 1 i) (remissão para o DL 237-A/2006 parece errada **[NC]**) | Opção do cliente (em prova), atrás de `tvde_client_options_enabled` | Ligar; saber quem fala português | Dia da licença | amarelo |
| IN-09 | Mobilidade reduzida: pedir carro adaptado; espera < 15 min (máx. 30); **mesmo preço**; cão-guia, cadeira de rodas e carrinho de bebé; se não houver, informar outros prestadores | art. 6.º | `tvde_client_prefs`, `tvde_mobilidade_disponivel`, `tvde_mobilidade_espera_min` = 15; matching atrás de `tvde_pref_matching_enforce` | 0 carros adaptados; lista de "outros prestadores" | Admin preenche a lista (táxis adaptados da Guarda) | amarelo |
| IN-10 | Não discriminação; recusa só nos casos da lei; animais não se recusam sem motivo | arts. 7.º e 8.º | Nada escrito para o motorista | Regras no contrato do motorista e motivos de recusa na app | PL-08 + `estafeta-motorista` | amarelo |
| IN-11 | Subscrições: gestão de conta e cancelamento a pedido | art. 19.º n.º 2 d) | Há pacote e plano TVDE; cancelamento a pedido **[A CONFIRMAR]** | Confirmar botão de cancelar | `cliente` verifica | amarelo |
| IN-12 | Avaliação da viagem **pelo utilizador e pelo motorista** | art. 19.º n.º 2 c) | `tvde_rate` dos dois lados; interruptor para esconder existe mas **não se liga** (contradição A) | Nada | Nunca ligar `tvde_driver_rates_client_disabled` | verde |

## 6. Preço e pagamento

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| PR-01 | Antes e durante a viagem: fórmula, preço total, **taxa de intermediação** e tarifas discriminadas | art. 15.º n.º 4 a); art. 19.º n.º 1 b) | `tvde_fare_breakdown` + preço discriminado antes de pedir (em prova) | Mostrar também **durante** a viagem | `flutter-ui` + prova | amarelo |
| PR-02 | Taxa de intermediação até **25 %** do valor da viagem, sem IVA | art. 15.º n.º 3 | Verificação automática (`tvde_intermediacao_verificacao`); **5 de 116 acima**: balcão 60 %, 2 pacotes ida-e-volta só com a ida (50 %), 2 corridas com paragem (26,67 %) | Repartição que nunca passe 25 % | **Proposta vermelha (dinheiro)**: paragem com parte maior para o motorista; balcão com repartição normal; pacote incompleto com acerto. Espera o "vai" | vermelho |
| PR-03 | Tarifa dinâmica só com fórmula comunicada antes | art. 15.º n.º 5 | Não há fator dinâmico (5 € até 6 km + 1 €/km) | Nada | Manter | verde |
| PR-04 | **Opção de preço fixo fechado obrigatória para qualquer percurso** | art. 15.º n.º 6 | Preço recalculado pela distância real no fim; interruptor `tvde_fixed_price_option_enabled` desligado | Construir preço fixo pela rota | **Contradição B: proposta vermelha, espera o "vai"** | vermelho |
| PR-05 | Pagamento processado pela plataforma, **só por meios eletrónicos** | art. 15.º n.º 7 | **63 de 116 corridas em dinheiro**; interruptor `tvde_electronic_payment_only` pronto (esconde o dinheiro e o servidor recusa) | Ligar; confirmar que cartão e MB Way funcionam no TVDE **[A CONFIRMAR]** | Dia da licença | vermelho |
| PR-06 | Cancelamento com penalização proporcional (sem cláusula penal desproporcionada) | DL 446/85, art. 19.º c) (cláusulas contratuais gerais); art. 5.º n.º 2 da Lei 45/2018 | Grátis até `cancel_grace_seconds` (180 s); depois o cliente paga o **valor total estimado** (`tvde_cancel_full_after_grace` = true); existe também `tvde_cancel_fee_cents` = 250 | Decidir: 2,50 € ou valor total | Proposta vermelha: taxa fixa de 2,50 € (mais defensável perante a AMT). Espera o "vai" | amarelo |

## 7. Segurança e SOS

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| SE-01 | Serviço de emergência para passageiros e motoristas: ligação às autoridades em tempo real + partilha da localização do carro | art. 19.º n.º 1 j); art. 17.º-A n.º 2 e) | Botão SOS (em prova): liga 112 pelo telefone, partilha localização, regista em `tvde_sos_events` e avisa o admin | Prova; saber se o IMT aceita a chamada pelo telefone do utilizador **[NC]** | Juiz + pergunta ao IMT | amarelo |
| SE-02 | Vídeo no carro é facultativo; se existir, só imagem, cifrado, 30 dias | art. 19.º-A | O Bora **não grava vídeo nem som** | Nada | Manter a decisão | verde |
| SE-03 | Localização e tempos não servem para vigiar o desempenho do motorista | Código do Trabalho, art. 20.º; parecer CNPD 2026/37 §129 e) | Regra escrita na avaliação de impacto | Garantir no código (ver RG-08, CT-02) | `seguranca` confirma | amarelo |

## 8. Queixas e litígios

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| QX-01 | Botão de queixas visível na **página principal** que leva ao Livro de Reclamações Eletrónico | art. 19.º n.º 2 a); DL 156/2005, art. 5.º-B n.os 1–2 | Ecrã de queixas com link oficial (em prova) | Confirmar que está na página principal | Prova | amarelo |
| QX-02 | Informar a entidade de resolução alternativa de litígios (RAL) a que a empresa está vinculada, com o site | art. 19.º n.º 2 b); Lei 144/2015, art. 18.º | Informação RAL no ecrã de queixas (em prova) | Escolher a entidade: CNIACC ou AMADRI **[NC]** | Danilo adere; atualizar o texto | amarelo |
| QX-03 | Investigar queixas e guardar o registo durante pelo menos 2 anos | art. 19.º n.º 3 | `tvde_complaints` com diligências; nunca se apaga | Prazo máximo (RG-05) | Manter | verde |
| QX-04 | Responder à reclamação do Livro em 15 dias úteis | DL 156/2005, art. 5.º-B n.º 4 | Admin de queixas | Aviso de prazo a acabar | `admin` | amarelo |
| QX-05 | Registo do fornecedor na plataforma do Livro de Reclamações Eletrónico | DL 156/2005, art. 5.º-B n.º 1 | Nada (precisa de NIF) | Registo | Danilo, depois da empresa | vermelho |
| QX-06 | Lei portuguesa e tribunais portugueses; RAL suspende prazos | arts. 21.º e 22.º | Na minuta | Publicar | Com IN-01 | amarelo |

## 9. Tempos de trabalho

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| TT-01 | Máximo de 10 h de condução TVDE em 24 h, somando todas as plataformas; a plataforma garante-o | art. 13.º n.os 1–2 | `tvde_driver_horas_24h` + `tvde_driver_horas_total`; contador de 24 h (em prova); `tvde_work_limit_enforce` desligado | Ligar | Dia da licença | amarelo |
| TT-02 | Registo dos tempos de trabalho e dos limites de condução e repouso | art. 20.º n.º 3; art. 17.º-A n.º 2 b); DL 237/2007 ou DL 117/2012 (art. 10.º n.º 18) | `tvde_driver_work_log` desde 30/09 (conta tempo online) | Separar condução, espera e pausa; é a **infração mais apanhada pela AMT** (48 de 90 autos) | Afinar depois do arranque | amarelo |
| TT-03 | Guardar 2 anos os registos de atividade | art. 13.º n.º 3 | `tvde_retencao_anos` = 2; nunca se apaga | Nada | Manter | verde |
| TT-04 | Horas noutras plataformas | art. 13.º n.º 1 | Declaração do motorista (`tvde_horas_outras_plataformas`) | Cruzamento oficial pelo IMT **[NC]** | Aguardar IM-02 | amarelo |

## 10. Fiscalização e IMT

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| IM-01 | Integração com as bases de dados do IMT; verificar operador, carta, CMTVDE e carro antes de aceitar | art. 17.º-A n.º 2 a); art. 20.º n.os 5–7 | Esqueleto "aguarda IMT"; `tvde_imt_integration_enabled` desligado | **Especificação técnica não publicada** | Pedir ao IMT por escrito como adere uma plataforma nova | vermelho |
| IM-02 | Adesão obrigatória à plataforma de partilha de dados do IMT | art. 20.º-A n.os 1–4 e 7 (portaria **por publicar [NC]**) | Nada | Adesão | Depois da licença | vermelho |
| IM-03 | Acesso das entidades fiscalizadoras à informação estritamente necessária | art. 17.º-A n.º 2 d); art. 20.º-A | Código temporário + página `app.boraguarda.com/fiscalizacao.html` + CSV/PDF, sem dados do passageiro (em prova) | Prova; é solução provisória até à portaria | Juiz | amarelo |
| IM-04 | Ficha de fiscalização do motorista (QR) | art. 10.º n.os 14–15; art. 19.º n.º 1 e)–f) | Feito a 23/09 | Nada | Manter | verde |
| IM-05 | Bloquear operadores, motoristas ou carros que não cumpram | art. 14.º n.º 2 | Cálculo diário, portão no despacho, bloqueio manual; `tvde_compliance_block` desligado; bloqueio por documento expirado já ativo desde 23/09 | Revisão humana e contestação (RG-07) | Dia da licença | amarelo |
| IM-06 | Dar ao IMT e à AMT a informação que peçam | art. 23.º n.º 2; art. 25.º n.º 2 bb) | Exportações no admin | Nada | Manter | verde |

## 11. AMT

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| AM-01 | Contribuição de 5 % **da taxa de intermediação**, autoliquidada todos os meses e paga até ao fim do mês seguinte | art. 30.º n.os 1–3 | Cálculo mensal automático (`tvde_amt_reports`, dia 1) | Pagamento (precisa de empresa) | Depois da licença | amarelo |
| AM-02 | Reporte mensal (viagens, valor faturado, taxa cobrada) no formulário da AMT | art. 30.º n.os 4–5; Deliberação AMT 75/2018 | Relatório calcula (jul 8 €, ago 111,80 €, set 491,50 €) | Formulário novo pós-2026 **[NC]** | Usar o de 2018 até haver outro | amarelo |

## 12. Faturação

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| FA-01 | Fatura eletrónica com código único da viagem, origem, destino, tempo, distância, IVA discriminado e cálculo com a taxa de intermediação | art. 15.º n.º 8 | "Resumo da viagem" (não é fatura); adaptador em modo stub; `tvde_invoicing_enabled` desligado | Empresa + software | Dia da licença | vermelho |
| FA-02 | Software certificado pela AT, com ATCUD e QR | DL 28/2019, arts. 4.º e 7.º | `tvde_invoicing_provider` = stub | Escolher fornecedor (Moloni tem ambiente de teste; InvoiceXpress; Vendus — preços **[NC]**) | Danilo + contabilista | vermelho |
| FA-03 | Comunicar faturas à AT até ao dia 5 do mês seguinte | DL 198/2012, art. 3.º | Nada | Vem com o software | Com FA-02 | vermelho |
| FA-04 | Decidir quem emite a fatura da viagem (plataforma por conta do operador ou o operador) | art. 15.º n.º 8 (lacuna **[NC]**) | Nada | Parecer do contabilista | Danilo pergunta ao contabilista | vermelho |
| FA-05 | IVA discriminado (6 % no transporte de passageiros, `tvde_iva_transporte_pct`) | art. 15.º n.º 8; taxa **[NC — confirmar com contabilista]** | `tvde_iva_discriminar` desligado | NIF e regime de IVA | Dia da licença | amarelo |

## 13. Proteção de dados (RGPD)

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| RG-01 | Política de privacidade TVDE | RGPD arts. 12.º–14.º; art. 19.º n.º 4 da Lei 45/2018 | Escrita hoje | Marcadores + publicar | Dia da licença | amarelo |
| RG-02 | Registo das atividades de tratamento | RGPD art. 30.º | Escrito hoje | Confirmar subcontratantes e regiões | `seguranca` | amarelo |
| RG-03 | Avaliação de impacto (geolocalização) | RGPD art. 35.º; Lei 58/2019; parecer CNPD §129 u) | Escrita hoje | Revisão + aplicar medidas | `seguranca` | amarelo |
| RG-04 | Sistemas verificados e certificados em auditoria sob supervisão da CNPD | art. 20.º n.º 2 | Nada | Auditoria | Depois da empresa | vermelho |
| RG-05 | Prazo **máximo** de conservação (a lei só dá o mínimo de 2 anos) | RGPD art. 5.º n.º 1 e); parecer CNPD §§80–82 | Nada se apaga | Decidir o máximo | Proposta na política (2 anos + 1 ano) **POR CONFIRMAR** | amarelo |
| RG-06 | Minimização: fiscalizadores recebem só o necessário | parecer CNPD §129 l); art. 20.º-A | `_tvde_fiscal_dados` sem nome, telefone ou email do passageiro | Nada | Manter | verde |
| RG-07 | Bloqueio não 100 % automático; intervenção humana e direito de contestar | RGPD art. 22.º; parecer CNPD §129 n) | Admin revê; contestação por queixa | Ecrã de contestação visível ao motorista | `estafeta-motorista` | amarelo |
| RG-08 | Avaliação recíproca sem perfis nem castigo automático | RGPD arts. 4.º n.º 4 e 22.º; parecer CNPD §129 m) | Avaliação guardada | Confirmar que a nota não ordena nem exclui ninguém no despacho **[A CONFIRMAR]** | `dispatch` (só ler) | amarelo |
| RG-09 | Avaliar se é preciso Encarregado de Proteção de Dados | RGPD art. 37.º | Nada | Avaliação | Advogado | amarelo |

## 14. DAC7

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| DA-01 | Recolher dados dos vendedores e comunicar à AT até 31 de janeiro; guardar 10 anos | Lei 36/2023 (altera o DL 61/2013) **[NC — fonte OCC]** | Exportação DAC7 no admin desde 23/09 (`admin_conformidade_legal_screen.dart`, `admin_export_service.dart`) | No TVDE o "vendedor" é o **operador**, não o motorista **[NC]** | Acrescentar operadores à exportação | amarelo |
| DA-02 | Registo como operador de plataforma na AT | Portaria 455-D/2023 (modelo 61) **[NC]** | Nada | Registo | Depois da empresa | vermelho |

## 15. Acessibilidade

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| AC-01 | Cumprir as regras de acessibilidade e usabilidade em vigor | art. 19.º n.º 2 e) | Flutter com acessibilidade parcial | Revisão dos ecrãs TVDE (leitor de ecrã, contraste, tamanhos) | `flutter-ui` | amarelo |
| AC-02 | Ato Europeu de Acessibilidade | DL 82/2022, art. 2.º n.º 3 c) e n.º 5 b) | TVDE não está na lista; microempresas de serviços excluídas | Nada enquanto for microempresa | Rever se crescer | verde |

## 16. Código do Trabalho (plataformas)

| Cód. | Requisito | Artigo / fonte | O que o Bora tem hoje | O que falta | Ação | Estado |
|---|---|---|---|---|---|---|
| CT-01 | Evitar indícios de contrato de trabalho: a plataforma **fixar a retribuição** é um deles | CT art. 12.º-A n.º 1 a) e n.º 12 | O Bora fixa o ganho do motorista (4 € + 0,80 €/km) e paga-lhe diretamente | Passar a pagar ao **operador**, que acerta com o motorista | Proposta vermelha (dinheiro + estrutura) com advogado | vermelho |
| CT-02 | Não castigar recusas, não impor horários, não desativar contas como castigo | CT art. 12.º-A n.º 1 d)–e) | Bloqueio só por falta de requisito legal | Confirmar que recusar ofertas não baixa prioridade **[A CONFIRMAR]** | `dispatch` (só ler) | amarelo |

---

## PARA O DANILO

1. **Corridas sem licença**: continuar, suspender ou passar a teste fechado sem cobrança até haver licença (PL-00)?
2. **Estrutura da empresa**: levar a contradição C a um advogado antes de constituir a sociedade (PL-07).
3. **"Vai" ou não** para: preço fixo (PR-04), correção dos 25 % (PR-02), taxa de cancelamento fixa de 2,50 € (PR-06) e pagamento ao operador em vez de ao motorista (CT-01).
4. **Contabilista**: quem emite a fatura, taxa de IVA, software certificado (FA-02, FA-04, FA-05).
5. **IMT por escrito**: como adere uma plataforma nova à partilha de dados, e se o SOS pelo telefone do utilizador chega (IM-01, SE-01).
