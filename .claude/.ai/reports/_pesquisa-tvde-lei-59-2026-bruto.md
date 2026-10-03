# Pesquisa jurídica bruta — TVDE / Lei n.º 59/2026 (missão `tvde-conformidade-lei-59-2026`)

> Data: 30/09/2026 · Autor: pesquisador jurídico (Claude Code, subagente) · PT-PT
> Âmbito: só pesquisa. Não se tocou em código, base de dados nem Flutter.
> Legenda: **[C]** = CONFIRMADO no texto oficial lido nesta sessão · **[NC]** = NÃO CONFIRMADO em fonte oficial (indica-se a fonte secundária).
> Quem fica obrigado: **PLAT** = gestor de plataforma eletrónica (o que a Bora seria) · **OP** = operador de TVDE · **MOT** = motorista · **VEI** = veículo.

## 0. Fonte principal e como foi lida

- **Lei n.º 59/2026, de 25 de agosto** — DR, 1.ª série, n.º 164, 25/08/2026. Existe e foi lida por inteiro (42 páginas),
  incluindo o **anexo com a republicação completa da Lei n.º 45/2018**.
  - Página DR: https://diariodarepublica.pt/dr/detalhe/lei/59-2026-1161801432 (a página é uma SPA e não abre sem browser)
  - ELI do Diário: http://data.dre.pt/eli/diario/1/164/2026/0/pt/html
  - O PDF oficial do DR foi obtido através da ficha do diploma na AR: https://www.parlamento.pt/ActividadeParlamentar/Paginas/DetalheDiplomaAprovado.aspx?BID=135941
  - Processo legislativo (PPL 46/XVII ALRAM + PJL 396/XVII PSD + PJL 466/XVII CDS; aprovada 17/07/2026; promulgada 18/08; publicada 25/08): https://www.parlamento.pt/ActividadeParlamentar/Paginas/DetalheIniciativa.aspx?BID=356250
- Para comparar com o regime anterior usou-se a versão consolidada de 2018 da Lei 45/2018 (PDF da FDUC, cópia da consolidação DR): https://moodle-cdc-fc.fd.uc.pt/pluginfile.php/144/mod_folder/content/0/Consolida%C3%A7%C3%A3o%20Lei%20n.%C2%BA%2045_2018%20TVDE.pdf

**Artigos citados abaixo = numeração da Lei 45/2018 republicada pela Lei 59/2026**, salvo quando se diz "Lei 59/2026, art. X.º" (os artigos próprios da lei que altera).

---

## 1. Lei 45/2018 na versão da Lei 59/2026

### 1.1 Entrada em vigor e regime transitório

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.1.1 | A Lei 59/2026 entra em vigor no **1.º dia do mês seguinte ao da publicação → 01/09/2026**. | Lei 59/2026, art. 7.º | [C] | todos |
| 1.1.2 | O art. 33.º da **republicação** diz "primeiro dia do terceiro mês seguinte ao da sua publicação". É o texto **original de 2018** (a Lei 45/2018 entrou a 01/11/2018) que a republicação reproduz; a APTAD chamou-lhe "erro grave" (duas datas). Leitura técnica: vale o art. 7.º da Lei 59/2026 para as alterações; o art. 33.º refere-se à lei de 2018. | Lei 59/2026 art. 7.º vs. anexo art. 33.º; Observador 26/08/2026 https://observador.pt/2026/08/26/associacao-alerta-que-nova-lei-do-regime-tvde-tem-erro-grave/ | [C] texto / interpretação [NC] | — |
| 1.1.3 | Gestores de plataforma têm **120 dias** a contar da entrada em vigor para **demonstrar a capacidade tecnológica do art. 17.º-A** (≈ 30/12/2026 pela contagem corrida; forma de contagem por confirmar). | Lei 59/2026, art. 4.º n.º 1 | [C] | PLAT |
| 1.1.4 | Licenças emitidas ao abrigo da lei antiga continuam válidas até ao termo; a renovação faz-se pela lei nova. | Lei 59/2026, art. 4.º n.º 2 | [C] | PLAT/OP |
| 1.1.5 | Plataformas **já licenciadas** têm **1 ano** para demonstrar os requisitos do art. 17.º e receber licença nova (a antiga caduca com a nova). | Lei 59/2026, art. 4.º n.os 3–4 | [C] | PLAT |
| 1.1.6 | O art. 32.º republicado (60 dias plataformas / 120 dias operadores e motoristas; prorrogação até +180 dias pelo IMT) **não foi alterado** pela Lei 59/2026 (não consta da lista de artigos alterados do art. 2.º nem do aditamento do art. 3.º) — é o transitório de 2018. Pode haver quem o leia como aplicável de novo; **por confirmar** junto do IMT. | anexo art. 32.º; Lei 59/2026 arts. 2.º e 3.º | [C] texto / aplicação [NC] | — |
| 1.1.7 | Revogados: art. 1.º n.os 3 e 4; art. 3.º n.º 3; **art. 15.º n.º 4 b)** (estimativa de preço); art. 17.º n.º 3; **art. 19.º n.º 5 (proibição de avaliar passageiros)**; art. 27.º. | Lei 59/2026, art. 5.º | [C] | — |
| 1.1.8 | A Bora **não tem licença**: o regime transitório dos já licenciados **não lhe serve**. Entra pelo pedido novo (art. 17.º) e tem de cumprir o 17.º-A desde o início. | art. 17.º; Lei 59/2026 art. 4.º | [C] (dedução direta) | PLAT |

### 1.2 Acesso à atividade — plataforma (o que a Bora teria de ser)

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.2.1 | Licença do IMT, pedida por via eletrónica; **deferimento tácito a 30 dias úteis** após pagar a taxa. | art. 17.º n.º 1 | [C] | PLAT |
| 1.2.2 | Requisitos: identificação completa + representante legal, sede, email; situação fiscal e contributiva regularizada; **n.º de registo da marca**; idoneidade; **capacidade tecnológica**; **envio das cláusulas contratuais gerais à AMT**; pacto social; inscrições em registos públicos. | art. 17.º n.º 4 a)–h) | [C] | PLAT |
| 1.2.3 | Tem de ser **pessoa coletiva** (a noção de plataforma no art. 16.º exige titularidade de pessoa coletiva). | art. 16.º | [C] | PLAT |
| 1.2.4 | **Página pública na própria plataforma** com os dados dos n.os 4 e 5 do art. 17.º (exceto titulares dos órgãos e pacto social). | art. 17.º n.º 8 | [C] | PLAT |
| 1.2.5 | Licença **até 5 anos**, renovável; renovação pedida **6 meses** antes. | art. 17.º n.os 12–13 | [C] | PLAT |
| 1.2.6 | Alterações aos requisitos comunicadas ao IMT em **10 dias úteis**. | art. 17.º n.º 14 | [C] | PLAT |
| 1.2.7 | Falta superveniente de requisitos não suprida no prazo → revogação oficiosa. | art. 17.º n.os 15–16 | [C] | PLAT |
| 1.2.8 | Idoneidade dos gerentes; **envio anual** ao IMT do registo criminal dos gerentes (ou autorização de consulta). | art. 18.º | [C] | PLAT |
| 1.2.9 | **Capacidade tecnológica** (art. 17.º-A n.º 2): a) integração com as bases de dados do IMT; b) registo dos tempos de trabalho do motorista e cumprimento dos limites de condução e repouso; c) cumprimento do RGPD; d) acesso das entidades fiscalizadoras à informação estritamente necessária (art. 20.º-A); e) **serviço de emergência** do art. 19.º n.º 1 j). Supletivamente aplica-se o DL 7/2004 (comércio eletrónico). | art. 17.º-A n.os 1–3 | [C] | PLAT |
| 1.2.10 | A plataforma **não pode ser proprietária, financiar nem ter interesse direto ou indireto** em veículos TVDE, em **operadores de TVDE** nem em entidades formadoras de motoristas. | art. 12.º n.º 5; art. 20.º n.º 11 | [C] | PLAT |
| 1.2.11 | Operações de concentração de plataformas comunicadas à AMT. | art. 17.º n.º 17 | [C] | PLAT |
| 1.2.12 | Taxa IMT de licenciamento de plataforma: **500 €**; 2.ª via 30 €; averbamento 10 €. Pedido pelo **Modelo 30 IMT** para sec.dsrje@imt-ip.pt; CAE 62900, 52213 ou 52320 no objeto social. (A página do IMT ainda cita só a Lei 45/2018 — não foi atualizada para a Lei 59/2026.) | https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/licenciamento-de-operador-de-plataformas-eletronicas/ | [C] (fonte oficial IMT, regime anterior) | PLAT |
| 1.2.13 | Há **27 plataformas licenciadas** na lista do IMT de 14/05/2026, incluindo muito pequenas (Its My Ride, VemJa, Tazzi, Chofer, Klibber, Mobiz, IXAT, PVZ LEB…) — ser pequena não impede a licença. | https://www.imt-ip.pt/wp-content/uploads/2026/08/OperadoresPlataformaEletronicaTVDE-licenciados_14.05.2026-2.pdf | [C] | — |

### 1.3 Operador de TVDE

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.3.1 | Só **pessoas coletivas**; licença IMT, deferimento tácito 30 dias úteis; licença ≤ 5 anos, renovação 6 meses antes; alterações comunicadas em 10 dias. | arts. 2.º n.º 1, 3.º n.os 1, 8–10 | [C] | OP |
| 1.3.2 | Táxis (titulares de alvará) podem ser também operadores TVDE; o veículo táxi pode ser registado para TVDE, mas em serviço TVDE **não recolhe na rua, não usa praças nem faixas BUS**. | art. 2.º n.os 4–8 | [C] | OP/VEI |
| 1.3.3 | Operador não pode ter interesse em entidades formadoras. | art. 2.º n.º 9 | [C] | OP |
| 1.3.4 | Envio anual ao IMT do registo criminal dos gerentes. | art. 4.º n.º 4 | [C] | OP |
| 1.3.5 | O operador responde pelo acesso à plataforma de motoristas que não cumpram requisitos. | art. 14.º n.º 3 | [C] | OP |
| 1.3.6 | Contrato escrito operador–motorista; aplica-se o **art. 12.º do Código do Trabalho** (presunção de contrato de trabalho) independentemente do nome dado ao contrato; equipamentos = os do beneficiário ou alugados por ele. | art. 10.º n.º 2 e), n.os 16–17 | [C] | OP |
| 1.3.7 | Tempo de trabalho: DL 237/2007 (trabalhador por conta de outrem) ou DL 117/2012 (independente). | art. 10.º n.º 18 | [C] | OP/MOT |
| 1.3.8 | Taxa IMT operador, requisitos e CAE 49330: página do IMT (regime anterior). Taxa exata do operador não lida nesta sessão. | https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/licenciamento-de-operadores-de-tvde/ | [NC] (valor) | OP |

### 1.4 Motorista

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.4.1 | Só conduz quem tiver **certificado de motorista TVDE (CMTVDE) ou de motorista de táxi** válido **e** estiver inscrito em plataforma licenciada. | art. 10.º n.º 1 | [C] | MOT/PLAT |
| 1.4.2 | **Carta B há mais de 3 anos, com averbamento do grupo 2**. | art. 10.º n.º 2 a) | [C] | MOT |
| 1.4.3 | Curso de formação inicial **≥ 50 horas** (teórica + prática), válido 5 anos, frequência ≥ 80 % por módulo, **exame final de 30 perguntas, aprovação com ≥ 27**, feito pelo IMT ou centro autorizado. | art. 10.º n.os 6–8 | [C] | MOT |
| 1.4.4 | CMTVDE válido **5 anos**; renovação pedida **6 meses antes**, exige idoneidade + **curso de formação contínua de 8 horas** (substituível pelo de táxi). Dá um **número único de registo** usado em todas as plataformas. | art. 10.º n.os 2 d), 4, 5, 9, 10 | [C] | MOT |
| 1.4.5 | Certificado de táxi válido dispensa curso inicial e CMTVDE, mas exige inscrição em plataforma com n.º único de registo atribuído pelo IMT. | art. 10.º n.º 3 | [C] | MOT/PLAT |
| 1.4.6 | **Língua portuguesa**: o curso inicial passa a verificar o **domínio funcional da língua portuguesa**; sem isso não há aprovação. Conteúdos e critérios: **portaria a publicar**. | art. 10.º-A (aditado) | [C] (lei) / portaria [NC] | MOT |
| 1.4.7 | O motorista leva consigo o CMTVDE, a guia do IMT ou o certificado de táxi. | art. 10.º n.os 14–15 | [C] | MOT |
| 1.4.8 | Idoneidade: crimes contra a vida/integridade, liberdade sexual, condução perigosa/álcool, crimes no exercício da atividade; quem viveu ≥ 6 meses fora de Portugal nos últimos 5 anos apresenta registo criminal do país de residência. | art. 11.º | [C] | MOT |
| 1.4.9 | **Máximo 10 horas de condução TVDE em 24 horas**, somando todas as plataformas. | art. 13.º n.º 1 | [C] | MOT |

### 1.5 Veículo

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.5.1 | Só veículos **registados no IMT** e inscritos pelos operadores na plataforma; **a plataforma atesta o cumprimento dos requisitos**. | art. 12.º n.º 1 | [C] | PLAT/OP |
| 1.5.2 | Registo do veículo válido **5 anos**, nunca além da licença do operador. | art. 12.º n.os 3–4 | [C] | OP |
| 1.5.3 | Ligeiro de passageiros, **matrícula nacional**, **lotação ≤ 9 lugares incluindo o condutor**. | art. 12.º n.º 6 | [C] | VEI |
| 1.5.4 | **Idade inferior a 10 anos** desde a 1.ª matrícula; **elétricos puros até 12 anos**. (Antes: 7 anos.) | art. 12.º n.º 7 | [C] | VEI |
| 1.5.5 | Inspeção periódica **anual**, a primeira 1 ano após a 1.ª matrícula. | art. 12.º n.º 8 | [C] | VEI |
| 1.5.6 | Seguro de RC que cubra passageiros (valor ≥ mínimo legal). A referência antiga a "acidentes pessoais" desapareceu do n.º 9. | art. 12.º n.º 9 | [C] | OP |
| 1.5.7 | **Dístico inamovível**, com elementos antifraude (holográficos ou equivalentes), emitido pelo IMT, visível de fora, associado ao registo; tem **identificador digital (QR)** que confirma apenas: autorizado, matrícula, n.º de licença do operador, seguro válido. Modelo, taxa e regras: **portaria a publicar**. | art. 12.º n.os 2, 10, 13–15 | [C] (lei) / portaria [NC] | VEI/OP |
| 1.5.8 | **Publicidade no veículo passa a ser permitida** (nos termos do táxi). | art. 12.º n.º 11 | [C] | OP |
| 1.5.9 | Sem acesso às faixas BUS. | art. 12.º n.º 12 | [C] | MOT |
| 1.5.10 | Comodato e usufruto proibidos, **exceto** comodato motorista-proprietário ↔ operador, só se o carro for conduzido exclusivamente por esse motorista e a associação nominal constar do IMT **e da plataforma**; sem subcomodato nem cedência. | art. 12.º n.os 16–20 | [C] | OP/PLAT |
| 1.5.11 | A página do IMT sobre identificação de veículos **ainda descreve o dístico antigo amovível** (145×68 mm) — desatualizada face à lei. | https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/identificacao-de-veiculos-tvde/ | [C] (que está desatualizada) | — |

### 1.6 Contratação, acessibilidade, recusa

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.6.1 | Serviço só por **subscrição e reserva prévias na plataforma**; proibido "hailing" na rua e praças de táxi. | art. 5.º n.os 1 e 6 | [C] | PLAT/MOT |
| 1.6.2 | Contratos de adesão com utilizadores cumprem cláusulas contratuais gerais e defesa do consumidor. | art. 5.º n.º 2 | [C] | PLAT |
| 1.6.3 | **Minutas dos contratos de adesão enviadas à AMT** (e cada alteração). A AMT tem **20 dias** para mandar corrigir; silêncio = pronúncia favorável. | art. 5.º n.os 3–5 | [C] | PLAT |
| 1.6.4 | Os contratos de adesão **operador ↔ plataforma** (acesso e bloqueio de operadores, motoristas e veículos) são definidos e publicitados pela plataforma, comunicados antes à AMT, e dados a conhecer ao motorista na inscrição. | art. 20.º n.os 8–10 | [C] | PLAT |
| 1.6.5 | **Mobilidade reduzida**: opção obrigatória de pedir veículo adaptado; espera **< 15 min**, excecionalmente **≤ 30 min**; **mesmo cálculo de preço**; transporte obrigatório de cão-guia, cadeira de rodas, carrinho de bebé; se não houver, a plataforma **informa automaticamente de outros prestadores disponíveis**. | art. 6.º | [C] | PLAT/MOT |
| 1.6.6 | Não discriminação (lista longa de fatores, incluindo língua e nacionalidade). | art. 7.º | [C] | PLAT/MOT |
| 1.6.7 | Recusa só nos casos do art. 8.º; bagagem só se danificar o carro; **animais de companhia** não podem ser recusados salvo motivo atendível. | art. 8.º | [C] | MOT |

### 1.7 Preço, pagamento e fatura

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.7.1 | Tarifa por distância e/ou tempo **ou** preço fixo determinado antes da contratação. | art. 15.º n.º 1 | [C] | PLAT |
| 1.7.2 | Tarifas livres, mas o preço final tem de cobrir todos os custos do serviço. | art. 15.º n.º 2 | [C] | PLAT/OP |
| 1.7.3 | **Taxa de intermediação ≤ 25 % do valor da viagem, sem IVA.** | art. 15.º n.º 3 | [C] | PLAT |
| 1.7.4 | Antes e durante a viagem: **fórmula de cálculo** com preço total, **taxa de intermediação aplicada** e tarifas (distância, tempo, fator dinâmico) discriminados. A antiga alínea b) (estimativa do preço) foi **revogada**. | art. 15.º n.º 4 a); Lei 59/2026 art. 5.º | [C] | PLAT |
| 1.7.5 | **Tarifa dinâmica**: permitida segundo a fórmula comunicada antes. **Desapareceu o teto antigo** (majoração máx. 100 % sobre a média das 72 h anteriores). | art. 15.º n.º 5 (novo) vs. versão 2018 | [C] | PLAT |
| 1.7.6 | **Opção de preço fixo predeterminado obrigatória para qualquer itinerário**, que vincula mesmo que a viagem demore mais. | art. 15.º n.º 6 | [C] | PLAT |
| 1.7.7 | **Pagamento processado e registado pela plataforma, só por meios eletrónicos** (sem dinheiro). Já existia em 2018; mantido. | art. 15.º n.º 7 | [C] | PLAT |
| 1.7.8 | **Fatura eletrónica** ao utilizador num prazo razoável, com: código único da viagem; origem e destino; tempo e distância; total com IVA discriminado; demonstração do cálculo incluindo a taxa de intermediação. | art. 15.º n.º 8 | [C] | PLAT |

### 1.8 O que a app tem de mostrar e oferecer (art. 19.º)

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.8.1 | Termos e condições de acesso ao mercado. | art. 19.º n.º 1 a) | [C] | PLAT |
| 1.8.2 | Preço, elementos da fórmula e fator de ponderação. | art. 19.º n.º 1 b) | [C] | PLAT |
| 1.8.3 | **Percurso e mapa digital em tempo real** do trajeto do veículo. | art. 19.º n.º 1 c) | [C] | PLAT |
| 1.8.4 | Avaliação da qualidade pelo utilizador (botão por viagem) + botão de queixas. | art. 19.º n.º 1 d) | [C] | PLAT |
| 1.8.5 | **Identificação do motorista: n.º único de registo TVDE e fotografia.** | art. 19.º n.º 1 e) | [C] | PLAT |
| 1.8.6 | **Fotografia do veículo** + n.º de registo + matrícula, marca, modelo, **n.º de lugares, ano de fabrico** e, se for o caso, aviso claro de que é **táxi em serviço TVDE**. | art. 19.º n.º 1 f) | [C] | PLAT |
| 1.8.7 | Termos da emissão da fatura eletrónica. | art. 19.º n.º 1 g) | [C] | PLAT |
| 1.8.8 | Opções de serviço de transporte. | art. 19.º n.º 1 h) | [C] | PLAT |
| 1.8.9 | **Possibilidade de escolher motorista com conhecimento da língua portuguesa** (a lei remete para "n.º 2 do art. 25.º do DL 237-A/2006" — que é o Regulamento da Nacionalidade; a remissão parece errada, mas a obrigação existe). | art. 19.º n.º 1 i) | [C] (obrigação) / remissão [NC] | PLAT |
| 1.8.10 | **Serviço de emergência para utilizadores e motoristas**: **ligação telefónica em tempo real com as autoridades + partilha da localização do veículo**. | art. 19.º n.º 1 j); art. 17.º-A n.º 2 e) | [C] | PLAT |
| 1.8.11 | **Botão de queixas visível na página principal** que leva ao **Livro de Reclamações Eletrónico**, também disponível na plataforma. | art. 19.º n.º 2 a) | [C] | PLAT |
| 1.8.12 | Informação sobre **resolução alternativa de litígios** (Lei 144/2015). | art. 19.º n.º 2 b) | [C] | PLAT |
| 1.8.13 | **Avaliação da viagem pelo utilizador E pelo motorista** (avaliação recíproca é agora obrigatória). | art. 19.º n.º 2 c) | [C] | PLAT |
| 1.8.14 | Se houver subscrições: gestão de conta com cancelamento a pedido. | art. 19.º n.º 2 d) | [C] | PLAT |
| 1.8.15 | Cumprir as **regras de acessibilidade e usabilidade em vigor**. | art. 19.º n.º 2 e) | [C] | PLAT |
| 1.8.16 | Queixas: investigar e corrigir; **guardar registo de queixas e do procedimento ≥ 2 anos** (mínimo, não máximo). | art. 19.º n.º 3 | [C] | PLAT |
| 1.8.17 | Dados pessoais e histórico de percursos cumprem a lei de proteção de dados. | art. 19.º n.º 4 | [C] | PLAT |
| 1.8.18 | A **proibição de avaliar passageiros foi REVOGADA** (antigo art. 19.º n.º 5: "É proibida a criação e a utilização de mecanismos de avaliação de utilizadores por parte dos motoristas…"). | Lei 59/2026 art. 5.º; texto 2018 | [C] | — |

### 1.9 Vídeo facultativo (art. 19.º-A, aditado)

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.9.1 | Funcionalidade **facultativa**, só para segurança; **desligada por defeito**; ativa por viagem com informação prévia destacada e **aceitação expressa** do passageiro (antes de contratar) e do motorista (antes de aceitar). | art. 19.º-A n.os 1–2 | [C] | PLAT |
| 1.9.2 | **Só imagem, proibido som.** | n.º 3 | [C] | PLAT |
| 1.9.3 | Tem de haver sempre opção sem vídeo, sem agravamento; cancelamento sem penalização se o passageiro não aceitar. | n.º 4 | [C] | PLAT |
| 1.9.4 | Sinalização na app e dentro do carro. | n.º 5 | [C] | PLAT/OP |
| 1.9.5 | Imagens **cifradas e inacessíveis** à plataforma, operador, motorista e passageiro; só autoridades; acessos com **log de auditoria**. | n.os 7–8 | [C] | PLAT |
| 1.9.6 | Conservação **máx. 30 dias**, apagamento automático (salvo incidente/pedido de autoridade). | n.º 9 | [C] | PLAT |
| 1.9.7 | Proibido usar para controlo laboral, preço, perfilagem, publicidade; proibido reconhecimento facial/biometria/emoções. | n.os 10–11 | [C] | PLAT |

### 1.10 Controlo, tempos, bloqueio, dados partilhados

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.10.1 | A plataforma tem de **implementar mecanismos que garantam o limite de 10 h/24 h**. | art. 13.º n.º 2 | [C] | PLAT |
| 1.10.2 | **Conservar 2 anos** os registos de atividade de operadores, motoristas e veículos, pelo n.º único de registo. | art. 13.º n.º 3 | [C] | PLAT |
| 1.10.3 | O sistema informático **regista os tempos de trabalho do motorista e o cumprimento dos limites de condução e repouso**. | art. 20.º n.º 3; art. 17.º-A n.º 2 b) | [C] | PLAT |
| 1.10.4 | **Bloqueio obrigatório** de operadores, motoristas ou veículos que não cumpram requisitos, sempre que a plataforma saiba ou devesse saber. (A lei não diz "automático"; a CNPD recomendou intervenção humana e direito de contestação — ver §6.) | art. 14.º n.º 2 | [C] | PLAT |
| 1.10.5 | Só aceitar registo de operadores, motoristas e veículos que cumpram a lei, **verificando na plataforma de partilha de dados do IMT**: licença do operador, carta, CMTVDE/táxi; registo, matrícula, idade, inspeção e seguro do veículo — comunicando n.º de licença, n.º de certificado ou de registo e matrícula. | art. 20.º n.os 5–7 | [C] | PLAT |
| 1.10.6 | **Adesão obrigatória à plataforma de partilha de dados do IMT**; a plataforma assegura ligação, transmissão e atualização. Acedem IMT, AMT, AT, ISS, forças de segurança, com perfis diferenciados. | art. 20.º-A n.os 1–4 | [C] | PLAT |
| 1.10.7 | AT e ISS podem receber dados de gestores, operadores, motoristas e veículos ativos e períodos de atividade — por **portaria**. | art. 20.º-A n.os 5–6 | [C] (lei) / portaria [NC] | PLAT |
| 1.10.8 | Formatos, prazos, periodicidade, perfis, trilhos de auditoria, cifragem, conservação: **portaria a publicar**. | art. 20.º-A n.º 7 | [C] (lei) / portaria [NC] | PLAT |
| 1.10.9 | Responsabilidade solidária da plataforma perante o utilizador pelo cumprimento do contrato. | art. 20.º n.º 1 | [C] | PLAT |
| 1.10.10 | Sistemas verificados e certificados quanto a dados pessoais por **auditoria sob supervisão da CNPD**. | art. 20.º n.º 2 | [C] | PLAT |
| 1.10.11 | Política de preços compatível com a concorrência; AMT pode auditar. | art. 20.º n.º 4; art. 23.º n.º 3 | [C] | PLAT |
| 1.10.12 | AMT e IMT podem pedir **qualquer informação** necessária; recusar é coima. | art. 23.º n.º 2; art. 25.º n.º 2 bb) | [C] | PLAT/OP/MOT |

### 1.11 Contribuição de regulação (AMT)

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.11.1 | **Contribuição = 5 % da taxa de intermediação** cobrada em todas as operações (não 5 % do preço da viagem). | art. 30.º n.os 1–2 | [C] | PLAT |
| 1.11.2 | **Autoliquidação mensal**, sobre o mês anterior, **paga até ao último dia do mês seguinte**. | art. 30.º n.º 3 | [C] | PLAT |
| 1.11.3 | **Reporte mensal à AMT** até ao fim do mês seguinte: n.º de viagens, valor faturado individualmente, taxa de intermediação efetivamente cobrada, em **formulário aprovado pela AMT**. Suportado nas faturas; AMT pode auditar. | art. 30.º n.os 4–5 | [C] | PLAT |
| 1.11.4 | Receita: 40 % Fundo para o Serviço Público de Transportes, 30 % AMT, 30 % IMT. | art. 30.º n.º 8 | [C] | — |

### 1.12 Coimas e responsabilidades

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.12.1 | Coima **250 € a 4 500 € (pessoas singulares)** e **5 000 € a 44 000 € (pessoas coletivas)**, para todas as alíneas a) a ff). (Em 2018: 2 000–4 500 € / 5 000–15 000 €.) Tentativa e negligência puníveis. | art. 25.º n.os 2–3 | [C] | todos |
| 1.12.2 | Imputáveis à **plataforma**: d), e), g), h), l), o), r), s), t), u), v), w), x), y), z), aa), bb), cc), dd), ee) — inclui falta de mecanismo 10 h (r), não bloquear (s), preços (t), falta de informação de preço/fatura (u), falta da informação do art. 19.º n.º 1 (w), falta de LRE/RAL (x), falta de registo de tempos (y), não guardar queixas 2 anos (z), falhar a partilha de dados do IMT (aa), atraso no reporte/pagamento à AMT (cc, dd). | art. 25.º-B n.º 3 | [C] | PLAT |
| 1.12.3 | Sanção acessória: **interdição da atividade até 2 anos**. | art. 26.º | [C] | todos |
| 1.12.4 | Quem processa: IMT (licenças, veículos, dístico, bloqueio, preços), AMT (contratos, informação, contribuição), ACT (tempos 10 h e registo), AT/ISS (dados fiscais). | art. 25.º-A | [C] | — |
| 1.12.5 | Fiscalizam: IMT, AMT, ACT, ISS, GNR, PSP, AT, CNPD. | art. 24.º | [C] | — |

### 1.13 Litígios

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 1.13.1 | Lei portuguesa e tribunais portugueses para litígios com consumidores. | art. 21.º | [C] | PLAT/OP |
| 1.13.2 | RAL pela Lei 144/2015; o recurso a RAL suspende o prazo para ação judicial. | art. 22.º | [C] | — |

---

## 2. Sites do IMT

| ID | Ponto | Fonte | Grau |
|---|---|---|---|
| 2.1 | Páginas existentes: licenciamento de operador de plataforma, licenciamento de operadores TVDE, certificação de motoristas, identificação de veículos. **Todas ainda citam só a Lei 45/2018** (sem a Lei 59/2026) e descrevem o dístico antigo. | https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/ | [C] |
| 2.2 | O IMT anuncia que **"já entrou em funcionamento a nova plataforma de partilha e comunicação de dados"**, desenvolvida **em parceria com a Uber e a Bolt**. | mesma página | [C] |
| 2.3 | **Especificação técnica / API pública de integração: não encontrada.** A lei remete a definição técnica para **portaria** (art. 20.º-A n.º 7). Estado: **ainda não publicado** (nada encontrado até 30/09/2026). | art. 20.º-A n.º 7; pesquisa IMT + imprensa | [NC] — "ainda não publicado" |
| 2.4 | Formação: Portaria n.º 293/2018 (cursos inicial 50 h e contínuo 8 h); pedido de CMTVDE pelos Serviços Online do IMT (10 % de desconto online). | https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/certificacao-de-motoristas-tvde/ | [C] |
| 2.5 | Lista de operadores TVDE por denominação e por distrito publicada (05/08/2026) — útil para validar operadores da Guarda. | páginas IMT acima | [C] |

## 3. Portarias / deliberações depois de 25/08/2026

| ID | Ponto | Fonte | Grau |
|---|---|---|---|
| 3.1 | **Nenhuma portaria encontrada** sobre dístico (art. 12.º n.º 15), língua portuguesa (art. 10.º-A n.º 3), partilha de dados (art. 20.º-A n.os 5 e 7), formação (art. 10.º n.º 12) ou taxas. A imprensa (Observador, leitvde.pt a 30/08) confirma que a regulamentação está pendente e que as associações de táxis pediram esclarecimentos ao IMT. | https://observador.pt/especiais/lei-ja-mudou-e-ha-centenas-de-pedidos-mas-taxis-ainda-nao-podem-funcionar-como-tvde-ninguem-sabe-dizer-nada/ ; https://leitvde.pt/en/atualizacoes/ | [NC] (ausência não provável no DR por a pesquisa do DR ser SPA) |
| 3.2 | A lei manda o conselho diretivo do IMT aprovar o modelo do CMTVDE em 30 dias — é norma de 2018 (art. 32.º n.º 2), não nova. | art. 32.º n.º 2 | [C] |

## 4. AMT

| ID | Ponto | Fonte | Grau |
|---|---|---|---|
| 4.1 | Contribuição de 5 % e reporte mensal: ver 1.11. | art. 30.º | [C] |
| 4.2 | Formulário de autoliquidação: **Deliberação AMT n.º 75/2018, de 20/09/2018**, alterada a 31/10/2018 (novo modelo). Ainda é o que está publicado; **não se encontrou formulário novo** pós-Lei 59/2026. | https://www.amt-autoridade.pt/gest%C3%A3o-do-conhecimento/modo-rodovi%C3%A1rio/ ; https://www.amt-autoridade.pt/media/1804/novo_modelo_formulario_tvde_crs.pdf ; modelo: https://www.amt-autoridade.pt/media/1803/modelo-do-formulario_tvde.pdf | [C] |
| 4.3 | Minutas de contratos de adesão (utilizadores e operadores) enviadas à AMT; 20 dias para a AMT se opor. Canal/endereço de envio **não encontrado** no site da AMT. | art. 5.º n.os 3–5; art. 20.º n.os 8–9 | [C] lei / canal [NC] |
| 4.4 | A AMT fiscaliza no terreno: em 2025/2026 a **principal infração foi a falta de registo dos tempos de trabalho** (48 de 90 autos numa ação). | https://www.amt-autoridade.pt/media/6082/amt-fiscaliza-no-terreno-a-atividade-transportes-tvde_.pdf | [C] |

## 5. Livro de Reclamações Eletrónico e RAL

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 5.1 | Todos os prestadores têm de ter o **formato eletrónico** do livro de reclamações. | DL 156/2005, art. 5.º-B n.º 1 (aditado pelo DL 74/2017) — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?nid=737&tabela=leis | [C] | PLAT |
| 5.2 | **Divulgar no site, em local visível e destacado, o acesso à plataforma do Livro de Reclamações** (livroreclamacoes.pt). | DL 156/2005, art. 5.º-B n.º 2 | [C] | PLAT |
| 5.3 | **Responder ao consumidor em ≤ 15 dias úteis** para o email do formulário. | art. 5.º-B n.º 4 | [C] | PLAT |
| 5.4 | Falta do LRE / da divulgação = contraordenação económica **grave**; resposta fora de prazo = **leve** (RJCE); há advertência prévia de 90 dias para os n.os 1–3. | arts. 9.º e 9.º-A | [C] | PLAT |
| 5.5 | Na lei TVDE: botão de queixas na página principal → LRE (1.8.11). A AMT é a entidade reguladora do setor e publicou manual do ícone LRE. | art. 19.º n.º 2 a); https://www.amt-autoridade.pt/media/2053/manual_utilizacao_icone_lre.pdf | [C] | PLAT |
| 5.6 | **RAL**: informar os consumidores das entidades de RAL **a que a empresa está vinculada** (por adesão ou arbitragem necessária) com o **site** delas, no site e nos contratos de adesão ou noutro suporte duradouro. | Lei 144/2015, art. 18.º (red. DL 102/2017) — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?nid=2425&tabela=leis&so_miolo=S | [C] | PLAT |
| 5.7 | Centro competente para a Guarda: **CNIACC** (Centro Nacional de Informação e Arbitragem de Conflitos de Consumo, competência nacional supletiva, sem limite de valor, www.cniacc.pt). Existe também a **AMADRI** (Guarda, Parque Industrial) indicada para o distrito da Guarda. | Banco de Portugal (lista RACE por distrito) e pesquisa; cniacc.pt | [NC] (não li página oficial com a delimitação territorial) |

## 6. RGPD e CNPD (geolocalização, conservação)

| ID | Ponto | Fonte | Grau |
|---|---|---|---|
| 6.1 | **Parecer CNPD 2026/37 (PAR/2026/38), aprovado 02/06/2026**, sobre o projeto que deu a Lei 59/2026. Documento oficial da CNPD (anexo ao processo na AR). | https://www.parlamento.pt/ActividadeParlamentar/Paginas/DetalheIniciativa.aspx?BID=356250 ("Contributos - CNPD") | [C] |
| 6.2 | Localização: aplicar **minimização** e as **Diretrizes 01/2020 do CEPD**, porque a localização revela padrões e dados sensíveis (recomendação d). | Parecer CNPD, §129 d) | [C] |
| 6.3 | Acompanhamento do trajeto e registo de tempos podem ser **meio de vigilância à distância proibido para controlo de desempenho** (art. 20.º do CT) — densificar (recomendação e). | §129 e) | [C] |
| 6.4 | O "≥ 2 anos" do art. 19.º n.º 3 deixa guardar para sempre; a CNPD quer **prazo máximo certo** (recomendação k). **A lei publicada manteve "não inferior a dois anos"** → a Bora tem de fixar ela própria um máximo (princípio da limitação da conservação, RGPD art. 5.º n.º 1 e)). | §§80–82 e §129 k); art. 19.º n.º 3 | [C] |
| 6.5 | **Avaliação recíproca**: prever salvaguardas contra **perfis** (RGPD art. 4.º n.º 4 e art. 22.º) (recomendação m). | §129 m) | [C] |
| 6.6 | **Bloqueio**: afastar execução **algorítmica automatizada**; exigir **intervenção humana** e **direito de contestação** (recomendação n). A lei final não o disse expressamente, mas o RGPD art. 22.º aplica-se. | §129 n) | [C] (recomendação) |
| 6.7 | **Avaliação de impacto (AIPD) obrigatória** (Lei 43/2004 art. 18.º n.º 4 + Lei 58/2019 art. 7.º) (recomendação u). | §129 u) | [C] |
| 6.8 | Privacidade desde a conceção, pseudonimização, **respostas binárias de validade em vez de dados em bruto**, logs de acesso (recomendação l). | §129 l) | [C] |
| 6.9 | **Diretiva (UE) 2024/2831 (trabalho em plataformas / gestão algorítmica) — prazo de transposição 02/12/2026.** Vai acrescentar obrigações de transparência algorítmica e revisão humana. | §129 o) | [C] (prazo, segundo a CNPD) |
| 6.10 | Não se encontrou deliberação/diretriz específica da CNPD sobre TVDE para além deste parecer. | pesquisa cnpd.pt não feita a fundo | [NC] |

## 7. Faturação

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 7.1 | **Software certificado pela AT obrigatório** sempre que: volume de negócios > 50 000 € no ano anterior (ou anualizado no 1.º ano), **ou** use programa informático de faturação, **ou** tenha contabilidade organizada (uma Lda tem). Na prática, a Bora Lda **tem de usar software certificado**. | DL 28/2019, art. 4.º n.º 1 — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?nid=3015&tabela=leis | [C] (texto) / leitura "ou" [NC] | PLAT |
| 7.2 | **QR code e código único de documento (ATCUD)** em faturas e documentos fiscalmente relevantes; séries numeradas de forma contínua; registo em base de dados incluindo anulados; modo treino identificado. | DL 28/2019, art. 7.º n.os 3–6 | [C] | PLAT |
| 7.3 | Especificação do QR/ATCUD: Portaria n.º 195/2020. | referida no DL 28/2019 art. 7.º n.º 3 | [NC] (portaria não lida) | PLAT |
| 7.4 | **Comunicação e-fatura à AT até ao dia 5 do mês seguinte** (em tempo real, por SAF-T (PT) ou no Portal). Quem é obrigado a produzir SAF-T tem de usar tempo real ou ficheiro SAF-T. | DL 198/2012, art. 3.º n.os 1–3 — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?nid=1782&tabela=leis | [C] | PLAT |
| 7.5 | Lacuna de modelo: **quem emite a fatura da viagem** (a plataforma em nome do operador — faturação por terceiros/autofaturação — ou o operador)? O art. 15.º n.º 8 obriga a plataforma a **enviar** a fatura, não diz em nome de quem. Precisa de contabilista/AT. | art. 15.º n.º 8 | [NC] | PLAT/OP |
| 7.6 | **Comparação curta** (fontes comerciais, não oficiais): **InvoiceXpress** (Visma) — API REST v2/v3 com chave, inclui exportação SAF-T; planos por n.º de documentos (X3 3 €/mês, X10 7 €, X100 20 €) → caro para 1 fatura por viagem. **Moloni** — API com **Sandbox** documentada; API só em planos pagos (Flex ~10,90 €/mês; Pro 15,90 €); certificado AT n.º 2860. **Vendus** (Cegid) — API ("ws"), desde ~6,25 €/mês, 30 dias grátis; modo de teste não confirmado. | https://invoicexpress.com/planos-precos/ ; https://www.moloni.pt/dev/ ; https://sitesmaisuteis.pt/moloni-precos/ ; https://www.vendus.pt | [NC] (preços por fonte secundária) | — |

## 8. DAC7

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 8.1 | **A transposição é a Lei n.º 36/2023, de 26 de julho** (altera o DL 61/2013) — **não o "DL 41/2023"** do pedido. | OCC, "DAC 7 – Regime de comunicação… (Lei n.º 36/2023)", 03/08/2023 — https://portal.occ.pt/sites/default/files/public/2023-08/DAC7_4.pdf | [NC] (fonte OCC, qualificada mas não oficial; texto no DR não lido) | PLAT |
| 8.2 | Atividades relevantes incluem **"prestação de um serviço pessoal"** e aluguer de meios de transporte → uma viagem TVDE intermediada é atividade relevante; o "vendedor" é o **operador TVDE**. | OCC | [NC] | PLAT |
| 8.3 | Recolher do vendedor entidade: denominação, endereço, NIF (e Estado emissor), n.º IVA, registo comercial, estabelecimentos estáveis; de pessoa singular: nome, morada, NIF, data de nascimento. Verificar fiabilidade. | OCC | [NC] | PLAT |
| 8.4 | **Comunicar à AT até 31 de janeiro** do ano seguinte. | OCC | [NC] | PLAT |
| 8.5 | **Conservar registos 10 anos**. | OCC | [NC] | PLAT |
| 8.6 | Se o vendedor não der os dados após 2 avisos em 60 dias: **fechar a conta** ou **reter pagamentos**. | OCC | [NC] | PLAT |
| 8.7 | Coima por falta/atraso de registo ou comunicação: **500 € a 22 500 €**. Registo de operadores: Portaria 455-D/2023 (modelo 61). | OCC; pesquisa | [NC] | PLAT |

## 9. Ato Europeu de Acessibilidade

| ID | Requisito | Fonte | Grau | Obriga |
|---|---|---|---|---|
| 9.1 | Transposição: **DL n.º 82/2022, de 6 de dezembro** (Diretiva 2019/882). Produz efeitos a **28/06/2025**. | DL 82/2022, arts. 1.º, 39.º — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?nid=3669&tabela=leis&so_miolo= | [C] | — |
| 9.2 | Nos transportes, só abrange sites/apps/bilhética/info em tempo real do transporte **aéreo, de autocarro, ferroviário, marítimo e fluvial** — **TVDE não está na lista**. | art. 2.º n.º 3 c) | [C] | — |
| 9.3 | Mas abrange **"serviços de comércio eletrónico"** — uma app que vende viagens ao consumidor pode cair aqui. | art. 2.º n.º 3 g) | [C] texto / enquadramento TVDE [NC] | PLAT |
| 9.4 | **Microempresas que prestam serviços estão excluídas.** (< 10 pessoas e ≤ 2 M€ volume/balanço, pela definição da Diretiva.) A Bora, enquanto microempresa, fica fora. | art. 2.º n.º 5 b); art. 3.º remete para definições da Diretiva | [C] | PLAT |
| 9.5 | Independentemente do DL 82/2022, a **lei TVDE obriga a cumprir "as regras de acessibilidade e usabilidade em vigor"**. | Lei 45/2018 art. 19.º n.º 2 e) | [C] | PLAT |

## 10. Código do Trabalho, art. 12.º-A (plataformas)

| ID | Requisito | Fonte | Grau |
|---|---|---|---|
| 10.1 | Presume-se contrato de trabalho quando se verifiquem **algumas** destas características: a) plataforma **fixa a retribuição** ou limites máx./mín.; b) **poder de direção** / regras específicas de apresentação, conduta perante o cliente ou prestação; c) **controla e supervisiona, incluindo em tempo real**, ou verifica a qualidade por meios eletrónicos ou **gestão algorítmica**; d) **restringe autonomia**: horário, ausências, **aceitar/recusar tarefas**, subcontratar/substituir, **através de sanções**, escolha de clientes, trabalhar para terceiros; e) **poder disciplinar**, incluindo **desativação da conta**; f) equipamentos pertencem à plataforma ou são alugados por ela. | CT art. 12.º-A n.º 1 (Lei 13/2023) — https://www.pgdlisboa.pt/leis/lei_mostra_articulado.php?artigo_id=1047A0012A&nid=1047&tabela=leis&pagina=1&ficha=1&so_miolo=&nversao= | [C] |
| 10.2 | **Aplica-se expressamente às plataformas TVDE.** | CT art. 12.º-A n.º 12 | [C] |
| 10.3 | Pode ser ilidida provando **autonomia efetiva**; a plataforma pode alegar que o motorista trabalha para um **intermediário** (o operador TVDE) — então o tribunal decide quem é o empregador; **responsabilidade solidária** plataforma + intermediário + gerentes pelos créditos dos últimos 3 anos. | n.os 4–6, 8 | [C] |
| 10.4 | A plataforma **não pode** dar condições mais desfavoráveis a quem trabalha direto com ela do que a quem vem por intermediário. | n.º 7 | [C] |
| 10.5 | Falsa autonomia = **contraordenação muito grave**; reincidência → perda de apoios públicos e concursos até 2 anos. | n.os 10–11 | [C] |
| 10.6 | O que a app **não deve fazer** (derivado de 10.1): fixar o ganho do motorista sem margem de negociação ou impor mín./máx.; penalizar recusas (ex.: baixar prioridade, suspender, cortar acesso por taxa de aceitação); impor horários/turnos; impor código de vestuário/guião de conduta; supervisão em tempo real para avaliar desempenho; desativar conta como castigo disciplinar (o bloqueio do art. 14.º deve ser só por falta de requisito legal, documentado); fornecer/alugar o carro ou telemóvel. **Tensão**: a lei TVDE obriga a mapa em tempo real, registo de tempos, avaliação e bloqueio — usá-los **só para os fins legais** e nunca como controlo disciplinar. | dedução de 10.1 + Parecer CNPD e) | [NC] (é interpretação, não texto) |

---

## Valores numéricos confirmados (no texto oficial)

| Valor | O quê | Fonte |
|---|---|---|
| 01/09/2026 | entrada em vigor da Lei 59/2026 | Lei 59/2026 art. 7.º |
| 120 dias | plataformas provarem capacidade tecnológica (art. 17.º-A) | Lei 59/2026 art. 4.º n.º 1 |
| 1 ano | plataformas já licenciadas pedirem licença nova | Lei 59/2026 art. 4.º n.º 3 |
| 30 dias úteis | deferimento tácito da licença (plataforma e operador) | arts. 3.º n.º 1, 17.º n.º 1 |
| ≤ 5 anos | licença de plataforma / de operador; registo do veículo; CMTVDE | arts. 17.º n.º 12, 3.º n.º 8, 12.º n.º 3, 10.º n.º 4 |
| 6 meses | antecedência para renovar licenças e CMTVDE | arts. 17.º n.º 13, 3.º n.º 9, 10.º n.º 5 |
| 10 dias úteis | plataforma comunicar alterações ao IMT | art. 17.º n.º 14 |
| 10 dias | operador comunicar alterações ao IMT | art. 3.º n.º 10 |
| 20 dias | AMT opor-se às minutas de contratos de adesão | art. 5.º n.º 4 |
| 15 min / 30 min | espera máxima normal / excecional para veículo adaptado | art. 6.º n.os 2–3 |
| > 3 anos | carta B com grupo 2 | art. 10.º n.º 2 a) |
| ≥ 50 h | curso inicial de motorista | art. 10.º n.º 6 |
| 80 % | frequência mínima por módulo | art. 10.º n.º 7 |
| 27/30 | respostas certas para aprovar no exame final | art. 10.º n.º 8 |
| 8 h | curso de formação contínua | art. 10.º n.º 9 |
| 6 meses em 5 anos | residência no estrangeiro que obriga a registo criminal estrangeiro | art. 11.º n.º 3 |
| ≤ 9 lugares | lotação incluindo o condutor | art. 12.º n.º 6 |
| < 10 anos / ≤ 12 anos | idade do veículo / elétrico puro | art. 12.º n.º 7 |
| anual | inspeção (1.ª a 1 ano da matrícula) | art. 12.º n.º 8 |
| 10 h em 24 h | limite de condução TVDE | art. 13.º n.º 1 |
| 2 anos | conservação dos registos de atividade | art. 13.º n.º 3 |
| ≤ 25 % s/ IVA | taxa de intermediação | art. 15.º n.º 3 |
| ≥ 2 anos | conservação do registo de queixas | art. 19.º n.º 3 |
| ≤ 30 dias | conservação das imagens de vídeo | art. 19.º-A n.º 9 |
| 250–4 500 € / 5 000–44 000 € | coimas singulares / coletivas | art. 25.º n.º 2 |
| ≤ 2 anos | interdição de atividade (acessória) | art. 26.º n.º 3 |
| 5 % da taxa de intermediação | contribuição AMT | art. 30.º n.º 2 |
| último dia do mês seguinte | pagamento e reporte mensal à AMT | art. 30.º n.os 3–4 |
| 40/30/30 % | repartição da contribuição (FSPT/AMT/IMT) | art. 30.º n.º 8 |
| 60/20/20 % | repartição das coimas (Estado/IMT/fundo) | art. 28.º |
| 500 € | taxa IMT de licenciamento de plataforma (página IMT, regime anterior) | site IMT |
| 15 dias úteis | resposta a reclamação do LRE | DL 156/2005 art. 5.º-B n.º 4 |
| 90 dias | advertência prévia antes de coima do LRE | DL 156/2005 art. 9.º-A |
| dia 5 do mês seguinte | comunicação e-fatura | DL 198/2012 art. 3.º n.º 2 |
| 50 000 € | limiar de volume de negócios p/ software certificado (um dos critérios) | DL 28/2019 art. 4.º n.º 1 a) |
| 28/06/2025 | efeitos do DL 82/2022 (acessibilidade) | DL 82/2022 art. 39.º |
| 02/12/2026 | prazo de transposição da Diretiva 2024/2831 (segundo a CNPD) | Parecer CNPD §129 o) |
| 3 anos | responsabilidade solidária por créditos laborais (CT 12.º-A) | CT art. 12.º-A n.º 8 |

Não confirmados em fonte oficial: DAC7 — 31 janeiro, 10 anos, 500–22 500 € (fonte OCC); preços de software de faturação (fontes comerciais).

## Lacunas (não foi possível confirmar)

1. **Portarias da Lei 59/2026** (dístico + QR, língua portuguesa, partilha de dados/AT-ISS, formação, taxas): nenhuma encontrada até 30/09/2026. A pesquisa no DR é SPA e não permite prova negativa absoluta.
2. **Especificação técnica/API da plataforma de partilha de dados do IMT**: não publicada; o IMT diz que já funciona com Uber e Bolt. Não se sabe como uma plataforma nova adere.
3. **Formulário AMT pós-2026**: só existe o de 2018 (Deliberação 75/2018). Canal de envio das minutas de contratos de adesão não encontrado.
4. **Qual transitório vale** para plataformas novas: art. 4.º da Lei 59/2026 vs. art. 32.º republicado (60/120 dias) — e a data do art. 33.º (erro apontado pela APTAD). Pedir posição escrita ao IMT.
5. **Contagem exata dos 120 dias** (corridos → ~30/12/2026; se úteis, mais tarde).
6. **Remissão do art. 19.º n.º 1 i)** para o DL 237-A/2006 (Regulamento da Nacionalidade): parece erro de redação; a obrigação de oferecer motorista que fala português existe, mas o critério de "conhecimento" não está definido.
7. **Quem emite a fatura da viagem** (plataforma por conta do operador ou o operador) e regime de IVA da taxa de intermediação: precisa de contabilista.
8. **DAC7**: texto da Lei 36/2023 no DR não lido diretamente; dados vêm da OCC.
9. **Centro de arbitragem da Guarda**: CNIACC (nacional) e AMADRI indicados por fontes secundárias; delimitação territorial oficial não lida.
10. **Taxas IMT** atualizadas (operador, veículo, dístico novo): só a da plataforma (500 €) foi vista, e é do regime anterior.
11. **Acessibilidade (DL 82/2022)**: se uma app TVDE conta como "comércio eletrónico" não está esclarecido — irrelevante enquanto a Bora for microempresa.
12. **CNPD**: não se procurou a fundo deliberações próprias sobre geolocalização em TVDE além do parecer de 2026.
13. **Portaria 195/2020** (QR/ATCUD) e **Portaria 293/2018** (formação) não foram lidas.

## PARA O DANILO

- Decidir se a Bora TVDE avança como **plataforma licenciada** (empresa + licença IMT 500 € + contrato com a AMT + partilha de dados IMT + software de faturação certificado) — sem empresa e sem licença, nada disto pode ir para o ar.
- Atenção a **conflito de interesses**: a plataforma não pode ter interesse direto ou indireto em **operadores TVDE** nem em veículos TVDE (arts. 12.º n.º 5 e 20.º n.º 11). Se o Danilo ou a empresa dele forem operador TVDE, isso tem de ser visto por advogado antes de pedir a licença.
