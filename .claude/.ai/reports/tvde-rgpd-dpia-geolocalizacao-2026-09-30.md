# Avaliação de Impacto (AIPD) — Geolocalização de motoristas e passageiros no TVDE Bora

> 30/09/2026 · agente `compliance-pt` · RGPD art. 35.º; Lei n.º 58/2019; parecer da CNPD 2026/37 (PAR/2026/38, de 02/06/2026) §129 d), e), l), m), n), u).
> Porque é obrigatória: acompanhamento sistemático da localização, de trabalhadores e em escala regular. A própria CNPD disse que a AIPD é obrigatória neste setor (parecer §129 u)).
> Estado: **primeira versão**, para rever com o advogado e reavaliar no dia da licença. Não foi pedida opinião aos titulares (art. 35.º n.º 9). Recomenda-se ouvir pelo menos 2 motoristas.

## 1. O que se trata

| Fluxo | Quem | Quando | Para quê | Onde |
|---|---|---|---|---|
| Posição e sinal do motorista | motorista | enquanto está **ligado** (disponível) e em viagem | escolher o carro mais perto, mostrar o carro ao passageiro, SOS, fechar o período de serviço quando não há sinal (`tvde_work_log_sweep`) | `drivers` (última posição, `last_heartbeat_at`) |
| Percurso da viagem | motorista e passageiro | durante a viagem | preço pela distância, fatura (art. 15.º n.º 8), registo de atividade (art. 13.º n.º 3) | `tvde_rides` |
| Local de recolha e destino | passageiro | no pedido | prestar o transporte | `tvde_rides` |
| Posição no SOS | ambos | quando se carrega no SOS | emergência (art. 19.º n.º 1 j)) | `tvde_sos_events` |
| Períodos em serviço | motorista | ligado / desligado | limite de 10 h (art. 13.º) | `tvde_driver_work_log` |
| Dados para a fiscalização | motorista, veículo | a pedido de autoridade | art. 20.º-A | `_tvde_fiscal_dados` |

**Necessidade e proporcionalidade.** Sem localização não há despacho nem o mapa em tempo real que a lei exige (art. 19.º n.º 1 c)). Os tempos de trabalho e a sua conservação são obrigação legal (arts. 13.º e 20.º n.º 3). A recolha fora do serviço **não é necessária** e não deve existir.

## 2. Riscos

| # | Risco | Para quem | Probabilidade | Gravidade | Nível |
|---|---|---|---|---|---|
| R1 | A localização revela rotinas, casa, trabalho, saúde ou religião (idas regulares a um hospital ou a uma igreja) | ambos | média | alta | **alto** |
| R2 | Usar a posição e os tempos para **vigiar o desempenho** do motorista (proibido pelo art. 20.º do Código do Trabalho; parecer CNPD §129 e)) e criar indício de contrato de trabalho (CT art. 12.º-A n.º 1 c)) | motorista | média | alta | **alto** |
| R3 | **Bloqueio 100 % automático** por um documento mal lido, sem pessoa a rever e sem forma de contestar (RGPD art. 22.º; parecer CNPD §129 n)) | motorista | média | alta (perde rendimento) | **alto** |
| R4 | Usar as avaliações ou a localização como **disciplina** (baixar prioridade, desligar a conta, castigar recusas), criando perfis (RGPD art. 4.º n.º 4; CNPD §129 m); CT art. 12.º-A n.º 1 d)–e)) | ambos | média | alta | **alto** |
| R5 | Recolher a localização do passageiro fora do pedido ou da viagem | passageiro | baixa **[A CONFIRMAR no código]** | média | médio |
| R6 | Guardar para sempre (a lei só dá o mínimo de "2 anos"; CNPD §§80–82) | ambos | alta (hoje nada se apaga) | média | **alto** |
| R7 | Acesso de fiscalização abusivo ou demasiado largo (código partilhado, agente falso) | ambos | baixa | alta | médio |
| R8 | O motorista vê a morada do passageiro depois da viagem; o passageiro vê a posição do motorista fora da viagem | ambos | baixa | média | médio |
| R9 | Dados de mobilidade reduzida (saúde) expostos ao motorista para além do necessário | passageiro | baixa | alta | médio |
| R10 | Transferência para fora da UE por subcontratantes (mapas, notificações, pagamentos) | ambos | média | média | médio |
| R11 | Violação de dados (fuga da base de dados) | ambos | baixa | alta | médio |

## 3. Medidas

| Risco | Medida | Estado |
|---|---|---|
| R1, R5 | Passageiro: localização **só durante o pedido e a viagem**. Motorista: **só enquanto está ligado**; ao desligar, a recolha pára. | política escrita; **confirmar no código** (`estafeta-motorista` e `cliente`) |
| R1 | Guardar só a **última posição** do motorista (sobrescrita), não um histórico contínuo; o percurso fica apenas com a viagem | **[A CONFIRMAR se há tabela de histórico de posições]** |
| R2 | **Regra escrita:** a localização, os tempos e as avaliações **não** servem para medir nem pontuar o desempenho do motorista. Os tempos servem só para o limite legal das 10 h e para mostrar à ACT e ao IMT. | escrita aqui e na política; incluir no contrato operador ↔ plataforma |
| R2 | Os ecrãs do admin mostram horas por motorista **só para o limite legal**; não há rankings de produtividade | verificar no painel "Conformidade TVDE" |
| R3 | **Bloqueio não 100 % automático** (recomendação da CNPD): o cálculo diário marca os motivos, o **admin revê** na secção Conformidade TVDE e o motorista vê o motivo e pode **contestar** pelo botão de queixas. Só **documento legal caducado ou em falta** bloqueia; nunca a nota nem a taxa de aceitação. | desenho feito (`tvde_compliance_block` desligado; descrição na base de dados já diz isto); falta um "Contestar" bem visível para o motorista |
| R3 | Histórico de cada bloqueio e desbloqueio, com quem decidiu e porquê | feito (`tvde_compliance_events`, `bloqueio_manual_por`) |
| R4 | A avaliação do passageiro pelo motorista é **obrigatória por lei** (art. 19.º n.º 2 c)), mas **não entra** em decisões automáticas: não ordena o despacho, não exclui passageiros nem motoristas | **[A CONFIRMAR em `dispatch`, só leitura]** |
| R4 | Recusar ofertas **não** baixa prioridade nem suspende | **[A CONFIRMAR em `dispatch`]** |
| R6 | Prazo máximo: **2 anos (mínimo legal) + até 1 ano** para processos pendentes; depois apagar ou anonimizar. Tarefa automática de limpeza **só depois da decisão** | **POR CONFIRMAR** (decisão do Danilo com advogado) |
| R7 | Código temporário com prazo, finalidade, entidade e agente; revogável; contador de consultas; sem nome, telefone nem email do passageiro; registo de cada exportação | feito (`tvde_fiscal_access`, `_tvde_fiscal_dados`) |
| R7 | Respostas "válido / não válido" em vez de dados em bruto sempre que possível (CNPD §129 l)) | parcial: a página pública do QR mostra o mínimo |
| R8 | A morada do passageiro deixa de ser visível ao motorista depois de a viagem terminar; o passageiro só vê o motorista durante a viagem | **[A CONFIRMAR no código]** |
| R9 | O motorista só vê "precisa de carro adaptado / leva cão-guia / cadeira / carrinho", nunca o motivo; a opção é **consentimento explícito** e pode ser desligada | tabela `tvde_client_prefs`; texto de consentimento a pôr no ecrã |
| R10 | Contratos do art. 28.º e garantias de transferência (decisão de adequação ou cláusulas-tipo) com cada subcontratante | **[A CONFIRMAR]** |
| R11 | RLS, bucket privado, funções fechadas ao público, procedimento de violação em 72 h | RLS feito; procedimento por escrever |
| todos | Auditoria sob supervisão da CNPD (Lei 45/2018, art. 20.º n.º 2) | depois da empresa |
| todos | Reavaliar quando a Diretiva (UE) 2024/2831 (trabalho em plataformas, gestão algorítmica) for transposta (prazo 02/12/2026, segundo a CNPD) | calendário |

## 4. Risco residual

Com as medidas marcadas "feito" e as que estão por confirmar aplicadas, o risco residual fica **médio**. **Não é preciso consulta prévia à CNPD** (RGPD art. 36.º) **se** R2, R3, R4 e R6 ficarem fechados antes de ligar `tvde_compliance_enforce`. Se algum destes quatro ficar aberto, o risco continua **alto** e deve-se consultar a CNPD antes de ligar o bloqueio.

## 5. Decisões para o Danilo

1. Prazo máximo de conservação (proposta: 2 anos + 1 ano).
2. Pôr no contrato operador ↔ plataforma a regra "localização, tempos e avaliações não servem para medir desempenho".
3. Ouvir 2 motoristas sobre esta avaliação (recomendado, art. 35.º n.º 9).
