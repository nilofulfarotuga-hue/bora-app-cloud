-- tvde-conformidade-lei-59-2026 · checklist "Pronto para licenciamento" — 2026-09-30
-- Semeia public.tvde_legal_requirements a partir da matriz
-- .claude/.ai/reports/tvde-matriz-legal-2026-09-30.md (80 das 90 linhas).
-- Só INSERT com ON CONFLICT (codigo) DO UPDATE: pode correr várias vezes.
-- Não mexe em preço, comissão, ganho, pedidos nem motoristas.
-- interruptor = chave em platform_settings que liga o requisito (quando existe).

insert into public.tvde_legal_requirements
  (codigo, ordem, area, requisito, base_legal, estado, o_que_falta, interruptor)
values
-- 1. Plataforma e licença
('PL-00', 10, 'Plataforma e licença', 'Não operar TVDE sem licença de plataforma', 'Lei 45/2018 arts. 16.º, 17.º n.º 1, 25.º n.º 2, 26.º', 'vermelho', '116 corridas feitas sem licença (63 em dinheiro). Danilo decide: suspender ou teste fechado sem cobrança.', null),
('PL-01', 20, 'Plataforma e licença', 'Plataforma é pessoa coletiva', 'art. 16.º; art. 17.º n.º 4', 'vermelho', 'Constituir a sociedade depois de resolver a independência (PL-07).', null),
('PL-02', 30, 'Plataforma e licença', 'Licença IMT de plataforma (Modelo 30, 500 euros, deferimento tácito 30 dias úteis)', 'art. 17.º n.os 1 e 4', 'vermelho', 'Pedido completo ao IMT com situação fiscal e contributiva, pacto social e registos.', null),
('PL-03', 40, 'Plataforma e licença', 'Número de registo da marca', 'art. 17.º n.º 4', 'amarelo', 'Confirmar ou registar a marca Bora no INPI.', null),
('PL-04', 50, 'Plataforma e licença', 'Capacidade tecnológica desde o início (IMT, tempos, RGPD, fiscalização, emergência)', 'art. 17.º-A; Lei 59/2026 art. 4.º', 'vermelho', 'Falta a ligação ao IMT (alínea a). O resto está construído atrás do mestre.', 'tvde_compliance_enforce'),
('PL-05', 60, 'Plataforma e licença', 'Página pública com os dados do operador da plataforma', 'art. 17.º n.º 8', 'amarelo', 'Preencher denominação, NIF, sede e licença em platform_settings. Página em prova.', null),
('PL-06', 70, 'Plataforma e licença', 'Idoneidade dos gerentes e registo criminal anual ao IMT', 'art. 18.º', 'vermelho', 'Registo criminal do gerente todos os anos.', null),
('PL-07', 80, 'Plataforma e licença', 'Plataforma sem interesse direto ou indireto em operadores, carros ou escolas TVDE', 'art. 12.º n.º 5; art. 20.º n.º 11', 'vermelho', 'Contradição com o plano de uma só empresa Bora + operador. Advogado antes de constituir.', null),
('PL-08', 90, 'Plataforma e licença', 'Contrato de adesão operador-plataforma publicitado, comunicado à AMT e mostrado ao motorista', 'art. 20.º n.os 8 a 10', 'vermelho', 'Minuta para operadores por redigir.', null),
('PL-09', 100, 'Plataforma e licença', 'Minuta do contrato de adesão do passageiro enviada à AMT (20 dias)', 'art. 5.º n.os 2 a 5', 'amarelo', 'Minuta escrita a 30/09. Falta preencher, rever com advogado e enviar.', null),
('PL-10', 110, 'Plataforma e licença', 'Só por reserva prévia na plataforma; proibido apanhar na rua', 'art. 5.º n.os 1 e 6', 'amarelo', 'Rever a corrida de balcão: tem de ser pedido do cliente na app antes de começar.', null),
-- 2. Motorista
('MO-01', 200, 'Motorista', 'CMTVDE ou certificado de táxi válido', 'art. 10.º n.os 1 e 3', 'amarelo', 'Hoje é declarado pelo motorista; confirmação oficial só com a ligação ao IMT.', 'tvde_compliance_block'),
('MO-02', 210, 'Motorista', 'Carta B há mais de 3 anos com averbamento do grupo 2', 'art. 10.º n.º 2 a)', 'amarelo', 'Falta perguntar pelo grupo 2.', 'tvde_compliance_block'),
('MO-03', 220, 'Motorista', 'CMTVDE válido 5 anos; renovação com curso de 8 horas', 'art. 10.º n.os 4, 5 e 9', 'verde', null, null),
('MO-04', 230, 'Motorista', 'Número único de registo e fotografia visíveis ao passageiro', 'art. 10.º n.º 10; art. 19.º n.º 1 e)', 'amarelo', 'Cartão do motorista em prova.', null),
('MO-05', 240, 'Motorista', 'Idoneidade; registo criminal estrangeiro de quem viveu fora 6 meses nos últimos 5 anos', 'art. 11.º', 'amarelo', 'Falta a pergunta sobre residência no estrangeiro.', null),
('MO-06', 250, 'Motorista', 'Domínio funcional do português verificado no curso inicial', 'art. 10.º-A (portaria por publicar)', 'amarelo', 'Aguarda portaria. Hoje é declarado.', null),
('MO-07', 260, 'Motorista', 'Motorista entra por operador licenciado', 'art. 10.º; art. 14.º n.º 3', 'vermelho', 'Os 4 motoristas aprovados não têm operador.', 'tvde_compliance_block'),
('MO-08', 270, 'Motorista', 'Contrato escrito operador-motorista', 'art. 10.º n.º 2 e) e n.os 16 a 17', 'vermelho', 'Nenhum contrato carregado.', 'tvde_compliance_block'),
-- 3. Veículo
('VE-01', 300, 'Veículo', 'Só carros registados no IMT, inscritos pelo operador, atestados pela plataforma', 'art. 12.º n.º 1', 'vermelho', 'Zero carros registados.', 'tvde_compliance_block'),
('VE-02', 310, 'Veículo', 'Ligeiro, matrícula nacional, até 9 lugares com o condutor', 'art. 12.º n.º 6', 'amarelo', 'Validar formato de matrícula portuguesa.', null),
('VE-03', 320, 'Veículo', 'Menos de 10 anos; elétrico até 12', 'art. 12.º n.º 7', 'verde', null, 'tvde_compliance_block'),
('VE-04', 330, 'Veículo', 'Inspeção anual', 'art. 12.º n.º 8', 'verde', null, 'tvde_compliance_block'),
('VE-05', 340, 'Veículo', 'Seguro de responsabilidade civil que cubra passageiros', 'art. 12.º n.º 9', 'amarelo', 'Mudar o aviso de acidentes pessoais (saiu da lei) para RC com passageiros.', null),
('VE-06', 350, 'Veículo', 'Dístico inamovível do IMT com QR', 'art. 12.º n.os 2, 10, 13 a 15 (portaria por publicar)', 'amarelo', 'Aguarda portaria e modelo.', null),
('VE-08', 360, 'Veículo', 'Táxi em serviço TVDE: aviso ao passageiro; sem faixas BUS', 'art. 2.º n.os 4 a 8; art. 12.º n.º 12; art. 19.º n.º 1 f)', 'amarelo', 'Falta o campo é táxi e o aviso no cartão.', null),
-- 4. Operador
('OP-01', 400, 'Operador', 'Operador é pessoa coletiva com licença IMT válida', 'arts. 2.º, 3.º; art. 20.º n.º 5', 'vermelho', 'Zero operadores aprovados. Contactar operadores da Guarda.', 'tvde_compliance_block'),
('OP-02', 410, 'Operador', 'Obrigações próprias do operador no contrato com a plataforma', 'art. 2.º n.º 9; art. 4.º n.º 4; art. 14.º n.º 3', 'amarelo', 'Incluir no contrato operador-plataforma.', null),
-- 5. Informação ao cliente
('IN-01', 500, 'Informação ao cliente', 'Termos e condições de acesso', 'art. 19.º n.º 1 a)', 'amarelo', 'Publicar depois de a AMT não se opor.', null),
('IN-02', 510, 'Informação ao cliente', 'Percurso e mapa em tempo real', 'art. 19.º n.º 1 c)', 'verde', null, null),
('IN-03', 520, 'Informação ao cliente', 'Avaliação da viagem pelo utilizador', 'art. 19.º n.º 1 d)', 'verde', null, null),
('IN-04', 530, 'Informação ao cliente', 'Motorista: número único de registo e fotografia', 'art. 19.º n.º 1 e)', 'amarelo', 'Cartão em prova.', null),
('IN-05', 540, 'Informação ao cliente', 'Carro: foto, registo, matrícula, marca, modelo, lugares, ano', 'art. 19.º n.º 1 f)', 'amarelo', 'Cartão em prova; falta aviso de táxi.', null),
('IN-06', 550, 'Informação ao cliente', 'Termos da emissão da fatura eletrónica', 'art. 19.º n.º 1 g)', 'vermelho', 'Depende da faturação certificada.', 'tvde_invoicing_enabled'),
('IN-08', 560, 'Informação ao cliente', 'Escolher motorista que fala português', 'art. 19.º n.º 1 i)', 'amarelo', 'Opção em prova; ligar no dia da licença.', 'tvde_client_options_enabled'),
('IN-09', 570, 'Informação ao cliente', 'Mobilidade reduzida: carro adaptado, espera até 15 min, mesmo preço, alternativas', 'art. 6.º', 'amarelo', 'Zero carros adaptados; falta lista de outros prestadores.', 'tvde_pref_matching_enforce'),
('IN-10', 580, 'Informação ao cliente', 'Não discriminação; recusa só nos casos da lei', 'arts. 7.º e 8.º', 'amarelo', 'Regras no contrato do motorista e motivos de recusa na app.', null),
('IN-12', 590, 'Informação ao cliente', 'Avaliação pelo utilizador e pelo motorista (obrigatória)', 'art. 19.º n.º 2 c); Lei 59/2026 art. 5.º', 'verde', 'Nunca ligar tvde_driver_rates_client_disabled.', null),
-- 6. Preço e pagamento
('PR-01', 600, 'Preço e pagamento', 'Fórmula, preço total e taxa de intermediação antes e durante a viagem', 'art. 15.º n.º 4 a); art. 19.º n.º 1 b)', 'amarelo', 'Antes: em prova. Durante a viagem: falta.', null),
('PR-02', 610, 'Preço e pagamento', 'Taxa de intermediação até 25 por cento sem IVA', 'art. 15.º n.º 3', 'vermelho', '5 de 116 acima (balcão 60, ida-e-volta incompleta 50, paragem 26,67). Proposta de dinheiro espera o vai.', null),
('PR-04', 620, 'Preço e pagamento', 'Opção de preço fixo fechado para qualquer percurso', 'art. 15.º n.º 6', 'vermelho', 'Hoje o preço é recalculado pela distância real. Proposta de dinheiro espera o vai.', 'tvde_fixed_price_option_enabled'),
('PR-05', 630, 'Preço e pagamento', 'Pagamento só por meios eletrónicos, processado pela plataforma', 'art. 15.º n.º 7', 'vermelho', '63 de 116 corridas em dinheiro. Confirmar cartão e MB Way no TVDE e ligar.', 'tvde_electronic_payment_only'),
('PR-06', 640, 'Preço e pagamento', 'Cancelamento com penalização proporcional', 'DL 446/85 art. 19.º c); Lei 45/2018 art. 5.º n.º 2', 'amarelo', 'Hoje cobra o valor total após 180 s. Proposta: taxa fixa de 2,50 euros. Espera o vai.', null),
-- 7. Segurança e SOS
('SE-01', 700, 'Segurança e SOS', 'Emergência: ligação às autoridades e partilha da localização', 'art. 19.º n.º 1 j); art. 17.º-A n.º 2 e)', 'amarelo', 'Botão SOS em prova; perguntar ao IMT se a chamada pelo telefone chega.', null),
('SE-03', 710, 'Segurança e SOS', 'Localização e tempos não servem para vigiar desempenho', 'Código do Trabalho art. 20.º; parecer CNPD 2026/37', 'amarelo', 'Confirmar no código e pôr no contrato operador-plataforma.', null),
-- 8. Queixas e litígios
('QX-01', 800, 'Queixas e litígios', 'Botão de queixas na página principal que leva ao Livro de Reclamações Eletrónico', 'art. 19.º n.º 2 a); DL 156/2005 art. 5.º-B', 'amarelo', 'Ecrã em prova; confirmar que está na página principal.', null),
('QX-02', 810, 'Queixas e litígios', 'Informar a entidade RAL a que a empresa está vinculada', 'art. 19.º n.º 2 b); Lei 144/2015 art. 18.º', 'amarelo', 'Escolher e aderir (CNIACC ou AMADRI, não confirmado).', null),
('QX-03', 820, 'Queixas e litígios', 'Investigar queixas e guardar o registo pelo menos 2 anos', 'art. 19.º n.º 3', 'verde', 'Falta só o prazo máximo (RG-05).', null),
('QX-04', 830, 'Queixas e litígios', 'Responder à reclamação do Livro em 15 dias úteis', 'DL 156/2005 art. 5.º-B n.º 4', 'amarelo', 'Aviso de prazo no admin.', null),
('QX-05', 840, 'Queixas e litígios', 'Registo do fornecedor no Livro de Reclamações Eletrónico', 'DL 156/2005 art. 5.º-B n.º 1', 'vermelho', 'Precisa do NIF da empresa.', null),
('QX-06', 850, 'Queixas e litígios', 'Lei e tribunais portugueses; RAL suspende prazos', 'arts. 21.º e 22.º', 'amarelo', 'Publicar com os termos.', null),
-- 9. Tempos de trabalho
('TT-01', 900, 'Tempos de trabalho', 'Máximo 10 horas de condução em 24 horas, todas as plataformas', 'art. 13.º n.os 1 e 2', 'amarelo', 'Construído; ligar no dia da licença.', 'tvde_work_limit_enforce'),
('TT-02', 910, 'Tempos de trabalho', 'Registo dos tempos de trabalho, condução e repouso', 'art. 20.º n.º 3; art. 17.º-A n.º 2 b); art. 10.º n.º 18', 'amarelo', 'Hoje conta tempo online; separar condução, espera e pausa.', null),
('TT-03', 920, 'Tempos de trabalho', 'Guardar 2 anos os registos de atividade', 'art. 13.º n.º 3', 'verde', null, null),
('TT-04', 930, 'Tempos de trabalho', 'Horas noutras plataformas', 'art. 13.º n.º 1', 'amarelo', 'Só declaração do motorista até haver cruzamento do IMT.', null),
-- 10. Fiscalização e IMT
('IM-01', 1000, 'Fiscalização e IMT', 'Integração com as bases de dados do IMT', 'art. 17.º-A n.º 2 a); art. 20.º n.os 5 a 7', 'vermelho', 'Especificação técnica não publicada. Pedir ao IMT por escrito.', 'tvde_imt_integration_enabled'),
('IM-02', 1010, 'Fiscalização e IMT', 'Adesão à plataforma de partilha de dados do IMT', 'art. 20.º-A (portaria por publicar)', 'vermelho', 'Depois da licença.', 'tvde_imt_integration_enabled'),
('IM-03', 1020, 'Fiscalização e IMT', 'Acesso das entidades fiscalizadoras ao estritamente necessário', 'art. 17.º-A n.º 2 d); art. 20.º-A', 'amarelo', 'Código temporário e página pública em prova.', null),
('IM-04', 1030, 'Fiscalização e IMT', 'Ficha de fiscalização do motorista com QR', 'art. 10.º n.os 14 e 15; art. 19.º n.º 1 e) e f)', 'verde', null, null),
('IM-05', 1040, 'Fiscalização e IMT', 'Bloquear quem não cumpre requisitos, com revisão humana', 'art. 14.º n.º 2; RGPD art. 22.º', 'amarelo', 'Construído; ligar depois de completar motoristas, carros e operadores.', 'tvde_compliance_block'),
-- 11. AMT
('AM-01', 1100, 'AMT', 'Contribuição de 5 por cento da taxa de intermediação, mensal', 'art. 30.º n.os 1 a 3', 'amarelo', 'Calculada todos os meses; pagar quando houver empresa.', null),
('AM-02', 1110, 'AMT', 'Reporte mensal no formulário da AMT', 'art. 30.º n.os 4 e 5; Deliberação AMT 75/2018', 'amarelo', 'Relatório calcula; formulário novo não publicado.', null),
-- 12. Faturação
('FA-01', 1200, 'Faturação', 'Fatura eletrónica com código da viagem, percurso, IVA e cálculo da taxa', 'art. 15.º n.º 8', 'vermelho', 'Só Resumo da viagem; adaptador em modo stub.', 'tvde_invoicing_enabled'),
('FA-02', 1210, 'Faturação', 'Software certificado pela AT com ATCUD e QR', 'DL 28/2019 arts. 4.º e 7.º', 'vermelho', 'Escolher fornecedor com o contabilista.', 'tvde_invoicing_enabled'),
('FA-03', 1220, 'Faturação', 'Comunicar faturas à AT até dia 5', 'DL 198/2012 art. 3.º', 'vermelho', 'Vem com o software certificado.', null),
('FA-04', 1230, 'Faturação', 'Definir quem emite a fatura da viagem', 'art. 15.º n.º 8 (lacuna)', 'vermelho', 'Parecer do contabilista.', null),
('FA-05', 1240, 'Faturação', 'IVA discriminado ao cliente', 'art. 15.º n.º 8', 'amarelo', 'Só com NIF e taxa confirmada pelo contabilista.', 'tvde_iva_discriminar'),
-- 13. RGPD
('RG-01', 1300, 'RGPD', 'Política de privacidade TVDE', 'RGPD arts. 12.º a 14.º; Lei 45/2018 art. 19.º n.º 4', 'amarelo', 'Escrita a 30/09; preencher e publicar.', null),
('RG-02', 1310, 'RGPD', 'Registo das atividades de tratamento', 'RGPD art. 30.º', 'amarelo', 'Escrito a 30/09; confirmar subcontratantes e regiões.', null),
('RG-03', 1320, 'RGPD', 'Avaliação de impacto da geolocalização', 'RGPD art. 35.º; Lei 58/2019; parecer CNPD 2026/37', 'amarelo', 'Escrita a 30/09; aplicar as medidas por confirmar.', null),
('RG-04', 1330, 'RGPD', 'Auditoria dos sistemas sob supervisão da CNPD', 'art. 20.º n.º 2', 'vermelho', 'Depois da empresa.', null),
('RG-05', 1340, 'RGPD', 'Prazo máximo de conservação', 'RGPD art. 5.º n.º 1 e); parecer CNPD 2026/37', 'amarelo', 'Proposta 2 anos + 1 ano, por confirmar.', null),
('RG-06', 1350, 'RGPD', 'Fiscalizadores recebem só o necessário', 'parecer CNPD 2026/37; art. 20.º-A', 'verde', null, null),
('RG-07', 1360, 'RGPD', 'Bloqueio com intervenção humana e direito de contestar', 'RGPD art. 22.º; parecer CNPD 2026/37', 'amarelo', 'Falta o botão Contestar visível ao motorista.', 'tvde_compliance_block'),
('RG-08', 1370, 'RGPD', 'Avaliações sem perfis nem castigo automático', 'RGPD arts. 4.º n.º 4 e 22.º', 'amarelo', 'Confirmar que a nota não entra no despacho.', null),
-- 14. DAC7
('DA-01', 1400, 'DAC7', 'Dados dos vendedores comunicados à AT até 31 de janeiro', 'Lei 36/2023 (não confirmado em fonte oficial)', 'amarelo', 'No TVDE o vendedor é o operador; acrescentar à exportação.', null),
('DA-02', 1410, 'DAC7', 'Registo como operador de plataforma na AT', 'Portaria 455-D/2023 (não confirmado)', 'vermelho', 'Depois da empresa.', null),
-- 15. Acessibilidade
('AC-01', 1500, 'Acessibilidade', 'Regras de acessibilidade e usabilidade em vigor', 'art. 19.º n.º 2 e)', 'amarelo', 'Rever ecrãs TVDE: leitor de ecrã, contraste, tamanhos.', null),
-- 16. Código do Trabalho
('CT-01', 1600, 'Código do Trabalho', 'Plataforma não fixa a retribuição do motorista', 'Código do Trabalho art. 12.º-A n.º 1 a) e n.º 12', 'vermelho', 'Hoje o Bora fixa e paga o ganho do motorista. Proposta: pagar ao operador. Espera o vai e advogado.', null),
('CT-02', 1610, 'Código do Trabalho', 'Não castigar recusas nem desativar contas como castigo', 'Código do Trabalho art. 12.º-A n.º 1 d) e e)', 'amarelo', 'Confirmar no despacho que recusar não baixa prioridade.', null)
on conflict (codigo) do update set
  ordem = excluded.ordem,
  area = excluded.area,
  requisito = excluded.requisito,
  base_legal = excluded.base_legal,
  estado = excluded.estado,
  o_que_falta = excluded.o_que_falta,
  interruptor = excluded.interruptor,
  atualizado_em = now();
